import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/database_helper.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/drug_model.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/clinical_and_rx_models.dart';
import 'package:global_enterprise_pharmacy_erp/providers/pos_and_drugs_provider.dart';
import 'treasury_integrity_integration_test.dart' show openSaleDatabase;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  late Database db;
  late PosAndDrugsProvider pos;
  late int floor, mainStore;
  int sequence = 0;
  setUp(() async {
    db = await openSaleDatabase(inMemoryDatabasePath);
    pos = PosAndDrugsProvider(database: DatabaseHelper.forTesting(db));
    floor =
        (await db.query('warehouses', where: 'code=?', whereArgs: ['PHARM']))
            .single['id'] as int;
    mainStore =
        (await db.query('warehouses', where: 'code=?', whereArgs: ['MAIN']))
            .single['id'] as int;
  });
  tearDown(() async {
    pos.dispose();
    await db.close();
  });
  Future<DrugModel> drug(String name) async {
    final id = await db.insert('drugs', {
      'uuid': 'scope-drug-${sequence++}',
      'branch_id': 1,
      'created_at': '2026-11-14',
      'updated_at': '2026-11-14',
      'internal_code': 'SCOPE-${sequence++}',
      'trade_name_ar': name,
      'units_per_pack': 1,
      'strips_per_pack': 1,
      'units_per_strip': 1,
      'sell_price_unit': 100.0,
      'sell_price_pack': 100.0,
      'stock_total_units': 0
    });
    return DrugModel.fromMap(
        (await db.query('drugs', where: 'id=?', whereArgs: [id])).single);
  }

  Future<int> stock(DrugModel drug, int warehouse, int units,
      {String expiry = '2030-12-31', String status = 'ACTIVE'}) async {
    final id = await db.insert('batches_fefo', {
      'uuid': 'scope-b-${sequence++}',
      'drug_id': drug.id,
      'warehouse_id': warehouse,
      'batch_no': 'SCOPE-B-${sequence++}',
      'expiry_date': expiry,
      'sealed_packs': units,
      'loose_units': 0,
      'total_units': units,
      'unit_cost': 10.0,
      'pack_cost': 10.0,
      'status': status
    });
    await db.rawUpdate(
        'UPDATE drugs SET stock_total_units=stock_total_units+? WHERE id=?',
        [units, drug.id]);
    return id;
  }

  Future<int> checkout() async => pos.checkout(
      cashierId: 1,
      saleType: 'CASH',
      payments: [
        (
          cashAccountId: await pos.defaultCashAccountId(),
          amount: pos.total,
          method: 'CASH',
          walletRef: null
        )
      ],
      clinicalVerdict: ClinicalVerdict(const []));

  test(
      'default pharmacy catalog excludes global-only, other-store and unfit stock',
      () async {
    final available = await drug('دواء الصيدلية');
    final elsewhere = await drug('دواء المخزن');
    await drug('دليل فقط');
    final expired = await drug('منتهي');
    final quarantined = await drug('محجور');
    await stock(available, floor, 3);
    await stock(elsewhere, mainStore, 20);
    await stock(expired, floor, 5, expiry: '2000-01-01');
    await stock(quarantined, floor, 5, status: 'QUARANTINED');
    await pos.loadSaleWarehouses();
    expect(pos.saleError, isNull);
    expect(pos.saleWarehouseId, floor);
    expect(pos.saleDrugs.map((d) => d.id), [available.id]);
    expect(pos.saleDrugs.single.stockTotalUnits, 3);
    await pos.loadSaleDrugs('المخزن');
    expect(pos.saleDrugs, isEmpty);
    await pos.selectSaleWarehouse(mainStore);
    expect(pos.saleError, isNull);
    expect(pos.saleDrugs.map((d) => d.id), [elsewhere.id]);
    expect(pos.saleDrugs.single.stockTotalUnits, 20);
    // General encyclopedia state remains independent of the sales selection.
    await pos.searchDrugs('دليل');
    expect(pos.drugs.single.tradeNameAr, 'دليل فقط');
    expect(pos.saleDrugs.single.id, elsewhere.id);
  });
  test(
      'FEFO deducts exclusively from selected pharmacy and never borrows another store',
      () async {
    final shared = await drug('دواء مشترك');
    final floorBatch = await stock(shared, floor, 2);
    final storeBatch =
        await stock(shared, mainStore, 100, expiry: '2029-01-01');
    await pos.loadSaleWarehouses();
    pos.addDrug(pos.saleDrugs.single, unit: 'UNIT');
    await checkout();
    expect(
        (await db.query('batches_fefo', where: 'id=?', whereArgs: [floorBatch]))
            .single['total_units'],
        1);
    expect(
        (await db.query('batches_fefo', where: 'id=?', whereArgs: [storeBatch]))
            .single['total_units'],
        100);
    pos.addDrug(shared, unit: 'UNIT');
    pos.changeQuantity(pos.cart.single, 2);
    await expectLater(checkout(), throwsStateError);
    expect(await db.query('sales_invoices'), hasLength(1));
    expect(
        (await db.query('batches_fefo', where: 'id=?', whereArgs: [floorBatch]))
            .single['total_units'],
        1);
    expect(
        (await db.query('batches_fefo', where: 'id=?', whereArgs: [storeBatch]))
            .single['total_units'],
        100);
    expect(pos.cart, hasLength(1));
  });
  test(
      'explicit main-store selection can sell its stock while pharmacy stays empty',
      () async {
    final medicine = await drug('دواء في المخزن فقط');
    final batch = await stock(medicine, mainStore, 3);
    await pos.loadSaleWarehouses();
    expect(pos.saleDrugs, isEmpty);
    await pos.selectSaleWarehouse(mainStore);
    pos.addDrug(pos.saleDrugs.single, unit: 'UNIT');
    await checkout();
    expect(
        (await db.query('batches_fefo', where: 'id=?', whereArgs: [batch]))
            .single['total_units'],
        2);
    expect(
        (await db.query('stock_movements', where: "movement_type='SALE_OUT'"))
            .single['warehouse_id'],
        mainStore);
  });
  test(
      'warehouse follows invoice tabs and cannot change under an existing cart',
      () async {
    final medicine = await drug('دواء');
    await stock(medicine, floor, 3);
    await stock(medicine, mainStore, 9);
    await pos.loadSaleWarehouses();
    pos.addDrug(pos.saleDrugs.single);
    await expectLater(pos.selectSaleWarehouse(mainStore), throwsStateError);
    expect(pos.createTab(), isTrue);
    await pos.selectSaleWarehouse(mainStore);
    expect(pos.saleWarehouseId, mainStore);
    expect(pos.saleDrugs.single.stockTotalUnits, 9);
    pos.selectTab(0);
    await pos.loadSaleDrugs();
    expect(pos.saleWarehouseId, floor);
    expect(pos.saleDrugs.single.stockTotalUnits, 3);
  });
  test('27k global catalog does not leak into bounded pharmacy results',
      () async {
    for (var offset = 0; offset < 27000; offset += 900) {
      await db.rawInsert(
          "WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM seq WHERE n<900) "
          "INSERT INTO drugs(id,uuid,branch_id,created_at,updated_at,internal_code,trade_name_ar) "
          "SELECT n+?, 'bulk-'||(n+?),1,'2026-11-14','2026-11-14','BULK-'||(n+?),'دليل عام '||(n+?) FROM seq",
          [50000 + offset, offset, offset, offset]);
    }
    for (var i = 0; i < 105; i++) {
      await stock(await drug('صيدلية $i'), floor, 1);
    }
    await pos.loadSaleWarehouses();
    expect(pos.saleError, isNull);
    expect(pos.saleDrugs, hasLength(100));
    await pos.loadSaleDrugs('دليل عام');
    expect(pos.saleDrugs, isEmpty);
    await pos.loadSaleDrugs('صيدلية');
    expect(pos.saleDrugs, hasLength(100));
  });
  test('default cash is active local drawer, then safe, never wallet',
      () async {
    final drawer = await pos.defaultCashAccountId();
    expect(
        (await db.query('cash_accounts', where: 'id=?', whereArgs: [drawer]))
            .single['code'],
        'CASH-DRAWER');
    await db.update('cash_accounts', {'is_deleted': 1},
        where: 'id=?', whereArgs: [drawer]);
    final safe = await pos.defaultCashAccountId();
    expect(
        (await db.query('cash_accounts', where: 'id=?', whereArgs: [safe]))
            .single['account_kind'],
        'MAIN_SAFE');
    await db.update('cash_accounts', {'is_deleted': 1},
        where: "account_kind='MAIN_SAFE'");
    await expectLater(pos.defaultCashAccountId(), throwsStateError);
  });
  test('missing pharmacy does not silently select a different warehouse',
      () async {
    await db.update('warehouses', {'is_sellable': 0},
        where: 'id=?', whereArgs: [floor]);
    await pos.loadSaleWarehouses();
    expect(pos.saleWarehouseId, isNull);
    expect(pos.saleDrugs, isEmpty);
    await pos.selectSaleWarehouse(mainStore);
    expect(pos.saleWarehouseId, mainStore);
  });
}
