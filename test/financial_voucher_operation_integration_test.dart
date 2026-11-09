import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/database_helper.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_builder.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration2.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration3.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration4.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration5.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration6.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration7.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration8.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration9.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration10.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration11.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration12.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration13.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/seed_data.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/cash_voucher_integrity_validator.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/financial_voucher_operation.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/financial_voucher_relay_worker.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/posting_and_sales_service.dart';

const branchUuid = '11111111-1111-4111-8111-111111111111';
const partyUuid = '22222222-2222-4222-8222-222222222222';
const cashUuid = '33333333-3333-4333-8333-333333333333';

class FinanceFixture {
  FinanceFixture(this.db);
  final Database db;
  late final helper = DatabaseHelper.forTesting(db);
  late final posting =
      PostingAndSalesService(helper: helper, financialSyncFractionDigits: 0);
  late int partyId;
  late int cashId;

  static Future<FinanceFixture> open(String filename,
      {bool shiftIds = false}) async {
    final db = await databaseFactoryFfi.openDatabase(filename,
        options: OpenDatabaseOptions(onConfigure: (d) async {
      await d.execute('PRAGMA foreign_keys=ON');
    }));
    await SchemaBuilder.build(db);
    await SchemaIteration12.upgrade(db);
    await SeedData.run(db);
    await SchemaIteration2.upgrade(db);
    await SchemaIteration3.upgrade(db);
    await SchemaIteration4.upgrade(db);
    await SchemaIteration5.upgrade(db);
    await SchemaIteration6.upgrade(db);
    await SchemaIteration7.upgrade(db);
    await SchemaIteration8.upgrade(db);
    await SchemaIteration9.upgrade(db);
    await SchemaIteration10.upgrade(db);
    await SchemaIteration11.upgrade(db);
    await SchemaIteration12.upgrade(db);
    await SchemaIteration13.upgrade(db);
    await db.update('branches', {'uuid': branchUuid},
        where: 'id=?', whereArgs: [1]);
    for (final e in {
      '1102': '44444444-4444-4444-8444-444444444444',
      '1201': '55555555-5555-4555-8555-555555555555',
      '2101': '66666666-6666-4666-8666-666666666666',
    }.entries) {
      await db.update('chart_of_accounts', {'uuid': e.value},
          where: 'code=?', whereArgs: [e.key]);
    }
    await db.update('cash_accounts', {'uuid': cashUuid},
        where: 'code=?', whereArgs: ['CASH-DRAWER']);
    if (shiftIds) {
      await db.insert('parties', {
        'uuid': '77777777-7777-4777-8777-777777777777',
        'branch_id': 1,
        'created_at': '2026-11-09',
        'updated_at': '2026-11-09',
        'party_type': 'CUSTOMER',
        'code': 'OTHER-LOCAL-ONLY',
        'name_ar': 'طرف آخر',
      });
    }
    final fixture = FinanceFixture(db);
    fixture.partyId = await db.insert('parties', {
      'uuid': partyUuid,
      'branch_id': 1,
      'created_at': '2026-11-09',
      'updated_at': '2026-11-09',
      'party_type': 'CUSTOMER',
      'code': 'FINANCE-TEST',
      'name_ar': 'طرف اختبار',
    });
    fixture.cashId = (await db.query('cash_accounts',
            columns: ['id'], where: 'code=?', whereArgs: ['CASH-DRAWER']))
        .single['id'] as int;
    return fixture;
  }

  Future<int> post([String type = 'RECEIPT']) => posting.postVoucher(
      branchId: 1,
      voucherNo: 'ignored',
      voucherType: type,
      partyId: partyId,
      cashAccountId: cashId,
      amount: 125.0,
      method: 'CASH',
      description: 'PRIVATE_SENTINEL');
  Future<Map<String, Object?>> outbox() async =>
      (await db.query('financial_operation_outbox')).single;
}

