import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/database_helper.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/drug_model.dart';
import 'package:global_enterprise_pharmacy_erp/providers/pos_and_drugs_provider.dart';
import 'package:global_enterprise_pharmacy_erp/screens/purchases/purchase_medicine_search_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('purchase medicine search remains bounded with 27,000 records',
      () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE drugs (
              id INTEGER PRIMARY KEY, branch_id INTEGER NOT NULL,
              is_deleted INTEGER NOT NULL, is_active INTEGER NOT NULL,
              internal_code TEXT, trade_name_ar TEXT, trade_name_en TEXT,
              scientific_name TEXT, strength_text TEXT,
              barcode_local TEXT, barcode_international TEXT,
              requires_refrigeration INTEGER
            )''');
        },
      ),
    );
    try {
      // SQLite populates all rows without creating 27k Dart widgets or models.
      for (var offset = 0; offset < 27000; offset += 900) {
        await db.rawInsert('''
          WITH RECURSIVE seq(n) AS (
            SELECT 1 UNION ALL SELECT n+1 FROM seq WHERE n<900
          )
          INSERT INTO drugs
            (id, branch_id, is_deleted, is_active, internal_code,
             trade_name_ar, trade_name_en, scientific_name)
          SELECT n + ?, 1, 0, 1, 'DR-' || (n + ?),
                 'دواء تجريبي ' || (n + ?), 'Medicine ' || (n + ?),
                 'test-substance' FROM seq
        ''', [offset, offset, offset, offset]);
      }
      await db.insert('drugs', {
        'id': 27001,
        'branch_id': 2,
        'is_deleted': 0,
        'is_active': 1,
        'internal_code': 'OTHER-BRANCH',
        'trade_name_ar': 'دواء مميز خاص',
      });
      await db.insert('drugs', {
        'id': 27002,
        'branch_id': 1,
        'is_deleted': 0,
        'is_active': 1,
        'internal_code': 'SPECIAL-A',
        'trade_name_ar': 'دواء مميز',
        'barcode_international': '1234567890123',
        'requires_refrigeration': 1,
      });
      final provider =
          PosAndDrugsProvider(database: DatabaseHelper.forTesting(db));
      final results = await provider.searchPurchaseDrugs('دواء', branchId: 1);
      expect(results.length, 40);
      expect(provider.drugs, isEmpty,
          reason: 'Purchase search must not mutate the POS medicines cache');

      final special = await provider.searchPurchaseDrugs('مميز', branchId: 1);
      expect(special.map((d) => d.id).toList(), [27002]);
      expect(special.single.requiresRefrigeration, isTrue);

      final barcode =
          await provider.searchPurchaseDrugs('1234567890123', branchId: 1);
      expect(barcode.single.id, 27002);

      final otherBranch =
          await provider.searchPurchaseDrugs('مميز', branchId: 2);
      expect(otherBranch.single.id, 27001);
      expect(await provider.searchPurchaseDrugs('', branchId: 1), isEmpty);
      expect(await provider.searchPurchaseDrugs('%', branchId: 1), isEmpty);
      // Checkout is never allowed to load all 27k medicine objects.
      await provider.loadDrugs();
      expect(provider.drugs, hasLength(100));
      expect(provider.drugs.every((d) => d.branchId == 1), isTrue);
      await provider.searchDrugs('مميز');
      expect(provider.drugs.map((d) => d.id), [27002]);
      await provider.searchDrugs('1234567890123');
      expect(provider.drugs.single.id, 27002);
      await provider.searchDrugs('');
      expect(provider.drugs.length, lessThanOrEqualTo(100));
      expect(provider.search, isEmpty);
      await provider.setBranchId(2);
      expect(provider.drugs.every((d) => d.branchId == 2), isTrue);
      await provider.searchDrugs('مميز');
      expect(provider.drugs.map((d) => d.id), [27001]);
    } finally {
      await db.close();
    }
  });

  testWidgets('purchase picker searches after typing and selects medicine',
      (tester) async {
    DrugModel? picked;
    final medicine = DrugModel(
      id: 123,
      branchId: 1,
      tradeNameAr: 'دواء البحث',
      tradeNameEn: 'Search medicine',
      internalCode: 'MED-123',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await showModalBottomSheet<DrugModel>(
                context: context,
                isScrollControlled: true,
                builder: (_) => PurchaseMedicineSearchSheet(
                  search: (text) async {
                    expect(text, 'البحث');
                    return [medicine];
                  },
                ),
              );
            },
            child: const Text('فتح البحث'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('فتح البحث'));
    await tester.pumpAndSettle();
    expect(find.text('دواء البحث'), findsNothing);
    await tester.enterText(find.byType(TextField).last, 'البحث');
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pumpAndSettle();
    expect(find.text('دواء البحث'), findsOneWidget);
    await tester.tap(find.text('دواء البحث'));
    await tester.pumpAndSettle();
    expect(picked?.id, 123);
  });
}
