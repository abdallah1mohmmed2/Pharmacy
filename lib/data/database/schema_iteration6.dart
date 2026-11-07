// lib/data/database/schema_iteration6.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/constants/setting_keys.dart';

abstract final class SchemaIteration6 {
 static Future<void> upgrade(DatabaseExecutor db) async {
  await _migrateLegacyAudit(db);
  await _migrateLegacySettings(db);
  await db.execute('''CREATE TABLE IF NOT EXISTS system_settings(
   setting_no INTEGER PRIMARY KEY CHECK(setting_no BETWEEN 1 AND 35),
   setting_key TEXT NOT NULL UNIQUE, group_name TEXT NOT NULL,
   value_type TEXT NOT NULL CHECK(value_type IN ('STRING','BOOL','INT','REAL','JSON')),
   setting_value TEXT NOT NULL, default_value TEXT NOT NULL,
   description_ar TEXT NOT NULL, requires_manager INTEGER NOT NULL DEFAULT 0 CHECK(requires_manager IN (0,1)),
   allowed_values_json TEXT NOT NULL DEFAULT '[]', updated_at TEXT, updated_by INTEGER
  )''');
  for(final spec in SettingKeys.all) {
   await db.insert('system_settings',{
    'setting_no':spec.number,'setting_key':spec.name,'group_name':spec.groupName,'value_type':spec.typeName,
    'setting_value':spec.defaultJson,'default_value':spec.defaultJson,'description_ar':spec.descriptionAr,
    'requires_manager':spec.requiresManager?1:0,'allowed_values_json':_allowedJson(spec.allowedValues),
   },conflictAlgorithm:ConflictAlgorithm.ignore);
  }
  final legacySettings=await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='system_settings_legacy_i5'");
  if(legacySettings.isNotEmpty){
   final oldRows=await db.query('system_settings_legacy_i5');
   for(final row in oldRows){
    final key=row['setting_key'];final value=row['value_text']??row['setting_value'];
    if(key is! String||value==null)continue;
    final matchingSpecs=SettingKeys.all.where((item)=>item.name==key).toList();
    if(matchingSpecs.isEmpty)continue;
    final spec=matchingSpecs.first;final raw=value.toString();String? normalized;
    if(spec.type==SettingValueType.boolean){
     if({'1','true','TRUE'}.contains(raw))normalized='1';
     if({'0','false','FALSE'}.contains(raw))normalized='0';
    }else if(spec.type==SettingValueType.integer){
     if(int.tryParse(raw)!=null)normalized=raw;
    }else if(spec.type==SettingValueType.real){
     if(double.tryParse(raw)!=null)normalized=raw;
    }else if(spec.type==SettingValueType.string){
     if(spec.allowedValues.isEmpty||spec.allowedValues.contains(raw))normalized=raw;
    }else if(spec.type==SettingValueType.json){
     try{jsonDecode(raw);normalized=raw;}catch(_){}
    }
    if(normalized!=null)await db.update('system_settings',{'setting_value':normalized},where:'setting_key=?',whereArgs:[key]);
   }
  }
  await db.execute('''CREATE TABLE IF NOT EXISTS import_jobs(
   id INTEGER PRIMARY KEY AUTOINCREMENT,
   source_type TEXT NOT NULL CHECK(source_type IN ('CSV','JSON','OPENFDA','EXPORT_CSV','EXPORT_JSON')),
   file_name TEXT,mapping_json TEXT NOT NULL DEFAULT '{}',
   conflict_policy TEXT NOT NULL DEFAULT 'SKIP' CHECK(conflict_policy IN ('SKIP','UPDATE_EMPTY_ONLY','OVERWRITE')),
   total_rows INTEGER NOT NULL DEFAULT 0,inserted_rows INTEGER NOT NULL DEFAULT 0,
   updated_rows INTEGER NOT NULL DEFAULT 0,skipped_rows INTEGER NOT NULL DEFAULT 0,error_rows INTEGER NOT NULL DEFAULT 0,
   status TEXT NOT NULL DEFAULT 'PENDING',started_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,finished_at TEXT
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS audit_logs(
   id INTEGER PRIMARY KEY AUTOINCREMENT,event_at TEXT NOT NULL,user_id INTEGER,branch_id INTEGER NOT NULL DEFAULT 1,
   device_id TEXT,action TEXT NOT NULL CHECK(action IN ('LOGIN','LOGOUT','LOGIN_FAILED','CREATE','UPDATE','DELETE','VOID','PRICE_CHANGE','DISCOUNT_OVERRIDE','CLINICAL_OVERRIDE','SETTING_CHANGE','PERIOD_CLOSE','BACKUP','RESTORE','PRINT','EXPORT','MANAGER_PIN_USED')),
   entity_type TEXT,entity_id INTEGER,entity_label TEXT,old_values_json TEXT,new_values_json TEXT,reason TEXT,
   severity TEXT NOT NULL DEFAULT 'INFO' CHECK(severity IN ('INFO','WARNING','CRITICAL')),
   prev_hash TEXT NOT NULL,row_hash TEXT NOT NULL
  )''');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_audit_event_at ON audit_logs(event_at)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_audit_user_action ON audit_logs(user_id,action)');
  await db.execute('DROP TRIGGER IF EXISTS trg_audit_no_update');
  await db.execute('DROP TRIGGER IF EXISTS trg_audit_no_delete');
  await db.execute("CREATE TRIGGER trg_audit_no_update BEFORE UPDATE ON audit_logs BEGIN SELECT RAISE(ABORT,'audit_logs are immutable'); END");
  await db.execute("CREATE TRIGGER trg_audit_no_delete BEFORE DELETE ON audit_logs BEGIN SELECT RAISE(ABORT,'audit_logs are immutable'); END");
  await _migrateLegacyAuditRows(db);
  await db.execute('''CREATE TABLE IF NOT EXISTS backup_log(
   id INTEGER PRIMARY KEY AUTOINCREMENT,backup_at TEXT NOT NULL,trigger_type TEXT NOT NULL CHECK(trigger_type IN ('MANUAL','ON_SHIFT_CLOSE','ON_APP_CLOSE','BEFORE_RESTORE','BEFORE_PERIOD_CLOSE')),
   file_path TEXT NOT NULL,size_bytes INTEGER NOT NULL DEFAULT 0,sha256 TEXT NOT NULL,encrypted INTEGER NOT NULL DEFAULT 0,
   result TEXT NOT NULL,error_text TEXT,user_id INTEGER
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS sync_queue(
   id INTEGER PRIMARY KEY AUTOINCREMENT,table_name TEXT NOT NULL,row_uuid TEXT NOT NULL,
   operation TEXT NOT NULL CHECK(operation IN ('INSERT','UPDATE','SOFT_DELETE')),payload_json TEXT NOT NULL,
   sync_version INTEGER NOT NULL DEFAULT 1,attempts INTEGER NOT NULL DEFAULT 0,last_error TEXT,
   status TEXT NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','SENDING','DONE','FAILED','CONFLICT')),
   queued_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,UNIQUE(table_name,row_uuid,sync_version)
  )''');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(status,queued_at)');
  await db.execute('''CREATE TABLE IF NOT EXISTS fiscal_periods(
   id INTEGER PRIMARY KEY AUTOINCREMENT,period_code TEXT NOT NULL UNIQUE,
   period_type TEXT NOT NULL CHECK(period_type IN ('MONTH','YEAR')),start_date TEXT NOT NULL,end_date TEXT NOT NULL,
   status TEXT NOT NULL DEFAULT 'OPEN' CHECK(status IN ('OPEN','CLOSED')),closed_at TEXT,closed_by INTEGER,
   CHECK(start_date<=end_date)
  )''');
  await _installPeriodTriggers(db);
  await _installRelatedPeriodTriggers(db);
  await _installDistributionPeriodTriggers(db);
  await db.execute('''CREATE TABLE IF NOT EXISTS roles(
   role_code TEXT PRIMARY KEY,role_name_ar TEXT NOT NULL,is_system INTEGER NOT NULL DEFAULT 1
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS role_permissions(
   id INTEGER PRIMARY KEY AUTOINCREMENT,role_code TEXT NOT NULL REFERENCES roles(role_code) ON DELETE CASCADE,
   permission_code TEXT NOT NULL,is_allowed INTEGER NOT NULL DEFAULT 0 CHECK(is_allowed IN (0,1)),
   UNIQUE(role_code,permission_code)
  )''');
  await _ensureColumn(db,'users','system_role_code','TEXT');
  await db.execute('UPDATE users SET system_role_code=role_code WHERE system_role_code IS NULL');
  const roles=<String,String>{'OWNER':'المالك','MANAGER':'مدير','PHARMACIST':'صيدلي','CASHIER':'كاشير','STOREKEEPER':'أمين مخزن','ACCOUNTANT':'محاسب','AUDITOR':'مراجع'};
  const permissions=<String>['dashboard.view','pos.sell','pos.discount.override','drugs.view','drugs.create','drugs.update','drugs.import','drugs.export','inventory.view','inventory.adjust','inventory.stocktake','purchases.manage','sales.returns','clinical.override','finance.view','finance.manage','partners.manage','reports.view','reports.export','settings.view','settings.manage','settings.manager_pin','audit.view','audit.verify','backup.create','backup.restore','sync.manage','period.close','users.manage','roles.manage'];
  for(final role in roles.entries){
   await db.insert('roles',{'role_code':role.key,'role_name_ar':role.value},conflictAlgorithm:ConflictAlgorithm.ignore);
   for(final permission in permissions){
    final allowed=role.key=='OWNER'||(role.key=='MANAGER'&&!{'settings.manager_pin','roles.manage'}.contains(permission))||
     (role.key=='PHARMACIST'&&{'dashboard.view','pos.sell','drugs.view','drugs.create','drugs.update','inventory.view','clinical.override','reports.view'}.contains(permission))||
     (role.key=='CASHIER'&&{'dashboard.view','pos.sell','drugs.view','reports.view'}.contains(permission))||
     (role.key=='STOREKEEPER'&&{'dashboard.view','drugs.view','inventory.view','inventory.adjust','inventory.stocktake','reports.view'}.contains(permission))||
     (role.key=='ACCOUNTANT'&&{'dashboard.view','finance.view','finance.manage','partners.manage','reports.view','reports.export','audit.view'}.contains(permission))||
     (role.key=='AUDITOR'&&{'dashboard.view','reports.view','reports.export','audit.view','audit.verify'}.contains(permission));
    await db.insert('role_permissions',{'role_code':role.key,'permission_code':permission,'is_allowed':allowed?1:0},conflictAlgorithm:ConflictAlgorithm.ignore);
   }
  }
 }
 static Future<void> _ensureColumn(DatabaseExecutor db,String table,String column,String declaration) async {
  final columns=await db.rawQuery('PRAGMA table_info('+table+')');
  if(!columns.any((row)=>row['name']==column))await db.execute('ALTER TABLE '+table+' ADD COLUMN '+column+' '+declaration);
 }
 static String _allowedJson(List<String> values)=>values.isEmpty?'[]':'["'+values.join('","')+'"]';

