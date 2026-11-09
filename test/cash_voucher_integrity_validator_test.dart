import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/cash_voucher_integrity_validator.dart';

const branchId = 1;
const voucherUuid = '11111111-1111-4111-8111-111111111111';
const journalUuid = '22222222-2222-4222-8222-222222222222';
const partyUuid = '33333333-3333-4333-8333-333333333333';
const cashUuid = '44444444-4444-4444-8444-444444444444';
const cashGlUuid = '55555555-5555-4555-8555-555555555555';
const partyGlUuid = '66666666-6666-4666-8666-666666666666';
const cashLineUuid = '77777777-7777-4777-8777-777777777777';
const partyLineUuid = '88888888-8888-4888-8888-888888888888';
const ledgerUuid = '99999999-9999-4999-8999-999999999999';

Future<void> createFixture(Database db,
    {bool receipt = true, int offset = 0}) async {
  // A deliberately minimal subset of the real schema. This is NOT a
  // cross-device transfer test and cannot authorize production financial sync.
  for (final sql in [
    'CREATE TABLE vouchers(id INTEGER PRIMARY KEY,uuid TEXT,branch_id INTEGER,is_deleted INTEGER,voucher_type TEXT,method TEXT,amount REAL,party_id INTEGER,cash_account_id INTEGER,journal_entry_id INTEGER)',
    'CREATE TABLE parties(id INTEGER PRIMARY KEY,uuid TEXT,branch_id INTEGER)',
    'CREATE TABLE cash_accounts(id INTEGER PRIMARY KEY,uuid TEXT,branch_id INTEGER,account_kind TEXT,gl_account_id INTEGER)',
    'CREATE TABLE chart_of_accounts(id INTEGER PRIMARY KEY,uuid TEXT,branch_id INTEGER,code TEXT)',
    'CREATE TABLE journal_entries(id INTEGER PRIMARY KEY,uuid TEXT,branch_id INTEGER,source_type TEXT,source_id INTEGER,is_posted INTEGER,is_deleted INTEGER)',
    'CREATE TABLE journal_lines(id INTEGER PRIMARY KEY,uuid TEXT,branch_id INTEGER,journal_entry_id INTEGER,account_id INTEGER,party_id INTEGER,dr_amount REAL,cr_amount REAL)',
    'CREATE TABLE lah_alayh_ledger(id INTEGER PRIMARY KEY,uuid TEXT,branch_id INTEGER,doc_type TEXT,doc_id INTEGER,party_id INTEGER,entry_type TEXT,is_deleted INTEGER,alayh_amount REAL,lah_amount REAL)',
    'CREATE TABLE cash_transactions(id INTEGER PRIMARY KEY,branch_id INTEGER,doc_type TEXT,doc_id INTEGER,cash_account_id INTEGER,direction TEXT,tx_type TEXT,amount REAL)',
  ]) {
    await db.execute(sql);
  }
  final v = 10 + offset, p = 20 + offset, c = 30 + offset;
  final j = 40 + offset, cg = 50 + offset, pg = 60 + offset;
  await db
      .insert('parties', {'id': p, 'uuid': partyUuid, 'branch_id': branchId});
  await db.insert('chart_of_accounts',
      {'id': cg, 'uuid': cashGlUuid, 'branch_id': branchId, 'code': '1001'});
  await db.insert('chart_of_accounts', {
    'id': pg,
    'uuid': partyGlUuid,
    'branch_id': branchId,
    'code': receipt ? '1201' : '2101'
  });
  await db.insert('cash_accounts', {
    'id': c,
    'uuid': cashUuid,
    'branch_id': branchId,
    'account_kind': 'CASHIER_DRAWER',
    'gl_account_id': cg
  });
  await db.insert('vouchers', {
    'id': v,
    'uuid': voucherUuid,
    'branch_id': branchId,
    'is_deleted': 0,
    'voucher_type': receipt ? 'RECEIPT' : 'PAYMENT',
    'method': 'CASH',
    'amount': 125.25,
    'party_id': p,
    'cash_account_id': c,
    'journal_entry_id': j
  });
  await db.insert('journal_entries', {
    'id': j,
    'uuid': journalUuid,
    'branch_id': branchId,
    'source_type': 'VOUCHER',
    'source_id': v,
    'is_posted': 1,
    'is_deleted': 0
  });
  await db.insert('journal_lines', {
    'id': 1 + offset,
    'uuid': cashLineUuid,
    'branch_id': branchId,
    'journal_entry_id': j,
    'account_id': cg,
    'party_id': null,
    'dr_amount': receipt ? 125.25 : 0.0,
    'cr_amount': receipt ? 0.0 : 125.25
  });
  await db.insert('journal_lines', {
    'id': 2 + offset,
    'uuid': partyLineUuid,
    'branch_id': branchId,
    'journal_entry_id': j,
    'account_id': pg,
    'party_id': p,
    'dr_amount': receipt ? 0.0 : 125.25,
    'cr_amount': receipt ? 125.25 : 0.0
  });
  await db.insert('lah_alayh_ledger', {
    'id': 3 + offset,
    'uuid': ledgerUuid,
    'branch_id': branchId,
    'doc_type': 'VOUCHER',
    'doc_id': v,
    'party_id': p,
    'entry_type': receipt ? 'RECEIPT' : 'PAYMENT',
    'is_deleted': 0,
    'alayh_amount': receipt ? 0.0 : 125.25,
    'lah_amount': receipt ? 125.25 : 0.0
  });
  await db.insert('cash_transactions', {
    'id': 4 + offset,
    'branch_id': branchId,
    'doc_type': 'VOUCHER',
    'doc_id': v,
    'cash_account_id': c,
    'direction': receipt ? 'IN' : 'OUT',
    'tx_type': receipt ? 'RECEIPT_VOUCHER' : 'PAYMENT_VOUCHER',
    'amount': 125.25
  });
}

