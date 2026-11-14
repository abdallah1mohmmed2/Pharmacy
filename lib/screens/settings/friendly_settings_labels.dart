import '../../core/constants/setting_keys.dart';

/// Presentation labels only. These do not modify setting keys or saved values.
abstract final class FriendlySettingsLabels {
  static const titles = <SettingKey, String>{
    SettingKey.pharmacyName: 'اسم الصيدلية',
    SettingKey.logoPath: 'شعار الصيدلية',
    SettingKey.reportHeaderFooter: 'مقدمة وتذييل التقارير',
    SettingKey.currency: 'العملة والمنازل العشرية',
    SettingKey.themeMode: 'مظهر التطبيق',
    SettingKey.invoiceLanguage: 'لغة الفواتير',
    SettingKey.allowNegativeStock: 'السماح بالبيع دون رصيد مخزون',
    SettingKey.enforceFefo: 'صرف الدفعات الأقرب انتهاءً أولاً',
    SettingKey.maxCashierDiscountPct: 'الحد الأعلى لخصم الكاشير',
    SettingKey.priceRounding: 'تقريب أسعار البيع',
    SettingKey.autoStripPrice: 'حساب سعر الشريط والحبة تلقائيًا',
    SettingKey.showCostToPharmacist: 'عرض تكلفة الدواء للصيدلي',
    SettingKey.requireWalletRef: 'طلب الرقم المرجعي للمحفظة',
    SettingKey.creditLimitMode: 'التعامل مع تجاوز حد المديونية',
    SettingKey.interactionAlerts: 'مستوى تنبيهات التداخلات الدوائية',
    SettingKey.blockPregnancyX: 'منع صرف أدوية الحمل من الفئة X',
    SettingKey.renalHepaticDoseAlerts: 'تنبيهات جرعات الكلى والكبد',
    SettingKey.controlledDrugAlerts: 'تنبيهات الأدوية المراقبة',
    SettingKey.autoPrintDoseLabel: 'طباعة ملصق الجرعة',
    SettingKey.ageAllergyAlerts: 'تنبيهات العمر والحساسية',
    SettingKey.expiryWarningDays: 'التنبيه قبل انتهاء الصلاحية',
    SettingKey.blockExpiredSale: 'منع بيع المنتهي',
    SettingKey.minStockAlerts: 'طريقة التنبيه عند نقص المخزون',
    SettingKey.costingMethod: 'طريقة احتساب تكلفة المخزون',
    SettingKey.bonusReducesCost: 'احتساب البونص ضمن تخفيض التكلفة',
    SettingKey.multiWarehouse: 'العمل بأكثر من مخزن',
    SettingKey.partnerDistributionMode: 'طريقة توزيع أرباح الشركاء',
    SettingKey.shiftDiffHandling: 'معالجة فروقات صندوق الوردية',
    SettingKey.periodLock: 'قفل التواريخ المالية السابقة',
    SettingKey.vat: 'ضريبة القيمة المضافة',
    SettingKey.lahAlayhTermsOnly: 'اعتماد مصطلحي «له» و«عليه»',
    SettingKey.receiptPaper: 'مقاس ورق الإيصال',
    SettingKey.reportPaper: 'ورق التقارير',
    SettingKey.autoLocalOnClose: 'النسخ الاحتياطي التلقائي',
    SettingKey.cloudSync: 'المزامنة السحابية',
  };

