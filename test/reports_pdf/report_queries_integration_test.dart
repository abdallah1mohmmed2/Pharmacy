import 'package:flutter_test/flutter_test.dart';

import '../../lib/data/database/database_helper.dart';
import '../../lib/reports_pdf/models_and_contracts.dart';
import '../../lib/reports_pdf/registry/report_registry_and_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await DatabaseHelper.instance.database;
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
  });

  test('registry contains all 55 reports without gaps', () {
    final registry = ReportRegistry();
    expect(registry.all, hasLength(55));
    for (var index = 0; index < registry.all.length; index++) {
      expect(registry.all[index].number, index + 1);
    }
  });

  test('all 55 report queries execute against the current SQLite schema', () async {
    final registry = ReportRegistry();
    for (final definition in registry.all) {
      final values = <String, Object?>{};
      for (final parameter in definition.params) {
        if (parameter.defaultValue != null) {
          values[parameter.key] = parameter.defaultValue;
        } else if (parameter.required) {
          values[parameter.key] = switch (parameter.kind) {
            ReportParamKind.date => '2026-01-01',
            ReportParamKind.dateRange => '2026-01-01',
            ReportParamKind.customer ||
            ReportParamKind.supplier ||
            ReportParamKind.employee ||
            ReportParamKind.drug ||
            ReportParamKind.warehouse ||
            ReportParamKind.cashier ||
            ReportParamKind.category ||
            ReportParamKind.number => 1,
            ReportParamKind.text => 'test',
            ReportParamKind.boolean => true,
            ReportParamKind.orientation => 'portrait',
          };
        }
      }

      final result = await definition.run(
        ReportParams(
          branchId: 1,
          userId: 1,
          userName: 'اختبار',
          canViewCost: true,
          showCostSetting: true,
          values: values,
        ),
      );
      expect(result.reportNumber, definition.number);
    }
  });
}
