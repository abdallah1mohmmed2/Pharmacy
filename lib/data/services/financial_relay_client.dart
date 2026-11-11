import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../database/global_uuid.dart';
import 'financial_voucher_operation.dart';
import 'financial_sale_wire_operation.dart';
import 'financial_sale_two_database_replay.dart';

/// Explicit, authenticated transport for the financial voucher contract.
///
/// This is intentionally separate from generic Firestore row synchronization.
/// A trusted backend must validate Firebase ID tokens, branch claims, roles,
/// provisioned references and the complete operation before acknowledging it.
/// No financial data is sent when [endpoint] is absent or insecure.
class FinancialRelayClient {
  FinancialRelayClient({
    required Uri endpoint,
    required Future<String> Function() idTokenProvider,
    http.Client? client,
    bool allowInsecureLocalhostForTesting = false,
    bool saleTransportEnabled = false,
  })  : _endpoint = endpoint,
        _idTokenProvider = idTokenProvider,
        _client = client ?? http.Client(),
        _saleTransportEnabled = saleTransportEnabled {
    final secure = endpoint.scheme == 'https';
    final localTest = allowInsecureLocalhostForTesting &&
        endpoint.scheme == 'http' &&
        {'localhost', '127.0.0.1', '::1'}.contains(endpoint.host);
    if ((!secure && !localTest) ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.query.isNotEmpty ||
        endpoint.fragment.isNotEmpty ||
        !endpoint.path.endsWith('/v1/operations')) {
      throw ArgumentError('A trusted financial relay endpoint is required');
    }
  }

  final Uri _endpoint;
  final Future<String> Function() _idTokenProvider;
  final http.Client _client;
  // Explicit opt-in; server separately enforces a default-off domain gate.
  final bool _saleTransportEnabled;