  static const descriptions = <SettingKey, String>{
    SettingKey.pharmacyName: 'الاسم الذي يظهر في بيانات المنشأة.',
    SettingKey.logoPath: 'صورة الشعار التي تريد عرضها في التطبيق.',
    SettingKey.reportHeaderFooter: 'النص الذي يظهر أعلى التقارير وأسفلها.',
    SettingKey.currency: 'العملة ورمزها وعدد المنازل العشرية.',
    SettingKey.themeMode: 'المظهر المتاح في هذا الإصدار.',
    SettingKey.invoiceLanguage: 'لغة العناوين المطبوعة على الفواتير.',
    SettingKey.allowNegativeStock: 'قد يسمح ببيع كمية غير متوفرة؛ استخدمه بحذر.',
    SettingKey.enforceFefo: 'بيع الدفعات الأقرب لانتهاء الصلاحية أولاً.',
    SettingKey.maxCashierDiscountPct: 'نسبة من 0 إلى 100 بالمئة.',
    SettingKey.priceRounding: 'كيفية تقريب سعر البيع.',
    SettingKey.autoStripPrice: 'توزيع سعر العبوة على الأشرطة والحبات.',
    SettingKey.showCostToPharmacist: 'عرض التكلفة للمستخدمين المخولين.',
    SettingKey.requireWalletRef: 'طلب رقم عملية المحفظة عند الدفع.',
    SettingKey.creditLimitMode: 'الإجراء عند تجاوز العميل الحد المسموح.',
    SettingKey.interactionAlerts: 'درجة شمول تحذيرات التداخلات.',
    SettingKey.blockPregnancyX: 'حماية إضافية عند وجود حمل.',
    SettingKey.renalHepaticDoseAlerts: 'عرض التحذيرات الخاصة بالكلى والكبد.',
    SettingKey.controlledDrugAlerts: 'عرض تحذيرات الأدوية الخاضعة للرقابة.',
    SettingKey.autoPrintDoseLabel: 'متى يظهر طلب طباعة تعليمات الجرعة.',
    SettingKey.ageAllergyAlerts: 'التحذير من الحساسية وموانع العمر.',
    SettingKey.expiryWarningDays: 'عدد الأيام التي تسبق تاريخ الانتهاء.',
    SettingKey.blockExpiredSale: 'رفض صرف الدفعات منتهية الصلاحية.',
    SettingKey.minStockAlerts: 'مكان ظهور تحذير نقص المخزون.',
    SettingKey.costingMethod: 'تؤثر في حساب التكلفة ويُفضل مراجعة المحاسب.',
    SettingKey.bonusReducesCost: 'إدخال الكميات المجانية في متوسط التكلفة.',
    SettingKey.multiWarehouse: 'إدارة مخازن متعددة.',
    SettingKey.partnerDistributionMode: 'يتطلب اعتماد المالك وقد يؤثر في حقول الحصص والنسب.',
    SettingKey.shiftDiffHandling: 'كيفية تسجيل فروق النقد عند نهاية الوردية.',
    SettingKey.periodLock: 'منع تسجيل عمليات بتاريخ يقع قبل تاريخ القفل أو يساويه.',
    SettingKey.vat: 'تفعيل الضريبة وتحديد نسبتها.',
    SettingKey.lahAlayhTermsOnly: 'إعداد إلزامي محمي لا يمكن تعطيله.',
    SettingKey.receiptPaper: 'ورق الطابعة الحرارية.',
    SettingKey.reportPaper: 'مقاس واتجاه ورق التقارير.',
    SettingKey.autoLocalOnClose: 'ضبط حفظ النسخ المحلية وعدد النسخ المحفوظة.',
    SettingKey.cloudSync: 'تحتاج إلى إعداد وصلاحيات Firebase قبل التشغيل.',
  };

  static String title(SettingSpec spec) => titles[spec.key] ?? spec.descriptionAr;
  static String explanation(SettingSpec spec) =>
      descriptions[spec.key] ?? spec.descriptionAr;