Future<CashVoucherIntegrityResult> verify(Database db,
        {int offset = 0, int fractionDigits = 2}) =>
    CashVoucherIntegrityValidator.validate(
        database: db,
        branchId: branchId,
        voucherId: 10 + offset,
        fractionDigits: fractionDigits);

void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await createFixture(db);
  });
  tearDown(() => db.close());

  test('valid receipt is balanced in integer minor units', () async {
    final result = await verify(db);
    expect(result.amountMinor, 12525);
    expect(result.journalUuid, journalUuid);
    expect(result.voucherUuid, voucherUuid);
  });

  test('payment uses inverse debit and credit sides', () async {
    final other = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    try {
      await createFixture(other, receipt: false);
      expect((await verify(other)).amountMinor, 12525);
    } finally {
      await other.close();
    }
  });

  test('local row IDs can differ without changing global document UUIDs',
      () async {
    final other = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    try {
      await createFixture(other, offset: 100);
      final first = await verify(db);
      final second = await verify(other, offset: 100);
      expect(second.voucherUuid, first.voucherUuid);
      expect(second.journalUuid, first.journalUuid);
      expect(second.amountMinor, first.amountMinor);
    } finally {
      await other.close();
    }
  });

  test('missing journal line rejects an incomplete document', () async {
    await db.delete('journal_lines', where: 'id=?', whereArgs: [2]);
    await expectLater(
        verify(db), throwsA(isA<CashVoucherIntegrityException>()));
  });

  test('wrong debit/credit amounts reject an unbalanced entry', () async {
    await db.update('journal_lines', {'cr_amount': 125.24},
        where: 'id=?', whereArgs: [2]);
    await expectLater(
        verify(db), throwsA(isA<CashVoucherIntegrityException>()));
  });

  test('foreign journal source cannot be treated as voucher entry', () async {
    await db.update('journal_entries', {'source_id': 999},
        where: 'id=?', whereArgs: [40]);
    await expectLater(
        verify(db), throwsA(isA<CashVoucherIntegrityException>()));
  });

  test('wrong cash movement direction is rejected', () async {
    await db.update('cash_transactions', {'direction': 'OUT'});
    await expectLater(
        verify(db), throwsA(isA<CashVoucherIntegrityException>()));
  });

  test('duplicate cash movement is rejected', () async {
    await db.insert('cash_transactions', {
      'id': 900,
      'branch_id': 1,
      'doc_type': 'VOUCHER',
      'doc_id': 10,
      'cash_account_id': 30,
      'direction': 'IN',
      'tx_type': 'RECEIPT_VOUCHER',
      'amount': 125.25
    });
    await expectLater(
        verify(db), throwsA(isA<CashVoucherIntegrityException>()));
  });

  test('missing ledger is rejected', () async {
    await db.delete('lah_alayh_ledger');
    await expectLater(
        verify(db), throwsA(isA<CashVoucherIntegrityException>()));
  });

  test('fraction digits cannot silently round amounts', () async {
    await db.update('vouchers', {'amount': 125.251});
    await expectLater(
        verify(db), throwsA(isA<CashVoucherIntegrityException>()));
  });

  test('invalid currency precision is rejected', () async {
    await expectLater(verify(db, fractionDigits: 4),
        throwsA(isA<CashVoucherIntegrityException>()));
  });

  test('non-finite amount is rejected', () async {
    await db.update('vouchers', {'amount': double.infinity});
    await expectLater(
        verify(db), throwsA(isA<CashVoucherIntegrityException>()));
  });

  test('unsupported settlement and offset are not accidentally authorized',
      () async {
    await db
        .update('vouchers', {'voucher_type': 'SETTLEMENT', 'method': 'OFFSET'});
    await expectLater(
        verify(db), throwsA(isA<CashVoucherIntegrityException>()));
  });
}
