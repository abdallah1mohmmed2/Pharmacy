import '../services/security_hash_service.dart';
import 'package:sqflite/sqflite.dart';

abstract final class SeedData {
  static const _now = '2026-11-05T00:00:00.000';
  static Future<void> run(DatabaseExecutor db) async {
    final branchId = await db.insert('branches', {'uuid':'branch-main','branch_id':1,'created_at':_now,'updated_at':_now,'code':'MAIN','name_ar':'الفرع الرئيسي','name_en':'Main Branch','is_main':1,'is_active':1});
    final base = {'uuid':'seed','branch_id':branchId,'created_at':_now,'updated_at':_now,'is_deleted':0,'sync_status':'LOCAL','sync_version':1};
    await db.insert('users',{...base,'uuid':'user-owner','username':'admin','full_name':'مدير النظام','role_code':'OWNER','password_hash':SecurityHashService.hash('123456'),'manager_pin_hash':SecurityHashService.hash('9999'),'is_active':1});
    final settings = <List<String>>[
      ['BRANCH_NAME','GENERAL','TEXT','اسم الفرع'],['CURRENCY','GENERAL','TEXT','العملة'],['CURRENCY_SYMBOL','GENERAL','TEXT','رمز العملة'],['TAX_ENABLED','SALES','BOOL','تفعيل الضريبة'],['TAX_RATE','SALES','NUMBER','نسبة الضريبة'],['DEFAULT_DISCOUNT','SALES','NUMBER','الخصم الافتراضي'],['MAX_DISCOUNT','SALES','NUMBER','الحد الأعلى للخصم'],['ALLOW_CREDIT','SALES','BOOL','السماح بالبيع الآجل'],['CREDIT_LIMIT_REQUIRED','SALES','BOOL','اشتراط حد ائتماني'],['LOW_STOCK_ALERT','INVENTORY','BOOL','تنبيه المخزون المنخفض'],['DEFAULT_MIN_STOCK','INVENTORY','NUMBER','حد المخزون الافتراضي'],['ALLOW_NEGATIVE_STOCK','INVENTORY','BOOL','السماح بمخزون سالب'],['AUTO_STRIP_PRICE','PRICING','BOOL','حساب سعر الشريط تلقائياً'],['AUTO_UNIT_PRICE','PRICING','BOOL','حساب سعر الحبة تلقائياً'],['PRICE_ROUNDING','PRICING','TEXT','تقريب الأسعار'],['MANAGER_PIN_REQUIRED','SECURITY','BOOL','طلب رمز المدير'],['SESSION_TIMEOUT','SECURITY','NUMBER','مهلة الجلسة'],['BARCODE_REQUIRED','DRUGS','BOOL','إلزامية الباركود'],['PRESCRIPTION_WARNING','DRUGS','BOOL','تنبيه الوصفة'],['ANTIBIOTIC_WARNING','DRUGS','BOOL','تنبيه المضاد الحيوي'],['PREGNANCY_ALERT','CLINICAL','BOOL','تنبيه الحمل'],['RENAL_ALERT','CLINICAL','BOOL','تنبيه الكلى'],['HEPATIC_ALERT','CLINICAL','BOOL','تنبيه الكبد'],['PEDIATRIC_ALERT','CLINICAL','BOOL','تنبيه الأطفال'],['GERIATRIC_ALERT','CLINICAL','BOOL','تنبيه كبار السن'],['WALLET_JAWALI','PAYMENTS','TEXT','محفظة جوالي'],['WALLET_JAIB','PAYMENTS','TEXT','محفظة جيب'],['WALLET_FLOUSK','PAYMENTS','TEXT','محفظة فلوسك'],['WALLET_KURAIMI','PAYMENTS','TEXT','محفظة كريمي'],['INVOICE_PREFIX','DOCS','TEXT','بادئة الفاتورة'],['VOUCHER_PREFIX','DOCS','TEXT','بادئة السند'],['BRANCH_PHONE','GENERAL','TEXT','هاتف الفرع'],['BRANCH_ADDRESS','GENERAL','TEXT','عنوان الفرع'],['MANAGER_APPROVAL','SECURITY','BOOL','اعتماد المدير'],['BACKUP_REMINDER','SYSTEM','BOOL','تذكير النسخ الاحتياطي']
    ];
    for(var i=0;i<settings.length;i++){final s=settings[i];await db.insert('system_settings',{...base,'uuid':'setting-'+(i+1).toString(),'setting_no':i+1,'setting_key':s[0],'group_code':s[1],'value_type':s[2],'value_text':null,'default_text':null,'label_ar':s[3],'requires_manager':0});}
    final accounts = <List<String>>[
      ['1101','الصندوق الرئيسي'],['1102','درج الكاشير'],['1103','محفظة جوالي'],['1104','محفظة جيب'],['1105','محفظة فلوسك'],['1106','محفظة كريمي'],['1107','الحسابات البنكية'],
      ['1201','ذمم العملاء'],['1202','سلف العاملين'],['1301','مخزون الأدوية'],['1302','بضاعة بالطريق'],['1401','الأصول الثابتة'],
      ['2101','ذمم الموردين'],['2102','مصروفات مستحقة'],['2201','ضريبة مستحقة'],['2301','التزامات أخرى'],
      ['3101','رأس المال'],['3201','الأرباح المحتجزة'],
      ['4101','إيرادات المبيعات'],['4102','إيرادات أخرى'],['4201','خصومات مكتسبة'],
      ['5101','تكلفة البضاعة المباعة'],['5102','تالف ومنتهي الصلاحية'],
      ['5201','مصروفات تشغيلية'],['5202','رواتب وأجور'],['5203','إيجارات'],['5204','مرافق واتصالات'],
      ['5301','عمولات بنكية ومحافظ'],['5302','خصومات مسموحة'],['5303','فروقات جرد'],['5304','فروقات وتسويات'],
    ];
    for(final a in accounts){await db.insert('chart_of_accounts',{...base,'uuid':'acc-'+a[0],'code':a[0],'name_ar':a[1],'acc_type':a[0].startsWith('1')?'ASSET':a[0].startsWith('2')?'LIABILITY':a[0].startsWith('3')?'EQUITY':a[0].startsWith('4')?'REVENUE':'EXPENSE'});}
    final cashKinds=<List<String>>[
      ['CASH-MAIN','الصندوق الرئيسي','MAIN_SAFE',''],['CASH-DRAWER','درج الكاشير','CASHIER_DRAWER',''],
      ['W-JAWALI','محفظة جوالي','WALLET','JAWALI'],['W-JAIB','محفظة جيب','WALLET','JAIB'],['W-FLOUSK','محفظة فلوسك','WALLET','FLOUSK'],['W-KURAIMI','محفظة كريمي','WALLET','KURAIMI'],['BANK-MAIN','الحساب البنكي','BANK','']
    ];
    final glCodes={'CASH-MAIN':'1101','CASH-DRAWER':'1102','W-JAWALI':'1103','W-JAIB':'1104','W-FLOUSK':'1105','W-KURAIMI':'1106','BANK-MAIN':'1107'};
    for(final c in cashKinds){final gl=await db.query('chart_of_accounts',columns:['id'],where:'code=?',whereArgs:[glCodes[c[0]]],limit:1);await db.insert('cash_accounts',{...base,'uuid':'cash-'+c[0],'code':c[0],'name_ar':c[1],'account_kind':c[2],'wallet_provider':c[3].isEmpty?null:c[3],'gl_account_id':gl.first['id'],'current_balance':0});}
    await db.insert('number_sequences',{...base,'uuid':'seq-invoice','branch_id':branchId,'doc_type':'INVOICE','prefix':'INV','year':DateTime.now().year,'last_no':0,'pad_length':6});
    await db.insert('number_sequences',{...base,'uuid':'seq-voucher','branch_id':branchId,'doc_type':'VOUCHER','prefix':'VCH','year':DateTime.now().year,'last_no':0,'pad_length':6});
  }
}
