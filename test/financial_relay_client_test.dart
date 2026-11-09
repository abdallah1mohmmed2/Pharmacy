import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/financial_relay_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database database;
  setUp(() async {
    // A real SQLite handle is required even when a page has no operations.
    // Avoid null-as-dynamic: Dart rejects it before receivePage is entered.
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  });
  tearDown(() async {
    await database.close();
  });

  test('financial transport refuses unencrypted remote endpoint', () {
    expect(
      () => FinancialRelayClient(
        endpoint: Uri.parse('http://example.org/v1/operations'),
        idTokenProvider: () async => 'token',
      ),
      throwsArgumentError,
    );
  });

  test('financial transport refuses credentials in endpoint URL', () {
    expect(
      () => FinancialRelayClient(
        endpoint: Uri.parse('https://user:pass@example.org/v1/operations'),
        idTokenProvider: () async => 'token',
      ),
      throwsArgumentError,
    );
  });

  test('receive rejects malformed branch and cursor before network request',
      () async {
    var called = false;
    final client = FinancialRelayClient(
      endpoint: Uri.parse('https://example.org/v1/operations'),
      idTokenProvider: () async => 'token',
      client: MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );
    // Invalid arguments are rejected before accessing the SQLite connection.
    await expectLater(
      client.receivePage(database,
          branchId: 1, branchUuid: 'invalid', afterCursor: '0'),
      throwsA(isA<FinancialRelayException>()),
    );
    await expectLater(
      client.receivePage(database,
          branchId: 1,
          branchUuid: 'd1111111-1111-4111-8111-111111111111',
          afterCursor: '-1'),
      throwsA(isA<FinancialRelayException>()),
    );
    expect(called, isFalse);
    client.close();
  });

  test('empty authenticated page returns cursor without applying anything',
      () async {
    var requests = 0;
    final client = FinancialRelayClient(
      endpoint: Uri.parse('https://example.org/v1/operations'),
      idTokenProvider: () async => 'signed-token',
      client: MockClient((request) async {
        requests++;
        expect(request.method, 'GET');
        expect(request.headers['Authorization'], 'Bearer signed-token');
        expect(request.url.queryParameters['after'], '0');
        expect(request.url.queryParameters['limit'], '20');
        return http.Response(
            jsonEncode({'operations': <Object>[], 'next_cursor': '0'}), 200,
            headers: {'content-type': 'application/json'});
      }),
    );
    final cursor = await client.receivePage(database,
        branchId: 1,
        branchUuid: 'd1111111-1111-4111-8111-111111111111',
        afterCursor: '0');
    expect(cursor, '0');
    expect(requests, 1);
    client.close();
  });

  test('relay errors do not advance a receive cursor', () async {
    final client = FinancialRelayClient(
      endpoint: Uri.parse('https://example.org/v1/operations'),
      idTokenProvider: () async => 'signed-token',
      client: MockClient((request) async => http.Response(
          jsonEncode({'error': 'FINANCIAL_REFERENCES_NOT_APPROVED'}), 403)),
    );
    await expectLater(
      client.receivePage(database,
          branchId: 1,
          branchUuid: 'd1111111-1111-4111-8111-111111111111',
          afterCursor: '0'),
      throwsA(isA<FinancialRelayException>()),
    );
    client.close();
  });
}
