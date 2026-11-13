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
      // Derived amounts must round UP to the next multiple of ten.
      final rounded = const OpeningStockPrices(carton: 1070).fillMissing(3, 4);
      expect(rounded.carton, 1070); // The manually entered source is untouched.
      expect(rounded.packet, 360); // 356.67 => 360.
      expect(rounded.unit, 90); // 89.17 => 90.
      final packetSource =
          const OpeningStockPrices(packet: 107).fillMissing(3, 4);
      expect(packetSource.packet, 107); // Manual source stays 107.
      expect(packetSource.carton, 330);
      expect(packetSource.unit, 30);
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

  group('Opening inventory dosage-form Excel mapping', () {
    test('optional Arabic form maps to the app enum without a new field', () {
      final workbook = Excel.decodeBytes(OpeningInventoryExcel.templateBytes());
      workbook['الرصيد الافتتاحي'].appendRow([
        null,
        TextCellValue('دواء تجريبي'),
        null,
        IntCellValue(1),
        null,
        null,
        IntCellValue(10),
        IntCellValue(12),
        null,
        null,
        null,
        TextCellValue('2028-06-30'),
        null,
        null,
        null,
        null,
        null,
        TextCellValue('أقراص'),
      ]);
      final parsed = OpeningInventoryExcel.parse(workbook.save()!,
          defaultWarehouseId: 3, warehousesByCode: {});
      expect(parsed.errors, isEmpty);
      expect(parsed.lines.single.dosageForm, 'TABLET');
    });

    test('rejects unrecognized types before any stock is posted', () {
      final workbook = Excel.decodeBytes(OpeningInventoryExcel.templateBytes());
      workbook['الرصيد الافتتاحي'].appendRow([
        null,
        TextCellValue('دواء تجريبي'),
        null,
        IntCellValue(1),
        null,
        null,
        IntCellValue(10),
        IntCellValue(12),
        null,
        null,
        null,
        TextCellValue('2028-06-30'),
        null,
        null,
        null,
        null,
        null,
        TextCellValue('نوع غير معروف'),
      ]);
      final parsed = OpeningInventoryExcel.parse(workbook.save()!,
          defaultWarehouseId: 3, warehousesByCode: {});
      expect(parsed.lines, isEmpty);
      expect(parsed.errors.single, contains('نوع الدواء غير معتمد'));
    });
  });

  group('Opening XLSX with three optional cost inputs', () {
    test('carton acquisition cost derives precise unit cost', () {
      final book = Excel.decodeBytes(OpeningInventoryExcel.templateBytes());
      book['الرصيد الافتتاحي'].appendRow([
        null,
        TextCellValue('دواء تجريبي'),
        null,
        IntCellValue(1),
        null,
        null,
        IntCellValue(10),
        IntCellValue(12),
        null,
        null,
        null,
        TextCellValue('2028-06-30'),
        null,
        null,
        null,
        FormulaCellValue('V2/G2/H2'),
        null,
        TextCellValue('أقراص'),
        DoubleCellValue(5000),
        null,
        null,
      ]);
      final parsed = OpeningInventoryExcel.parse(book.save()!,
          defaultWarehouseId: 3, warehousesByCode: {});
      expect(parsed.errors, isEmpty);
      expect(parsed.lines, hasLength(1));
      expect(parsed.lines.single.unitCost, closeTo(5000 / 120, 1e-8));
      expect(parsed.lines.single.dosageForm, 'TABLET');
    });

    test('multiple acquisition-cost sources cannot silently conflict', () {
      final book = Excel.decodeBytes(OpeningInventoryExcel.templateBytes());
      book['الرصيد الافتتاحي'].appendRow([
        null,
        TextCellValue('دواء تجريبي'),
        null,
        IntCellValue(1),
        null,
        null,
        IntCellValue(10),
        IntCellValue(12),
        null,
        null,
        null,
        TextCellValue('2028-06-30'),
        null,
        null,
        null,
        null,
        null,
        TextCellValue('أقراص'),
        DoubleCellValue(5000),
        DoubleCellValue(550),
        null,
      ]);
      final parsed = OpeningInventoryExcel.parse(book.save()!,
          defaultWarehouseId: 3, warehousesByCode: {});
      expect(parsed.lines, isEmpty);
      expect(parsed.errors.single, contains('تكلفة شراء واحدة فقط'));
    });
  });

  group('Opening XLSX with source-price columns', () {
    test('formula display prices are ignored and raw user price is imported',
        () {
      final workbook = Excel.createExcel();
      final sheet = workbook['الرصيد الافتتاحي'];
      final orderedHeaders = <String>[
        'اسم الدواء',
        'معرّف الدواء',
        'رمز المخزن',
        'عدد الكراتين',
        'الباكتات الإضافية',
        'الحبات الإضافية',
        'باكتات في الكرتون',
        'حبات في الباكت',
        'إدخال سعر الكرتون',
        'إدخال سعر الباكت',
        'إدخال سعر الحبة',
        'سعر الكرتون',
        'سعر الباكت',
        'سعر الحبة',
        'تاريخ الانتهاء',
        'رقم التشغيلة',
        'رقم الرف (اختياري)',
        'تاريخ الإدخال',
        'تكلفة الحبة',
        'ملاحظات',
      ];
      sheet.appendRow(orderedHeaders.map((s) => TextCellValue(s)).toList());
      sheet.appendRow([
        TextCellValue('دواء تجريبي'),
        null,
        null,
        IntCellValue(2),
        IntCellValue(3),
        IntCellValue(4),
        IntCellValue(10),
        IntCellValue(10),
        DoubleCellValue(10000),
        null,
        null,
        FormulaCellValue('I2'),
        FormulaCellValue('I2/G2'),
        FormulaCellValue('I2/G2/H2'),
        TextCellValue('2028-06-30'),
        TextCellValue('B-01'),
        null,
        null,
        null,
        null,
      ]);
      final parsed = OpeningInventoryExcel.parse(workbook.save()!,
          defaultWarehouseId: 3, warehousesByCode: {});
      expect(parsed.errors, isEmpty);
      expect(parsed.lines, hasLength(1));
      final price = parsed.lines.single.prices;
      expect(price.carton, 10000);
      expect(price.packet, isNull);
      expect(price.unit, isNull);
      final suggested = price.fillMissing(10, 10);
      expect(suggested.packet, 1000);
      expect(suggested.unit, 100);
      expect(parsed.lines.single.quantityUnits, 234);
      expect(parsed.lines.single.shelfCode, isNull);
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
      String? dosageForm,
    }) =>
        OpeningStockLine(
          drugId: drugId,
          dosageForm: dosageForm,
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

    test('four-column Excel uses stored tablets per strip and pack price',
        () async {
      // The template specifies 3 strips per pack, not tablets per strip.
      // The latter comes from the existing drug card (10 tablets/strip).
      await db.update(
          'drugs',
          {
            'strips_per_pack': 3,
            'units_per_strip': 10,
            'units_per_pack': 30,
          },
          where: 'id=?',
          whereArgs: [drugId]);

      final book =
          Excel.decodeBytes(OpeningInventoryExcel.simpleTemplateBytes());
      final sheet = book['الرصيد الافتتاحي'];
      sheet.appendRow([
        TextCellValue('دواء مرجعي فقط'),
        null,
        null,
        null,
      ]);
      sheet.appendRow([
        TextCellValue('دواء تجريبي'),
        IntCellValue(12),
        IntCellValue(3),
        DoubleCellValue(1000),
      ]);
      final parsed = OpeningInventoryExcel.parse(
        book.save()!,
        defaultWarehouseId: warehouseId,
        warehousesByCode: const {},
        defaultExpiryDate: futureExpiry,
      );
      expect(parsed.errors, isEmpty);
      expect(parsed.lines, hasLength(1));
      expect(parsed.lines.single.resolveUnitsFromCatalog, isTrue);
      final preview = await service.preview(
        branchId: branchId,
        effectiveDate: DateTime.now().toIso8601String().substring(0, 10),
        lines: parsed.lines,
      );
      expect(preview.errors, isEmpty);
      expect(preview.totalUnits, 360); // 12 packs * 3 strips * 10 tablets
      await post('simple-stock-first', parsed.lines, hash: 'simple-file-1');

      final stored =
          (await db.query('drugs', where: 'id=?', whereArgs: [drugId])).single;
      expect(stored['stock_total_units'], 360);
      expect(stored['sell_price_pack'], 1000);
      expect(stored['strips_per_pack'], 3);
      expect(stored['units_per_strip'], 10);
      expect(
          await db.query('drugs',
              where: 'trade_name_ar=?', whereArgs: ['دواء مرجعي فقط']),
          isEmpty);
      expect(await db.query('stock_movements'), hasLength(1));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });

    test('simple template does not invent missing tablets-per-strip', () async {
      final book =
          Excel.decodeBytes(OpeningInventoryExcel.simpleTemplateBytes());
      book['الرصيد الافتتاحي'].appendRow([
        TextCellValue('صنف غير موجود'),
        IntCellValue(2),
        IntCellValue(3),
        DoubleCellValue(400),
      ]);
      final parsed = OpeningInventoryExcel.parse(
        book.save()!,
        defaultWarehouseId: warehouseId,
        warehousesByCode: const {},
        defaultExpiryDate: futureExpiry,
      );
      expect(parsed.errors, isEmpty);
      final preview = await service.preview(
        branchId: branchId,
        effectiveDate: DateTime.now().toIso8601String().substring(0, 10),
        lines: parsed.lines,
      );
      expect(preview.errors, hasLength(1));
      expect(preview.errors.single, contains('الصنف غير موجود'));
      expect(
          await db.query('drugs',
              where: 'trade_name_ar=?', whereArgs: ['صنف غير موجود']),
          isEmpty);
    });

    test('unknown Excel drug is created automatically only on approval',
        () async {
      final imported = OpeningStockLine(
        drugName: 'باراسيتامول - أدكو 1 جم 20 قرص',
        dosageForm: 'TABLET',
        warehouseId: warehouseId,
        expiryDate: futureExpiry,
        cartons: 0,
        packets: 0,
        units: 140,
        packetsPerCarton: 1,
        unitsPerPacket: 20,
        prices: const OpeningStockPrices(unit: 50),
      );
      final before = await db.query('drugs');
      final preview = await service.preview(
          branchId: branchId,
          effectiveDate: DateTime.now().toIso8601String().substring(0, 10),
          lines: [imported]);
      expect(preview.errors, isEmpty);
      expect(preview.totalUnits, 140);
      expect(await db.query('drugs'), before,
          reason: 'Preview must never persist provisional medicines');
      await post('opening-auto-new', [imported], hash: 'auto-hash-1');
      final drugs = await db.query('drugs',
          where: 'trade_name_ar=?',
          whereArgs: ['باراسيتامول - أدكو 1 جم 20 قرص']);
      expect(drugs, hasLength(1));
      expect(drugs.single['dosage_form'], 'TABLET');
      expect(drugs.single['units_per_pack'], 20);
      expect(drugs.single['stock_total_units'], 140);
      expect(await db.query('stock_movements'), hasLength(1));
      expect(await db.query('batches_fefo'), hasLength(1));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await expectLater(
          post('opening-auto-repeat', [imported], hash: 'auto-hash-1'),
          throwsStateError);
      expect(
          await db.query('drugs',
              where: 'trade_name_ar=?',
              whereArgs: ['باراسيتامول - أدكو 1 جم 20 قرص']),
          hasLength(1));
    });

    test('failed import rolls back newly created medicine and its stock',
        () async {
      final missing = OpeningStockLine(
        drugName: 'دواء غير مسجل',
        warehouseId: warehouseId,
        expiryDate: futureExpiry,
        cartons: 0,
        packets: 0,
        units: 10,
        packetsPerCarton: 1,
        unitsPerPacket: 10,
      );
      await expectLater(
          post('opening-auto-rollback', [
            missing,
            row(lot: 'INVALID-SHELF', shelf: 'MISSING-SHELF'),
          ]),
          throwsStateError);
      expect(
          await db.query('drugs',
              where: 'trade_name_ar=?', whereArgs: ['دواء غير مسجل']),
          isEmpty);
      expect(await db.query('stock_movements'), isEmpty);
      expect(await db.query('opening_inventory_posts'), isEmpty);
    });

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

    test(
        'opening stock fills OTHER dosage form without overwriting a known one',
        () async {
      await post('opening-type-tablet', [row(dosageForm: 'TABLET')]);
      final drug =
          (await db.query('drugs', where: 'id=?', whereArgs: [drugId])).single;
      expect(drug['dosage_form'], 'TABLET');
      await expectLater(
          post('opening-type-conflict', [row(dosageForm: 'CAPSULE')]),
          throwsStateError);
      expect(await db.query('opening_inventory_posts'), hasLength(1));
      expect(await db.query('stock_movements'), hasLength(1));
    });

    test('conflicting forms across lots fail atomically', () async {
      await expectLater(
          post('opening-mixed-types', [
            row(lot: 'TYPE-A', dosageForm: 'TABLET'),
            row(lot: 'TYPE-B', dosageForm: 'CAPSULE'),
          ]),
          throwsStateError);
      expect(await db.query('opening_inventory_posts'), isEmpty);
      expect(await db.query('stock_movements'), isEmpty);
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