 static String _auditHash(String value)=>sha256.convert(utf8.encode(value)).toString();
 static Future<void> _migrateLegacyAuditRows(DatabaseExecutor db) async {
  final tables=await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='audit_logs_legacy_i5'");
  if(tables.isEmpty)return;
  final rows=await db.query('audit_logs_legacy_i5',orderBy:'id');
  var previous='GENESIS';
  final existing=await db.query('audit_logs',columns:['row_hash'],orderBy:'id DESC',limit:1);
  if(existing.isNotEmpty)previous=existing.first['row_hash'] as String;
  const allowed={'LOGIN','LOGOUT','LOGIN_FAILED','CREATE','UPDATE','DELETE','VOID','PRICE_CHANGE','DISCOUNT_OVERRIDE','CLINICAL_OVERRIDE','SETTING_CHANGE','PERIOD_CLOSE','BACKUP','RESTORE','PRINT','EXPORT','MANAGER_PIN_USED'};
  for(final row in rows){
   final eventAt=(row['occurred_at']??DateTime.now().toIso8601String()).toString();
   final requested=(row['action_code']??'UPDATE').toString().toUpperCase();
   final action=allowed.contains(requested)?requested:'UPDATE';
   final oldJson=row['old_value']==null?null:jsonEncode({'legacy_value':row['old_value']});
   final newJson=row['new_value']==null?null:jsonEncode({'legacy_value':row['new_value']});
   final userId=row['user_id'] as int?;final entityType=row['entity_type'] as String?;final entityId=row['entity_id'] as int?;
   final canonical=[previous,eventAt,userId?.toString()??'',action,entityType??'',entityId?.toString()??'',oldJson??'',newJson??''].join('|');
   final hash=_auditHash(canonical);
   final severity=(row['severity']??'INFO').toString().toUpperCase();
   await db.insert('audit_logs',{'event_at':eventAt,'user_id':userId,'branch_id':row['branch_id']??1,'action':action,'entity_type':entityType,'entity_id':entityId,'entity_label':row['reference_no'],'old_values_json':oldJson,'new_values_json':newJson,'reason':row['reason'],'severity':{'INFO','WARNING','CRITICAL'}.contains(severity)?severity:'INFO','prev_hash':previous,'row_hash':hash});
   previous=hash;
  }
  await db.execute('ALTER TABLE audit_logs_legacy_i5 RENAME TO audit_logs_legacy_i5_migrated');
 }

