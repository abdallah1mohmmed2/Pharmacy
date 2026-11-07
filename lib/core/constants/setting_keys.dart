// lib/core/constants/setting_keys.dart
enum SettingGroup { general, sales, clinical, inventory, accounting, printBackup }
enum SettingValueType { string, boolean, integer, real, json }
enum SettingKey { pharmacyName, logoPath, reportHeaderFooter, currency, themeMode, invoiceLanguage, allowNegativeStock, enforceFefo, maxCashierDiscountPct, priceRounding, autoStripPrice, showCostToPharmacist, requireWalletRef, creditLimitMode, interactionAlerts, blockPregnancyX, renalHepaticDoseAlerts, controlledDrugAlerts, autoPrintDoseLabel, ageAllergyAlerts, expiryWarningDays, blockExpiredSale, minStockAlerts, costingMethod, bonusReducesCost, multiWarehouse, partnerDistributionMode, shiftDiffHandling, periodLock, vat, lahAlayhTermsOnly, receiptPaper, reportPaper, autoLocalOnClose, cloudSync }
class SettingSpec {
 const SettingSpec({required this.key,required this.number,required this.name,required this.group,required this.type,required this.defaultValue,required this.descriptionAr,this.allowedValues=const [],this.requiresManager=false});
 final SettingKey key; final int number; final String name; final SettingGroup group; final SettingValueType type; final Object defaultValue; final String descriptionAr; final List<String> allowedValues; final bool requiresManager;
 String get groupName=>switch(group){SettingGroup.general=>'GENERAL',SettingGroup.sales=>'SALES',SettingGroup.clinical=>'CLINICAL',SettingGroup.inventory=>'INVENTORY',SettingGroup.accounting=>'ACCOUNTING',SettingGroup.printBackup=>'PRINT_BACKUP'};
 String get typeName=>switch(type){SettingValueType.string=>'STRING',SettingValueType.boolean=>'BOOL',SettingValueType.integer=>'INT',SettingValueType.real=>'REAL',SettingValueType.json=>'JSON'};
 String get defaultJson=>defaultValue is String?defaultValue as String:defaultValue.toString();
 Map<String,Object?> toMap()=>{'setting_no':number,'setting_key':name,'group_name':groupName,'value_type':typeName,'setting_value':defaultJson,'default_value':defaultJson,'description_ar':descriptionAr,'requires_manager':requiresManager?1:0,'allowed_values_json':allowedValues};
}
abstract final class SettingKeys {
 static const List<SettingSpec> all=[
 SettingSpec(key:SettingKey.pharmacyName,number:1,name:'general.pharmacy_name',group:SettingGroup.general,type:SettingValueType.string,defaultValue:'الصيدلية',descriptionAr:'اسم المنشأة'),
 SettingSpec(key:SettingKey.logoPath,number:2,name:'general.logo_path',group:SettingGroup.general,type:SettingValueType.string,defaultValue:'',descriptionAr:'مسار الشعار'),
 SettingSpec(key:SettingKey.reportHeaderFooter,number:3,name:'general.report_header_footer',group:SettingGroup.general,type:SettingValueType.json,defaultValue:'{"header":"","footer":""}',descriptionAr:'ترويسة وتذييل التقارير'),
 SettingSpec(key:SettingKey.currency,number:4,name:'general.currency',group:SettingGroup.general,type:SettingValueType.json,defaultValue:'{"code":"YER","symbol":"ر.ي","decimals":0}',descriptionAr:'العملة'),
 SettingSpec(key:SettingKey.themeMode,number:5,name:'general.theme_mode',group:SettingGroup.general,type:SettingValueType.string,defaultValue:'enterprise_dark',descriptionAr:'المظهر',allowedValues:['enterprise_dark']),
 SettingSpec(key:SettingKey.invoiceLanguage,number:6,name:'general.invoice_language',group:SettingGroup.general,type:SettingValueType.string,defaultValue:'ar',descriptionAr:'لغة الفاتورة',allowedValues:['ar','en','bilingual']),
 SettingSpec(key:SettingKey.allowNegativeStock,number:7,name:'sales.allow_negative_stock',group:SettingGroup.sales,type:SettingValueType.boolean,defaultValue:false,descriptionAr:'السماح بالمخزون السالب'),
 SettingSpec(key:SettingKey.enforceFefo,number:8,name:'sales.enforce_fefo',group:SettingGroup.sales,type:SettingValueType.boolean,defaultValue:true,descriptionAr:'تطبيق FEFO'),
 SettingSpec(key:SettingKey.maxCashierDiscountPct,number:9,name:'sales.max_cashier_discount_pct',group:SettingGroup.sales,type:SettingValueType.real,defaultValue:0.0,descriptionAr:'سقف خصم الكاشير'),
 SettingSpec(key:SettingKey.priceRounding,number:10,name:'sales.price_rounding',group:SettingGroup.sales,type:SettingValueType.string,defaultValue:'none',descriptionAr:'تقريب السعر',allowedValues:['none','nearest_5','nearest_10','nearest_50','nearest_100']),
 SettingSpec(key:SettingKey.autoStripPrice,number:11,name:'sales.auto_strip_price',group:SettingGroup.sales,type:SettingValueType.boolean,defaultValue:true,descriptionAr:'تسعير الشريط تلقائياً'),
 SettingSpec(key:SettingKey.showCostToPharmacist,number:12,name:'sales.show_cost_to_pharmacist',group:SettingGroup.sales,type:SettingValueType.boolean,defaultValue:false,descriptionAr:'إظهار التكلفة للصيدلي'),
 SettingSpec(key:SettingKey.requireWalletRef,number:13,name:'sales.require_wallet_ref',group:SettingGroup.sales,type:SettingValueType.boolean,defaultValue:true,descriptionAr:'إلزام مرجع المحفظة'),
 SettingSpec(key:SettingKey.creditLimitMode,number:14,name:'sales.credit_limit_mode',group:SettingGroup.sales,type:SettingValueType.string,defaultValue:'warn',descriptionAr:'سياسة الحد الائتماني',allowedValues:['off','warn','block','manager_override']),
 SettingSpec(key:SettingKey.interactionAlerts,number:15,name:'clinical.interaction_alerts',group:SettingGroup.clinical,type:SettingValueType.string,defaultValue:'major_and_above',descriptionAr:'مستوى تنبيه التفاعلات',allowedValues:['off','contraindicated_only','major_and_above','moderate_and_above','all']),
 SettingSpec(key:SettingKey.blockPregnancyX,number:16,name:'clinical.block_pregnancy_x',group:SettingGroup.clinical,type:SettingValueType.boolean,defaultValue:true,descriptionAr:'حظر فئة الحمل X'),
 SettingSpec(key:SettingKey.renalHepaticDoseAlerts,number:17,name:'clinical.renal_hepatic_dose_alerts',group:SettingGroup.clinical,type:SettingValueType.boolean,defaultValue:true,descriptionAr:'تنبيهات الكلى والكبد'),
 SettingSpec(key:SettingKey.controlledDrugAlerts,number:18,name:'clinical.controlled_drug_alerts',group:SettingGroup.clinical,type:SettingValueType.boolean,defaultValue:true,descriptionAr:'تنبيهات الأدوية المراقبة'),
 SettingSpec(key:SettingKey.autoPrintDoseLabel,number:19,name:'clinical.auto_print_dose_label',group:SettingGroup.clinical,type:SettingValueType.string,defaultValue:'ask',descriptionAr:'طباعة ملصق الجرعة',allowedValues:['off','ask','always']),
 SettingSpec(key:SettingKey.ageAllergyAlerts,number:20,name:'clinical.age_allergy_alerts',group:SettingGroup.clinical,type:SettingValueType.boolean,defaultValue:true,descriptionAr:'تنبيهات العمر والحساسية'),
 SettingSpec(key:SettingKey.expiryWarningDays,number:21,name:'inventory.expiry_warning_days',group:SettingGroup.inventory,type:SettingValueType.integer,defaultValue:90,descriptionAr:'أيام تنبيه الصلاحية'),
 SettingSpec(key:SettingKey.blockExpiredSale,number:22,name:'inventory.block_expired_sale',group:SettingGroup.inventory,type:SettingValueType.boolean,defaultValue:true,descriptionAr:'منع بيع المنتهي'),
 SettingSpec(key:SettingKey.minStockAlerts,number:23,name:'inventory.min_stock_alerts',group:SettingGroup.inventory,type:SettingValueType.string,defaultValue:'dashboard',descriptionAr:'تنبيهات النواقص',allowedValues:['off','dashboard','daily_dashboard','notify_on_sale']),
 SettingSpec(key:SettingKey.costingMethod,number:24,name:'inventory.costing_method',group:SettingGroup.inventory,type:SettingValueType.string,defaultValue:'weighted_average',descriptionAr:'طريقة التكلفة',allowedValues:['weighted_average','last_purchase','batch_specific']),
 SettingSpec(key:SettingKey.bonusReducesCost,number:25,name:'inventory.bonus_reduces_cost',group:SettingGroup.inventory,type:SettingValueType.boolean,defaultValue:true,descriptionAr:'تخفيض التكلفة بالبونص'),
 SettingSpec(key:SettingKey.multiWarehouse,number:26,name:'inventory.multi_warehouse',group:SettingGroup.inventory,type:SettingValueType.boolean,defaultValue:false,descriptionAr:'تعدد المخازن'),
 SettingSpec(key:SettingKey.partnerDistributionMode,number:27,name:'accounting.partner_distribution_mode',group:SettingGroup.accounting,type:SettingValueType.string,defaultValue:'shares',descriptionAr:'طريقة توزيع أرباح الشركاء',allowedValues:['shares','percentage'],requiresManager:true),
 SettingSpec(key:SettingKey.shiftDiffHandling,number:28,name:'accounting.shift_diff_handling',group:SettingGroup.accounting,type:SettingValueType.string,defaultValue:'suspense',descriptionAr:'معالجة فرق الوردية',allowedValues:['post_to_cashier','expense','suspense','none']),
 SettingSpec(key:SettingKey.periodLock,number:29,name:'accounting.period_lock',group:SettingGroup.accounting,type:SettingValueType.json,defaultValue:'{"locked_through":null}',descriptionAr:'قفل الفترات المالية',requiresManager:true),
 SettingSpec(key:SettingKey.vat,number:30,name:'accounting.vat',group:SettingGroup.accounting,type:SettingValueType.json,defaultValue:'{"enabled":false,"rate_pct":0}',descriptionAr:'الضريبة المضافة',requiresManager:true),
 SettingSpec(key:SettingKey.lahAlayhTermsOnly,number:31,name:'accounting.lah_alayh_terms_only',group:SettingGroup.accounting,type:SettingValueType.boolean,defaultValue:true,descriptionAr:'قفل المصطلحات المحاسبية',requiresManager:true),
 SettingSpec(key:SettingKey.receiptPaper,number:32,name:'print.receipt_paper',group:SettingGroup.printBackup,type:SettingValueType.string,defaultValue:'80mm',descriptionAr:'ورق الإيصال',allowedValues:['80mm','58mm']),
 SettingSpec(key:SettingKey.reportPaper,number:33,name:'print.report_paper',group:SettingGroup.printBackup,type:SettingValueType.json,defaultValue:'{"size":"A4","orientation":"portrait"}',descriptionAr:'ورق التقارير'),
 SettingSpec(key:SettingKey.autoLocalOnClose,number:34,name:'backup.auto_local_on_close',group:SettingGroup.printBackup,type:SettingValueType.json,defaultValue:'{"enabled":true,"keep_last":10,"compress":true}',descriptionAr:'النسخ التلقائي'),
 SettingSpec(key:SettingKey.cloudSync,number:35,name:'sync.cloud',group:SettingGroup.printBackup,type:SettingValueType.json,defaultValue:'{"enabled":false,"base_url":"","api_key":"","batch_size":100}',descriptionAr:'المزامنة السحابية',requiresManager:true),
 ];
 static SettingSpec byKey(SettingKey key)=>all.firstWhere((e)=>e.key==key);
 static SettingSpec byName(String name)=>all.firstWhere((e)=>e.name==name);
}
