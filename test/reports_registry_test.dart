// test/reports_registry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy/reports_pdf/models_and_contracts.dart';
import 'package:pharmacy/reports_pdf/registry/report_registry_and_provider.dart';
import 'package:pharmacy/reports_pdf/engine/pdf_report_engine.dart';

void main() {
  group('Reports registry', () {
    test('contains every report number from 1 through 55 exactly once', () {
      final registry = ReportRegistry();
      expect(registry.all, hasLength(55));
      expect(registry.all.map((r) => r.number).toList(),
          List<int>.generate(55, (index) => index + 1));
      for (final category in ReportCategory.values) {
        expect(registry.byCategory(category), hasLength(category.reportCount));
      }
    });

    test('search supports report number and Arabic title', () {
      final registry = ReportRegistry();
      expect(registry.search('45').single.number, 45);
      expect(registry.search('كشف حساب عميل').single.number, 33);
    });

    test('cost columns are hidden unless permission and setting are both enabled', () {
      const masker = CostMasker();
      const columns = [
        ReportColumn(key: 'name', label: 'الصنف'),
        ReportColumn(key: 'cost', label: 'التكلفة', costSensitive: true),
      ];
      final denied = ReportParams(canViewCost: true, showCostSetting: false);
      final allowed = ReportParams(canViewCost: true, showCostSetting: true);
      expect(masker.filter(columns, denied).map((c) => c.key), ['name']);
      expect(masker.filter(columns, allowed).map((c) => c.key), ['name', 'cost']);
    });

    test('totals sum only configured columns and calculate derived percentages', () {
      const columns = [
        ReportColumn(key: 'sales', label: 'المبيعات', sumInTotals: true),
        ReportColumn(key: 'profit', label: 'الربح', sumInTotals: true),
      ];
      final spec = TotalsSpec(
        sumKeys: const ['sales', 'profit'],
        derivedValues: {
          'margin': (values) => values['sales']! == 0
              ? 0
              : values['profit']! * 100 / values['sales']!,
        },
      );
      final result = spec.calculate([
        {'sales': 100, 'profit': 20},
        {'sales': 300, 'profit': 90},
      ], columns);
      expect(result['sales'], 400);
      expect(result['profit'], 110);
      expect(result['margin'], 27.5);
    });
  });
}
