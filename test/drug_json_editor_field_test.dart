import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/screens/drugs/drug_json_editor_field.dart';

Future<void> _show(
    WidgetTester tester, TextEditingController controller, String key) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: DrugJsonEditorField(
          fieldKey: key,
          label: 'تركيب الدواء المركب',
          controller: controller,
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('compound JSON displays names, not a long raw text field',
      (tester) async {
    final controller = TextEditingController(
      text:
          '[{"name":"first","dose":"20 mg"},{"ingredient":"second","code":9}]',
    );
    addTearDown(controller.dispose);
    await _show(tester, controller, 'ingredients_json');
    expect(find.textContaining('2 مكونات: first، second'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('compound edits preserve legacy metadata and list ordering',
      (tester) async {
    final controller = TextEditingController(
        text: '[{"name":"first","dose":"20 mg"},'
            '{"ingredient":"second","code":9}]');
    addTearDown(controller.dispose);
    await _show(tester, controller, 'ingredients_json');
    await tester.tap(find.byKey(const ValueKey('drug-json-ingredients_json')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('drug-ingredient-0')), 'renamed');
    await tester.tap(find.text('إضافة مكون'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('drug-ingredient-2')), 'third');
    await tester.tap(find.text('حفظ التعديل'));
    await tester.pumpAndSettle();

    final rows = jsonDecode(controller.text) as List;
    expect(rows, [
      {'name': 'renamed', 'dose': '20 mg'},
      {'ingredient': 'second', 'code': 9},
      {'name': 'third'}
    ]);
  });

  testWidgets('opening and closing existing JSON preserves original bytes',
      (tester) async {
    const original = '[ { "ingredient": "one", "weight": 12 } ]';
    final controller = TextEditingController(text: original);
    addTearDown(controller.dispose);
    await _show(tester, controller, 'ingredients_json');
    await tester.tap(find.byKey(const ValueKey('drug-json-ingredients_json')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ التعديل'));
    await tester.pumpAndSettle();
    expect(controller.text, original);
  });

  testWidgets('cancel does not overwrite complex or unknown legacy JSON',
      (tester) async {
    const original = '[{"unknown":{"nested":[1,2,3]}}]';
    final controller = TextEditingController(text: original);
    addTearDown(controller.dispose);
    await _show(tester, controller, 'ingredients_json');
    await tester.tap(find.byKey(const ValueKey('drug-json-ingredients_json')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('drug-json-raw-editor')), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(controller.text, original);
  });

  testWidgets('malformed JSON cannot be silently saved', (tester) async {
    const original = '[broken';
    final controller = TextEditingController(text: original);
    addTearDown(controller.dispose);
    await _show(tester, controller, 'warnings_json');
    await tester.tap(find.byKey(const ValueKey('drug-json-warnings_json')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('drug-json-raw-editor')), '{invalid');
    await tester.tap(find.text('حفظ التعديل'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تنسيق البيانات غير صحيح'), findsOneWidget);
    expect(controller.text, original);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
  });

  testWidgets('unchanged clinical JSON map is shown compactly and preserved',
      (tester) async {
    final controller = TextEditingController(
        text: '{"first":{"risk":"low"},"second":{"risk":"high"}}');
    addTearDown(controller.dispose);
    await _show(tester, controller, 'pregnancy_trimester_json');
    expect(find.textContaining('2 حقول محفوظة'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('drug-json-pregnancy_trimester_json')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ التعديل'));
    await tester.pumpAndSettle();
    expect(jsonDecode(controller.text), {
      'first': {'risk': 'low'},
      'second': {'risk': 'high'}
    });
  });
}
