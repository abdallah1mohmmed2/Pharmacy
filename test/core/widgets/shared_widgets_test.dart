import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/core/theme/enterprise_dark_theme.dart';
import 'package:global_enterprise_pharmacy_erp/core/widgets/shared_widgets.dart';

void main() {
  group('Responsive shared widgets', () {
    testWidgets('ResponsiveLayout selects the phone layout below 700px',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: ResponsiveLayout(
              mobile: const Text('phone-layout'),
              desktop: const Text('desktop-layout'),
            ),
          ),
        ),
      );

      expect(find.text('phone-layout'), findsOneWidget);
      expect(find.text('desktop-layout'), findsNothing);
    });

    testWidgets('ResponsiveLayout selects the desktop layout at 700px',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(700, 900)),
            child: ResponsiveLayout(
              mobile: const Text('phone-layout'),
              desktop: const Text('desktop-layout'),
            ),
          ),
        ),
      );

      expect(find.text('desktop-layout'), findsOneWidget);
      expect(find.text('phone-layout'), findsNothing);
    });

    testWidgets('PartyBalanceChip uses the approved balance wording',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: EnterpriseDarkTheme.data,
          home: const Scaffold(
            body: Center(
              child: PartyBalanceChip(totalAlayh: 125, totalLah: 25),
            ),
          ),
        ),
      );

      expect(find.text('المتبقي عليه 100.00'), findsOneWidget);
    });

    testWidgets('SmartExpandableCard reveals details after expansion',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: EnterpriseDarkTheme.data,
          home: const Scaffold(
            body: SmartExpandableCard(
              title: 'دواء تجريبي',
              primary: '100.00',
              details: [Text('تفاصيل إضافية')],
            ),
          ),
        ),
      );

      expect(find.text('تفاصيل إضافية'), findsNothing);
      await tester.tap(find.text('دواء تجريبي'));
      await tester.pumpAndSettle();
      expect(find.text('تفاصيل إضافية'), findsOneWidget);
    });

    testWidgets('LahAlayhTable displays mobile movement cards',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: EnterpriseDarkTheme.data,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Scaffold(
              body: SizedBox(
                height: 700,
                child: LahAlayhTable(
                rows: const [
                  LahAlayhRow(
                    date: '2026-11-07',
                    statement: 'فاتورة بيع',
                    document: 'INV-1',
                    alayh: 100,
                    lah: 20,
                  ),
                ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('فاتورة بيع'), findsOneWidget);
      expect(find.text('عرض الجدول'), findsOneWidget);
    });
  });
}

