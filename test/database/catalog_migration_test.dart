import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('catalog migration preserves existing operational drug data', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 12,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) async {
          await SchemaBuilder.build(database);
          await SeedData.run(database);
          await SchemaIteration2.upgrade(database);
          await SchemaIteration3.upgrade(database);
          await SchemaIteration4.upgrade(database);
          await SchemaIteration5.upgrade(database);
          await SchemaIteration6.upgrade(database);
          await SchemaIteration7.upgrade(database);
          await SchemaIteration8.upgrade(database);
          await SchemaIteration9.upgrade(database);
        },
      ),
    );

    try {
      final branch = (await db.query('branches', columns: ['id'], limit: 1))
          .single['id'] as int;
      final now = DateTime.utc(2026, 11, 8).toIso8601String();
      final drugId = await db.insert('drugs', {
        'uuid': 'catalog-migration-fixture-drug',
        'branch_id': branch,
        'created_at': now,
        'updated_at': now,
        'internal_code': 'MIGRATION-KEEP-001',
        'trade_name_ar': 'دواء اختبار الترحيل',
        'scientific_name': 'Migration fixture',
        'cost_price_pack': 125.5,
        'sell_price_pack': 180.0,
        'stock_total_units': 0,
      });

      await SchemaIteration10.upgrade(db);
      await SchemaIteration10.upgrade(db);

      final drug = (await db.query(
        'drugs',
        where: 'id=?',
        whereArgs: [drugId],
      )).single;
      expect(drug['internal_code'], 'MIGRATION-KEEP-001');
      expect(drug['trade_name_ar'], 'دواء اختبار الترحيل');
      expect(drug['cost_price_pack'], 125.5);
      expect(drug['sell_price_pack'], 180.0);
      expect(drug['stock_total_units'], 0);
      expect(drug['catalog_uuid'], isNull);
      expect(drug['catalog_version'], isNull);

      expect(
        await db.rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
      );
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name IN ('catalog_cache','catalog_sync_state')",
        ),
        hasLength(2),
      );
    } finally {
      await db.close();
    }
  });
}
