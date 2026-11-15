import '../models/drug_model.dart';

/// The real drugs table/model contract, not a hand-maintained import column list.
/// Every exported column has a label and a declared import policy.
abstract final class DrugImportFieldCatalog {
  static const protectedFields = <String>{
    'id',
    'uuid',
    'branch_id',
    'created_at',
    'updated_at',
    'is_deleted',
    'sync_status',
    'sync_version',
    'completeness_pct',
    'stock_total_units',
    'units_per_pack',
    'catalog_uuid',
    'catalog_version',
  };

  static const labels = <String, String>{
    'id': 'معرّف السجل المحلي',
    'uuid': 'معرّف السجل العالمي',
    'branch_id': 'الفرع',
    'created_at': 'تاريخ الإنشاء',
    'updated_at': 'تاريخ آخر تعديل',
    'is_deleted': 'حالة الحذف',
    'sync_status': 'حالة المزامنة',
    'sync_version': 'إصدار المزامنة',
    'completeness_pct': 'نسبة اكتمال البيانات',
    'units_per_pack': 'إجمالي الوحدات في العبوة (محسوب)',
    'stock_total_units': 'الرصيد المخزني (محسوب)',
    'catalog_uuid': 'معرّف الربط بالكتالوج المركزي',
    'catalog_version': 'إصدار الدواء في الكتالوج المركزي',
    'internal_code': 'الرمز الداخلي SKU',
    'is_active': 'حالة الصنف (1 فعال / 0 متوقف)',
    'trade_name_ar': 'الاسم التجاري بالعربية',
    'trade_name_en': 'الاسم التجاري بالإنجليزية',
    'manufacturer_id': 'رقم الشركة المصنعة',
    'scientific_name': 'الاسم العلمي / INN',
    'active_ingredient_id': 'رقم المادة الفعالة',
    'ingredients_json': 'تركيب الدواء المركب JSON',
    'chemical_composition': 'التركيب الكيميائي',
    'category_id': 'رقم التصنيف',
    'therapeutic_class': 'الفئة العلاجية',
    'pharmacologic_class': 'الفئة الدوائية',
    'atc_code': 'تصنيف ATC',
    'dosage_form': 'الشكل الصيدلاني',
    'strength_text': 'التركيز النصي',
    'strength_value': 'قيمة التركيز',
    'strength_unit': 'وحدة التركيز',
    'route': 'طريق الإعطاء',
    'is_strip_based': 'يباع بالأشرطة (1/0)',
    'indications': 'دواعي الاستعمال',
    'dosage_administration': 'الجرعة وطريقة الاستخدام',
    'adult_dose_min_mg': 'أقل جرعة للبالغين mg',
    'adult_dose_max_mg_per_day': 'الحد اليومي الأعلى mg',
    'dose_frequency_text': 'تكرار الجرعة',
    'take_with_food': 'علاقته بالطعام',
    'label_dose_text_ar': 'تعليمات الجرعة بالعربية',
    'contraindications': 'موانع الاستعمال',
    'contraindications_json': 'موانع إضافية JSON',
    'warnings_precautions': 'التحذيرات والاحتياطات',
    'black_box_warning': 'تحذير الصندوق الأسود',
    'warnings_json': 'تحذيرات إضافية JSON',
    'interactions_summary': 'التفاعلات الدوائية',
    'has_critical_interactions': 'تداخلات حرجة (1/0)',
    'side_effects_common': 'الآثار الجانبية الشائعة',
    'side_effects_serious': 'الآثار الجانبية الخطيرة',
    'strips_per_pack': 'عدد الأشرطة في الباكت',
    'units_per_strip': 'عدد الحبات في الشريط',
    'cost_price_pack': 'تكلفة الباكت',
    'last_purchase_cost_pack': 'آخر تكلفة شراء',
    'sell_price_pack': 'سعر بيع الباكت',
    'sell_price_strip': 'سعر بيع الشريط',
    'sell_price_unit': 'سعر بيع الحبة',
    'strip_price_mode': 'نمط سعر الشريط AUTO / MANUAL',
    'profit_margin_pct': 'هامش الربح %',
    'public_price_pack': 'السعر العام للباكت',
    'tax_rate_pct': 'الضريبة %',
    'min_stock_units': 'حد إعادة الطلب بالحبة',
    'reorder_qty_packs': 'كمية إعادة الطلب بالباكت',
    'min_age_months': 'أقل عمر بالأشهر',
    'max_age_months': 'أكبر عمر بالأشهر',
    'allowed_populations_json': 'الفئات السكانية المسموحة JSON',
    'hepatic_status':
        'حالة القصور الكبدي SAFE / ADJUST / AVOID / CONTRAINDICATED / UNKNOWN',
    'hepatic_notes': 'ملاحظات الكبد',
    'renal_status':
        'حالة القصور الكلوي SAFE / ADJUST / AVOID / CONTRAINDICATED / UNKNOWN',
    'renal_notes': 'ملاحظات الكلى GFR / CrCl',
    'is_nephrotoxic': 'سام للكلى (1/0)',
    'geriatric_status': 'حالة كبار السن SAFE / ADJUST / AVOID / UNKNOWN',
    'geriatric_notes': 'ملاحظات كبار السن',
    'beers_criteria': 'معايير Beers',
    'geriatric_age_threshold': 'حد عمر كبار السن',
    'pediatric_status':
        'حالة الأطفال SAFE / ADJUST / AVOID / CONTRAINDICATED / UNKNOWN',
    'pediatric_notes': 'ملاحظات الأطفال وحديثي الولادة',
    'ped_dose_mg_per_kg_min': 'أقل جرعة mg/kg',
    'ped_dose_mg_per_kg_max': 'أعلى جرعة mg/kg',
    'ped_max_daily_mg_per_kg': 'الحد اليومي mg/kg',
    'ped_doses_per_day': 'عدد الجرعات يومياً',
    'neonate_allowed': 'يسمح لحديثي الولادة (1/0)',
    'pregnancy_category': 'تصنيف الحمل A / B / C / D / X / N / UNKNOWN',
    'pregnancy_notes': 'ملاحظات الحمل',
    'pregnancy_trimester_json': 'أمان الأثلاث JSON',
    'lactation_risk': 'خطر الرضاعة L1 / L2 / L3 / L4 / L5 / UNKNOWN',
    'lactation_notes': 'ملاحظات الرضاعة',
    'storage_conditions': 'شروط التخزين',
    'storage_temp_min_c': 'أدنى حرارة مئوية',
    'storage_temp_max_c': 'أعلى حرارة مئوية',
    'requires_refrigeration': 'يتطلب تبريداً (1/0)',
    'protect_from_light': 'يحفظ بعيداً عن الضوء (1/0)',
    'barcode_international': 'الباركود العالمي',
    'barcode_local': 'الباركود المحلي',
    'registration_no': 'رقم التسجيل',
    'is_controlled': 'دواء مراقب (1/0)',
    'controlled_schedule': 'جدول الرقابة',
    'requires_prescription': 'يتطلب وصفة (1/0)',
    'prescription_restricted': 'وصفة مقيدة (1/0)',
    'is_antibiotic': 'مضاد حيوي (1/0)',
  };

  // Added by SchemaIteration10 to SQLite, not represented by DrugModel.toMap.
  static const databaseOnlyFields = <String>{'catalog_uuid', 'catalog_version'};
  static final allFields = <String>{
    ...DrugModel().toMap().keys,
    ...databaseOnlyFields,
  };
  // Virtual input is resolved to a real branch-local reference, never a column.
  static const importOnlyFields = <String>{'manufacturer_name'};
  static final editableFields = {
    ...allFields.difference(protectedFields),
    ...importOnlyFields,
  };

  static bool isEditable(String key) => editableFields.contains(key);
  static bool isProtected(String key) => protectedFields.contains(key);
  static bool isKnown(String key) =>
      allFields.contains(key) || importOnlyFields.contains(key);
  static String label(String key) => key == 'manufacturer_name'
      ? 'اسم الشركة (ربط أو إنشاء تلقائي)'
      : labels[key] ?? key;

  static String status(String target) {
    if (isProtected(target)) return 'للعرض فقط؛ لا يُكتب من ملف JSON';
    if (isEditable(target)) return 'حقل قابل للاستيراد';
    return 'غير معروف؛ يلزم ربطه بحقل موجود';
  }
}
