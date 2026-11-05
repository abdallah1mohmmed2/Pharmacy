// lib/data/database/schema_iteration3.dart
import 'package:sqflite/sqflite.dart';

abstract final class SchemaIteration3 {
  static Future<void> upgrade(DatabaseExecutor db) async {
    final statements = <String>[
      '''CREATE TABLE IF NOT EXISTS drug_interactions(id INTEGER PRIMARY KEY AUTOINCREMENT,drug_a_ingredient_id INTEGER,drug_a_id INTEGER,interactant_type TEXT NOT NULL CHECK(interactant_type IN('DRUG','FOOD','ALCOHOL','HERBAL')),drug_b_ingredient_id INTEGER,drug_b_id INTEGER,interactant_name TEXT NOT NULL DEFAULT '',severity TEXT NOT NULL CHECK(severity IN('CONTRAINDICATED','MAJOR','MODERATE','MINOR')),severity_rank INTEGER NOT NULL CHECK(severity_rank BETWEEN 1 AND 4),mechanism TEXT NOT NULL DEFAULT '',clinical_effect TEXT NOT NULL DEFAULT '',management TEXT NOT NULL DEFAULT '',evidence_level TEXT NOT NULL DEFAULT 'UNVERIFIED',CHECK(drug_a_ingredient_id IS NOT NULL OR drug_a_id IS NOT NULL))''',
      '''CREATE TABLE IF NOT EXISTS drug_renal_rules(id INTEGER PRIMARY KEY AUTOINCREMENT,drug_id INTEGER NOT NULL REFERENCES drugs(id),crcl_min REAL NOT NULL,crcl_max REAL NOT NULL,action TEXT NOT NULL CHECK(action IN('NO_CHANGE','REDUCE_DOSE','EXTEND_INTERVAL','AVOID','CONTRAINDICATED')),dose_factor REAL,interval_hours INTEGER,max_daily_mg REAL,note_ar TEXT NOT NULL DEFAULT '',CHECK(crcl_min<=crcl_max))''',
      '''CREATE TABLE IF NOT EXISTS drug_hepatic_rules(id INTEGER PRIMARY KEY AUTOINCREMENT,drug_id INTEGER NOT NULL REFERENCES drugs(id),child_pugh_class TEXT NOT NULL CHECK(child_pugh_class IN('A','B','C')),action TEXT NOT NULL CHECK(action IN('NO_CHANGE','REDUCE_DOSE','AVOID','CONTRAINDICATED')),dose_factor REAL,max_daily_mg REAL,note_ar TEXT NOT NULL DEFAULT '')''',
      '''CREATE TABLE IF NOT EXISTS drug_pediatric_rules(id INTEGER PRIMARY KEY AUTOINCREMENT,drug_id INTEGER NOT NULL REFERENCES drugs(id),age_min_months INTEGER NOT NULL DEFAULT 0,age_max_months INTEGER NOT NULL DEFAULT 216,weight_min_kg REAL NOT NULL DEFAULT 0,weight_max_kg REAL NOT NULL DEFAULT 200,mg_per_kg_dose_min REAL NOT NULL DEFAULT 0,mg_per_kg_dose_max REAL NOT NULL DEFAULT 0,mg_per_kg_day_max REAL NOT NULL DEFAULT 0,doses_per_day INTEGER NOT NULL DEFAULT 1,absolute_max_dose_mg REAL NOT NULL DEFAULT 100000,action TEXT NOT NULL CHECK(action IN('DOSE_BY_WEIGHT','FIXED_DOSE','AVOID','CONTRAINDICATED')),note_ar TEXT NOT NULL DEFAULT '',CHECK(age_min_months<=age_max_months),CHECK(weight_min_kg<=weight_max_kg))''',
      '''CREATE TABLE IF NOT EXISTS patients(id INTEGER PRIMARY KEY AUTOINCREMENT,party_id INTEGER REFERENCES parties(id),full_name TEXT NOT NULL,birth_date TEXT,sex TEXT NOT NULL DEFAULT 'M' CHECK(sex IN('M','F')),weight_kg REAL,height_cm REAL,is_pregnant INTEGER NOT NULL DEFAULT 0 CHECK(is_pregnant IN(0,1)),pregnancy_status_known INTEGER NOT NULL DEFAULT 0 CHECK(pregnancy_status_known IN(0,1)),pregnancy_trimester INTEGER CHECK(pregnancy_trimester BETWEEN 1 AND 3),is_lactating INTEGER NOT NULL DEFAULT 0 CHECK(is_lactating IN(0,1)),serum_creatinine REAL,egfr_ml_min REAL,renal_stage TEXT,child_pugh_class TEXT CHECK(child_pugh_class IN('A','B','C')),allergies_json TEXT NOT NULL DEFAULT '[]',chronic_conditions_json TEXT NOT NULL DEFAULT '[]',current_meds_json TEXT NOT NULL DEFAULT '[]',created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)''',
      '''CREATE TABLE IF NOT EXISTS clinical_alert_logs(id INTEGER PRIMARY KEY AUTOINCREMENT,alert_at TEXT NOT NULL,invoice_id INTEGER,drug_id INTEGER,other_drug_id INTEGER,patient_id INTEGER REFERENCES patients(id),alert_category TEXT NOT NULL,level TEXT NOT NULL CHECK(level IN('INFO','CAUTION','WARNING','BLOCK')),message_ar TEXT NOT NULL,rule_ref TEXT,user_decision TEXT CHECK(user_decision IN('ACKNOWLEDGED','CANCELLED_ITEM','SUBSTITUTED','OVERRIDDEN_WITH_PIN','BLOCKED')),decided_by INTEGER,override_reason TEXT,manager_user_id INTEGER)''',
      '''CREATE TABLE IF NOT EXISTS controlled_drug_log(id INTEGER PRIMARY KEY AUTOINCREMENT,invoice_item_id INTEGER,drug_id INTEGER NOT NULL REFERENCES drugs(id),batch_id INTEGER,qty_units INTEGER NOT NULL CHECK(qty_units>0),patient_name TEXT NOT NULL,patient_national_id TEXT NOT NULL,receiver_name TEXT NOT NULL,receiver_national_id TEXT NOT NULL,prescription_id INTEGER,doctor_name TEXT NOT NULL,pharmacist_user_id INTEGER,running_balance_units INTEGER NOT NULL DEFAULT 0,recorded_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)''',
      '''CREATE TABLE IF NOT EXISTS insurance_companies(id INTEGER PRIMARY KEY AUTOINCREMENT,party_id INTEGER NOT NULL UNIQUE REFERENCES parties(id),name_ar TEXT NOT NULL,default_coverage_pct REAL NOT NULL DEFAULT 0 CHECK(default_coverage_pct BETWEEN 0 AND 100),claim_cycle_days INTEGER NOT NULL DEFAULT 30)''',
      '''CREATE TABLE IF NOT EXISTS insurance_policies(id INTEGER PRIMARY KEY AUTOINCREMENT,insurance_company_id INTEGER NOT NULL REFERENCES insurance_companies(id),customer_party_id INTEGER NOT NULL REFERENCES parties(id),policy_no TEXT NOT NULL UNIQUE,coverage_pct REAL NOT NULL CHECK(coverage_pct BETWEEN 0 AND 100),copay_pct REAL NOT NULL CHECK(copay_pct BETWEEN 0 AND 100),annual_limit REAL NOT NULL DEFAULT 0,used_limit REAL NOT NULL DEFAULT 0,valid_from TEXT,valid_to TEXT,excluded_categories_json TEXT NOT NULL DEFAULT '[]',CHECK(ABS(coverage_pct+copay_pct-100)<0.01))''',
      '''CREATE TABLE IF NOT EXISTS prescriptions(id INTEGER PRIMARY KEY AUTOINCREMENT,rx_no TEXT NOT NULL UNIQUE,patient_id INTEGER NOT NULL REFERENCES patients(id),customer_party_id INTEGER REFERENCES parties(id),doctor_name TEXT NOT NULL,doctor_license_no TEXT NOT NULL DEFAULT '',facility_name TEXT NOT NULL DEFAULT '',rx_date TEXT NOT NULL,valid_until TEXT NOT NULL,rx_type TEXT NOT NULL CHECK(rx_type IN('NORMAL','CONTROLLED','CHRONIC_REFILL','INSURANCE')),insurance_policy_id INTEGER REFERENCES insurance_policies(id),refills_allowed INTEGER NOT NULL DEFAULT 0,refills_used INTEGER NOT NULL DEFAULT 0,status TEXT NOT NULL DEFAULT 'OPEN' CHECK(status IN('OPEN','PARTIAL','DISPENSED','EXPIRED')))''',
      '''CREATE TABLE IF NOT EXISTS prescription_items(id INTEGER PRIMARY KEY AUTOINCREMENT,prescription_id INTEGER NOT NULL REFERENCES prescriptions(id) ON DELETE CASCADE,drug_id INTEGER NOT NULL REFERENCES drugs(id),prescribed_qty_units INTEGER NOT NULL CHECK(prescribed_qty_units>0),dispensed_qty_units INTEGER NOT NULL DEFAULT 0 CHECK(dispensed_qty_units>=0),dose_instruction TEXT NOT NULL DEFAULT '',duration_days INTEGER NOT NULL DEFAULT 0,CHECK(dispensed_qty_units<=prescribed_qty_units))''',
      '''CREATE TABLE IF NOT EXISTS sales_returns(id INTEGER PRIMARY KEY AUTOINCREMENT,return_no TEXT NOT NULL UNIQUE,return_date TEXT NOT NULL,original_invoice_id INTEGER NOT NULL REFERENCES sales_invoices(id),customer_party_id INTEGER REFERENCES parties(id),refund_method TEXT NOT NULL CHECK(refund_method IN('CASH','WALLET','CREDIT_TO_ACCOUNT')),reason_code TEXT NOT NULL CHECK(reason_code IN('WRONG_ITEM','DOCTOR_CHANGED','ADVERSE_REACTION','DAMAGED','EXPIRED_AT_SALE','OTHER')),reason_text TEXT NOT NULL DEFAULT '',total_refund REAL NOT NULL DEFAULT 0,approved_by INTEGER,journal_entry_id INTEGER,status TEXT NOT NULL DEFAULT 'POSTED')''',
      '''CREATE TABLE IF NOT EXISTS sales_return_items(id INTEGER PRIMARY KEY AUTOINCREMENT,sales_return_id INTEGER NOT NULL REFERENCES sales_returns(id) ON DELETE CASCADE,invoice_item_id INTEGER NOT NULL REFERENCES sales_invoice_items(id),batch_id INTEGER REFERENCES batches_fefo(id),qty_units INTEGER NOT NULL CHECK(qty_units>0),refund_amount REAL NOT NULL CHECK(refund_amount>=0),disposition TEXT NOT NULL CHECK(disposition IN('RESTOCK','QUARANTINE','DISPOSE')),inspection_note TEXT NOT NULL DEFAULT '')''',
      '''CREATE INDEX IF NOT EXISTS idx_clinical_interactions_a ON drug_interactions(drug_a_ingredient_id,drug_a_id,severity_rank)''',
      '''CREATE INDEX IF NOT EXISTS idx_clinical_renal_drug ON drug_renal_rules(drug_id,crcl_min,crcl_max)''',
      '''CREATE INDEX IF NOT EXISTS idx_clinical_patient_party ON patients(party_id)''',
      '''CREATE INDEX IF NOT EXISTS idx_prescription_patient ON prescriptions(patient_id,rx_date)''',
      '''CREATE INDEX IF NOT EXISTS idx_returns_invoice ON sales_returns(original_invoice_id)''',
      'DROP VIEW IF EXISTS v_drug_alternatives',
      '''CREATE VIEW v_drug_alternatives AS SELECT a.id AS source_drug_id,b.id AS drug_id,b.trade_name_ar,b.trade_name_en,b.strength_text,b.dosage_form,b.sell_price_pack,b.sell_price_strip,CASE WHEN a.strength_text=b.strength_text AND a.dosage_form=b.dosage_form THEN 'EXACT' ELSE 'SAME_INGREDIENT' END AS match_type,(b.sell_price_pack-a.sell_price_pack) AS price_diff_pack,COALESCE((SELECT SUM(x.total_units) FROM batches_fefo x JOIN warehouses w ON w.id=x.warehouse_id WHERE x.drug_id=b.id AND x.status='ACTIVE' AND x.expiry_date>=date('now') AND w.is_sellable=1),b.stock_total_units) AS available_units,(SELECT MIN(x.expiry_date) FROM batches_fefo x JOIN warehouses w ON w.id=x.warehouse_id WHERE x.drug_id=b.id AND x.status='ACTIVE' AND x.expiry_date>=date('now') AND w.is_sellable=1) AS nearest_expiry FROM drugs a JOIN drugs b ON b.active_ingredient_id=a.active_ingredient_id AND b.id<>a.id WHERE a.active_ingredient_id IS NOT NULL AND a.is_deleted=0 AND b.is_deleted=0'''
    ];
    for(final sql in statements){await db.execute(sql);}
    await _ensureColumn(db,'sales_returns','wallet_ref_no','TEXT');
    await _ensureColumn(db,'sales_invoice_items','is_substitute','INTEGER NOT NULL DEFAULT 0');
    await _ensureColumn(db,'sales_invoice_items','substituted_for_drug_id','INTEGER');
    await _seed(db);
  }

