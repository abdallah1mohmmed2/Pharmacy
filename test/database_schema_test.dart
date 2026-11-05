import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_builder.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/seed_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('creates the ERP schema and required seed records', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
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
        },
      ),
    );
    try {
      final drugs = (await db.rawQuery('SELECT COUNT(*) AS c FROM drugs')).first['c'] as int;
      final settings = (await db.rawQuery('SELECT COUNT(*) AS c FROM system_settings')).first['c'] as int;
      final accounts = (await db.rawQuery('SELECT COUNT(*) AS c FROM chart_of_accounts')).first['c'] as int;
      final wallets = (await db.rawQuery("SELECT COUNT(*) AS c FROM cash_accounts WHERE account_kind='WALLET'")).first['c'] as int;
      expect(drugs, 6);
      expect(settings, 35);
      expect(accounts, greaterThanOrEqualTo(30));
      expect(wallets, 4);
      final view = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='view' AND name='v_party_balance'");
      expect(view, hasLength(1));
    } finally {
      await db.close();
    }
  });
}
