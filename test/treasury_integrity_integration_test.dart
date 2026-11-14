import 'dart:async';
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
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration14.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/seed_data.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/posting_and_sales_service.dart';

import 'package:global_enterprise_pharmacy_erp/data/services/shift_and_treasury_service.dart';
import 'package:global_enterprise_pharmacy_erp/providers/treasury_hr_partner_provider.dart';

Future<Database> openSaleDatabase(String path) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      onConfigure: (d) async {
        await d.execute('PRAGMA foreign_keys=ON');
      },
    ),
  );
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
  await SchemaIteration14.upgrade(db);
  return db;
}


class _DelayedTransfer extends ShiftAndTreasuryService {
  final result = Completer<void>();
  int calls = 0;
  @override
  Future<void> transfer({required int branchId, required int fromAccountId,
      required int toAccountId, required double amount, double fee = 0,
      String? walletRefNo, String note = ''}) {
    calls++;
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });
  late Database db;
  late ShiftAndTreasuryService service;
  late PostingAndSalesService posting;
  late int drawer, wallet, party;
  setUp(() async {
    db = await openSaleDatabase(inMemoryDatabasePath);
    final helper = DatabaseHelper.forTesting(db);
    service = ShiftAndTreasuryService(helper: helper);
    posting = PostingAndSalesService(helper: helper);
    drawer = (await db.query('cash_accounts', where: 'code=?', whereArgs: ['CASH-DRAWER'])).single['id'] as int;
    wallet = (await db.query('cash_accounts', where: 'code=?', whereArgs: ['W-JAWALI'])).single['id'] as int;
    // Fixture opening balance; tests assert subsequent posted movements.
    await db.update('cash_accounts', {'current_balance': 1000.0}, where: 'id=?', whereArgs: [drawer]);
    party = await db.insert('parties', {'uuid': 'treasury-party', 'branch_id': 1,
      'created_at': '2026-11-14', 'updated_at': '2026-11-14', 'code': 'TR-P',
      'name_ar': 'طرف اختبار', 'party_type': 'CUSTOMER'});
  });
  tearDown(() => db.close());
  Future<double> balance(int id) async => ((await db.query('cash_accounts', where: 'id=?', whereArgs: [id])).single['current_balance'] as num).toDouble();
  Future<void> transfer({double amount = 100, double fee = 0}) => service.transfer(
    branchId: 1, fromAccountId: drawer, toAccountId: wallet, amount: amount, fee: fee, walletRefNo: 'REF123');
  Future<int> voucher({String type = 'RECEIPT', String method = 'CASH', int? account, int? targetParty, double amount = 100}) => posting.postVoucher(
    branchId: 1, voucherNo: 'ignored', voucherType: type, partyId: targetParty ?? party,
    cashAccountId: account ?? drawer, amount: amount, method: method, description: 'اختبار', walletRefNo: 'REF123');
  Future<void> balancedJournals() async {
    final rows = await db.rawQuery('SELECT journal_entry_id,SUM(dr_amount) d,SUM(cr_amount) c FROM journal_lines GROUP BY journal_entry_id');
    for (final row in rows) expect(row['d'], row['c']);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  }
  test('transfer fee updates both balances and three traceable movements atomically', () async {
    await transfer(amount: 100, fee: 5);
    expect(await balance(drawer), 895);
    expect(await balance(wallet), 100);
    final rows = await db.query('cash_transactions');
    expect(rows, hasLength(3));
    expect(rows.map((r) => r['wallet_ref_no']).toSet(), {'REF123'});
    await balancedJournals();
  });
  test('insufficient transfer including fees leaves no partial records', () async {
    await expectLater(transfer(amount: 1000, fee: 1), throwsStateError);
    expect(await balance(drawer), 1000);
    expect(await balance(wallet), 0);
    expect(await db.query('journal_entries'), isEmpty);
    expect(await db.query('cash_transactions'), isEmpty);
  });
  for (final field in ['branch_id', 'is_deleted']) {
    test('transfer rejects invalid destination $field without mutation', () async {
      if (field == 'branch_id') {
        await db.execute('PRAGMA foreign_keys=OFF');
      }
      await db.update('cash_accounts', {field: field == 'branch_id' ? 2 : 1}, where: 'id=?', whereArgs: [wallet]);
      await expectLater(transfer(), throwsStateError);
      expect(await balance(drawer), 1000);
      expect(await db.query('journal_entries'), isEmpty);
      expect(await db.query('cash_transactions'), isEmpty);
    });
  }
  test('nonfinite transfers and fees are rejected before writes', () async {
    for (final invalid in [double.nan, double.infinity, -1.0]) {
      await expectLater(transfer(amount: invalid), throwsArgumentError);
      await expectLater(transfer(fee: invalid), throwsArgumentError);
    }
    expect(await balance(drawer), 1000);
    expect(await db.query('cash_transactions'), isEmpty);
  });
  test('wallet reconciliation posts positive and negative deltas and is idempotent', () async {
    expect(await service.reconcileWallet(branchId: 1, accountId: wallet, actualBalance: 200), 200);
    expect(await service.reconcileWallet(branchId: 1, accountId: wallet, actualBalance: 150), -50);
    expect(await service.reconcileWallet(branchId: 1, accountId: wallet, actualBalance: 150), 0);
    expect(await balance(wallet), 150);
    expect(await db.query('cash_transactions'), hasLength(2));
    await balancedJournals();
  });
  test('reconciliation rejects drawers, deleted wallets and nonfinite actual balances', () async {
    await expectLater(service.reconcileWallet(branchId: 1, accountId: drawer, actualBalance: 200), throwsStateError);
    await expectLater(service.reconcileWallet(branchId: 1, accountId: wallet, actualBalance: double.nan), throwsArgumentError);
    await db.update('cash_accounts', {'is_deleted': 1}, where: 'id=?', whereArgs: [wallet]);
    await expectLater(service.reconcileWallet(branchId: 1, accountId: wallet, actualBalance: 200), throwsStateError);
    expect(await db.query('journal_entries'), isEmpty);
  });
  test('voucher receipt and payment preserve balance and reject overdraft', () async {
    await voucher(amount: 100);
    await voucher(type: 'PAYMENT', amount: 250);
    expect(await balance(drawer), 850);
    await expectLater(voucher(type: 'PAYMENT', amount: 851), throwsStateError);
    expect(await balance(drawer), 850);
    expect(await db.query('vouchers'), hasLength(2));
    expect(await db.query('cash_transactions'), hasLength(2));
    await balancedJournals();
  });
  test('voucher rejects wrong payment kind, deleted accounts and foreign parties', () async {
    await expectLater(voucher(account: wallet), throwsStateError);
    await db.execute('PRAGMA foreign_keys=OFF');
    await db.update('parties', {'branch_id': 2}, where: 'id=?', whereArgs: [party]);
    await expectLater(voucher(), throwsStateError);
    await db.update('parties', {'branch_id': 1}, where: 'id=?', whereArgs: [party]);
    await db.update('cash_accounts', {'is_deleted': 1}, where: 'id=?', whereArgs: [drawer]);
    await expectLater(voucher(), throwsStateError);
    expect(await db.query('vouchers'), isEmpty);
    expect(await balance(drawer), 1000);
  });
  test('wallet vouchers collect and pay against wallet balance only', () async {
    await voucher(method: 'WALLET', account: wallet, amount: 300);
    await voucher(type: 'PAYMENT', method: 'WALLET', account: wallet, amount: 100);
    expect(await balance(wallet), 200);
    expect(await balance(drawer), 1000);
    await balancedJournals();
  });
  test('shift creation requires a drawer and serializes duplicate requests', () async {
    await expectLater(service.openShift(branchId: 1, userId: 1, drawerAccountId: wallet), throwsStateError);
    final first = service.openShift(branchId: 1, userId: 1, drawerAccountId: drawer, openingCash: 1000);
    final second = service.openShift(branchId: 1, userId: 1, drawerAccountId: drawer, openingCash: 1000);
    final blocked = expectLater(second, throwsStateError);
    await first;
    await blocked;
    expect(await db.query('cashier_shifts'), hasLength(1));
  });
  test('shift rejects malformed denominations and foreign wallet counts', () async {
    final shift = await service.openShift(branchId: 1, userId: 1, drawerAccountId: drawer, openingCash: 1000);
    await expectLater(service.closeShiftBlind(shiftId: shift, denominations: {'NaN': 1}, diffHandling: 'NONE'), throwsArgumentError);
    await expectLater(service.closeShiftBlind(shiftId: shift, denominations: {'1000': 1}, diffHandling: 'NONE', countedWallets: {'999999': 100}), throwsStateError);
    expect((await db.query('cashier_shifts')).single['status'], 'OPEN');
    expect(await db.query('journal_entries'), isEmpty);
  });
  test('expense deducts cash once and rejects an unaffordable second expense', () async {
    final gl = (await db.query('chart_of_accounts', where: 'code=?', whereArgs: ['5201'])).single['id'];
    final category = await db.insert('expense_categories', {'name_ar': 'مصروف اختبار', 'branch_id': 1, 'gl_account_id': gl});
    Future<int> expense(double amount) => service.recordExpense(branchId: 1, categoryId: category,
        cashAccountId: drawer, amount: amount, description: 'اختبار مصروف');
    await expense(100);
    expect(await balance(drawer), 900);
    await expectLater(expense(901), throwsStateError);
    expect(await db.query('expenses'), hasLength(1));
    expect(await db.query('cash_transactions'), hasLength(1));
    await balancedJournals();
  });
  test('provider blocks duplicate transfer and releases lock after failure', () async {
    final delayed = _DelayedTransfer();
    final provider = TreasuryHrPartnerProvider(treasury: delayed);
    Future<int> submit() => provider.transfer(fromAccountId: drawer, toAccountId: wallet, amount: 100);
    final first = submit();
    expect(provider.operationPending, isTrue);
    await expectLater(submit(), throwsStateError);
    expect(delayed.calls, 1);
    final failed = expectLater(first, throwsStateError);
    delayed.result.completeError(StateError('database failure'));
    await failed;
    expect(provider.operationPending, isFalse);
  });
}
