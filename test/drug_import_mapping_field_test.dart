import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/screens/drugs/drug_import_mapping_field.dart';

Future<void> _render(
  WidgetTester tester,
  TextEditingController controller, {
  VoidCallback? onChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: DrugImportMappingField(
            controller: controller,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('raw mapping JSON is replaced by a compact summary',
      (tester) async {
    final controller = TextEditingController(
      text: '{"اسم الدواء":"trade_name_ar","التركيز":"strength_text"}',
    );
    addTearDown(controller.dispose);
    await _render(tester, controller);
    expect(find.text('2 أعمدة مرتبطة'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('opening and canceling keeps original JSON bytes', (tester) async {
    const original = '{ "اسم الدواء" : "trade_name_ar" }';
    final controller = TextEditingController(text: original);
    addTearDown(controller.dispose);
    var changes = 0;
    await _render(tester, controller, onChanged: () => changes++);
    await tester.tap(find.byKey(const ValueKey('import-mapping-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(controller.text, original);
    expect(changes, 0);
  });

  testWidgets('adding a mapping retains existing entries', (tester) async {
    final controller = TextEditingController(
        text: '{"اسم الدواء":"trade_name_ar","التركيز":"strength_text"}');
    addTearDown(controller.dispose);
    var changes = 0;
    await _render(tester, controller, onChanged: () => changes++);
    await tester.tap(find.byKey(const ValueKey('import-mapping-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-mapping-add')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
        find.byKey(const ValueKey('import-mapping-source-2')));
    await tester.enterText(
        find.byKey(const ValueKey('import-mapping-source-2')), 'الشركة');
    await tester.enterText(
        find.byKey(const ValueKey('import-mapping-target-2')),
        'manufacturer_id');
    await tester.tap(find.byKey(const ValueKey('import-mapping-save')));
    await tester.pumpAndSettle();
    expect(jsonDecode(controller.text), {
      'اسم الدواء': 'trade_name_ar',
      'التركيز': 'strength_text',
      'الشركة': 'manufacturer_id',
    });
    expect(changes, 1);
  });

  testWidgets('duplicate source columns cannot replace a saved mapping',
      (tester) async {
    const original = '{"أ":"trade_name_ar"}';
    final controller = TextEditingController(text: original);
    addTearDown(controller.dispose);
    await _render(tester, controller);
    await tester.tap(find.byKey(const ValueKey('import-mapping-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-mapping-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('import-mapping-source-1')), 'أ');
    await tester.enterText(
        find.byKey(const ValueKey('import-mapping-target-1')),
        'scientific_name');
    await tester.tap(find.byKey(const ValueKey('import-mapping-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('اسم العمود مكرر'), findsOneWidget);
    expect(controller.text, original);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
  });

  testWidgets('unknown mapping format is not silently cleared',
      (tester) async {
    const original = '{"nested": {"legacy":true}}';
    final controller = TextEditingController(text: original);
    addTearDown(controller.dispose);
    await _render(tester, controller);
    expect(find.text('صيغة الربط تحتاج إلى مراجعة'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-mapping-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('import-mapping-raw-editor')),
        findsOneWidget);
    await tester.tap(find.text('حفظ الربط'));
    await tester.pumpAndSettle();
    expect(controller.text, original);
  });
}
