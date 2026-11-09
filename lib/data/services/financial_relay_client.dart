import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../database/global_uuid.dart';
import 'financial_voucher_operation.dart';

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
  })  : _endpoint = endpoint,
        _idTokenProvider = idTokenProvider,
        _client = client ?? http.Client() {
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

  Future<Map<String, Object?>> _request(
      String method, Uri uri, Object? payload) async {
    final token = await _idTokenProvider();
    if (token.trim().isEmpty || token.contains(RegExp(r'\\s'))) {
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
        int.parse(cursor) < int.parse(afterCursor)) {
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

  void close() => _client.close();
}

class FinancialRelayException implements Exception {
  const FinancialRelayException(this.code);
  final String code;
  @override
  String toString() => 'FinancialRelayException: $code';
}
