import 'dart:convert';
import 'dart:io';
import 'package:global_enterprise_pharmacy_erp/providers/pos_and_drugs_provider.dart';

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
import 'package:global_enterprise_pharmacy_erp/data/services/drug_import_export_service.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/drug_import_field_catalog.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/drug_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('File-based streaming drug import', () {
    late Database db;
    late DrugImportExportService importer;
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('drug-import-test-');
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
      importer = DrugImportExportService(helper: DatabaseHelper.forTesting(db));
    });

    tearDown(() async {
      await db.close();
      await temp.delete(recursive: true);
    });

    Future<File> put(String name, String text) async {
      final file = File(temp.path + '/' + name);
      await file.writeAsString(text, encoding: utf8);
      return file;
    }

    test('1,201 JSON drugs import in small transactions; retry skips all',
        () async {
      final source = List.generate(
          1201,
          (i) => {
                'internal_code': 'STREAM-$i',
                'trade_name_ar': 'دواء تجريبي $i',
                'trade_name_en': 'Test medicine $i',
                'scientific_name': 'substance-$i',
                'indications': 'تجربة فقط',
                'barcode_international': '',
              });
      final file = await put('bulk.json', jsonEncode(source));
      final preview =
          await importer.dryRunImportFile(file: file, format: 'JSON');
      expect(preview.validRows, 1201);
      expect(preview.errors, isEmpty);
      final calls = <int>[];
      final first = await importer.executeImportFile(
          file: file,
          format: 'JSON',
          batchSize: 37,
          expectedRows: 1201,
          onProgress: (done, _) => calls.add(done));
      expect(first.inserted, 1201);
      expect(first.errors, 0);
      expect(calls.last, 1201);
      expect(calls.length, greaterThan(20));
      expect((await db.rawQuery('SELECT COUNT(*) AS n FROM drugs')).single['n'],
          1201);
      final retry = await importer.executeImportFile(
          file: file, format: 'JSON', batchSize: 31);
      expect(retry.inserted, 0);
      expect(retry.skipped, 1201);
      expect(retry.errors, 0);
    });

    test('CSV handles UTF-8, BOM, commas, multiline cells, blank numbers',
        () async {
      final file = await put(
          'multiline.csv',
          '\uFEFFtrade_name_ar,scientific_name,indications,strips_per_pack\n'
              '"دواء, واحد",x,"سطر أول\nسطر ثان",\n'
              'دواء ثان,y,"نص به ""اقتباس""",2\n');
      final preview =
          await importer.dryRunImportFile(file: file, format: 'CSV');
      expect(preview.validRows, 2);
      expect(preview.errors, isEmpty);
      final result = await importer.executeImportFile(
          file: file, format: 'CSV', batchSize: 1);
      expect(result.inserted, 2);
      final rows = await db.query('drugs');
      expect(rows, hasLength(2));
      final first = (await db.query('drugs',
              where: 'trade_name_ar=?', whereArgs: ['دواء, واحد']))
          .single;
      final second = (await db.query('drugs',
              where: 'trade_name_ar=?', whereArgs: ['دواء ثان']))
          .single;
      expect(first['indications'], 'سطر أول\nسطر ثان');
      expect(second['indications'], 'نص به "اقتباس"');
    });

    test('UPDATE_EMPTY_ONLY preserves stock and existing price', () async {
      final file = await put(
          'update.json',
          jsonEncode([
            {
              'internal_code': 'PRICE-KEEP',
              'trade_name_ar': 'دواء السعر',
              'scientific_name': 'active',
              'indications': 'معلومة جديدة',
              'sell_price_pack': 200,
              'stock_total_units': 0,
            }
          ]));
      final now = DateTime.now().toIso8601String();
      await db.insert('drugs', {
        'uuid': 'existing-price-fixture',
        'branch_id': 1,
        'created_at': now,
        'updated_at': now,
        'internal_code': 'PRICE-KEEP',
        'trade_name_ar': 'دواء السعر',
        'scientific_name': 'active',
        'sell_price_pack': 120,
        'stock_total_units': 70,
      });
      final result = await importer.executeImportFile(
          file: file, format: 'JSON', conflictPolicy: 'UPDATE_EMPTY_ONLY');
      expect(result.updated, 1);
      final row = (await db.query('drugs',
              where: 'internal_code=?', whereArgs: ['PRICE-KEEP']))
          .single;
      expect(row['sell_price_pack'], 120);
      expect(row['stock_total_units'], 70);
      expect(row['indications'], 'معلومة جديدة');
    });

    test('duplicate barcodes do not merge different source medicines',
        () async {
      final file = await put(
          'shared-barcode.json',
          jsonEncode([
            {
              'internal_code': 'SHARED-001',
              'trade_name_ar': 'دواء مختلف',
              'scientific_name': 'compound-a',
              'barcode_international': '6221000003295',
            },
            {
              'internal_code': 'SHARED-002',
              'trade_name_ar': 'دواء مختلف',
              'scientific_name': 'compound-a',
              'barcode_international': '6221000003295',
            }
          ]));
      final preview =
          await importer.dryRunImportFile(file: file, format: 'JSON');
      expect(preview.validRows, 2);
      expect(preview.barcodeDuplicates, 1);
      final result =
          await importer.executeImportFile(file: file, format: 'JSON');
      expect(result.inserted, 2);
      expect(result.errors, 0);
      expect(result.barcodeConflicts, 1);
      final rows = await db.query('drugs', orderBy: 'internal_code');
      expect(rows, hasLength(2));
      expect(rows.first['barcode_international'], '6221000003295');
      expect(rows.last['barcode_international'], isNull);
      final retry =
          await importer.executeImportFile(file: file, format: 'JSON');
      expect(retry.inserted, 0);
      expect(retry.skipped, 2);
    });

    test('JSON drugs envelope and incomplete input validation', () async {
      final file = await put(
          'wrapped.json',
          '{"drugs":[{"trade_name_ar":"دواء بغلاف",'
              '"scientific_name":"x"}]}');
      final result =
          await importer.dryRunImportFile(file: file, format: 'JSON');
      expect(result.validRows, 1);
      final bad = await put('incomplete.json', '[{"trade_name_ar":"x"}');
      expect(() => importer.dryRunImportFile(file: bad, format: 'JSON'),
          throwsFormatException);
    });

    test('duplicate codes inside one file are flagged by dry-run', () async {
      final file = await put(
          'duplicate.json',
          jsonEncode([
            {'internal_code': 'DUP-1', 'trade_name_ar': 'دواء أ'},
            {'internal_code': 'DUP-1', 'trade_name_ar': 'دواء ب'},
          ]));
      final result =
          await importer.dryRunImportFile(file: file, format: 'JSON');
      expect(result.totalRows, 2);
      expect(result.validRows, 1);
      expect(result.duplicates, 1);
      expect(result.errors, hasLength(1));
    });
    test('field catalog covers every real model column including read-only',
        () async {
      final actual = <String>{
        ...DrugModel().toMap().keys,
        ...DrugImportFieldCatalog.databaseOnlyFields,
      };
      expect(DrugImportFieldCatalog.allFields, actual);
      expect(DrugImportFieldCatalog.labels.keys.toSet(), actual);
      // PRAGMA reads the actual migrated SQLite schema, not a UI mock.
      // This protects against silent drift in either the model or migrations.
      final tableInfo = await db.rawQuery('PRAGMA table_info(drugs)');
      final databaseColumns =
          tableInfo.map((row) => row['name'].toString()).toSet();
      expect(DrugImportFieldCatalog.allFields, databaseColumns);

      expect(actual, contains('strip_price_mode'));
      expect(actual, contains('ped_doses_per_day'));
      expect(DrugImportFieldCatalog.isEditable('strip_price_mode'), isTrue);
      expect(DrugImportFieldCatalog.isEditable('ped_doses_per_day'), isTrue);
      for (final field in [
        'id',
        'branch_id',
        'uuid',
        'stock_total_units',
        'sync_version',
        'units_per_pack'
      ]) {
        expect(DrugImportFieldCatalog.isProtected(field), isTrue);
        expect(DrugImportFieldCatalog.isEditable(field), isFalse);
      }
    });

    test('real JSON export includes complete fields and can reimport a clone',
        () async {
      final now = DateTime.now().toIso8601String();
      final ingredients = jsonEncode([
        {'name': 'amoxicillin', 'amount': '500 mg'}
      ]);
      await db.insert('drugs', {
        'uuid': 'original-round-trip',
        'branch_id': 1,
        'created_at': now,
        'updated_at': now,
        'internal_code': 'ROUND-ORIGINAL',
        'trade_name_ar': 'دواء دورة كاملة',
        'scientific_name': 'active value',
        'ingredients_json': ingredients,
        'ped_doses_per_day': 3,
        'strip_price_mode': 'MANUAL',
        'sell_price_pack': 120,
        'sell_price_strip': 60,
        'sell_price_unit': 6,
        'strips_per_pack': 2,
        'units_per_strip': 10,
        'units_per_pack': 20,
        'is_antibiotic': 1,
        'indications': 'بيانات حقيقية للاستعمال'
      });
      final exported = await importer.exportDrugs(
          format: 'JSON',
          hideCostPrices: false,
          branchId: 1,
          outputDirectory: temp);
      final decoded = jsonDecode(await exported.readAsString()) as List;
      expect(decoded, hasLength(1));
      final original = Map<String, Object?>.from(decoded.single as Map);
      expect(original.keys.toSet(), DrugImportFieldCatalog.allFields);
      expect(original.keys, contains('catalog_uuid'));
      expect(original.keys, contains('catalog_version'));
      expect(original['ingredients_json'], ingredients);
      expect(original['ped_doses_per_day'], 3);
      expect(original['strip_price_mode'], 'MANUAL');
      expect(original['indications'], 'بيانات حقيقية للاستعمال');
      original['internal_code'] = 'ROUND-CLONE';
      original['uuid'] = 'file-uuid-must-not-be-restored';
      original['stock_total_units'] = 5000;
      final cloneFile = await put('round-trip.json', jsonEncode([original]));
      final preview =
          await importer.dryRunImportFile(file: cloneFile, format: 'JSON');
      expect(preview.errors, isEmpty);
      final result =
          await importer.executeImportFile(file: cloneFile, format: 'JSON');
      expect(result.inserted, 1);
      expect(result.errors, 0);
      final cloned = (await db.query('drugs',
              where: 'internal_code=?', whereArgs: ['ROUND-CLONE']))
          .single;
      expect(cloned['ingredients_json'], ingredients);
      expect(cloned['ped_doses_per_day'], 3);
      expect(cloned['strip_price_mode'], 'MANUAL');
      expect(cloned['sell_price_strip'], 60);
      expect(cloned['indications'], 'بيانات حقيقية للاستعمال');
      expect(cloned['is_antibiotic'], 1);
      expect(cloned['uuid'], isNot('file-uuid-must-not-be-restored'));
      expect(cloned['stock_total_units'], 0);
    });

    test('pasted JSON updates only its real fields and never overwrites stock',
        () async {
      final now = DateTime.now().toIso8601String();
      await db.insert('drugs', {
        'uuid': 'existing-paste',
        'branch_id': 1,
        'created_at': now,
        'updated_at': now,
        'internal_code': 'PASTE-SAFE',
        'trade_name_ar': 'دواء محفوظ',
        'sell_price_pack': 145,
        'stock_total_units': 28,
        'indications': 'السابق'
      });
      final source = jsonEncode([
        {
          'internal_code': 'PASTE-SAFE',
          'indications': 'الجديد من JSON',
          'ped_doses_per_day': 4,
          'strip_price_mode': 'MANUAL',
          'stock_total_units': 99999,
          'uuid': 'malicious-overwrite'
        }
      ]);
      final preview = await importer.dryRunImport(
          source: source, format: 'JSON', branchId: 1);
      expect(preview.validRows, 1);
      expect(preview.errors, isEmpty);
      final result = await importer.executeImport(
        source: source,
        format: 'JSON',
        branchId: 1,
        conflictPolicy: 'OVERWRITE',
      );
      expect(result.updated, 1);
      expect(result.errors, 0);
      final saved = (await db.query('drugs',
              where: 'internal_code=?', whereArgs: ['PASTE-SAFE']))
          .single;
      expect(saved['indications'], 'الجديد من JSON');
      expect(saved['ped_doses_per_day'], 4);
      expect(saved['strip_price_mode'], 'MANUAL');
      expect(saved['stock_total_units'], 28);
      expect(saved['sell_price_pack'], 145);
      expect(saved['uuid'], 'existing-paste');
      expect(saved['trade_name_ar'], 'دواء محفوظ');
    });

    test('field preview shows actual values, matching and read-only status',
        () async {
      final file = await put(
          'preview-fields.json',
          jsonEncode([
            {
              'trade_name_ar': 'المادة الحقيقية',
              'medical_details': {'note': 'قيمة حقيقية'},
              'stock_total_units': 99,
              'strip_price_mode': 'MANUAL'
            }
          ]));
      final preview = await importer.inspectImportFile(
          file: file,
          format: 'JSON',
          mapping: {'medical_details': 'warnings_json'});
      final mapped =
          preview.singleWhere((row) => row.sourceField == 'medical_details');
      expect(mapped.targetField, 'warnings_json');
      expect(mapped.sampleValue, contains('قيمة حقيقية'));
      expect(mapped.willImport, isTrue);
      final readonly =
          preview.singleWhere((row) => row.sourceField == 'stock_total_units');
      expect(readonly.willImport, isFalse);
      expect(readonly.status, contains('محمي'));
      final dry = await importer.dryRunImportFile(
          file: file,
          format: 'JSON',
          mapping: {'medical_details': 'warnings_json'});
      expect(dry.errors, isEmpty);
      final result = await importer.executeImportFile(
          file: file,
          format: 'JSON',
          mapping: {'medical_details': 'warnings_json'});
      expect(result.inserted, 1);
      final saved = (await db.query('drugs',
              where: 'trade_name_ar=?', whereArgs: ['المادة الحقيقية']))
          .single;
      expect(saved['warnings_json'], '{"note":"قيمة حقيقية"}');
      expect(saved['stock_total_units'], 0);
      expect(saved['strip_price_mode'], 'MANUAL');
    });

    test('unknown and nonexistent mapped fields fail instead of disappearing',
        () async {
      final file = await put(
          'invalid-fields.json',
          jsonEncode([
            {
              'trade_name_ar': 'دواء آخر',
              'fictional_column': 'القيمة التي لا يجوز إخفاؤها'
            }
          ]));
      final unbound =
          await importer.dryRunImportFile(file: file, format: 'JSON');
      expect(unbound.validRows, 0);
      expect(unbound.errors.single.message, contains('fictional_column'));
      final invalidMapping = await importer.dryRunImportFile(
          file: file,
          format: 'JSON',
          mapping: {'fictional_column': 'nonexistent_field'});
      expect(invalidMapping.validRows, 0);
      expect(
          invalidMapping.errors.single.message, contains('nonexistent_field'));
      final validMapping = await importer.dryRunImportFile(
          file: file,
          format: 'JSON',
          mapping: {'fictional_column': 'indications'});
      expect(validMapping.validRows, 1);
    });

    test('export respects the selected branch and does not leak other drugs',
        () async {
      final now = DateTime.now().toIso8601String();
      await db.insert('drugs', {
        'uuid': 'export-scope-test',
        'branch_id': 1,
        'created_at': now,
        'updated_at': now,
        'internal_code': 'EXPORTED-ONE',
        'trade_name_ar': 'دواء الفرع',
      });
      final other = await importer.exportDrugs(
          format: 'JSON', branchId: 989, outputDirectory: temp);
      expect(jsonDecode(await other.readAsString()), isEmpty);
      final own = await importer.exportDrugs(
          format: 'JSON', branchId: 1, outputDirectory: temp);
      expect(jsonDecode(await own.readAsString()), hasLength(1));
    });
    test('JSON import persists real calculated package units and AUTO prices',
        () async {
      final file = await put(
          'auto-price.json',
          jsonEncode([
            {
              'internal_code': 'AUTO-PRICE',
              'trade_name_ar': 'دواء بتسعير محسوب',
              'sell_price_pack': 120,
              'strips_per_pack': 2,
              'units_per_strip': 10,
              'strip_price_mode': 'AUTO'
            }
          ]));
      final import =
          await importer.executeImportFile(file: file, format: 'JSON');
      expect(import.inserted, 1);
      final original = (await db.query('drugs',
              where: 'internal_code=?', whereArgs: ['AUTO-PRICE']))
          .single;
      expect(original['units_per_pack'], 20);
      expect(original['sell_price_strip'], 60);
      expect(original['sell_price_unit'], 6);

      final changed = await put(
          'auto-update.json',
          jsonEncode([
            {
              'internal_code': 'AUTO-PRICE',
              'strips_per_pack': 3,
              'sell_price_pack': 180
            }
          ]));
      final preview =
          await importer.dryRunImportFile(file: changed, format: 'JSON');
      expect(preview.validRows, 1);
      expect(preview.errors, isEmpty);
      final update = await importer.executeImportFile(
          file: changed, format: 'JSON', conflictPolicy: 'OVERWRITE');
      expect(update.updated, 1);
      final stored = (await db.query('drugs',
              where: 'internal_code=?', whereArgs: ['AUTO-PRICE']))
          .single;
      expect(stored['strips_per_pack'], 3);
      expect(stored['units_per_pack'], 30);
      expect(stored['sell_price_pack'], 180);
      expect(stored['sell_price_strip'], 60);
      expect(stored['sell_price_unit'], 6);
    });

    test(
      'code-only patches cannot create nameless drugs or cross branches',
      () async {
        final now = DateTime.now().toIso8601String();
        await db.insert('drugs', {
          'uuid': 'scoped-partial-update',
          'branch_id': 1,
          'created_at': now,
          'updated_at': now,
          'internal_code': 'SCOPED-PATCH',
          'trade_name_ar': 'دواء الفرع الأول',
          'indications': 'القيمة الأصلية',
        });
        for (final scenario in [
          {'code': 'UNKNOWN-PATCH', 'branch': 1, 'strips': 2},
          {'code': 'SCOPED-PATCH', 'branch': 989, 'strips': 2},
          {'code': 'SCOPED-PATCH', 'branch': 1, 'strips': 0},
        ]) {
          final source = jsonEncode([
            {
              'internal_code': scenario['code'],
              'indications': 'قيمة مرفوضة',
              'strips_per_pack': scenario['strips'],
            },
          ]);
          final branchId = scenario['branch'] as int;
          final preview = await importer.dryRunImport(
            source: source,
            format: 'JSON',
            branchId: branchId,
          );
          expect(preview.validRows, 0);
          expect(preview.errors, hasLength(1));
          final result = await importer.executeImport(
            source: source,
            format: 'JSON',
            branchId: branchId,
            conflictPolicy: 'OVERWRITE',
          );
          expect(result.inserted, 0);
          expect(result.updated, 0);
          expect(result.errors, 1);
        }
        final rows = await db.query('drugs');
        expect(rows, hasLength(1));
        expect(rows.single['indications'], 'القيمة الأصلية');
      },
    );

    test('JSON cannot change packaging while a drug has physical stock',
        () async {
      final now = DateTime.now().toIso8601String();
      await db.insert('drugs', {
        'uuid': 'live-packaging',
        'branch_id': 1,
        'created_at': now,
        'updated_at': now,
        'internal_code': 'PACK-LOCKED',
        'trade_name_ar': 'دواء بمخزون قائم',
        'strips_per_pack': 2,
        'units_per_strip': 10,
        'units_per_pack': 20,
        'stock_total_units': 20
      });
      final file = await put(
          'illegal-packaging.json',
          jsonEncode([
            {
              'internal_code': 'PACK-LOCKED',
              'strips_per_pack': 5,
              'stock_total_units': 0
            }
          ]));
      final result = await importer.executeImportFile(
          file: file, format: 'JSON', conflictPolicy: 'OVERWRITE');
      expect(result.updated, 0);
      expect(result.errors, 1);
      final stored = (await db.query('drugs',
              where: 'internal_code=?', whereArgs: ['PACK-LOCKED']))
          .single;
      expect(stored['strips_per_pack'], 2);
      expect(stored['units_per_pack'], 20);
      expect(stored['stock_total_units'], 20);
    });

    test('manufacturer names preview without writes, reuse and display by name',
        () async {
      final file = await put(
          'companies.json',
          jsonEncode([
            {
              'internal_code': 'COMP-A',
              'trade_name_ar': 'صنف أ',
              'manufacturer_name': 'Hikma Pharma'
            },
            {
              'internal_code': 'COMP-B',
              'trade_name_ar': 'صنف ب',
              'manufacturer_name': '  hikma pharma  '
            },
          ]));
      final preview =
          await importer.dryRunImportFile(file: file, format: 'JSON');
      expect(preview.validRows, 2);
      expect(await db.query('manufacturers'), isEmpty);
      final imported =
          await importer.executeImportFile(file: file, format: 'JSON');
      expect(imported.inserted, 2);
      expect(imported.errors, 0);
      final company = (await db.query('manufacturers')).single;
      final drugs = await db.query('drugs');
      expect(drugs.every((r) => r['manufacturer_id'] == company['id']), isTrue);
      final provider =
          PosAndDrugsProvider(database: DatabaseHelper.forTesting(db));
      await provider.loadDrugs();
      expect(provider.drugs, hasLength(2));
      expect(provider.drugs.every((d) => d.manufacturerName == 'Hikma Pharma'),
          isTrue);
      await provider.searchDrugs('COMP-');
      expect(provider.drugs.every((d) => d.manufacturerName == 'Hikma Pharma'),
          isTrue);
      provider.dispose();
      final retry =
          await importer.executeImportFile(file: file, format: 'JSON');
      expect(retry.skipped, 2);
      expect(await db.query('manufacturers'), hasLength(1));
    });

    test(
        'fill-empty company repair preserves existing prices, stock and identity',
        () async {
      final original = await put(
          'company-original.json',
          jsonEncode([
            {
              'internal_code': 'COMP-REPAIR',
              'trade_name_ar': 'صنف سابق',
              'sell_price_pack': 145
            }
          ]));
      expect(
          (await importer.executeImportFile(file: original, format: 'JSON'))
              .inserted,
          1);
      final old = (await db.query('drugs')).single;
      await db.update(
          'drugs',
          {
            'stock_total_units': 28,
            'sell_price_strip': 77,
            'sell_price_unit': 11
          },
          where: 'id=?',
          whereArgs: [old['id']]);
      final source = jsonEncode([
        {'internal_code': 'COMP-REPAIR', 'manufacturer_name': 'Repair Company'}
      ]);
      expect(
          (await importer.dryRunImport(source: source, format: 'JSON'))
              .validRows,
          1);
      final repair = await importer.executeImport(
          source: source, format: 'JSON', conflictPolicy: 'UPDATE_EMPTY_ONLY');
      expect(repair.updated, 1);
      final saved = (await db.query('drugs')).single;
      expect(saved['manufacturer_id'], isNotNull);
      expect(saved['sell_price_pack'], 145);
      expect(saved['sell_price_strip'], 77);
      expect(saved['sell_price_unit'], 11);
      expect(saved['stock_total_units'], 28);
      expect(saved['uuid'], old['uuid']);
      expect(saved['trade_name_ar'], old['trade_name_ar']);
      final ignored = await importer.executeImport(
          source: jsonEncode([
            {
              'internal_code': 'COMP-REPAIR',
              'manufacturer_name': 'Do Not Create'
            }
          ]),
          format: 'JSON',
          conflictPolicy: 'UPDATE_EMPTY_ONLY');
      expect(ignored.skipped, 1);
      expect(await db.query('manufacturers'), hasLength(1));
    });

    test('a rejected drug row rolls back its newly created company', () async {
      final original = await put(
          'rollback-original.json',
          jsonEncode([
            {'internal_code': 'COMP-ROLLBACK', 'trade_name_ar': 'دواء له مخزون'}
          ]));
      await importer.executeImportFile(file: original, format: 'JSON');
      await db.update('drugs', {'stock_total_units': 5});
      final result = await importer.executeImport(
          source: jsonEncode([
            {
              'internal_code': 'COMP-ROLLBACK',
              'manufacturer_name': 'Orphan Must Not Exist',
              'strips_per_pack': 2
            }
          ]),
          format: 'JSON',
          conflictPolicy: 'OVERWRITE');
      expect(result.errors, 1);
      expect(result.updated, 0);
      expect(await db.query('manufacturers'), isEmpty);
      expect((await db.query('drugs')).single['manufacturer_id'], isNull);
    });

    test('company names do not reuse another branch or contradict explicit IDs',
        () async {
      final now = DateTime.now().toIso8601String();
      final other = await db.insert('manufacturers', {
        'uuid': 'other-company',
        'branch_id': 2,
        'created_at': now,
        'updated_at': now,
        'name_ar': 'Shared Company',
        'name_en': 'Shared Company',
      });
      final source = jsonEncode([
        {
          'internal_code': 'COMP-SCOPE',
          'trade_name_ar': 'صنف الفرع',
          'manufacturer_name': 'Shared Company'
        }
      ]);
      final result = await importer.executeImport(
          source: source, format: 'JSON', branchId: 1);
      expect(result.inserted, 1);
      final own = (await db.query('drugs')).single['manufacturer_id'];
      expect(own, isNot(other));
      final conflict = jsonEncode([
        {
          'internal_code': 'COMP-CONFLICT',
          'trade_name_ar': 'اسم متعارض',
          'manufacturer_name': 'Different Company',
          'manufacturer_id': own
        }
      ]);
      expect(
          (await importer.dryRunImport(source: conflict, format: 'JSON'))
              .validRows,
          0);
      expect(
          (await importer.executeImport(source: conflict, format: 'JSON'))
              .errors,
          1);
      expect(await db.query('drugs'), hasLength(1));
      expect(await db.query('manufacturers'), hasLength(2));
    });

    test('dry run rejects fake foreign keys instead of reporting success',
        () async {
      final file = await put(
          'broken-reference.json',
          jsonEncode([
            {'trade_name_ar': 'دواء بمرجع مفقود', 'manufacturer_id': 999999}
          ]));
      final preview = await importer.dryRunImportFile(
          file: file, format: 'JSON', branchId: 1);
      expect(preview.validRows, 0);
      expect(preview.errors, hasLength(1));
      expect(preview.errors.single.message, contains('manufacturer_id'));
      final import = await importer.executeImportFile(
          file: file, format: 'JSON', branchId: 1);
      expect(import.inserted, 0);
      expect(import.errors, 1);
    });
  });
}
