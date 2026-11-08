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

  test('fresh database has required structure but no demo business data',
      () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 13,
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
          await SchemaIteration10.upgrade(database);
        },
      ),
    );

    try {
      final requiredTables = [
        'drugs',
        'parties',
        'sales_invoices',
        'purchase_invoices',
        'batches_fefo',
        'stock_movements',
        'patients',
        'prescriptions',
        'insurance_companies',
        'employees',
        'partners',
        'expenses',
        'cashier_shifts',
        'journal_entries',
        'lah_alayh_ledger',
        'catalog_cache',
        'catalog_sync_state',
      ];
      for (final table in requiredTables) {
        final rows = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          [table],
        );
        expect(rows, hasLength(1), reason: 'Missing required table $table');
      }

      final counts = <String, int>{};
      for (final table in [
        'drugs',
        'parties',
        'sales_invoices',
        'purchase_invoices',
        'batches_fefo',
        'stock_movements',
        'patients',
        'prescriptions',
        'insurance_companies',
        'employees',
        'partners',
        'expenses',
        'cashier_shifts',
        'journal_entries',
        'lah_alayh_ledger',
      ]) {
        counts[table] = (await db
            .rawQuery('SELECT COUNT(*) AS count FROM $table')
            .then((rows) => rows.first['count'] as int));
      }
      for (final entry in counts.entries) {
        expect(entry.value, 0,
            reason: 'Unexpected demo/business rows in ${entry.key}');
      }

      expect(await db.rawQuery('SELECT id FROM warehouses'), hasLength(6));
      expect(await db.rawQuery('SELECT id FROM shelf_locations'), hasLength(6));
      expect(await db.rawQuery('SELECT id FROM users'), hasLength(1));
      expect(await db.rawQuery('SELECT id FROM chart_of_accounts'),
          hasLength(greaterThanOrEqualTo(30)));
      expect(await db.rawQuery('SELECT id FROM cash_accounts'), hasLength(7));
      expect(await db.rawQuery('SELECT setting_no FROM system_settings'),
          hasLength(35));

      // Re-running the cleanup migration must remain safe and idempotent.
      await SchemaIteration9.upgrade(db);
      await SchemaIteration10.upgrade(db);
      expect(await db.rawQuery('SELECT id FROM drugs'), isEmpty);
      expect(await db.rawQuery('SELECT id FROM batches_fefo'), isEmpty);
      expect(
          await db.rawQuery('SELECT catalog_uuid FROM catalog_cache'), isEmpty);
      final drugColumns = await db.rawQuery('PRAGMA table_info(drugs)');
      expect(drugColumns.any((row) => row['name'] == 'catalog_uuid'), isTrue);
      expect(
          drugColumns.any((row) => row['name'] == 'catalog_version'), isTrue);
    } finally {
      await db.close();
    }
  });
}
