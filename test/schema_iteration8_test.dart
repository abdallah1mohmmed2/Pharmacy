import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/data/database/schema_iteration8.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => sqfliteFfiInit());

  test('rebuilds purchase and sales period guards without JSON1', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, onCreate: (database, version) async {
        await database.execute('CREATE TABLE system_settings(setting_no INTEGER PRIMARY KEY, setting_value TEXT NOT NULL)');
        await database.insert('system_settings', {'setting_no': 29, 'setting_value': '{"locked_through":null}'});
        await database.execute('CREATE TABLE fiscal_periods(id INTEGER PRIMARY KEY, period_code TEXT, status TEXT, start_date TEXT, end_date TEXT)');
        await database.execute('CREATE TABLE purchase_invoices(id INTEGER PRIMARY KEY, invoice_date TEXT)');
        await database.execute('CREATE TABLE sales_invoices(id INTEGER PRIMARY KEY, invoice_date TEXT)');
        await database.execute('CREATE TABLE sales_invoice_items(id INTEGER PRIMARY KEY, invoice_id INTEGER)');
        await database.execute('CREATE TABLE sales_payments(id INTEGER PRIMARY KEY, invoice_id INTEGER)');
        await database.execute('CREATE TABLE journal_lines(id INTEGER PRIMARY KEY, journal_entry_id INTEGER)');
        await database.execute('CREATE TABLE journal_entries(id INTEGER PRIMARY KEY, entry_date TEXT)');
        await database.execute('CREATE TABLE sales_return_items(id INTEGER PRIMARY KEY, sales_return_id INTEGER)');
        await database.execute('CREATE TABLE sales_returns(id INTEGER PRIMARY KEY, return_date TEXT)');
        await database.execute('CREATE TABLE partner_distribution_lines(id INTEGER PRIMARY KEY, distribution_id INTEGER)');
        await database.execute('CREATE TABLE partner_distributions(id INTEGER PRIMARY KEY, period_code TEXT)');
      }),
    );
    try {
      await SchemaIteration8.upgrade(db);
      final triggers = await db.rawQuery("SELECT name,sql FROM sqlite_master WHERE type='trigger' AND name LIKE 'trg_period_%'");
      expect(triggers, isNotEmpty);
      expect(triggers.every((row) => !(row['sql'] as String).contains('json_extract')), isTrue);
      await db.insert('purchase_invoices', {'invoice_date': '2026-12-01'});
      final salesId = await db.insert('sales_invoices', {'invoice_date': '2026-11-20'});
      await db.update('system_settings', {'setting_value': '{"locked_through":"2026-11-30"}'}, where: 'setting_no=29');
      await expectLater(db.insert('purchase_invoices', {'invoice_date': '2026-11-15'}), throwsA(isA<DatabaseException>()));
      await db.insert('purchase_invoices', {'invoice_date': '2026-12-02'});
      await expectLater(db.insert('sales_invoice_items', {'invoice_id': salesId}), throwsA(isA<DatabaseException>()));
    } finally {
      await db.close();
    }
  });
}
