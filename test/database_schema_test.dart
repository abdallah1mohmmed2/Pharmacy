import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_builder.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration2.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration3.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/seed_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('creates the ERP and Iteration 2 inventory schemas with valid seed data',
      () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 5,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
          await database.execute('PRAGMA journal_mode = WAL');
          await database.execute('PRAGMA synchronous = NORMAL');
          await database.execute('PRAGMA busy_timeout = 5000');
          await database.execute('PRAGMA temp_store = MEMORY');
        },
        onCreate: (database, version) async {
          await SchemaBuilder.build(database);
          await SeedData.run(database);
          await SchemaIteration2.upgrade(database);
          await SchemaIteration3.upgrade(database);
        },
      ),
    );
    try {
      final drugs = (await db.rawQuery(
        'SELECT COUNT(*) AS c FROM drugs',
      )).first['c'] as int;
      final settings = (await db.rawQuery(
        'SELECT COUNT(*) AS c FROM system_settings',
      )).first['c'] as int;
      final accounts = (await db.rawQuery(
        'SELECT COUNT(*) AS c FROM chart_of_accounts',
      )).first['c'] as int;
      final wallets = (await db.rawQuery(
        "SELECT COUNT(*) AS c FROM cash_accounts WHERE account_kind='WALLET'",
      )).first['c'] as int;
      final openingJournals = (await db.rawQuery(
        "SELECT COUNT(*) AS c FROM journal_entries WHERE source_type='OPENING'",
      )).first['c'] as int;
      final incompleteDrugs = (await db.rawQuery(
        'SELECT COUNT(*) AS c FROM drugs WHERE completeness_pct < 100',
      )).first['c'] as int;
      final unbalancedJournals = await db.rawQuery(
        'SELECT je.id FROM journal_entries je '
        'JOIN journal_lines jl ON jl.journal_entry_id=je.id '
        'GROUP BY je.id '
        'HAVING ABS(SUM(jl.dr_amount)-SUM(jl.cr_amount))>0.005',
      );

      expect(drugs, 6);
      expect(settings, 35);
      expect(accounts, greaterThanOrEqualTo(30));
      expect(wallets, 4);
      expect(openingJournals, 4);
      expect(incompleteDrugs, 0);
      expect(unbalancedJournals, isEmpty);

      final warehouses = (await db.rawQuery(
        'SELECT COUNT(*) AS c FROM warehouses',
      )).first['c'] as int;
      final shelves = (await db.rawQuery(
        'SELECT COUNT(*) AS c FROM shelf_locations',
      )).first['c'] as int;
      final batches = (await db.rawQuery(
        'SELECT COUNT(*) AS c FROM batches_fefo',
      )).first['c'] as int;
      final movements = (await db.rawQuery(
        'SELECT COUNT(*) AS c FROM stock_movements',
      )).first['c'] as int;
      final expiredBatches = (await db.rawQuery(
        "SELECT COUNT(*) AS c FROM batches_fefo WHERE status='EXPIRED'",
      )).first['c'] as int;
      final invalidBalances = await db.rawQuery(
        'SELECT b.id FROM batches_fefo b '
        'JOIN drugs d ON d.id=b.drug_id '
        'WHERE b.loose_units<0 OR b.loose_units>=d.units_per_pack '
        'OR b.total_units != b.sealed_packs*d.units_per_pack+b.loose_units',
      );
      final stockTotals = await db.rawQuery(
        'SELECT d.id,d.stock_total_units,COALESCE(SUM(b.total_units),0) batch_units '
        'FROM drugs d LEFT JOIN batches_fefo b ON b.drug_id=d.id '
        'GROUP BY d.id HAVING d.stock_total_units != COALESCE(SUM(b.total_units),0)',
      );

      expect(warehouses, 6);
      expect(shelves, 6);
      expect(batches, greaterThan(0));
      expect(movements, greaterThan(0));
      expect(expiredBatches, greaterThan(0));
      final activeExpired = (await db.rawQuery(
        "SELECT COUNT(*) AS c FROM batches_fefo WHERE status='ACTIVE' AND expiry_date<date('now')",
      )).first['c'] as int;
      expect(activeExpired, 0);
      final fefoViewRows = await db.rawQuery(
        'SELECT units_per_pack,sell_price_pack,average_daily_units FROM v_fefo_batch_balances LIMIT 1',
      );
      expect(fefoViewRows, hasLength(1));
      expect(fefoViewRows.first.containsKey('units_per_pack'), isTrue);
      expect(fefoViewRows.first.containsKey('average_daily_units'), isTrue);
      expect(invalidBalances, isEmpty);

      expect(stockTotals, isEmpty);
      final clinicalTables = ['drug_interactions','drug_renal_rules','drug_hepatic_rules','drug_pediatric_rules','patients','clinical_alert_logs','controlled_drug_log','insurance_companies','insurance_policies','prescriptions','prescription_items','sales_returns','sales_return_items'];
      for (final table in clinicalTables) {
        final rows = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name=?", [table]);
        expect(rows, hasLength(1), reason: 'Missing clinical table $table');
      }
      final alternativesView = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='view' AND name='v_drug_alternatives'");
      expect(alternativesView, hasLength(1));
      final patientCount = (await db.rawQuery('SELECT COUNT(*) AS c FROM patients')).first['c'] as int;
      final insuranceCount = (await db.rawQuery('SELECT COUNT(*) AS c FROM insurance_companies')).first['c'] as int;
      final alternativeCount = (await db.rawQuery("SELECT COUNT(*) AS c FROM drugs WHERE internal_code LIKE 'ALT-I3-%'")).first['c'] as int;
      expect(patientCount, 3);
      expect(insuranceCount, 2);
      expect(alternativeCount, 4);


      final requiredTables = [
        'warehouses',
        'shelf_locations',
        'cold_chain_log',
        'batches_fefo',
        'stock_movements',
        'sales_invoice_item_batches',
        'stocktaking_sessions',
        'stocktaking_lines',
        'disposals',
        'disposal_items',
        'stock_transfers',
        'stock_transfer_items',
        'purchase_orders',
        'purchase_order_items',
        'purchase_invoices',
        'purchase_invoice_items',
        'purchase_returns',
        'purchase_return_items',
        'price_history',
      ];
      for (final table in requiredTables) {
        final rows = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          [table],
        );
        expect(rows, hasLength(1), reason: 'Missing table $table');
      }

      final countedColumn = await db.rawQuery(
        'PRAGMA table_info(stocktaking_lines)',
      );
      expect(countedColumn.any((column) => column['name'] == 'is_counted'), isTrue);

      final movement = (await db.query(
        'stock_movements',
        columns: ['id'],
        limit: 1,
      )).first;
      await expectLater(
        db.update(
          'stock_movements',
          {'note': 'محاولة تعديل غير مسموحة'},
          where: 'id=?',
          whereArgs: [movement['id']],
        ),
        throwsA(anything),
      );
      await expectLater(
        db.delete(
          'stock_movements',
          where: 'id=?',
          whereArgs: [movement['id']],
        ),
        throwsA(anything),
      );

      final partyBalanceView = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='view' AND name='v_party_balance'",
      );
      final inventoryView = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='view' AND name='v_inventory_by_drug'",
      );
      expect(partyBalanceView, hasLength(1));
      expect(inventoryView, hasLength(1));
    } finally {
      await db.close();
    }
  });
}
