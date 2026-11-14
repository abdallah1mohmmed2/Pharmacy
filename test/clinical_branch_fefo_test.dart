import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/database_helper.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/fefo_allocator_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Database db;
  late FefoAllocator allocator;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    for (final sql in <String>[
      '''CREATE TABLE drugs (
        id INTEGER PRIMARY KEY, branch_id INTEGER, units_per_pack INTEGER,
        stock_total_units INTEGER, updated_at TEXT)''',
      '''CREATE TABLE warehouses (
        id INTEGER PRIMARY KEY, branch_id INTEGER,
        is_sellable INTEGER, wh_type TEXT)''',
      '''CREATE TABLE batches_fefo (
        id INTEGER PRIMARY KEY, drug_id INTEGER, warehouse_id INTEGER,
        status TEXT, expiry_date TEXT, total_units INTEGER,
        sealed_packs INTEGER, loose_units INTEGER, unit_cost REAL)''',
      '''CREATE TABLE stock_movements (
        id INTEGER PRIMARY KEY, drug_id INTEGER, batch_id INTEGER,
        warehouse_id INTEGER, movement_type TEXT, qty_units INTEGER,
        unit_cost REAL, unit_price REAL, balance_after_units INTEGER,
        movement_at TEXT, doc_type TEXT, doc_id INTEGER, note TEXT)''',
      '''CREATE TABLE sales_invoice_item_batches (
        id INTEGER PRIMARY KEY, invoice_item_id INTEGER, batch_id INTEGER,
        qty_units INTEGER, unit_cost REAL)''',
    ]) {
      await db.execute(sql);
    }
    await db.insert('drugs', {
      'id': 11,
      'branch_id': 1,
      'units_per_pack': 1,
      'stock_total_units': 5,
    });
    await db.insert('warehouses', {
      'id': 1, 'branch_id': 1, 'is_sellable': 1, 'wh_type': 'PHARMACY_FLOOR',
    });
    await db.insert('warehouses', {
      'id': 2, 'branch_id': 2, 'is_sellable': 1, 'wh_type': 'PHARMACY_FLOOR',
    });
    for (final batch in [
      {'id': 101, 'warehouse_id': 1, 'total_units': 5},
      {'id': 202, 'warehouse_id': 2, 'total_units': 90},
    ]) {
      await db.insert('batches_fefo', {
        ...batch,
        'drug_id': 11,
        'status': 'ACTIVE',
        'expiry_date': '2035-01-01',
        'sealed_packs': batch['total_units'],
        'loose_units': 0,
        'unit_cost': 1.0,
      });
    }
    allocator = FefoAllocator(helper: DatabaseHelper.forTesting(db));
  });
  tearDown(() async => db.close());

  test('branch-limited prescription cannot use another branch stock', () async {
    await expectLater(
      db.transaction((txn) => allocator.allocateAndApply(
        txn: txn,
        drugId: 11,
        needUnits: 7,
        unitsPerPack: 1,
        invoiceItemId: 1,
        branchId: 1,
        docType: 'PRESCRIPTION',
        docId: 1,
      )),
      throwsA(isA<StateError>()),
    );
    expect((await db.query('batches_fefo', where: 'id=101')).single['total_units'], 5);
    expect((await db.query('batches_fefo', where: 'id=202')).single['total_units'], 90);
    expect((await db.query('drugs', where: 'id=11')).single['stock_total_units'], 5);
    expect(await db.query('stock_movements'), isEmpty);
  });

  test('branch-limited prescription only debits its own batch', () async {
    await db.transaction((txn) => allocator.allocateAndApply(
      txn: txn,
      drugId: 11,
      needUnits: 5,
      unitsPerPack: 1,
      invoiceItemId: 1,
      branchId: 1,
      docType: 'PRESCRIPTION',
      docId: 1,
    ));
    expect((await db.query('batches_fefo', where: 'id=101')).single['total_units'], 0);
    expect((await db.query('batches_fefo', where: 'id=202')).single['total_units'], 90);
    expect((await db.query('drugs', where: 'id=11')).single['stock_total_units'], 0);
    final sales = await db.query('stock_movements',
        where: "movement_type='SALE_OUT'");
    expect(sales, hasLength(1));
    expect(sales.single['warehouse_id'], 1);
    expect(sales.single['qty_units'], -5);
  });
}
