/// Presentation-only metadata for the drug editor. All values remain the
/// existing SQLite/model contract, including enum codes and 1/0 booleans.
abstract final class DrugEditorFieldConfig {
  static const boolFields = <String>{
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
  };

  static const choiceLabels = <String, Map<String, String>>{
    'dosage_form': {
      'TABLET': 'أقراص',
      'CAPSULE': 'كبسولات',
      'SYRUP': 'شراب',
      'SUSPENSION': 'معلق',
      'DROPS': 'قطرات',
      'INJECTION': 'حقن',
      'CREAM': 'كريم',
      'OINTMENT': 'مرهم',
      'INHALER': 'بخاخ',
      'SUPPOSITORY': 'تحاميل',
      'SACHET': 'أكياس',
      'OTHER': 'أخرى',
    },
    'route': {
      'ORAL': 'فموي',
      'IV': 'وريدي (IV)',
      'IM': 'عضلي (IM)',
      'SC': 'تحت الجلد (SC)',
      'TOPICAL': 'موضعي',
      'OPHTHALMIC': 'للعين',
      'INHALATION': 'استنشاق',
      'RECTAL': 'شرجي',
      'OTHER': 'أخرى',
    },
    'take_with_food': {
      'BEFORE': 'قبل الطعام',
      'WITH': 'مع الطعام',
      'AFTER': 'بعد الطعام',
      'ANY': 'غير محدد / حسب تعليمات الدواء',
    },
    'strip_price_mode': {
      'AUTO': 'تلقائي من سعر العبوة والتعبئة',
      'MANUAL': 'يدوي: تحديد أسعار الشريط والحبة',
    },
    'hepatic_status': {
      'UNKNOWN': 'غير محدد',
      'SAFE': 'آمن حسب المعلومات المدخلة',
      'ADJUST': 'تعديل الجرعة',
      'AVOID': 'يُتجنب',
      'CONTRAINDICATED': 'مضاد استطباب',
    },
    'renal_status': {
      'UNKNOWN': 'غير محدد',
      'SAFE': 'آمن حسب المعلومات المدخلة',
      'ADJUST': 'تعديل الجرعة',
      'AVOID': 'يُتجنب',
      'CONTRAINDICATED': 'مضاد استطباب',
    },
    'geriatric_status': {
      'UNKNOWN': 'غير محدد',
      'SAFE': 'آمن حسب المعلومات المدخلة',
      'ADJUST': 'تعديل الجرعة',
      'AVOID': 'يُتجنب',
    },
    'pediatric_status': {
      'UNKNOWN': 'غير محدد',
      'SAFE': 'آمن حسب المعلومات المدخلة',
      'ADJUST': 'تعديل الجرعة',
      'AVOID': 'يُتجنب',
      'CONTRAINDICATED': 'مضاد استطباب',
    },
    'pregnancy_category': {
      'UNKNOWN': 'غير محدد',
      'A': 'الفئة A',
      'B': 'الفئة B',
      'C': 'الفئة C',
      'D': 'الفئة D',
      'X': 'الفئة X',
      'N': 'الفئة N / غير مصنف',
    },
    'lactation_risk': {
      'UNKNOWN': 'غير محدد',
      'L1': 'الفئة L1',
      'L2': 'الفئة L2',
      'L3': 'الفئة L3',
      'L4': 'الفئة L4',
      'L5': 'الفئة L5',
    },
  };

  /// Only these keys are directly visible at first. Every other existing
  /// editor key is still editable under the expanded section of its tab.
  static const primaryKeys = <String>{
    'internal_code',
    'is_active',
    'trade_name_ar',
    'trade_name_en',
    'manufacturer_id',
    'scientific_name',
    'active_ingredient_id',
    'category_id',
    'dosage_form',
    'strength_text',
    'route',
    'is_strip_based',
    'indications',
    'dosage_administration',
    'contraindications',
    'warnings_precautions',
    'interactions_summary',
    'strips_per_pack',
    'units_per_strip',
    'cost_price_pack',
    'sell_price_pack',
    'sell_price_strip',
    'sell_price_unit',
    'strip_price_mode',
    'min_stock_units',
    'pregnancy_category',
    'lactation_risk',
    'hepatic_status',
    'renal_status',
    'pediatric_status',
    'requires_prescription',
    'is_controlled',
    'requires_refrigeration',
    'barcode_local',
  };

  static const shortLabels = <String, String>{
    'is_active': 'الصنف فعال',
    'is_strip_based': 'يباع بالأشرطة',
    'has_critical_interactions': 'تداخلات دوائية حرجة',
    'is_nephrotoxic': 'قد يسبب سمية للكلى',
    'neonate_allowed': 'مسموح لحديثي الولادة',
    'requires_refrigeration': 'يحتاج إلى التبريد',
    'protect_from_light': 'يحفظ بعيداً عن الضوء',
    'is_controlled': 'دواء مراقب',
    'requires_prescription': 'يتطلب وصفة طبية',
    'prescription_restricted': 'وصفة طبية مقيدة',
    'is_antibiotic': 'مضاد حيوي',
    'hepatic_status': 'حالة الكبد',
    'renal_status': 'حالة الكلى',
    'geriatric_status': 'حالة كبار السن',
    'pediatric_status': 'حالة الأطفال',
    'pregnancy_category': 'تصنيف الحمل',
    'lactation_risk': 'تصنيف الرضاعة',
    'strip_price_mode': 'طريقة حساب سعر الشريط والحبة',
    'dosage_form': 'الشكل الصيدلاني',
    'route': 'طريقة الإعطاء',
    'take_with_food': 'تناول الدواء مع الطعام',
    'manufacturer_id': 'الشركة المصنعة',
    'active_ingredient_id': 'المادة الفعالة',
    'category_id': 'التصنيف الدوائي',
  };

  static String labelFor(String key, String legacyLabel) =>
      shortLabels[key] ?? legacyLabel.replaceFirst(RegExp(r'^\d+\.\s*'), '');

  static bool boolValue(String raw) =>
      raw.trim() == '1' || raw.trim().toLowerCase() == 'true';

  static String? choiceValue(String key, String raw) {
    final values = choiceLabels[key];
    if (values == null) return null;
    // Do not silently coerce old/unrecognized values to OTHER or UNKNOWN.
    return raw.trim();
  }

  static bool isPermittedChoice(String key, String value) =>
      choiceLabels[key]?.containsKey(value) ?? false;
}
