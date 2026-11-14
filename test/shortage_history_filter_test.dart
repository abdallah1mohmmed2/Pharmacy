import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/database_helper.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/purchase_and_bonus_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Database db;
  late PurchaseAndBonusService service;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    // Real query dependencies, with a deliberately small, deterministic
    // SQLite schema. This catches regressions in the executed SQL itself.
    await db.execute('''
      CREATE TABLE drugs (
        id INTEGER PRIMARY KEY,
        branch_id INTEGER NOT NULL,
        trade_name_ar TEXT NOT NULL,
        stock_total_units INTEGER NOT NULL,
        min_stock_units INTEGER NOT NULL,
        units_per_pack INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE warehouses (
        id INTEGER PRIMARY KEY,
        branch_id INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE batches_fefo (
        id INTEGER PRIMARY KEY,
        drug_id INTEGER NOT NULL,
        warehouse_id INTEGER NOT NULL,
        total_units INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE stock_movements (
        id INTEGER PRIMARY KEY,
        drug_id INTEGER NOT NULL,
        qty_units INTEGER NOT NULL,
        movement_type TEXT NOT NULL,
        movement_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE purchase_invoices (
        id INTEGER PRIMARY KEY, supplier_party_id INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE purchase_invoice_items (
        id INTEGER PRIMARY KEY,
        invoice_id INTEGER,
        drug_id INTEGER,
        effective_pack_cost REAL
      )
    ''');
    await db.execute('''
      CREATE TABLE parties (id INTEGER PRIMARY KEY, name_ar TEXT NOT NULL)
    ''');
    await db.insert('warehouses', {'id': 1, 'branch_id': 1});
    await db.insert('warehouses', {'id': 2, 'branch_id': 1});
    await db.insert('warehouses', {'id': 3, 'branch_id': 2});
    service = PurchaseAndBonusService(helper: DatabaseHelper.forTesting(db));
  });

  tearDown(() async => db.close());

  Future<void> addDrug(
    int id, {
    int branch = 1,
    int current = 0,
    int minimum = 10,
    int active = 1,
    int deleted = 0,
  }) async {
    await db.insert('drugs', {
      'id': id,
      'branch_id': branch,
      'trade_name_ar': 'دواء رقم $id',
      'stock_total_units': current,
      'min_stock_units': minimum,
      'units_per_pack': 10,
      'is_deleted': deleted,
      'is_active': active,
    });
  }

  Future<void> addHistoricalBatch(int drugId, int warehouseId,
      {int total = 0}) async {
    await db.insert('batches_fefo', {
      'drug_id': drugId,
      'warehouse_id': warehouseId,
      'total_units': total,
    });
  }

  test('catalog-only medicine is not a shortage even at or below minimum',
      () async {
    await addDrug(1, minimum: 50); // Imported catalog, never stocked.
    await addDrug(2, minimum: 0); // No threshold, never stocked.
    final shortages = await service.shortages(branchId: 1);
    expect(shortages, isEmpty);
  });

  test('previously stocked and now depleted in the pharmacy stays shortage',
      () async {
    await addDrug(1, minimum: 20, current: 0);
    await addHistoricalBatch(1, 1, total: 0);
    final shortages = await service.shortages(branchId: 1);
    expect(shortages, hasLength(1));
    expect(shortages.single['drug_id'], 1);
    expect(shortages.single['current_units'], 0);
    expect(shortages.single['minimum_units'], 20);
    expect(shortages.single['suggested_packs'], 4);
  });

  test('prior stock in another warehouse of the same branch qualifies',
      () async {
    await addDrug(1, minimum: 30, current: 12);
    await addHistoricalBatch(1, 2, total: 12);
    final shortages = await service.shortages(branchId: 1);
    expect(shortages.map((s) => s['drug_id']), [1]);
    expect(shortages.single['current_units'], 12);
  });

  test('another branch warehouse does not count as pharmacy history',
      () async {
    await addDrug(1, minimum: 20);
    await addHistoricalBatch(1, 3);
    final shortages = await service.shortages(branchId: 1);
    expect(shortages, isEmpty);
  });

  test('previously stocked medicine is not shortage when balance is enough',
      () async {
    await addDrug(1, current: 55, minimum: 20);
    await addHistoricalBatch(1, 1, total: 55);
    expect(await service.shortages(branchId: 1), isEmpty);
  });

  test('inactive, deleted and other-branch drugs are excluded',
      () async {
    await addDrug(1, active: 0);
    await addDrug(2, deleted: 1);
    await addDrug(3, branch: 2);
    await addHistoricalBatch(1, 1);
    await addHistoricalBatch(2, 1);
    await addHistoricalBatch(3, 3);
    expect(await service.shortages(branchId: 1), isEmpty);
  });

  test('supplier invoice metadata alone is not evidence of received stock',
      () async {
    await addDrug(1, minimum: 30);
    await db.insert('parties', {'id': 1, 'name_ar': 'المورد'});
    await db.insert('purchase_invoices', {'id': 1, 'supplier_party_id': 1});
    await db.insert('purchase_invoice_items', {
      'id': 1,
      'invoice_id': 1,
      'drug_id': 1,
      'effective_pack_cost': 50.0,
    });
    // No batch ever received. An order or supplier link is not stock.
    expect(await service.shortages(branchId: 1), isEmpty);
  });

  test('zero-threshold drug qualifies only if it was stocked before',
      () async {
    await addDrug(1, minimum: 0, current: 0);
    await addDrug(2, minimum: 0, current: 0);
    await addHistoricalBatch(1, 1);
    final shortages = await service.shortages(branchId: 1);
    expect(shortages.map((s) => s['drug_id']), [1]);
  });

  test('the same historical drug appears once with multiple batches',
      () async {
    await addDrug(1, minimum: 20);
    await addHistoricalBatch(1, 1);
    await addHistoricalBatch(1, 2);
    final shortages = await service.shortages(branchId: 1);
    expect(shortages, hasLength(1));
  });

  test('branch 2 sees only drugs received in its own warehouses',
      () async {
    await addDrug(1, branch: 1);
    await addDrug(2, branch: 2);
    await addHistoricalBatch(1, 1);
    await addHistoricalBatch(2, 3);
    final rows = await service.shortages(branchId: 2);
    expect(rows.map((s) => s['drug_id']), [2]);
  });
}
