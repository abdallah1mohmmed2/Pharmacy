import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/drug_model.dart';
import 'package:global_enterprise_pharmacy_erp/screens/drugs/drug_editor_field_config.dart';

void main() {
  test('all 11 old boolean codes are represented as switches', () {
    expect(DrugEditorFieldConfig.boolFields, {
      'is_active',
      'is_strip_based',
      'has_critical_interactions',
      'is_nephrotoxic',
      'neonate_allowed',
      'requires_refrigeration',
      'protect_from_light',
      'is_controlled',
      'requires_prescription',
      'prescription_restricted',
      'is_antibiotic',
    });
    expect(DrugEditorFieldConfig.boolValue('1'), isTrue);
    expect(DrugEditorFieldConfig.boolValue('0'), isFalse);
    expect(DrugEditorFieldConfig.boolValue('true'), isTrue);
    expect(DrugEditorFieldConfig.boolValue('false'), isFalse);
  });

  test('all ten enumerations keep the same SQLite codes', () {
    expect(
        DrugEditorFieldConfig.choiceLabels
            .map((key, value) => MapEntry(key, value.keys.toSet())),
        {
          'dosage_form': {
            'TABLET',
            'CAPSULE',
            'SYRUP',
            'SUSPENSION',
            'DROPS',
            'INJECTION',
            'CREAM',
            'OINTMENT',
            'INHALER',
            'SUPPOSITORY',
            'SACHET',
            'OTHER',
          },
          'route': {
            'ORAL',
            'IV',
            'IM',
            'SC',
            'TOPICAL',
            'OPHTHALMIC',
            'INHALATION',
            'RECTAL',
            'OTHER'
          },
          'take_with_food': {'BEFORE', 'WITH', 'AFTER', 'ANY'},
          'strip_price_mode': {'AUTO', 'MANUAL'},
          'hepatic_status': {
            'UNKNOWN',
            'SAFE',
            'ADJUST',
            'AVOID',
            'CONTRAINDICATED'
          },
          'renal_status': {
            'UNKNOWN',
            'SAFE',
            'ADJUST',
            'AVOID',
            'CONTRAINDICATED'
          },
          'geriatric_status': {'UNKNOWN', 'SAFE', 'ADJUST', 'AVOID'},
          'pediatric_status': {
            'UNKNOWN',
            'SAFE',
            'ADJUST',
            'AVOID',
            'CONTRAINDICATED'
          },
          'pregnancy_category': {'UNKNOWN', 'A', 'B', 'C', 'D', 'X', 'N'},
          'lactation_risk': {'UNKNOWN', 'L1', 'L2', 'L3', 'L4', 'L5'},
        });
  });

  test('editor choices are presentation only; model serialization is unchanged',
      () {
    const model = DrugModel(
      internalCode: 'SKU-CHECK',
      tradeNameAr: 'دواء',
      dosageForm: 'TABLET',
      route: 'ORAL',
      takeWithFood: 'BEFORE',
      stripPriceMode: 'MANUAL',
      stripsPerPack: 2,
      unitsPerStrip: 10,
      sellPricePack: 200,
      sellPriceStrip: 105,
      sellPriceUnit: 10.5,
      costPricePack: 150,
      isActive: false,
      isStripBased: true,
      hasCriticalInteractions: true,
      requiresPrescription: true,
      isControlled: true,
      requiresRefrigeration: true,
      renalStatus: 'ADJUST',
      hepaticStatus: 'UNKNOWN',
      pregnancyCategory: 'X',
      lactationRisk: 'L3',
      renalNotes: 'بيانات مرجعية سريرية',
      ingredientsJson: '[{"ingredient":"example"}]',
      minStockUnits: 100,
    );
    final stored = model.toMap();
    final parsed = DrugModel.fromMap(stored);
    expect(parsed.toMap(), stored);
    expect(stored['is_active'], 0);
    expect(stored['requires_prescription'], 1);
    expect(stored['strip_price_mode'], 'MANUAL');
    expect(stored['pregnancy_category'], 'X');
    expect(stored['renal_notes'], 'بيانات مرجعية سريرية');
    expect(stored['units_per_pack'], 20);
  });
}
