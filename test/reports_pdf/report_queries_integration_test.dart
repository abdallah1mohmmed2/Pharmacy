import 'package:flutter_test/flutter_test.dart';

import '../../lib/data/database/database_helper.dart';
import '../../lib/reports_pdf/models_and_contracts.dart';
import '../../lib/reports_pdf/registry/report_registry_and_provider.dart';
import '../../lib/providers/pos_and_drugs_provider.dart';
import '../../lib/data/models/drug_model.dart';

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

  test('reports provider initializes from Iteration 6 permissions and settings', () async {
    final provider = ReportsCenterProvider();
    await provider.initialize(
      userId: 1,
      userName: 'مدير النظام',
      branchId: 1,
    );

    expect(provider.hasCostPermission, isTrue);
    expect(provider.showCostSetting, isFalse);

    await provider.updateCostVisibility(true);
    expect(provider.showCostSetting, isTrue);
    expect(provider.canViewCost, isTrue);

    final db = await DatabaseHelper.instance.database;
    final setting = await db.query(
      'system_settings',
      columns: ['setting_value'],
      where: 'setting_key=?',
      whereArgs: ['sales.show_cost_to_pharmacist'],
      limit: 1,
    );
    expect(setting.single['setting_value'], 'true');

    await provider.updateCostVisibility(false);
    expect(provider.showCostSetting, isFalse);
    expect(provider.canViewCost, isFalse);
  });


  test('drug catalogue saves never alter batch-derived stock balances', () async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('drugs', orderBy: 'id', limit: 1);
    expect(rows, isNotEmpty);
    final original = DrugModel.fromMap(rows.single);
    final originalStock = rows.single['stock_total_units'];

    final alteredMap = Map<String, Object?>.from(original.toMap())
      ..['stock_total_units'] = 999999;
    final altered = DrugModel.fromMap(alteredMap);
    await PosAndDrugsProvider().saveDrug(altered);

    final saved = await db.query(
      'drugs',
      columns: ['stock_total_units'],
      where: 'id=?',
      whereArgs: [original.id],
      limit: 1,
    );
    expect(saved.single['stock_total_units'], originalStock);
  });

}
