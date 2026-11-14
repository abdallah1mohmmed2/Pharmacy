import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:global_enterprise_pharmacy_erp/core/theme/enterprise_dark_theme.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/drug_model.dart';
import 'package:global_enterprise_pharmacy_erp/providers/pos_and_drugs_provider.dart';
import 'package:global_enterprise_pharmacy_erp/screens/drugs/s08_s09_drug_encyclopedia_screen.dart';

class _Pos extends PosAndDrugsProvider {
  DrugModel? saved;
  @override
  Future<void> saveDrug(DrugModel drug) async {
    saved = drug;
  }

  @override
  Future<void> loadDrugs() async {}
}

Future<void> _setup(WidgetTester tester, _Pos provider) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(provider.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<PosAndDrugsProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: EnterpriseDarkTheme.data,
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: S08S09DrugEncyclopediaScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('new drug editor saves switch as 0, not changed field contract',
      (tester) async {
    final provider = _Pos();
    await _setup(tester, provider);
    await tester.tap(find.text('إضافة دواء يدوياً'));
    await tester.pumpAndSettle();
    expect(find.text('إضافة دواء'), findsOneWidget);
    expect(find.byKey(const ValueKey('drug-switch-is_active')), findsOneWidget);
    expect(find.byKey(const ValueKey('drug-choice-route')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('drug-text-internal_code')), 'SKU-NEW');
    await tester.enterText(
        find.byKey(const ValueKey('drug-text-trade_name_ar')), 'دواء تجريبي');
    await tester.tap(find.byKey(const ValueKey('drug-switch-is_active')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ جميع البيانات'));
    await tester.pumpAndSettle();
    expect(provider.saved, isNotNull);
    expect(provider.saved!.isActive, isFalse);
    expect(provider.saved!.internalCode, 'SKU-NEW');
    expect(provider.saved!.dosageForm, 'OTHER');
    expect(provider.saved!.route, 'OTHER');
    expect(provider.saved!.stripPriceMode, 'AUTO');
  });

  testWidgets(
      'editing drug preserves detailed and clinical data when sections remain closed',
      (tester) async {
    const old = DrugModel(
      id: 99,
      internalCode: 'SKU-OLD',
      tradeNameAr: 'دواء مسجل',
      scientificName: 'اسم علمي',
      dosageForm: 'CAPSULE',
      route: 'ORAL',
      stripPriceMode: 'MANUAL',
      stripsPerPack: 3,
      unitsPerStrip: 10,
      sellPricePack: 300,
      sellPriceStrip: 110,
      sellPriceUnit: 12,
      isControlled: true,
      isAntibiotic: true,
      isNephrotoxic: true,
      renalStatus: 'ADJUST',
      renalNotes: 'ملاحظة محفوظة',
      pregnancyCategory: 'D',
      ingredientsJson: '[{"active":"demo"}]',
    );
    final provider = _Pos()..drugs = [old];
    await _setup(tester, provider);
    await tester.tap(find.byTooltip('عرض التفاصيل'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit).first);
    await tester.pumpAndSettle();
    expect(find.text('تعديل بيانات الدواء'), findsOneWidget);
    await tester.tap(find.text('حفظ جميع البيانات'));
    await tester.pumpAndSettle();
    expect(provider.saved, isNotNull);
    expect(provider.saved!.toMap(), old.toMap());
  });
}
