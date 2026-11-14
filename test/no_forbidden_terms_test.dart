// test/no_forbidden_terms_test.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/core/utils/label_guard.dart';
import 'package:global_enterprise_pharmacy_erp/core/widgets/shared_widgets.dart';

void main() {
  test('LabelGuard detects and sanitizes forbidden accounting vocabulary', () {
    expect(LabelGuard.containsForbidden('رصيد مدين'), isTrue);
    expect(LabelGuard.containsForbidden('رصيد دائن'), isTrue);
    expect(LabelGuard.containsForbidden('له 500 وعليه 200'), isFalse);
    expect(LabelGuard.sanitize('مدين 10 / دائن 20'), 'رصيد 10 / رصيد 20');
    expect(() => LabelGuard.assertClean('نص مدين', context: 'اختبار'),
        throwsFormatException);
  });
  test('all screen, report and shared-widget Dart sources use approved labels',
      () async {
    final roots = [
      Directory('lib/screens'),
      Directory('lib/reports_pdf'),
      Directory('lib/core/widgets')
    ];
    final violations = <String>[];
    for (final root in roots) {
      if (!await root.exists()) continue;
      await for (final entity
          in root.list(recursive: true, followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = await entity.readAsString();
        if (RegExp(r'(مدين|دائن)').hasMatch(source))
          violations.add(entity.path);
      }
    }
    expect(violations, isEmpty,
        reason:
            'يجب إزالة المصطلحات التقليدية من الملفات: ${violations.join(', ')}');
  });
  testWidgets('PartyBalanceChip displays only lah-alayh wording',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Center(
                child: PartyBalanceChip(totalAlayh: 150, totalLah: 50)))));
    expect(find.textContaining('المتبقي عليه'), findsOneWidget);
    expect(find.textContaining('مدين'), findsNothing);
    expect(find.textContaining('دائن'), findsNothing);
  });
  testWidgets('PartyBalanceChip displays settled state for equal totals',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Center(
                child: PartyBalanceChip(totalAlayh: 75, totalLah: 75)))));
    expect(find.textContaining('مسدَّد'), findsOneWidget);
  });
}