 static Future<void> _installDistributionPeriodTriggers(DatabaseExecutor db) async {
  final tables=await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='partner_distributions'");
  if(tables.isEmpty)return;
  for(final event in ['INSERT','UPDATE']){
   final trigger='trg_period_partner_distributions_'+event.toLowerCase();
   await db.execute('DROP TRIGGER IF EXISTS '+trigger);
   final sql="CREATE TRIGGER "+trigger+" BEFORE "+event+" ON partner_distributions WHEN EXISTS(SELECT 1 FROM fiscal_periods p WHERE p.status='CLOSED' AND p.period_code=NEW.period_code) OR (json_extract((SELECT setting_value FROM system_settings WHERE setting_no=29),'$.locked_through') IS NOT NULL AND NEW.period_code<=substr(json_extract((SELECT setting_value FROM system_settings WHERE setting_no=29),'$.locked_through'),1,7)) BEGIN SELECT RAISE(ABORT,'FISCAL_PERIOD_CLOSED'); END";
   await db.execute(sql);
  }
 }

 static Future<void> _installRelatedPeriodTriggers(DatabaseExecutor db) async {
  const relations={
   'journal_lines':('journal_entry_id','journal_entries','id','entry_date'),
   'sales_invoice_items':('invoice_id','sales_invoices','id','invoice_date'),
   'sales_payments':('invoice_id','sales_invoices','id','invoice_date'),
   'sales_return_items':('sales_return_id','sales_returns','id','return_date'),
   'partner_distribution_lines':('distribution_id','partner_distributions','id','period_code'),
  };
  for(final entry in relations.entries){
   final child=entry.key,foreignKey=entry.value.$1,parent=entry.value.$2,parentKey=entry.value.$3,parentDate=entry.value.$4;
   final childExists=await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name=?",[child]);
   final parentExists=await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name=?",[parent]);
   if(childExists.isEmpty||parentExists.isEmpty)continue;
   final childCols=await db.rawQuery('PRAGMA table_info('+child+')');
   final parentCols=await db.rawQuery('PRAGMA table_info('+parent+')');
   if(!childCols.any((r)=>r['name']==foreignKey)||!parentCols.any((r)=>r['name']==parentDate))continue;
   for(final event in ['INSERT','UPDATE']){
    final trigger='trg_period_related_'+child+'_'+event.toLowerCase();
    await db.execute('DROP TRIGGER IF EXISTS '+trigger);
    final periodCheck=parentDate=='period_code'
     ?"EXISTS(SELECT 1 FROM fiscal_periods p WHERE p.status='CLOSED' AND p.period_code=parent."+parentDate+") OR (json_extract((SELECT setting_value FROM system_settings WHERE setting_no=29),'$.locked_through') IS NOT NULL AND parent."+parentDate+"<=substr(json_extract((SELECT setting_value FROM system_settings WHERE setting_no=29),'$.locked_through'),1,7))"
     :"EXISTS(SELECT 1 FROM fiscal_periods p WHERE p.status='CLOSED' AND substr(parent."+parentDate+",1,10) BETWEEN p.start_date AND p.end_date) OR (json_extract((SELECT setting_value FROM system_settings WHERE setting_no=29),'$.locked_through') IS NOT NULL AND substr(parent."+parentDate+",1,10)<=json_extract((SELECT setting_value FROM system_settings WHERE setting_no=29),'$.locked_through'))";
    final sql='CREATE TRIGGER '+trigger+' BEFORE '+event+' ON '+child+' WHEN EXISTS(SELECT 1 FROM '+parent+' parent WHERE parent.'+parentKey+'=NEW.'+foreignKey+' AND ('+periodCheck+')) BEGIN SELECT RAISE(ABORT,\'FISCAL_PERIOD_CLOSED\'); END';
    await db.execute(sql);
   }
  }
 }

