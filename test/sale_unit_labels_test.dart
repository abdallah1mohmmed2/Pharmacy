import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/drug_model.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/sale_unit_labels.dart';

void main() {
  test('tablets retain the three-level pack/strip/pill sale', () {
    const drug = DrugModel(dosageForm: 'TABLET', stripsPerPack: 3, unitsPerStrip: 10);
    expect(drugAvailableSaleUnits(drug), ['PACK', 'STRIP', 'UNIT']);
    expect(drugSaleUnitLabel(drug, 'STRIP'), 'شريط');
    expect(drugSaleUnitLabel(drug, 'UNIT'), 'حبة');
    expect(drug.toBaseUnits('PACK', 2), 60);
  });

  test('injectables do not offer strips', () {
    const drug = DrugModel(dosageForm: 'INJECTION', stripsPerPack: 5);
    expect(drugAvailableSaleUnits(drug), ['PACK', 'UNIT']);
    expect(drugSaleUnitLabel(drug, 'UNIT'), 'أمبولة/فيال');
    expect(drug.toBaseUnits('PACK', 2), 10);
  });

  test('syrups, creams and inhalers use correct retail unit names', () {
    for (final data in [
      ('SYRUP', 'زجاجة'),
      ('SUSPENSION', 'زجاجة'),
      ('DROPS', 'زجاجة'),
      ('CREAM', 'أنبوب'),
      ('OINTMENT', 'أنبوب'),
      ('INHALER', 'بخاخ'),
      ('SACHET', 'كيس'),
      ('SUPPOSITORY', 'تحميلة')
    ]) {
      final drug = DrugModel(dosageForm: data.$1);
      expect(drugSaleUnitLabel(drug, 'UNIT'), data.$2);
      expect(drugAvailableSaleUnits(drug), ['PACK', 'UNIT']);
    }
  });

  test('existing strip selection survives even on an unusual drug', () {
    const drug = DrugModel(dosageForm: 'OTHER');
    expect(drugAvailableSaleUnits(drug, selected: 'STRIP'),
        ['PACK', 'STRIP', 'UNIT']);
    expect(drugAvailableSaleUnits(drug), ['PACK', 'UNIT']);
  });
}
