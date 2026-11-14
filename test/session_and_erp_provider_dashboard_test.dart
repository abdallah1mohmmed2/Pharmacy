import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/database_helper.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_builder.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/seed_data.dart';
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
import 'package:global_enterprise_pharmacy_erp/providers/session_and_erp_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('dashboard aggregates are zero-safe when there are no sales or drugs',
      () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 15,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) async {
          await SchemaBuilder.build(database);
          await SchemaIteration12.upgrade(database);
          await SeedData.run(database);
          await SchemaIteration2.upgrade(database);
          await SchemaIteration3.upgrade(database);
          await SchemaIteration4.upgrade(database);
          await SchemaIteration5.upgrade(database);
          await SchemaIteration6.upgrade(database);
          await SchemaIteration7.upgrade(database);
          await SchemaIteration8.upgrade(database);
          await SchemaIteration9.upgrade(database);
          await SchemaIteration10.upgrade(database);
          await SchemaIteration11.upgrade(database);
          await SchemaIteration12.upgrade(database);
        },
      ),
    );

    try {
      final branchId = (await db.query(
        'branches',
        columns: ['id'],
        limit: 1,
      ))
          .single['id'] as int;
      await db.delete('drugs', where: 'branch_id=?', whereArgs: [branchId]);

      final provider = SessionAndErpProvider(
        database: DatabaseHelper.forTesting(db),
      );
      await provider.refresh();

      expect(provider.lastError, isNull);
      expect(provider.dashboard['sales'], 0);
      expect(provider.dashboard['profit'], 0);
      expect(provider.dashboard['invoiceCount'], 0);
      expect(provider.dashboard['drugCount'], 0);
      expect(provider.dashboard['lowStock'], 0);

      // Catalog-only drugs are counted in the encyclopedia, but never
      // as shortages. Historical zero-unit FEFO batches still qualify.
      final now = DateTime.now().toIso8601String();
      Future<int> registerDrug(String code, int stock, int minimum) =>
          db.insert('drugs', {
            'uuid': 'dashboard-stock-' + code,
            'branch_id': branchId,
            'created_at': now,
            'updated_at': now,
            'internal_code': 'DASH-' + code,
            'trade_name_ar': 'دواء ' + code,
            'strips_per_pack': 1,
            'units_per_strip': 10,
            'units_per_pack': 10,
            'stock_total_units': stock,
            'min_stock_units': minimum,
          });
      final catalogOnlyId = await registerDrug('CATALOG', 0, 20);
      final depletedPharmacyId = await registerDrug('PHARMACY', 0, 20);
      final depletedMainStoreId = await registerDrug('STORE', 0, 20);
      final healthyId = await registerDrug('HEALTHY', 20, 10);
      final floorId = (await db.query('warehouses',
          columns: ['id'], where: 'code=?', whereArgs: ['PHARM']))
          .single['id'] as int;
      final mainStoreId = (await db.query('warehouses',
          columns: ['id'], where: 'code=?', whereArgs: ['MAIN']))
          .single['id'] as int;
      Future<void> addBatch(int drugId, int warehouse, int sealedPacks,
          String number) async {
        await db.insert('batches_fefo', {
          'drug_id': drugId,
          'warehouse_id': warehouse,
          'batch_no': number,
          'expiry_date': '2030-12-31',
          'status': sealedPacks == 0 ? 'DEPLETED' : 'ACTIVE',
          'sealed_packs': sealedPacks,
          'loose_units': 0,
          'total_units': sealedPacks * 10,
        });
      }
      await addBatch(depletedPharmacyId, floorId, 0, 'HISTORY-PHARMACY');
      await addBatch(depletedMainStoreId, mainStoreId, 0, 'HISTORY-STORE');
      await addBatch(healthyId, mainStoreId, 2, 'STOCKED-HEALTHY');
      await provider.refresh();
      expect(provider.lastError, isNull);
      expect(provider.dashboard['drugCount'], 4);
      expect(provider.dashboard['lowStock'], 2);
      expect(
        provider.lowStockDrugs.map((row) => row['id']).toSet(),
        {depletedPharmacyId, depletedMainStoreId},
      );
      expect(provider.lowStockDrugs.map((row) => row['id']),
          isNot(contains(catalogOnlyId)));
    } finally {
      await db.close();
    }
  });
}
