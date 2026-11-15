import 'drug_model.dart';

/// Display the real retail unit for each dosage form without changing the
/// underlying PACK / STRIP / UNIT stock and accounting identifiers.
bool drugSupportsStripSale(DrugModel drug) =>
    drug.isStripBased ||
    drug.dosageForm == 'TABLET' ||
    drug.dosageForm == 'CAPSULE';

String drugSaleUnitLabel(DrugModel drug, String unit) => switch (unit) {
      'PACK' => 'باكت/علبة',
      'STRIP' => drugSupportsStripSale(drug) ? 'شريط' : 'وحدة داخل العلبة',
      'UNIT' => switch (drug.dosageForm) {
          'TABLET' => 'حبة',
          'CAPSULE' => 'كبسولة',
          'INJECTION' => 'أمبولة/فيال',
          'SYRUP' || 'SUSPENSION' || 'DROPS' => 'زجاجة',
          'CREAM' || 'OINTMENT' => 'أنبوب',
          'SUPPOSITORY' => 'تحميلة',
          'SACHET' => 'كيس',
          'INHALER' => 'بخاخ',
          _ => 'وحدة',
        },
      _ => unit,
    };

/// Preserve an already-selected strip unit from old invoices or carts,
/// but never suggest a strip for bottles, injections, tubes or inhalers.
List<String> drugAvailableSaleUnits(DrugModel drug, {String? selected}) => [
      'PACK',
      if (drugSupportsStripSale(drug) || selected == 'STRIP') 'STRIP',
      'UNIT',
    ];