  static Future<void> _ensureColumn(DatabaseExecutor db,String table,String column,String definition) async {
    final info=await db.rawQuery('PRAGMA table_info($table)');
    if(!info.any((r)=>r['name']==column))await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }
  static Future<void> _seed(DatabaseExecutor db) async {
    final now=DateTime.now().toIso8601String();
    final existingIngredients=await db.query('active_ingredients',columns:['inn_name']);
    final knownIngredients=existingIngredients.map((r)=>r['inn_name'].toString().toLowerCase()).toSet();
    for(final item in [('Ibuprofen','إيبوبروفين'),('Aspirin','أسبرين')]){
      if(!knownIngredients.contains(item.$1.toLowerCase()))await db.insert('active_ingredients',{'uuid':'iteration3-ingredient-${item.$1.toLowerCase()}','branch_id':1,'created_at':now,'updated_at':now,'is_deleted':0,'sync_status':'LOCAL','sync_version':1,'inn_name':item.$1,'name_ar':item.$2});
    }
    final ingredients=await db.query('active_ingredients',columns:['id','inn_name']);
    int? ingredient(String name){for(final r in ingredients){if((r['inn_name'] as String).toLowerCase()==name.toLowerCase())return r['id'] as int;}return null;}
    final baseIngredient=ingredient('Warfarin');
    final ibu=ingredient('Ibuprofen');
    final aspirin=ingredient('Aspirin');
    if(baseIngredient!=null){
      for(final row in [
        (type:'DRUG',id:ibu,name:'Ibuprofen / NSAID',severity:'MAJOR',rank:3,mechanism:'تثبيط الصفائح وزيادة خطر النزف مع الوارفارين',effect:'نزف هضمي أو جهازي',manage:'تجنب الجمع أو راقب INR والنزف وفق قرار الطبيب'),
        (type:'DRUG',id:aspirin,name:'Aspirin',severity:'MAJOR',rank:3,mechanism:'تأثير مضاد للصفيحات مع الوارفارين',effect:'زيادة خطر النزف',manage:'تجنب الجمع إلا بقرار اختصاصي ومراقبة دقيقة'),
      ]){
        final exists=await db.query('drug_interactions',where:'drug_a_ingredient_id=? AND interactant_name=?',whereArgs:[baseIngredient,row.name],limit:1);
        if(exists.isEmpty)await db.insert('drug_interactions',{'drug_a_ingredient_id':baseIngredient,'interactant_type':row.type,'drug_b_ingredient_id':row.id,'interactant_name':row.name,'severity':row.severity,'severity_rank':row.rank,'mechanism':row.mechanism,'clinical_effect':row.effect,'management':row.manage,'evidence_level':'REFERENCE_REVIEW_REQUIRED'});
      }
      final grapefruit=await db.query('drug_interactions',where:'drug_a_ingredient_id=? AND interactant_name=?',whereArgs:[baseIngredient,'الجريب فروت'],limit:1);
      if(grapefruit.isEmpty)await db.insert('drug_interactions',{'drug_a_ingredient_id':baseIngredient,'interactant_type':'FOOD','interactant_name':'الجريب فروت','severity':'MODERATE','severity_rank':2,'mechanism':'قد يؤثر الغذاء في استقلاب بعض الأدوية؛ يلزم تحقق المنتج المحدد','clinical_effect':'احتمال تغير التعرض الدوائي','management':'تحقق من النشرة الدوائية قبل إعطاء توصية','evidence_level':'REVIEW_REQUIRED'});
    }
    final drugs=await db.query('drugs',columns:['id','active_ingredient_id','scientific_name']);
    final alternativeCount=Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM drugs WHERE internal_code LIKE ?', ['ALT-I3-%']))??0;
    if(alternativeCount==0){
      final originals=await db.query('drugs',limit:4,orderBy:'id ASC');
      for(var i=0;i<originals.length;i++){
        final clone=Map<String,Object?>.from(originals[i]);
        clone.remove('id');
        clone['uuid']='iteration3-alternative-${i+1}';
        clone['internal_code']='ALT-I3-${(i+1).toString().padLeft(3,'0')}';
        clone['trade_name_ar']='بديل تجريبي - ${clone['trade_name_ar']}';
        clone['trade_name_en']='Generic alternative ${i+1}';
        clone['barcode_international']=null;
        clone['barcode_local']=null;
        clone['registration_no']='';
        clone['sell_price_pack']=((clone['sell_price_pack'] as num?)?.toDouble()??0)*0.9;
        clone['sell_price_strip']=((clone['sell_price_strip'] as num?)?.toDouble()??0)*0.9;
        clone['sell_price_unit']=((clone['sell_price_unit'] as num?)?.toDouble()??0)*0.9;
        clone['stock_total_units']=0;
        clone['created_at']=now;
        clone['updated_at']=now;
        await db.insert('drugs',clone);
      }
    }
    for(final d in drugs){
      final name=(d['scientific_name'] as String? ?? '').toLowerCase();
      final id=d['id'] as int;
      if(name.contains('metformin')){
        await _insertIfMissing(db,'drug_renal_rules',{'drug_id':id,'crcl_min':0,'crcl_max':29.99,'action':'CONTRAINDICATED','note_ar':'يمنع الاستخدام عند CrCl أقل من 30 وفق مرجع محلي معتمد.'},'drug_id=? AND crcl_min=0',[id]);
        await _insertIfMissing(db,'drug_renal_rules',{'drug_id':id,'crcl_min':30,'crcl_max':45,'action':'REDUCE_DOSE','dose_factor':0.5,'max_daily_mg':1000,'note_ar':'يلزم تقييم المنفعة والمخاطر وخفض الجرعة ومراقبة وظائف الكلى.'},'drug_id=? AND crcl_min=30',[id]);
      }
      if(name.contains('gentamicin')){
        await _insertIfMissing(db,'drug_renal_rules',{'drug_id':id,'crcl_min':0,'crcl_max':29.99,'action':'CONTRAINDICATED','note_ar':'يتطلب قرار اختصاصي ومراقبة مستويات الدواء ووظائف الكلى.'},'drug_id=? AND crcl_min=0',[id]);
        await _insertIfMissing(db,'drug_renal_rules',{'drug_id':id,'crcl_min':30,'crcl_max':45,'action':'REDUCE_DOSE','dose_factor':0.5,'interval_hours':24,'note_ar':'تعديل الجرعة والفاصل وفق مستويات الدواء.'},'drug_id=? AND crcl_min=30',[id]);
      }
      if(name.contains('paracetamol')||name.contains('amoxicillin')){
        final exists=await db.query('drug_pediatric_rules',where:'drug_id=?',whereArgs:[id],limit:1);
        if(exists.isEmpty)await db.insert('drug_pediatric_rules',{'drug_id':id,'age_min_months':1,'age_max_months':216,'weight_min_kg':2,'weight_max_kg':80,'mg_per_kg_dose_min':name.contains('paracetamol')?10:20,'mg_per_kg_dose_max':name.contains('paracetamol')?15:45,'mg_per_kg_day_max':name.contains('paracetamol')?60:90,'doses_per_day':name.contains('paracetamol')?4:2,'absolute_max_dose_mg':name.contains('paracetamol')?1000:1000,'action':'DOSE_BY_WEIGHT','note_ar':'نطاق إرشادي يحتاج تحققاً من المستحضر والتركيز والنشرة المحلية.'});}
      if(name.contains('metformin')||name.contains('warfarin')){await _insertIfMissing(db,'drug_hepatic_rules',{'drug_id':id,'child_pugh_class':'C','action':'AVOID','note_ar':'يلزم تقييم اختصاصي لحالة الكبد.'},'drug_id=? AND child_pugh_class=?',[id,'C']);}
    }
    final companies=await db.query('insurance_companies',columns:['id']);
    if(companies.isEmpty){
      for(var i=1;i<=2;i++){
        final partyId=await db.insert('parties',{'uuid':'seed-insurance-party-$i','branch_id':1,'created_at':DateTime.now().toIso8601String(),'updated_at':DateTime.now().toIso8601String(),'is_deleted':0,'sync_status':'LOCAL','sync_version':1,'party_type':'CUSTOMER','code':'INS-$i','name_ar':i==1?'شركة التأمين التجريبية الأولى':'شركة التأمين التجريبية الثانية','credit_limit':0,'payment_terms_days':30,'opening_alayh':0,'opening_lah':0});
        final companyId=await db.insert('insurance_companies',{'party_id':partyId,'name_ar':i==1?'شركة التأمين التجريبية الأولى':'شركة التأمين التجريبية الثانية','default_coverage_pct':i==1?80:70,'claim_cycle_days':30});
        final customer=await db.query('parties',columns:['id'],where:"party_type='CUSTOMER'",limit:1,offset:i-1);
        if(customer.isNotEmpty)await db.insert('insurance_policies',{'insurance_company_id':companyId,'customer_party_id':customer.first['id'],'policy_no':'DEMO-POLICY-$i','coverage_pct':i==1?80:70,'copay_pct':i==1?20:30,'annual_limit':50000,'used_limit':0,'valid_from':'2026-01-01','valid_to':'2027-12-31','excluded_categories_json':'[]'});
      }
    }
    final patientCount=Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM patients'))??0;
    if(patientCount==0){
      final customers=await db.query('parties',columns:['id'],where:"party_type='CUSTOMER'",limit:3);
      final rows=[('مريض تجريبي بالغ','1985-06-15','M',72.0,'[]','[]'),('مريضة تجريبية','1994-02-20','F',62.0,'["penicillin"]','[]'),('طفل تجريبي','2021-04-10','M',16.0,'[]','[]')];
      for(var i=0;i<rows.length;i++){final x=rows[i];await db.insert('patients',{'party_id':customers.isEmpty?null:customers[i%customers.length]['id'],'full_name':x.$1,'birth_date':x.$2,'sex':x.$3,'weight_kg':x.$4,'allergies_json':x.$5,'chronic_conditions_json':'[]','current_meds_json':'[]'});}
    }
  }

  static Future<void> _insertIfMissing(DatabaseExecutor db,String table,Map<String,Object?> values,String where,List<Object?> args) async {if((await db.query(table,where:where,whereArgs:args,limit:1)).isEmpty)await db.insert(table,values);}
}