  Future<Map<String, Object?>> _request(
      String method, Uri uri, Object? payload) async {
    final token = await _idTokenProvider();
    if (token.trim().isEmpty || token.contains(RegExp(r'\s'))) {
      throw const FinancialRelayException('AUTH_TOKEN_REQUIRED');
    }
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (payload != null) 'Content-Type': 'application/json',
    };
    final http.Response response;
    try {
      if (method == 'POST') {
        response = await _client
            .post(uri, headers: headers, body: jsonEncode(payload))
            .timeout(const Duration(seconds: 25));
      } else {
        response = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 25));
      }
    } catch (_) {
      throw const FinancialRelayException('FINANCIAL_RELAY_UNAVAILABLE');
    }
    if (response.statusCode != 200 || response.bodyBytes.length > 300000) {
      throw FinancialRelayException(
          'FINANCIAL_RELAY_HTTP_${response.statusCode}');
    }
    try {
      final parsed = jsonDecode(utf8.decode(response.bodyBytes));
      if (parsed is! Map || parsed.keys.any((key) => key is! String)) {
        throw const FormatException('Invalid response');
      }
      return Map<String, Object?>.from(parsed);
    } catch (_) {
      throw const FinancialRelayException('INVALID_FINANCIAL_RESPONSE');
    }
  }

  /// Send a previously committed, immutable outbox operation. The relay ACK
  /// must echo the exact UUID and hash before the local status may advance.
  Future<void> sendPending(Database database, int branchId,
      {int limit = 20}) async {
    final pending = await FinancialVoucherOperation.pending(database, branchId,
        limit: limit);
    for (final row in pending) {
      final operationUuid = row['operation_uuid'];
      final payloadHash = row['payload_hash'];
      final branchUuid = row['branch_uuid'];
      if (operationUuid is! String ||
          payloadHash is! String ||
          branchUuid is! String ||
          !GlobalUuid.isValid(operationUuid) ||
          !GlobalUuid.isValid(branchUuid)) {
        throw const FinancialRelayException('INVALID_OUTBOX_IDENTITY');
      }
      final envelope = jsonDecode(row['payload_json'] as String);
      final reply = await _request('POST', _endpoint, {
        'operation_uuid': operationUuid,
        'branch_uuid': branchUuid,
        'payload_hash': payloadHash,
        'envelope': envelope,
      });
      if (reply['status'] != 'COMMITTED' ||
          reply['operation_uuid'] != operationUuid ||
          reply['payload_hash'] != payloadHash) {
        throw const FinancialRelayException('FINANCIAL_ACK_MISMATCH');
      }
      await FinancialVoucherOperation.acknowledge(database,
          branchId: branchId,
          operationUuid: operationUuid,
          payloadHash: payloadHash,
          trustedRelay: true);
    }
  }

  /// The caller MUST persist [nextCursor] only after this returns. Failure
  /// leaves its previous cursor unchanged and replay is idempotent in SQLite.
  /// No untrusted row is ever sent through the generic sync inbox.
  Future<String> receivePage(
    Database database, {
    required int branchId,
    required String branchUuid,
    required String afterCursor,
    int limit = 20,
  }) async {
    if (!GlobalUuid.isValid(branchUuid) ||
        !RegExp(r'^(0|[1-9][0-9]{0,14})$').hasMatch(afterCursor) ||
        limit < 1 ||
        limit > 100) {
      throw const FinancialRelayException('INVALID_FINANCIAL_CURSOR');
    }
    final uri = _endpoint.replace(queryParameters: {
      'branch_uuid': branchUuid,
      'after': afterCursor,
      'limit': '$limit',
    });
    final reply = await _request('GET', uri, null);
    final operations = reply['operations'];
    final cursor = reply['next_cursor'];
    if (operations is! List ||
        operations.length > limit ||
        cursor is! String ||
        !RegExp(r'^(0|[1-9][0-9]{0,14})$').hasMatch(cursor) ||
        int.parse(cursor) < int.parse(afterCursor) ||
        (operations.isNotEmpty && cursor == afterCursor)) {
      throw const FinancialRelayException('INVALID_FINANCIAL_PAGE');
    }
    for (final raw in operations) {
      if (raw is! Map || raw.keys.any((key) => key is! String)) {
        throw const FinancialRelayException('INVALID_FINANCIAL_OPERATION');
      }
      final item = Map<String, Object?>.from(raw);
      final envelope = item['envelope'];
      if (envelope is! Map ||
          envelope.keys.any((key) => key is! String) ||
          item['operation_uuid'] != envelope['operation_uuid'] ||
          item['payload_hash'] is! String) {
        throw const FinancialRelayException('INVALID_FINANCIAL_OPERATION');
      }
      await FinancialVoucherOperation.applyVerified(database,
          branchId: branchId,
          expectedBranchUuid: branchUuid,
          envelope: Map<String, Object?>.from(envelope),
          payloadHash: item['payload_hash'] as String,
          trustedRelay: true);
    }
    return cursor;
  }

  /// Explicit voucher cycle with a restart-safe, branch-scoped cursor.
  /// Not scheduled by the app; requires a separately approved relay.
  Future<({int pages})> syncVouchersOnce(
    Database database, {
    required int branchId,
    int limit = 20,
  }) async {
    if (limit < 1 || limit > 100) {
      throw const FinancialRelayException('INVALID_FINANCIAL_PAGE_SIZE');
    }
    final branches = await database.query('branches',
        columns: ['uuid'], where: 'id=?', whereArgs: [branchId]);
    if (branches.length != 1 ||
        branches.single['uuid'] is! String ||
        !GlobalUuid.isValid(branches.single['uuid'] as String)) {
      throw const FinancialRelayException('INVALID_BRANCH_IDENTITY');
    }
    final branchUuid = branches.single['uuid'] as String;
    await sendPending(database, branchId, limit: limit);
    final key = 'financial.voucher.v2.yer.cursor.' + branchUuid;
    final saved = await database
        .query('app_settings', where: 'setting_key=?', whereArgs: [key]);
    var cursor = saved.isEmpty ? '0' : saved.single['value_text'] as String;
    if (!RegExp(r'^(0|[1-9][0-9]{0,14})$').hasMatch(cursor)) {
      throw const FinancialRelayException('INVALID_FINANCIAL_CURSOR');
    }
    var pages = 0;
    for (var page = 0; page < 20; page++) {
      final next = await receivePage(database,
          branchId: branchId,
          branchUuid: branchUuid,
          afterCursor: cursor,
          limit: limit);
      if (next == cursor) break;
      await database.insert(
          'app_settings',
          {
            'setting_key': key,
            'value_text': next,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      cursor = next;
      pages++;
    }
    return (pages: pages);
  }

  /// F10: use the existing authenticated HTTPS relay; never send local IDs.
  Future<void> sendCapturedSale(
    Database database, {
    required int branchId,
    required String operationUuid,
  }) async {
    if (!_saleTransportEnabled) {
      throw const FinancialRelayException('SALES_TRANSPORT_DISABLED');
    }
    final sale = await FinancialSaleWireOperation.export(database,
        branchId: branchId, operationUuid: operationUuid);
    final acknowledged = await database.query('financial_sale_delivery_acks',
        where: 'operation_uuid=?', whereArgs: [operationUuid]);
    if (acknowledged.isNotEmpty) {
      if (acknowledged.single['payload_hash'] != sale.hash) {
        throw const FinancialRelayException('SALE_ACK_CONFLICT');
      }
      return;
    }
    final reply = await _request('POST', _endpoint, {
      'operation_uuid': operationUuid,
      'branch_uuid': sale.envelope['branch_uuid'],
      'payload_hash': sale.hash,
      'envelope': sale.envelope,
    });
    if (reply['status'] != 'COMMITTED' ||
        reply['operation_uuid'] != operationUuid ||
        reply['payload_hash'] != sale.hash) {
      throw const FinancialRelayException('SALE_ACK_INVALID');
    }
    await database.insert(
        'financial_sale_delivery_acks',
        {
          'operation_uuid': operationUuid,
          'payload_hash': sale.hash,
          'acknowledged_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Isolated sale stream: never consume voucher cursor positions.
  Future<String> receiveSalePage(
    Database database, {
    required int branchId,
    required String branchUuid,
    required String afterCursor,
    int limit = 20,
  }) async {
    if (!_saleTransportEnabled) {
      throw const FinancialRelayException('SALES_TRANSPORT_DISABLED');
    }
    final cursorPattern = RegExp(r'^(0|[1-9][0-9]{0,14})$');
    if (!GlobalUuid.isValid(branchUuid) ||
        !cursorPattern.hasMatch(afterCursor) ||
        limit < 1 ||
        limit > 100) {
      throw const FinancialRelayException('INVALID_SALE_CURSOR');
    }
    final uri = _endpoint.replace(queryParameters: {
      'branch_uuid': branchUuid,
      'operation_type': 'CASH_SALE',
      'after': afterCursor,
      'limit': '$limit',
    });
    final reply = await _request('GET', uri, null);
    final operations = reply['operations'];
    final cursor = reply['next_cursor'];
    if (operations is! List ||
        operations.length > limit ||
        cursor is! String ||
        !cursorPattern.hasMatch(cursor) ||
        int.parse(cursor) < int.parse(afterCursor) ||
        (operations.isNotEmpty && cursor == afterCursor)) {
      throw const FinancialRelayException('INVALID_SALE_PAGE');
    }
    for (final raw in operations) {
      if (raw is! Map || raw.keys.any((key) => key is! String)) {
        throw const FinancialRelayException('INVALID_SALE_OPERATION');
      }
      final item = Map<String, Object?>.from(raw);
      final envelope = item['envelope'];
      if (envelope is! Map ||
          envelope.keys.any((key) => key is! String) ||
          item['operation_uuid'] != envelope['operation_uuid'] ||
          item['payload_hash'] is! String) {
        throw const FinancialRelayException('INVALID_SALE_OPERATION');
      }
      await FinancialSaleTwoDatabaseReplay.applyVerifiedWire(
          destination: database,
          destinationBranchId: branchId,
          expectedBranchUuid: branchUuid,
          envelope: Map<String, Object?>.from(envelope),
          payloadHash: item['payload_hash'] as String,
          trustedRelay: true);
    }
    return cursor;
  }

  /// Explicit cycle, disabled by default and not scheduled by the app.
  /// The ACK and restart cursor are separate from CASH voucher state.
  Future<({int sent, int pages})> syncSalesOnce(
    Database database, {
    required int branchId,
    int limit = 20,
  }) async {
    if (!_saleTransportEnabled) {
      throw const FinancialRelayException('SALES_TRANSPORT_DISABLED');
    }
    if (limit < 1 || limit > 100) {
      throw const FinancialRelayException('INVALID_SALE_PAGE_SIZE');
    }
    final branches = await database.query('branches',
        columns: ['uuid'], where: 'id=?', whereArgs: [branchId]);
    if (branches.length != 1 ||
        branches.single['uuid'] is! String ||
        !GlobalUuid.isValid(branches.single['uuid'] as String)) {
      throw const FinancialRelayException('INVALID_BRANCH_IDENTITY');
    }
    final branchUuid = branches.single['uuid'] as String;
    final pending = await database.rawQuery('''
      SELECT o.operation_uuid FROM financial_sale_capture_outbox o
      LEFT JOIN financial_sale_delivery_acks a
        ON a.operation_uuid=o.operation_uuid
      WHERE o.branch_id=? AND a.operation_uuid IS NULL
      ORDER BY o.created_at, o.operation_uuid LIMIT ?
    ''', [branchId, limit]);
    for (final row in pending) {
      await sendCapturedSale(database,
          branchId: branchId, operationUuid: row['operation_uuid'] as String);
    }
    final key = 'financial.sale.v1.yer.cursor.' + branchUuid;
    final saved = await database
        .query('app_settings', where: 'setting_key=?', whereArgs: [key]);
    var cursor = saved.isEmpty ? '0' : saved.single['value_text'] as String;
    var pages = 0;
    for (var page = 0; page < 20; page++) {
      final next = await receiveSalePage(database,
          branchId: branchId,
          branchUuid: branchUuid,
          afterCursor: cursor,
          limit: limit);
      if (next == cursor) break;
      await database.insert(
          'app_settings',
          {
            'setting_key': key,
            'value_text': next,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      cursor = next;
      pages++;
    }
    return (sent: pending.length, pages: pages);
  }

  void close() => _client.close();
}

class FinancialRelayException implements Exception {
  const FinancialRelayException(this.code);
  final String code;
  @override
  String toString() => 'FinancialRelayException: $code';
}
