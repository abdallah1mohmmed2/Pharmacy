import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../database/global_uuid.dart';
import 'financial_voucher_operation.dart';
import 'financial_minor_units.dart';

/// HTTP transport for complete P0-06 financial envelopes.
///
/// A deployable trusted relay is NOT shipped by this client. Until an
/// authenticated server validates branch membership, operation membership,
/// balancing and immutable hashes, this adapter must remain unwired in
/// production. It never uses the permissive general Firestore batch stream.
class FinancialVoucherRelayWorker {
  FinancialVoucherRelayWorker({
    required DatabaseHelper helper,
    required http.Client client,
    required Uri endpoint,
    required bool trustedRelayConfigured,
    bool allowLoopbackHttpForTests = false,
  })  : _helper = helper,
        _client = client,
        _endpoint = endpoint,
        _trustedRelayConfigured = trustedRelayConfigured,
        _allowLoopbackHttpForTests = allowLoopbackHttpForTests;

  final DatabaseHelper _helper;
  final http.Client _client;
  final Uri _endpoint;
  final bool _trustedRelayConfigured;
  final bool _allowLoopbackHttpForTests;

  static const _maxBytes = 250000;

  Future<FinancialVoucherSyncCycle> syncOnce({
    required int branchId,
    required String idToken,
    int pageSize = 50,
  }) async {
    if (!_trustedRelayConfigured) {
      throw const FinancialVoucherSyncException('TRUSTED_RELAY_NOT_CONFIGURED');
    }
    final isLoopback =
        {'localhost', '127.0.0.1', '::1'}.contains(_endpoint.host);
    if (_endpoint.scheme != 'https' &&
        !(_allowLoopbackHttpForTests &&
            _endpoint.scheme == 'http' &&
            isLoopback)) {
      throw const FinancialVoucherSyncException('INSECURE_RELAY_ENDPOINT');
    }
    if (branchId <= 0 ||
        idToken.trim().isEmpty ||
        pageSize < 1 ||
        pageSize > 100) {
      throw ArgumentError('Invalid trusted financial relay configuration');
    }
    final db = await _helper.database;
    final branches = await db.query('branches',
        columns: ['uuid'], where: 'id=?', whereArgs: [branchId]);
    if (branches.length != 1 ||
        branches.single['uuid'] is! String ||
        !GlobalUuid.isValid(branches.single['uuid'] as String)) {
      throw const FinancialVoucherSyncException('INVALID_BRANCH_IDENTITY');
    }
    final branchUuid = branches.single['uuid'] as String;
    final headers = <String, String>{
      'authorization': 'Bearer $idToken',
      'content-type': 'application/json',
      'accept': 'application/json',
    };

    var sent = 0;
    for (final row in await FinancialVoucherOperation.pending(db, branchId,
        limit: pageSize)) {
      final json = row['payload_json'] as String;
      final payload = jsonDecode(json);
      if (payload is! Map ||
          payload['schema_version'] !=
              FinancialVoucherOperation.schemaVersion ||
          payload['currency_code'] != FinancialMinorUnits.currencyCode ||
          payload['fraction_digits'] !=
              FinancialMinorUnits.currencyFractionDigits) {
        throw const FinancialVoucherSyncException('CURRENCY_POLICY_MISMATCH');
      }
      if (payload['operation_uuid'] != row['operation_uuid'] ||
          payload['voucher'] is! Map ||
          payload['journal'] is! Map ||
          payload['lines'] is! List ||
          payload['ledger'] is! Map ||
          payload['cash'] is! Map) {
        throw const FinancialVoucherSyncException(
            'UNSUPPORTED_FINANCIAL_DOMAIN');
      }
      final body = jsonEncode({
        'operation_uuid': row['operation_uuid'],
        'branch_uuid': branchUuid,
        'payload_hash': row['payload_hash'],
        'envelope': jsonDecode(json),
      });
      if (utf8.encode(body).length > _maxBytes) {
        throw const FinancialVoucherSyncException(
            'FINANCIAL_ENVELOPE_TOO_LARGE');
      }
      final response = await _client
          .post(_endpoint, headers: headers, body: body)
          .timeout(const Duration(seconds: 30));
      final ack = _successfulJson(response, 'FINANCIAL_UPLOAD_FAILED');
      if (ack['status'] != 'COMMITTED' ||
          ack['operation_uuid'] != row['operation_uuid'] ||
          ack['payload_hash'] != row['payload_hash']) {
        throw const FinancialVoucherSyncException('INVALID_FINANCIAL_ACK');
      }
      await FinancialVoucherOperation.acknowledge(db,
          branchId: branchId,
          operationUuid: row['operation_uuid'] as String,
          payloadHash: row['payload_hash'] as String,
          trustedRelay: true);
      sent++;
    }

    // Cursor is a trusted relay sequence, never a local SQLite row ID or
    // random UUID. Persist only AFTER all events in the page are applied.
    final key = 'financial.v2.yer.cursor.$branchUuid';
    final prior = await db
        .query('app_settings', where: 'setting_key=?', whereArgs: [key]);
    var cursor = prior.isEmpty ? '' : prior.single['value_text'] as String;
    var applied = 0;
    var duplicates = 0;
    for (var page = 0; page < 20; page++) {
      final uri = _endpoint.replace(queryParameters: {
        'branch_uuid': branchUuid,
        'after': cursor,
        'limit': pageSize.toString(),
      });
      final response = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));
      final data = _successfulJson(response, 'FINANCIAL_DOWNLOAD_FAILED');
      final items = data['operations'];
      if (items is! List || items.length > pageSize) {
        throw const FinancialVoucherSyncException('INVALID_FINANCIAL_PAGE');
      }
      if (items.isEmpty)
        return FinancialVoucherSyncCycle(
            sent: sent, applied: applied, duplicates: duplicates);
      final next = data['next_cursor'];
      if (next is! String || next.isEmpty || next == cursor) {
        throw const FinancialVoucherSyncException('INVALID_FINANCIAL_CURSOR');
      }
      for (final item in items) {
        if (item is! Map) {
          throw const FinancialVoucherSyncException('INVALID_FINANCIAL_EVENT');
        }
        final decoded = Map<String, Object?>.from(item);
        final payload = decoded['envelope'];
        if (payload is! Map ||
            decoded['operation_uuid'] != payload['operation_uuid'] ||
            decoded['payload_hash'] is! String) {
          throw const FinancialVoucherSyncException('INVALID_FINANCIAL_EVENT');
        }
        final result = await FinancialVoucherOperation.applyVerified(db,
            branchId: branchId,
            expectedBranchUuid: branchUuid,
            envelope: Map<String, Object?>.from(payload),
            payloadHash: decoded['payload_hash'] as String,
            trustedRelay: true);
        if (result.applied) {
          applied++;
        } else {
          duplicates++;
        }
      }
      // F09: the cursor must never advance before every event in this page
      // has completed. Persisting it after the loop allows safe replay on
      // restart; the financial inbox rejects already applied operations.
      await db.insert(
          'app_settings',
          {
            'setting_key': key,
            'value_text': next,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      cursor = next;
      if (items.length < pageSize) {
        return FinancialVoucherSyncCycle(
            sent: sent, applied: applied, duplicates: duplicates);
      }
    }
    throw const FinancialVoucherSyncException('FINANCIAL_PAGE_LIMIT');
  }

  static Map<String, dynamic> _successfulJson(
      http.Response response, String code) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FinancialVoucherSyncException(code);
    }
    if (response.bodyBytes.length > _maxBytes) {
      throw const FinancialVoucherSyncException('FINANCIAL_RESPONSE_TOO_LARGE');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FinancialVoucherSyncException('INVALID_RELAY_RESPONSE');
    }
    return decoded;
  }
}

class FinancialVoucherSyncCycle {
  const FinancialVoucherSyncCycle({
    required this.sent,
    required this.applied,
    required this.duplicates,
  });
  final int sent;
  final int applied;
  final int duplicates;
}
