import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/database_helper.dart';
import 'package:global_enterprise_pharmacy_erp/screens/drugs/drug_reference_picker_field.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => sqfliteFfiInit());

  test(
      'reference search is bounded, case insensitive, and branch-scoped for categories',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    try {
      await db.execute('''CREATE TABLE drug_categories (
        id INTEGER PRIMARY KEY, branch_id INTEGER NOT NULL, is_deleted INTEGER NOT NULL DEFAULT 0,
        code TEXT NOT NULL, name_ar TEXT, name_en TEXT
      )''');
      await db.execute('''CREATE TABLE manufacturers (
        id INTEGER PRIMARY KEY, is_deleted INTEGER NOT NULL DEFAULT 0,
        name_ar TEXT, name_en TEXT
      )''');
      await db.execute('''CREATE TABLE active_ingredients (
        id INTEGER PRIMARY KEY, is_deleted INTEGER NOT NULL DEFAULT 0,
        name_ar TEXT, inn_name TEXT
      )''');
      await db.insert('drug_categories', {
        'id': 1,
        'branch_id': 1,
        'code': 'ABX',
        'name_ar': 'مضادات حيوية',
      });
      await db.insert('drug_categories', {
        'id': 2,
        'branch_id': 2,
        'code': 'ABX',
        'name_ar': 'مضادات حيوية الفرع الآخر',
      });
      await db.insert('manufacturers', {
        'id': 3,
        'name_ar': 'شركة تجريبية',
      });
      await db.insert('active_ingredients', {
        'id': 4,
        'inn_name': 'Paracetamol',
      });
      final lookup = DrugReferenceLookup(helper: DatabaseHelper.forTesting(db));
      final categories =
          await lookup.search(DrugReferenceKind.category, 'مضادات', 1);
      expect(categories.map((e) => e.id), [1]);
      final maker =
          await lookup.search(DrugReferenceKind.manufacturer, 'تجريبية', 1);
      expect(maker.map((e) => e.id), [3]);
      final ingredient =
          await lookup.search(DrugReferenceKind.ingredient, 'para', 1);
      expect(ingredient.map((e) => e.id), [4]);
      expect(await lookup.search(DrugReferenceKind.category, '%', 1), isEmpty);
    } finally {
      await db.close();
    }
  });

  testWidgets('reference choice writes only the ID and can be cleared',
      (tester) async {
    final id = TextEditingController();
    addTearDown(id.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DrugReferencePickerField(
          fieldKey: 'manufacturer_id',
          label: 'الشركة المصنعة',
          kind: DrugReferenceKind.manufacturer,
          branchId: 1,
          controller: id,
          searcher: (_, __, ___) async =>
              const [DrugReferenceChoice(42, 'شركة الاختبار')],
        ),
      ),
    ));
    await tester
        .tap(find.byKey(const ValueKey('drug-reference-manufacturer_id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drug-ref-choice-42')));
    await tester.pumpAndSettle();
    expect(id.text, '42');
    expect(find.textContaining('شركة الاختبار'), findsOneWidget);
    await tester.tap(find.byTooltip('إلغاء اختيار الشركة المصنعة'));
    await tester.pumpAndSettle();
    expect(id.text, isEmpty);
  });
}