Map<String, Object?> envelopeOf(Map<String, Object?> row) =>
    Map<String, Object?>.from(jsonDecode(row['payload_json'] as String) as Map);
String hashOf(Map<String, Object?> payload) => sha256
    .convert(utf8.encode(FinancialVoucherOperation.canonicalJson(payload)))
    .toString();
Future<FinancialVoucherApplyResult> importInto(
        FinanceFixture target, Map<String, Object?> row,
        {Map<String, Object?>? payload, String? hash, bool trusted = true}) =>
    FinancialVoucherOperation.applyVerified(target.db,
        branchId: 1,
        expectedBranchUuid: branchUuid,
        envelope: payload ?? envelopeOf(row),
        payloadHash: hash ?? row['payload_hash'] as String,
        trustedRelay: trusted);

/// Local test double for a VERIFIED append-only relay. The production server,
/// Firebase claim verification and its financial validation are NOT shipped.
class FakeTrustedFinanceRelay {
  final operations = <Map<String, dynamic>>[];
  bool offline = false;
  bool alterAcknowledgement = false;
  http.Client client() => MockClient((request) async {
        if (offline) throw const SocketException('test relay unavailable');
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final existing = operations
              .where((row) => row['operation_uuid'] == body['operation_uuid'])
              .toList();
          if (existing.isEmpty) {
            operations.add(Map<String, dynamic>.from(body));
          } else if (existing.single['payload_hash'] != body['payload_hash']) {
            return http.Response('conflicting operation hash', 409);
          }
          return http.Response(
              jsonEncode({
                'status': 'COMMITTED',
                'operation_uuid': body['operation_uuid'],
                'payload_hash':
                    alterAcknowledgement ? 'BAD_HASH' : body['payload_hash'],
              }),
              200);
        }
        if (request.method == 'GET') {
          final after =
              int.tryParse(request.url.queryParameters['after'] ?? '') ?? 0;
          final limit = int.parse(request.url.queryParameters['limit'] ?? '50');
          final page = operations.skip(after).take(limit).toList();
          return http.Response(
              jsonEncode({
                'operations': page,
                'next_cursor': (after + page.length).toString(),
              }),
              200);
        }
        return http.Response('not supported', 405);
      });
}

