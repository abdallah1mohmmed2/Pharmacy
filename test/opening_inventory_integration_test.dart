import 'package:excel/excel.dart';
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
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration13.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration14.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration15.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/opening_inventory_service.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/opening_inventory_excel.dart';
import 'package:global_enterprise_pharmacy_erp/providers/pos_and_drugs_provider.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/drug_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Opening stock prices', () {
    test('any one source price derives only the blanks', () {
      expect(const OpeningStockPrices(carton: 10000).fillMissing(10, 10).packet,
          1000);
      expect(const OpeningStockPrices(carton: 10000).fillMissing(10, 10).unit,
          100);
      expect(const OpeningStockPrices(packet: 1000).fillMissing(10, 10).carton,
          10000);
      expect(const OpeningStockPrices(unit: 100).fillMissing(10, 10).carton,
          10000);
      final manual =
          const OpeningStockPrices(carton: 10000, packet: 1200, unit: 130)
              .fillMissing(10, 10);
      expect([manual.carton, manual.packet, manual.unit], [10000, 1200, 130]);
      expect(() => const OpeningStockPrices(carton: 10).fillMissing(0, 10),
          throwsArgumentError);
    });

    test('XLSX template is readable and blank optional shelf stays null', () {
      final workbook = Excel.decodeBytes(OpeningInventoryExcel.templateBytes());
      workbook['الرصيد الافتتاحي'].appendRow([
        TextCellValue(''),
        TextCellValue('دواء تجريبي'),
        TextCellValue(''),
        IntCellValue(2),
        IntCellValue(3),
        IntCellValue(4),
        IntCellValue(10),
        IntCellValue(12),
        DoubleCellValue(12000),
        null,
        null,
        TextCellValue('2028-06-30'),
        TextCellValue('B-01'),
        null,
        null,
        null,
        null,
      ]);
      final imported = OpeningInventoryExcel.parse(workbook.save()!,
          defaultWarehouseId: 3, warehousesByCode: {'WH': 3});
      expect(imported.errors, isEmpty);
      expect(imported.lines, hasLength(1));
      expect(imported.lines.single.quantityUnits, 280);
      expect(imported.lines.single.warehouseId, 3);
      expect(imported.lines.single.shelfCode, isNull);
      expect(imported.lines.single.prices.fillMissing(10, 12).packet, 1200);
    });
  });

  group('Atomic opening inventory in existing SQLite', () {
    late Database db;
    late OpeningInventoryService service;
    late DatabaseHelper helper;
    late int drugId;
    late int warehouseId;
    late String futureExpiry;
    const branchId = 1;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: 18,
            onConfigure: (d) async => d.execute('PRAGMA foreign_keys=ON'),
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
              await SchemaIteration15.upgrade(d);
            },
          ));
      helper = DatabaseHelper.forTesting(db);
      service = OpeningInventoryService(helper: helper);
      warehouseId = (await db.query('warehouses',
              where: 'branch_id=? AND wh_type=?',
              whereArgs: [branchId, 'PHARMACY_FLOOR'],
              limit: 1))
          .single['id'] as int;
      final now = DateTime.now().toIso8601String();
      final expiry = DateTime.now().add(const Duration(days: 730));
      futureExpiry =
          '${expiry.year.toString().padLeft(4, '0')}-${expiry.month.toString().padLeft(2, '0')}-${expiry.day.toString().padLeft(2, '0')}';
      drugId = await db.insert('drugs', {
        'uuid': 'opening-test-drug',
        'branch_id': branchId,
        'created_at': now,
        'updated_at': now,
        'internal_code': 'OPEN-TEST-1',
        'trade_name_ar': 'دواء تجريبي',
        'scientific_name': 'Example',
      });
    });

    tearDown(() async {
      await db.close();
    });

    OpeningStockLine row({
      String lot = 'LOT-001',
      String? shelf,
      int cartons = 2,
      int packets = 3,
      int units = 4,
      OpeningStockPrices prices = const OpeningStockPrices(carton: 12000),
    }) =>
        OpeningStockLine(
          drugId: drugId,
          warehouseId: warehouseId,
          expiryDate: futureExpiry,
          batchNo: lot,
          shelfCode: shelf,
          cartons: cartons,
          packets: packets,
          units: units,
          packetsPerCarton: 10,
          unitsPerPacket: 12,
          prices: prices,
        );

    Future<int> post(String uuid, List<OpeningStockLine> lines,
            {String? hash}) =>
        service.post(
          branchId: branchId,
          operationUuid: uuid,
          effectiveDate: DateTime.now().toIso8601String().substring(0, 10),
          lines: lines,
          sourceHash: hash,
        );

    test('280 units are posted to FEFO, movements, existing drug fields',
        () async {
      final settingsBefore =
          await db.query('system_settings', orderBy: 'setting_no');
      final result = await service.preview(
          branchId: branchId,
          effectiveDate: DateTime.now().toIso8601String().substring(0, 10),
          lines: [row()]);
      expect(result.errors, isEmpty);
      expect(result.totalUnits, 280);
      final operationId =
          await post('opening-uuid-1', [row()], hash: 'filehash-A');
      final batch = (await db.query('batches_fefo')).single;
      expect(batch['sealed_packs'], 2);
      expect(batch['loose_units'], 40);
      expect(batch['total_units'], 280);
      expect(batch['location_id'], isNull);
      expect(batch['expiry_date'], futureExpiry);
      final movement = (await db.query('stock_movements')).single;
      expect(movement['movement_type'], 'OPENING_IN');
      expect(movement['qty_units'], 280);
      expect(movement['doc_id'], operationId);
      expect((movement['note'] as String), contains('تاريخ الرصيد:'));
      final drug =
          (await db.query('drugs', where: 'id=?', whereArgs: [drugId])).single;
      expect(drug['stock_total_units'], 280);
      expect(drug['strips_per_pack'], 10);
      expect(drug['units_per_strip'], 12);
      expect(drug['units_per_pack'], 120);
      expect(drug['sell_price_pack'], 12000);
      expect(drug['sell_price_strip'], 1200);
      expect(drug['sell_price_unit'], 100);
      expect(drug['strip_price_mode'], 'MANUAL');
      expect(await db.query('system_settings', orderBy: 'setting_no'),
          settingsBefore);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });

    test('same operation and same XLSX file cannot inflate stock twice',
        () async {
      final first = await post('opening-uuid-2', [row()], hash: 'filehash-B');
      expect(await post('opening-uuid-2', [row()], hash: 'filehash-B'), first);
      await expectLater(post('opening-uuid-new', [row()], hash: 'filehash-B'),
          throwsStateError);
      expect((await db.query('batches_fefo')).single['total_units'], 280);
      expect(await db.query('stock_movements'), hasLength(1));
      expect(await db.query('opening_inventory_posts'), hasLength(1));
    });

    test('invalid shelf or wrong branch rejects whole operation', () async {
      await expectLater(
          post('opening-invalid', [
            row(),
            row(lot: 'LOT-002', shelf: 'UNKNOWN-SHELF'),
          ]),
          throwsStateError);
      expect(await db.query('batches_fefo'), isEmpty);
      expect(await db.query('stock_movements'), isEmpty);
      expect(await db.query('opening_inventory_posts'), isEmpty);
      await expectLater(
          service.post(
            branchId: 999,
            operationUuid: 'wrong-branch',
            effectiveDate: DateTime.now().toIso8601String().substring(0, 10),
            lines: [row()],
          ),
          throwsStateError);
    });

    test('mixed source prices across lots preserve every explicit price',
        () async {
      await post('opening-mixed-prices', [
        row(lot: 'MIX-A', prices: const OpeningStockPrices(carton: 12000)),
        row(lot: 'MIX-B', prices: const OpeningStockPrices(unit: 125)),
      ]);
      final drug =
          (await db.query('drugs', where: 'id=?', whereArgs: [drugId])).single;
      expect(drug['sell_price_pack'], 12000);
      expect(drug['sell_price_strip'], 1200);
      expect(drug['sell_price_unit'], 125);
    });

    test('conflicting explicit prices across lots reject entire import',
        () async {
      await expectLater(
          post('opening-conflicting-prices', [
            row(lot: 'A', prices: const OpeningStockPrices(carton: 12000)),
            row(lot: 'B', prices: const OpeningStockPrices(carton: 14000)),
          ]),
          throwsStateError);
      expect(await db.query('opening_inventory_posts'), isEmpty);
      expect(await db.query('batches_fefo'), isEmpty);
      expect(await db.query('stock_movements'), isEmpty);
    });

    test(
        'two lots retain separate FEFO batches while prices remain independent',
        () async {
      await post('opening-lots', [
        row(
            lot: 'LOT-A',
            prices: const OpeningStockPrices(
                carton: 12000, packet: 1350, unit: 115)),
        row(
            lot: 'LOT-B',
            cartons: 1,
            packets: 0,
            units: 0,
            prices: const OpeningStockPrices(
                carton: 12000, packet: 1350, unit: 115)),
      ]);
      expect(await db.query('batches_fefo'), hasLength(2));
      expect(await db.query('stock_movements'), hasLength(2));
      final drug =
          (await db.query('drugs', where: 'id=?', whereArgs: [drugId])).single;
      expect(drug['stock_total_units'], 400);
      expect(drug['sell_price_strip'], 1350);
      expect(drug['sell_price_unit'], 115);
      // The medicine editor must not destroy manual packet/unit prices.
      final editing = DrugModel.fromMap(drug);
      final updated = DrugModel.fromMap({
        ...editing.toMap(),
        'sell_price_pack': 14000,
      });
      final provider = PosAndDrugsProvider(database: helper);
      await provider.saveDrug(updated);
      final afterEdit =
          (await db.query('drugs', where: 'id=?', whereArgs: [drugId])).single;
      expect(afterEdit['sell_price_strip'], 1350);
      expect(afterEdit['sell_price_unit'], 115);
      expect(afterEdit['stock_total_units'], 400);
    });
  });
}