  static const choices = <String, String>{
    'enterprise_dark': 'المظهر الداكن الحالي',
    'shares': 'بحسب عدد الحصص',
    'percentage': 'بحسب النسبة المئوية',
    'none': 'دون تقريب',
    'nearest_5': 'لأقرب 5',
    'nearest_10': 'لأقرب 10',
    'nearest_50': 'لأقرب 50',
    'nearest_100': 'لأقرب 100',
    'off': 'إيقاف',
    'warn': 'إظهار تحذير فقط',
    'block': 'منع العملية',
    'manager_override': 'السماح باعتماد المدير',
    'contraindicated_only': 'التداخلات الممنوعة فقط',
    'major_and_above': 'الخطيرة وما فوق',
    'moderate_and_above': 'المتوسطة والخطيرة',
    'all': 'جميع المستويات',
    'ask': 'اسألني قبل الطباعة',
    'always': 'اطبع دائمًا',
    'weighted_average': 'المتوسط المرجح',
    'last_purchase': 'آخر سعر شراء',
    'batch_specific': 'بحسب تكلفة الدفعة',
    'dashboard': 'في لوحة التحكم',
    'daily_dashboard': 'في الملخص اليومي',
    'notify_on_sale': 'تنبيه عند البيع',
    'post_to_cashier': 'تحميل الفرق على الكاشير',
    'expense': 'تسجيل الفرق كمصروف',
    'suspense': 'حساب معلق لحين التسوية',
    '80mm': 'عرض 80 مم',
    '58mm': 'عرض 58 مم',
    'ar': 'العربية',
    'en': 'الإنجليزية',
    'bilingual': 'عربي وإنجليزي',
    'A4': 'ورق A4',
    'portrait': 'عمودي',
    'landscape': 'أفقي',
    'YER': 'ريال يمني',
    'SAR': 'ريال سعودي',
    'USD': 'دولار أمريكي',
    'EUR': 'يورو',
    '(default)': 'قاعدة البيانات الرئيسية',
    'firestore': 'Firebase / Firestore',
  };
  static String choice(String raw) => choices[raw] ?? raw;

  static String summary(SettingSpec spec, Object? value) {
    if (spec.type == SettingValueType.boolean) {
      return value == true ? 'مفعّل' : 'متوقف';
    }
    if (spec.allowedValues.isNotEmpty && value is String) return choice(value);
    if (spec.type == SettingValueType.json && value is Map) {
      final data = Map<String, Object?>.from(value);
      switch (spec.key) {
        case SettingKey.reportHeaderFooter:
          return 'تعديل النص أعلى التقارير وأسفلها';
        case SettingKey.currency:
          return choice(data['code']?.toString() ?? 'YER') + ' • ' +
              (data['symbol']?.toString() ?? '') + ' • ' +
              (data['decimals']?.toString() ?? '0') + ' منازل';
        case SettingKey.periodLock:
          return data['locked_through'] == null
              ? 'لا يوجد تاريخ قفل'
              : 'مقفل حتى ' + data['locked_through'].toString();
        case SettingKey.vat:
          return data['enabled'] == true
              ? 'مفعّلة — ' + (data['rate_pct']?.toString() ?? '0') + '%'
              : 'متوقفة';
        case SettingKey.reportPaper:
          return (data['size']?.toString() ?? 'A4') + ' • ' +
              choice(data['orientation']?.toString() ?? 'portrait');
        case SettingKey.autoLocalOnClose:
          return (data['enabled'] == true ? 'مفعّل' : 'متوقف') +
              ' • الاحتفاظ بـ ' + (data['keep_last']?.toString() ?? '10') + ' نسخ';
        case SettingKey.cloudSync:
          return data['enabled'] == true ? 'مفعّلة' : 'متوقفة';
        default:
          return 'خيارات متعددة';
      }
    }
    if (spec.key == SettingKey.logoPath) {
      return (value?.toString().isNotEmpty ?? false)
          ? 'تم تحديد ملف شعار' : 'لم يتم اختيار شعار';
    }
    if (spec.key == SettingKey.maxCashierDiscountPct) {
      return (value?.toString() ?? '0') + '%';
    }
    if (spec.key == SettingKey.expiryWarningDays) {
      return (value?.toString() ?? '0') + ' يومًا';
    }
    return value?.toString().isNotEmpty == true ? value.toString() : 'غير محدد';
  }
}