FinancialVoucherRelayWorker workerFor(
        FinanceFixture device, FakeTrustedFinanceRelay relay,
        {bool trusted = true}) =>
    FinancialVoucherRelayWorker(
      helper: device.helper,
      client: relay.client(),
      endpoint: Uri.parse('https://finance-relay.example.test/v1/operations'),
      trustedRelayConfigured: trusted,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  late Directory directory;
  late FinanceFixture source;
  late FinanceFixture target;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('finance-v16-');
    source = await FinanceFixture.open(directory.path + '/source.db');
    target = await FinanceFixture.open(directory.path + '/target.db',
        shiftIds: true);
  });
  tearDown(() async {
    await source.db.close();
    await target.db.close();
    await directory.delete(recursive: true);
  });

  test('YER v2 envelope binds currency and zero precision', () async {
    await source.post();
    final row = await source.outbox();
    final envelope = envelopeOf(row);
    expect(envelope['schema_version'], 2);
    expect(envelope['currency_code'], 'YER');
    expect(envelope['fraction_digits'], 0);
    expect((envelope['voucher'] as Map)['amount_minor'], 125);
    expect((await importInto(target, row)).applied, isTrue);
  });

  test('currency mismatch and legacy v1 are rejected without posting',
      () async {
    await source.post();
    final row = await source.outbox();
    for (final change in <Map<String, Object?>>[
      {'currency_code': 'USD'},
      {'fraction_digits': 2},
      {'schema_version': 1},
    ]) {
      final envelope = envelopeOf(row)..addAll(change);
      await expectLater(
          importInto(target, row, payload: envelope, hash: hashOf(envelope)),
          throwsA(isA<FinancialVoucherSyncException>()));
    }
    expect(await target.db.query('vouchers'), isEmpty);
    expect(await target.db.query('financial_operation_inbox'), isEmpty);
  });

  test('fractional YER is rejected before posting or outbox capture', () async {
    await expectLater(
        source.posting.postVoucher(
            branchId: 1,
            voucherNo: 'ignored',
            voucherType: 'RECEIPT',
            partyId: source.partyId,
            cashAccountId: source.cashId,
            amount: 125.25,
            method: 'CASH',
            description: 'reject fractional YER'),
        throwsA(isA<StateError>()));
    expect(await source.db.query('vouchers'), isEmpty);
    expect(await source.db.query('financial_operation_outbox'), isEmpty);
  });

  test('complete source receipt transfers to different local SQLite IDs',
      () async {
    await source.post();
    final row = await source.outbox();
    expect(row['status'], 'PENDING');
    expect(envelopeOf(row)['lines'], hasLength(2));
    expect(jsonEncode(envelopeOf(row)), isNot(contains('PRIVATE_SENTINEL')));
    expect(source.partyId, isNot(target.partyId));
    expect((await importInto(target, row)).applied, isTrue);
    final posted = (await target.db.query('vouchers')).single;
    expect(posted['party_id'], target.partyId);
    expect(posted['uuid'], row['operation_uuid']);
    final proof = await CashVoucherIntegrityValidator.validate(
        database: target.db,
        branchId: 1,
        voucherId: posted['id'] as int,
        fractionDigits: 0);
    expect(proof.amountMinor, 125);
    expect(await target.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect((await target.db.query('cash_transactions')).single['doc_id'],
        posted['id']);
  });

  test('payment transfers with inverse journal sides', () async {
    await source.post('PAYMENT');
    expect((await importInto(target, await source.outbox())).applied, isTrue);
    final posted = (await target.db.query('vouchers')).single;
    final proof = await CashVoucherIntegrityValidator.validate(
        database: target.db,
        branchId: 1,
        voucherId: posted['id'] as int,
        fractionDigits: 0);
    expect(proof.amountMinor, 125);
    expect(
        (await target.db.query('cash_accounts',
                where: 'id=?', whereArgs: [target.cashId]))
            .single['current_balance'],
        -125.0);
  });

  test('replay and own-device echo never repost balances', () async {
    await source.post();
    final row = await source.outbox();
    expect((await importInto(target, row)).applied, isTrue);
    expect((await importInto(target, row)).applied, isFalse);
    expect((await importInto(source, row)).applied, isFalse);
    expect(await target.db.query('vouchers'), hasLength(1));
    expect(await target.db.query('journal_entries'), hasLength(1));
    expect(await target.db.query('financial_operation_inbox'), hasLength(1));
    expect(
        (await target.db.query('cash_accounts',
                where: 'id=?', whereArgs: [target.cashId]))
            .single['current_balance'],
        125.0);
  });

  test('changed operation fingerprint conflicts with already applied receipt',
      () async {
    await source.post();
    final row = await source.outbox();
    await importInto(target, row);
    final changed = envelopeOf(row);
    final voucher = Map<String, Object?>.from(changed['voucher'] as Map);
    voucher['amount_minor'] = 126;
    changed['voucher'] = voucher;
    await expectLater(
        importInto(target, row, payload: changed, hash: hashOf(changed)),
        throwsA(isA<FinancialVoucherSyncException>()));
    expect(await target.db.query('vouchers'), hasLength(1));
  });

  test('missing parent blocks whole receipt until dependency is inserted',
      () async {
    await source.post();
    final row = await source.outbox();
    await target.db
        .delete('parties', where: 'id=?', whereArgs: [target.partyId]);
    await expectLater(
        importInto(target, row), throwsA(isA<FinancialVoucherSyncException>()));
    expect(await target.db.query('vouchers'), isEmpty);
    expect(await target.db.query('financial_operation_inbox'), isEmpty);
    target.partyId = await target.db.insert('parties', {
      'uuid': partyUuid,
      'branch_id': 1,
      'created_at': '2026-11-09',
      'updated_at': '2026-11-09',
      'party_type': 'CUSTOMER',
      'code': 'RETRY-PARTY',
      'name_ar': 'طرف مستعاد',
    });
    expect((await importInto(target, row)).applied, isTrue);
  });

  test('SQLite failure rolls back documents, journal, cash and inbox',
      () async {
    await source.post();
    final row = await source.outbox();
    await target.db.execute('''CREATE TRIGGER reject_cash
      BEFORE INSERT ON cash_transactions
      BEGIN SELECT RAISE(ABORT,'simulated fail'); END''');
    await expectLater(importInto(target, row), throwsA(anything));
    for (final table in [
      'vouchers',
      'journal_entries',
      'journal_lines',
      'lah_alayh_ledger',
      'cash_transactions',
      'financial_operation_inbox'
    ]) {
      expect(await target.db.query(table), isEmpty, reason: table);
    }
    expect(
        (await target.db.query('cash_accounts',
                where: 'id=?', whereArgs: [target.cashId]))
            .single['current_balance'],
        0);
    await target.db.execute('DROP TRIGGER reject_cash');
    expect((await importInto(target, row)).applied, isTrue);
  });

  test('altered debit with new hash fails accounting verification', () async {
    await source.post();
    final row = await source.outbox();
    final changed = envelopeOf(row);
    final lines = (changed['lines'] as List)
        .map((item) => Map<String, Object?>.from(item as Map))
        .toList();
    lines[0]['dr_minor'] = 124;
    changed['lines'] = lines;
    await expectLater(
        importInto(target, row, payload: changed, hash: hashOf(changed)),
        throwsA(isA<FinancialVoucherSyncException>()));
    expect(await target.db.query('vouchers'), isEmpty);
  });

  test('untrusted transport and wrong branch cannot apply voucher', () async {
    await source.post();
    final row = await source.outbox();
    await expectLater(importInto(target, row, trusted: false),
        throwsA(isA<FinancialVoucherSyncException>()));
    final changed = envelopeOf(row);
    changed['branch_uuid'] = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    await expectLater(
        importInto(target, row, payload: changed, hash: hashOf(changed)),
        throwsA(isA<FinancialVoucherSyncException>()));
    expect(await target.db.query('vouchers'), isEmpty);
  });

  test('unprovisioned master identity rejects capture and rolls back source',
      () async {
    await source.db.update('chart_of_accounts', {'uuid': 'acc-1201'},
        where: 'code=?', whereArgs: ['1201']);
    await expectLater(source.post(), throwsA(anything));
    expect(await source.db.query('vouchers'), isEmpty);
    expect(await source.db.query('cash_transactions'), isEmpty);
    expect(await source.db.query('financial_operation_outbox'), isEmpty);
  });

  test('legacy default posting remains local without financial capture',
      () async {
    final ordinary = PostingAndSalesService(helper: source.helper);
    await ordinary.postVoucher(
        branchId: 1,
        voucherNo: 'ignored',
        voucherType: 'RECEIPT',
        partyId: source.partyId,
        cashAccountId: source.cashId,
        amount: 10,
        method: 'CASH',
        description: 'local only');
    expect(await source.db.query('vouchers'), hasLength(1));
    expect(await source.db.query('financial_operation_outbox'), isEmpty);
  });

  test('outbox payload immutable and trusted ACK required', () async {
    await source.post();
    final row = await source.outbox();
    await expectLater(
        source.db.update('financial_operation_outbox', {'payload_json': '{}'}),
        throwsA(anything));
    await expectLater(
        source.db.delete('financial_operation_outbox'), throwsA(anything));
    await expectLater(
        FinancialVoucherOperation.acknowledge(source.db,
            branchId: 1,
            operationUuid: row['operation_uuid'] as String,
            payloadHash: row['payload_hash'] as String,
            trustedRelay: false),
        throwsA(isA<FinancialVoucherSyncException>()));
    expect(await FinancialVoucherOperation.pending(source.db, 1), hasLength(1));
    await FinancialVoucherOperation.acknowledge(source.db,
        branchId: 1,
        operationUuid: row['operation_uuid'] as String,
        payloadHash: row['payload_hash'] as String,
        trustedRelay: true);
    expect(await FinancialVoucherOperation.pending(source.db, 1), isEmpty);
    expect((await source.outbox())['status'], 'SENT');
  });

  test('v16 migration repeats safely and retains historic cash UUID as NULL',
      () async {
    await source.db.insert('cash_transactions', {
      'cash_account_id': source.cashId,
      'tx_date': '2026-11-09',
      'direction': 'IN',
      'amount': 1,
      'tx_type': 'OPENING',
      'branch_id': 1,
    });
    await SchemaIteration13.upgrade(source.db);
    await SchemaIteration13.upgrade(source.db);
    expect((await source.db.query('cash_transactions')).single['uuid'], isNull);
  });

  test('HTTP relay uploads and downloads one complete posted voucher',
      () async {
    final relay = FakeTrustedFinanceRelay();
    await source.post();
    final uploaded = await workerFor(source, relay)
        .syncOnce(branchId: 1, idToken: 'test-token');
    expect(uploaded.sent, 1);
    expect(relay.operations, hasLength(1));
    expect((await source.outbox())['status'], 'SENT');
    final downloaded = await workerFor(target, relay)
        .syncOnce(branchId: 1, idToken: 'test-token');
    expect(downloaded.applied, 1);
    expect(await target.db.query('vouchers'), hasLength(1));
    expect(
        (await workerFor(target, relay)
                .syncOnce(branchId: 1, idToken: 'test-token'))
            .applied,
        0);
    expect(await target.db.query('financial_operation_inbox'), hasLength(1));
  });

  test('offline relay retains pending envelope for retry', () async {
    final relay = FakeTrustedFinanceRelay()..offline = true;
    await source.post();
    await expectLater(
        workerFor(source, relay).syncOnce(branchId: 1, idToken: 'test-token'),
        throwsA(isA<SocketException>()));
    expect((await source.outbox())['status'], 'PENDING');
    relay.offline = false;
    expect(
        (await workerFor(source, relay)
                .syncOnce(branchId: 1, idToken: 'test-token'))
            .sent,
        1);
    expect(
        (await workerFor(target, relay)
                .syncOnce(branchId: 1, idToken: 'test-token'))
            .applied,
        1);
  });

  test('wrong relay acknowledgement never marks the outbox SENT', () async {
    final relay = FakeTrustedFinanceRelay()..alterAcknowledgement = true;
    await source.post();
    await expectLater(
        workerFor(source, relay).syncOnce(branchId: 1, idToken: 'test-token'),
        throwsA(isA<FinancialVoucherSyncException>()));
    expect((await source.outbox())['status'], 'PENDING');
    relay.alterAcknowledgement = false;
    expect(
        (await workerFor(source, relay)
                .syncOnce(branchId: 1, idToken: 'test-token'))
            .sent,
        1);
    expect(relay.operations, hasLength(1));
  });

  test('relay cannot be used without explicit trusted configuration', () async {
    await source.post();
    final relay = FakeTrustedFinanceRelay();
    await expectLater(
        workerFor(source, relay, trusted: false)
            .syncOnce(branchId: 1, idToken: 'test-token'),
        throwsA(isA<FinancialVoucherSyncException>()));
    expect(relay.operations, isEmpty);
    expect((await source.outbox())['status'], 'PENDING');
  });
}
