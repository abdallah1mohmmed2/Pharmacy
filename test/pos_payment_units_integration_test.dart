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
import 'package:global_enterprise_pharmacy_erp/data/models/drug_model.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/erp_models.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/clinical_and_rx_models.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/posting_and_sales_service.dart';

import 'package:global_enterprise_pharmacy_erp/data/services/rx_and_returns_service.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/purchase_and_bonus_service.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/shift_and_treasury_service.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  late Database db;
  late PostingAndSalesService posting;
  late DrugModel drug;
  late int cashId;
  late int customerId;
  setUp(() async {
    db = await openSaleDatabase(inMemoryDatabasePath);
    posting = PostingAndSalesService(helper: DatabaseHelper.forTesting(db));
    cashId = (await db.query(
      'cash_accounts',
      where: 'code=?',
      whereArgs: ['CASH-DRAWER'],
    ))
        .single['id'] as int;
    customerId = await db.insert('parties', {
      'uuid': 'pos-customer',
      'branch_id': 1,
      'created_at': '2026-11-14',
      'updated_at': '2026-11-14',
      'party_type': 'CUSTOMER',
      'code': 'POS-C',
      'name_ar': 'عميل اختبار',
    });
    final id = await db.insert('drugs', {
      'uuid': 'pos-drug',
      'branch_id': 1,
      'created_at': '2026-11-14',
      'updated_at': '2026-11-14',
      'internal_code': 'POS-D',
      'trade_name_ar': 'دواء اختبار',
      'units_per_pack': 20,
      'strips_per_pack': 2,
      'units_per_strip': 10,
      'sell_price_pack': 1000.0,
      'sell_price_strip': 600.0,
      'sell_price_unit': 75.0,
      'stock_total_units': 200,
    });
    drug = DrugModel.fromMap(
      (await db.query('drugs', where: 'id=?', whereArgs: [id])).single,
    );
    final wh = await db.insert('warehouses', {
      'uuid': 'pos-wh',
      'branch_id': 1,
      'code': 'POS-W',
      'name_ar': 'اختبار',
      'wh_type': 'MAIN_STORE',
      'created_at': '2026-11-14',
    });
    await db.insert('batches_fefo', {
      'uuid': 'pos-batch',
      'drug_id': id,
      'warehouse_id': wh,
      'batch_no': 'POS-B',
      'expiry_date': '2030-12-31',
      'sealed_packs': 10,
      'loose_units': 0,
      'total_units': 200,
      'unit_cost': 10.0,
      'pack_cost': 200.0,
    });
  });
  tearDown(() async {
    await db.close();
  });
  Future<int> sale(
    String unit,
    double paid, {
    String type = 'CASH',
    double discount = 0,
  }) =>
      posting.postSale(
        branchId: 1,
        cashierUserId: 1,
        items: [CartItemModel(drug: drug, sellUnit: unit)],
        saleType: type,
        payments: paid == 0
            ? []
            : [
                (
                  cashAccountId: cashId,
                  amount: paid,
                  method: 'CASH',
                  walletRef: null,
                ),
              ],
        customerPartyId: type == 'CASH' ? 0 : customerId,
        discountAmount: discount,
        clinicalVerdict: ClinicalVerdict(const []),
      );
  for (final example in [
    ('PACK', 1000.0, 20),
    ('STRIP', 600.0, 10),
    ('UNIT', 75.0, 1),
  ]) {
    test(
      'selected ${example.$1} uses its independent price and FEFO quantity',
      () async {
        final id = await sale(example.$1, example.$2 - 5, discount: 5);
        final invoice = (await db.query(
          'sales_invoices',
          where: 'id=?',
          whereArgs: [id],
        ))
            .single;
        final line = (await db.query(
          'sales_invoice_items',
          where: 'invoice_id=?',
          whereArgs: [id],
        ))
            .single;
        expect(invoice['subtotal'], example.$2);
        expect(invoice['discount_amount'], 5);
        expect(invoice['net_total'], example.$2 - 5);
        expect(invoice['remaining_alayh'], 0);
        expect(line['unit_price_sell_unit'], example.$2);
        expect(line['qty_units'], example.$3);
        expect(
          (await db.query('batches_fefo')).single['total_units'],
          200 - example.$3,
        );
        final sums = (await db.rawQuery(
          'SELECT SUM(dr_amount) d,SUM(cr_amount) c FROM journal_lines',
        ))
            .single;
        expect(sums['d'], sums['c']);
      },
    );
  }
  test(
    'mixed payment records only collected cash and remaining customer debt',
    () async {
      final id = await sale('PACK', 400, type: 'MIXED', discount: 100);
      final invoice = (await db.query(
        'sales_invoices',
        where: 'id=?',
        whereArgs: [id],
      ))
          .single;
      expect(invoice['net_total'], 900);
      expect(invoice['paid_total'], 400);
      expect(invoice['remaining_alayh'], 500);
      expect((await db.query('lah_alayh_ledger')).single['alayh_amount'], 500);
      expect((await db.query('sales_payments')).single['amount'], 400);
    },
  );
  test('credit sale creates debt without a cash payment', () async {
    final id = await sale('UNIT', 0, type: 'CREDIT');
    expect(
      (await db.query(
        'sales_invoices',
        where: 'id=?',
        whereArgs: [id],
      ))
          .single['remaining_alayh'],
      75,
    );
    expect(await db.query('sales_payments'), isEmpty);
  });
  test('overpayment rolls back invoice, inventory and cash', () async {
    await expectLater(sale('PACK', 1001), throwsStateError);
    expect(await db.query('sales_invoices'), isEmpty);
    expect(await db.query('stock_movements'), isEmpty);
    expect(await db.query('sales_payments'), isEmpty);
    expect((await db.query('batches_fefo')).single['total_units'], 200);
  });
  test('sales refund rejects an empty drawer and rolls back returned stock',
      () async {
    final id = await sale('UNIT', 75);
    final itemId = (await db.query('sales_invoice_items',
            where: 'invoice_id=?', whereArgs: [id]))
        .single['id'] as int;
    final wallet = (await db
            .query('cash_accounts', where: 'code=?', whereArgs: ['W-JAWALI']))
        .single['id'] as int;
    final treasury =
        ShiftAndTreasuryService(helper: DatabaseHelper.forTesting(db));
    await treasury.transfer(
        branchId: 1, fromAccountId: cashId, toAccountId: wallet, amount: 75);
    final returns = RxAndReturnsService(helper: DatabaseHelper.forTesting(db));
    Future<int> refund() => returns.createSalesReturn(
        invoiceId: id,
        invoiceItemId: itemId,
        qtyUnits: 1,
        refundAmount: 75,
        reasonCode: 'OTHER',
        reasonText: 'اختبار',
        refundMethod: 'CASH',
        disposition: 'RESTOCK',
        approvedBy: 1,
        cashAccountId: cashId);
    await expectLater(refund(), throwsStateError);
    expect(await db.query('sales_returns'), isEmpty);
    expect((await db.query('batches_fefo')).single['total_units'], 199);
    expect(
        (await db.query('sales_invoice_item_batches'))
            .single['returned_qty_units'],
        0);
    await treasury.transfer(
        branchId: 1, fromAccountId: wallet, toAccountId: cashId, amount: 75);
    await refund();
    expect((await db.query('batches_fefo')).single['total_units'], 200);
    expect(
        (await db.query('cash_accounts', where: 'id=?', whereArgs: [cashId]))
            .single['current_balance'],
        0);
  });
  test(
      'purchase payment cannot overdraft cash or leave partially received stock',
      () async {
    final supplier = await db.insert('parties', {
      'uuid': 'purchase-supplier',
      'branch_id': 1,
      'created_at': '2026-11-14',
      'updated_at': '2026-11-14',
      'code': 'SUP-TEST',
      'name_ar': 'مورد اختبار',
      'party_type': 'SUPPLIER'
    });
    final wh =
        (await db.query('warehouses', where: 'code=?', whereArgs: ['POS-W']))
            .single['id'] as int;
    final purchase =
        PurchaseAndBonusService(helper: DatabaseHelper.forTesting(db));
    Future<int> buy() => purchase.postInvoice(
            branchId: 1,
            supplierPartyId: supplier,
            warehouseId: wh,
            invoiceNo: 'BUY-TEST',
            paymentType: 'CASH',
            paidTotal: 100,
            cashAccountId: cashId,
            items: [
              PurchaseLineInput(
                  drugId: drug.id!,
                  batchNo: 'NEW-BUY',
                  expiryDate: '2030-12-31',
                  warehouseId: wh,
                  qtyPacksPaid: 1,
                  bonusPacks: 0,
                  packPrice: 100)
            ]);
    await expectLater(buy(), throwsStateError);
    expect(await db.query('purchase_invoices'), isEmpty);
    expect(await db.query('batches_fefo'), hasLength(1));
    await posting.postVoucher(
        branchId: 1,
        voucherNo: 'FUND',
        voucherType: 'RECEIPT',
        partyId: customerId,
        cashAccountId: cashId,
        amount: 100,
        method: 'CASH',
        description: 'تمويل الاختبار');
    await buy();
    expect(await db.query('purchase_invoices'), hasLength(1));
    expect(
        (await db.query('cash_accounts', where: 'id=?', whereArgs: [cashId]))
            .single['current_balance'],
        0);
    expect(
        (await db.query('drugs', where: 'id=?', whereArgs: [drug.id]))
            .single['stock_total_units'],
        220);
  });
}
