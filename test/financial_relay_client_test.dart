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
  test('voucher cycle persists cursor across independent client instances',
      () async {
    const branchUuid = 'd1111111-1111-4111-8111-111111111111';
    await database.execute(
        'CREATE TABLE branches (id INTEGER PRIMARY KEY, uuid TEXT NOT NULL)');
    await database.execute(
        'CREATE TABLE financial_operation_outbox (operation_uuid TEXT, branch_id INTEGER, status TEXT, created_at TEXT)');
    await database.execute(
        'CREATE TABLE app_settings (setting_key TEXT PRIMARY KEY, value_text TEXT, updated_at TEXT)');
    await database.insert('branches', {'id': 1, 'uuid': branchUuid});
    final seen = <String>[];
    final mock = MockClient((request) async {
      final after = request.url.queryParameters['after']!;
      seen.add(after);
      return http.Response(
          jsonEncode({
            'operations': <Object>[],
            'next_cursor': after == '0' ? '5' : after,
          }),
          200);
    });
    FinancialRelayClient makeClient() => FinancialRelayClient(
          endpoint: Uri.parse('https://example.org/v1/operations'),
          idTokenProvider: () async => 'signed-token',
          client: mock,
        );
    final first = makeClient();
    final firstResult = await first.syncVouchersOnce(database, branchId: 1);
    expect(firstResult.pages, 1);
    expect(seen, ['0', '5']);
    final stored = await database.query('app_settings');
    expect(stored.single['value_text'], '5');

    // A fresh client reads the durable cursor rather than starting at zero.
    final second = makeClient();
    final secondResult = await second.syncVouchersOnce(database, branchId: 1);
    expect(secondResult.pages, 0);
    expect(seen, ['0', '5', '5']);
  });

  test('voucher cycle leaves cursor unchanged on relay failure', () async {
    const branchUuid = 'd1111111-1111-4111-8111-111111111111';
    await database.execute(
        'CREATE TABLE branches (id INTEGER PRIMARY KEY, uuid TEXT NOT NULL)');
    await database.execute(
        'CREATE TABLE financial_operation_outbox (operation_uuid TEXT, branch_id INTEGER, status TEXT, created_at TEXT)');
    await database.execute(
        'CREATE TABLE app_settings (setting_key TEXT PRIMARY KEY, value_text TEXT, updated_at TEXT)');
    await database.insert('branches', {'id': 1, 'uuid': branchUuid});
    final client = FinancialRelayClient(
      endpoint: Uri.parse('https://example.org/v1/operations'),
      idTokenProvider: () async => 'signed-token',
      client: MockClient((request) async => http.Response('denied', 403)),
    );
    await expectLater(client.syncVouchersOnce(database, branchId: 1),
        throwsA(isA<FinancialRelayException>()));
    expect(await database.query('app_settings'), isEmpty);
  });
  test('voucher page with operations must advance cursor before apply',
      () async {
    const branchUuid = 'd1111111-1111-4111-8111-111111111111';
    final client = FinancialRelayClient(
      endpoint: Uri.parse('https://example.org/v1/operations'),
      idTokenProvider: () async => 'signed-token',
      client: MockClient((request) async => http.Response(
            jsonEncode({
              'operations': [
                {'operation_uuid': 'invalid-operation'}
              ],
              'next_cursor': '0',
            }),
            200,
          )),
    );
    await expectLater(
      client.receivePage(database,
          branchId: 1, branchUuid: branchUuid, afterCursor: '0'),
      throwsA(isA<FinancialRelayException>()
          .having((e) => e.code, 'code', 'INVALID_FINANCIAL_PAGE')),
    );
    client.close();
  });
  test('voucher cursors are isolated between branch identities', () async {
    const firstUuid = 'd1111111-1111-4111-8111-111111111111';
    const secondUuid = 'd2222222-2222-4222-8222-222222222222';
    await database.execute(
        'CREATE TABLE branches (id INTEGER PRIMARY KEY, uuid TEXT NOT NULL)');
    await database.execute(
        'CREATE TABLE financial_operation_outbox (operation_uuid TEXT, branch_id INTEGER, status TEXT, created_at TEXT)');
    await database.execute(
        'CREATE TABLE app_settings (setting_key TEXT PRIMARY KEY, value_text TEXT, updated_at TEXT)');
    await database.insert('branches', {'id': 1, 'uuid': firstUuid});
    await database.insert('branches', {'id': 2, 'uuid': secondUuid});
    final seen = <String>[];
    final client = FinancialRelayClient(
      endpoint: Uri.parse('https://example.org/v1/operations'),
      idTokenProvider: () async => 'signed-token',
      client: MockClient((request) async {
        final branch = request.url.queryParameters['branch_uuid']!;
        final after = request.url.queryParameters['after']!;
        seen.add('$branch:$after');
        return http.Response(
            jsonEncode({
              'operations': <Object>[],
              'next_cursor':
                  after == '0' ? (branch == firstUuid ? '3' : '9') : after,
            }),
            200);
      }),
    );
    await client.syncVouchersOnce(database, branchId: 1);
    await client.syncVouchersOnce(database, branchId: 2);
    await client.syncVouchersOnce(database, branchId: 1);
    expect(seen, [
      '$firstUuid:0',
      '$firstUuid:3',
      '$secondUuid:0',
      '$secondUuid:9',
      '$firstUuid:3',
    ]);
    final saved = await database.query('app_settings', orderBy: 'setting_key');
    expect(saved.length, 2);
    expect(saved.map((row) => row['value_text']).toSet(), {'3', '9'});
    client.close();
  });
  test('sale cycle rejects corrupt persisted cursor before network access',
      () async {
    const branchUuid = 'd1111111-1111-4111-8111-111111111111';
    await database.execute(
        'CREATE TABLE branches (id INTEGER PRIMARY KEY, uuid TEXT NOT NULL)');
    await database.execute(
        'CREATE TABLE financial_sale_capture_outbox (operation_uuid TEXT, branch_id INTEGER, created_at TEXT)');
    await database.execute(
        'CREATE TABLE financial_sale_delivery_acks (operation_uuid TEXT)');
    await database.execute(
        'CREATE TABLE app_settings (setting_key TEXT PRIMARY KEY, value_text TEXT, updated_at TEXT)');
    await database.insert('branches', {'id': 1, 'uuid': branchUuid});
    await database.insert('app_settings', {
      'setting_key': 'financial.sale.v1.yer.cursor.$branchUuid',
      'value_text': '-1',
    });
    var called = false;
    final client = FinancialRelayClient(
      endpoint: Uri.parse('https://example.org/v1/operations'),
      idTokenProvider: () async => 'signed-token',
      saleTransportEnabled: true,
      client: MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      client.syncSalesOnce(database, branchId: 1),
      throwsA(isA<FinancialRelayException>()
          .having((e) => e.code, 'code', 'INVALID_SALE_CURSOR')),
    );
    expect(called, isFalse);
    client.close();
  });
}
