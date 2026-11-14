import 'dart:io';
import 'package:path/path.dart' as p;
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
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration13.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration14.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration15.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('upgrade from v17 to v18 retains settings, drug, and existing data',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('pharmacy-opening-upgrade-');
    final file = p.join(directory.path, 'preexisting-pharmacy.db');
    Database? old;
    Database? upgraded;
    try {
      old = await databaseFactoryFfi.openDatabase(file,
          options: OpenDatabaseOptions(
            version: 17,
            onConfigure: (d) async {
              await d.execute('PRAGMA foreign_keys=ON');
            },
            onCreate: (d, _) async {
              await SchemaBuilder.build(d);
              await SchemaIteration12.upgrade(d);
              await SeedData.run(d);
              await SchemaIteration2.upgrade(d);
              await SchemaIteration3.upgrade(d);
              await SchemaIteration4.upgrade(d);
              await SchemaIteration5.upgrade(d);
              await SchemaIteration6.upgrade(d);
              await SchemaIteration7.upgrade(d);
              await SchemaIteration8.upgrade(d);
              await SchemaIteration9.upgrade(d);
              await SchemaIteration10.upgrade(d);
              await SchemaIteration11.upgrade(d);
              await SchemaIteration12.upgrade(d);
              await SchemaIteration13.upgrade(d);
              await SchemaIteration14.upgrade(d);
            },
          ));
      final settingsBefore =
          await old.query('system_settings', orderBy: 'setting_no');
      final drugId = await old.insert('drugs', {
        'uuid': 'existing-drug-before-opening',
        'branch_id': 1,
        'created_at': '2026-11-10',
        'updated_at': '2026-11-10',
        'internal_code': 'KEEP-OLD-STOCK',
        'trade_name_ar': 'دواء محفوظ',
        'sell_price_pack': 15000.0,
        'sell_price_strip': 1500.0,
        'sell_price_unit': 150.0,
      });
      await old.close();
      old = null;

      upgraded = await databaseFactoryFfi.openDatabase(file,
          options: OpenDatabaseOptions(
            version: 18,
            onConfigure: (d) async {
              await d.execute('PRAGMA foreign_keys=ON');
            },
            onUpgrade: (d, previous, target) async {
              expect(previous, 17);
              expect(target, 18);
              await SchemaIteration15.upgrade(d);
            },
          ));
      expect(await upgraded.getVersion(), 18);
      expect(await upgraded.query('system_settings', orderBy: 'setting_no'),
          settingsBefore);
      final existing =
          (await upgraded.query('drugs', where: 'id=?', whereArgs: [drugId]))
              .single;
      expect(existing['trade_name_ar'], 'دواء محفوظ');
      expect(existing['sell_price_pack'], 15000);
      expect(existing['sell_price_unit'], 150);
      expect(await upgraded.query('opening_inventory_posts'), isEmpty);
      expect(await upgraded.rawQuery('PRAGMA foreign_key_check'), isEmpty);

      await SchemaIteration15.upgrade(upgraded);
      expect(await upgraded.query('opening_inventory_posts'), isEmpty);
    } finally {
      await upgraded?.close();
      await old?.close();
      await directory.delete(recursive: true);
    }
  });
}
