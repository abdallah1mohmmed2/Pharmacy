import 'dart:convert';
import 'dart:io';
import 'package:global_enterprise_pharmacy_erp/data/services/sync_table_policy.dart';
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
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration11.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration12.dart';

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
      // Cross-check the source inventory against the actual v15 database.
      final classification = jsonDecode(
        File('docs/SYNC_SCHEMA_CLASSIFICATION.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final inventory = classification['objects'] as Map<String, dynamic>;
      expect(await db.getVersion(), classification['schema_version']);
      final schemaObjects = await db.rawQuery(
        "SELECT name,type FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%'",
      );
      final actualNames = schemaObjects.map((row) => row['name'] as String).toSet();
      expect(actualNames.difference(inventory.keys.toSet()), isEmpty,
          reason: 'Runtime objects need an explicit sync classification');
      final requiredNames = inventory.entries
          .where((entry) => (entry.value as Map)['lifecycle'] == 'schema')
          .map((entry) => entry.key).toSet();
      expect(requiredNames.difference(actualNames), isEmpty,
          reason: 'Schema inventory claims objects missing from a fresh database');
      final allowedNames = inventory.entries
          .where((entry) => (entry.value as Map)['sync_allowed'] == true)
          .map((entry) => entry.key).toSet();
      expect(allowedNames, SyncTablePolicy.outboundTables);
      expect(allowedNames, SyncTablePolicy.inboundTables);
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
        'tenants',
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
      final tenantBranch = await db.rawQuery('''
        SELECT t.uuid AS tenant_uuid, b.tenant_uuid AS branch_tenant_uuid
        FROM tenants t JOIN branches b ON b.tenant_uuid=t.uuid
      ''');
      expect(tenantBranch, hasLength(1));
      expect(tenantBranch.single['tenant_uuid'], 'tenant-main');
      expect(tenantBranch.single['branch_tenant_uuid'], 'tenant-main');

      // Re-running the cleanup migration must remain safe and idempotent.
      await SchemaIteration9.upgrade(db);
      await SchemaIteration10.upgrade(db);
      await SchemaIteration11.upgrade(db);
      await SchemaIteration12.upgrade(db);
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
  test('version 14 database upgrades its existing branch into the first tenant',
      () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 14,
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
          await SchemaIteration11.upgrade(database);
        },
      ),
    );

    try {
      final before = (await db.query('branches')).single;
      expect(before['uuid'], 'branch-main');
      expect(before.containsKey('tenant_uuid'), isFalse);

      await SchemaIteration12.upgrade(db);
      await SchemaIteration12.upgrade(db);

      final after = (await db.query('branches')).single;
      expect(after['uuid'], before['uuid']);
      expect(after['name_ar'], before['name_ar']);
      expect(after['tenant_uuid'], 'tenant-main');
      expect(await db.query('tenants'), hasLength(1));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      await db.close();
    }
  });
}
