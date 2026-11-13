import 'dart:convert';
import 'dart:io';

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
      final file = await put('shared-barcode.json', jsonEncode([
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
      final preview = await importer.dryRunImportFile(
          file: file, format: 'JSON');
      expect(preview.validRows, 2);
      expect(preview.barcodeDuplicates, 1);
      final result = await importer.executeImportFile(
          file: file, format: 'JSON');
      expect(result.inserted, 2);
      expect(result.errors, 0);
      expect(result.barcodeConflicts, 1);
      final rows = await db.query('drugs', orderBy: 'internal_code');
      expect(rows, hasLength(2));
      expect(rows.first['barcode_international'], '6221000003295');
      expect(rows.last['barcode_international'], isNull);
      final retry = await importer.executeImportFile(
          file: file, format: 'JSON');
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
  });
}