 static Future<void> _installPeriodTriggers(DatabaseExecutor db) async {
  const candidates={'sales_invoices':'invoice_date','purchase_invoices':'invoice_date','vouchers':'voucher_date','journal_entries':'entry_date','expenses':'expense_date','stock_movements':'movement_at','stocktaking_sessions':'created_at','sales_returns':'return_date','lah_alayh_ledger':'entry_date','employee_attendance':'work_date','disposals':'disposal_date'};
  for(final entry in candidates.entries){
   final tables=await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name=?",[entry.key]);
   if(tables.isEmpty)continue;
   final columns=await db.rawQuery('PRAGMA table_info('+entry.key+')');
   if(!columns.any((row)=>row['name']==entry.value))continue;
   final table=entry.key,column=entry.value;
   for(final event in ['INSERT','UPDATE']){
    final trigger='trg_period_guard_'+table.toLowerCase()+'_'+event.toLowerCase();
    await db.execute('DROP TRIGGER IF EXISTS '+trigger);
    final sql="CREATE TRIGGER "+trigger+" BEFORE "+event+" ON "+table+" WHEN (json_extract((SELECT setting_value FROM system_settings WHERE setting_no=29),'$.locked_through') IS NOT NULL AND substr(NEW."+column+",1,10)<=json_extract((SELECT setting_value FROM system_settings WHERE setting_no=29),'$.locked_through')) OR EXISTS(SELECT 1 FROM fiscal_periods p WHERE p.status='CLOSED' AND substr(NEW."+column+",1,10) BETWEEN p.start_date AND p.end_date) BEGIN SELECT RAISE(ABORT,'FISCAL_PERIOD_CLOSED'); END";
    await db.execute(sql);
   }
  }
 }

 static Future<void> _migrateLegacySettings(DatabaseExecutor db) async {
  final tables=await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='system_settings'");
  if(tables.isEmpty)return;
  final cols=await db.rawQuery('PRAGMA table_info(system_settings)');
  if(cols.any((r)=>r['name']=='group_name'))return;
  await db.execute('ALTER TABLE system_settings RENAME TO system_settings_legacy_i5');
 }
 static Future<void> _migrateLegacyAudit(DatabaseExecutor db) async {
  final tables=await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='audit_logs'");
  if(tables.isEmpty)return;
  final cols=await db.rawQuery('PRAGMA table_info(audit_logs)');
  if(cols.any((r)=>r['name']=='event_at'))return;
  await db.execute('ALTER TABLE audit_logs RENAME TO audit_logs_legacy_i5');
 }
}
