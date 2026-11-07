// lib/data/services/settings_and_audit_service.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/settings_audit_sync_models.dart';
import '../../core/constants/setting_keys.dart';

typedef ManagerPinVerifier = Future<bool> Function(String pin);
class SettingsService {
 SettingsService({DatabaseHelper? helper,required ManagerPinVerifier verifyManagerPin}):_helper=helper??DatabaseHelper.instance,_verifyManagerPin=verifyManagerPin;
 final DatabaseHelper _helper; final ManagerPinVerifier _verifyManagerPin;
 final Map<String,Object?> _cache={}; bool _loaded=false;
 Future<void> load() async {
  final rows=await _helper.query('system_settings',orderBy:'setting_no');
  _cache.clear();
  for(final row in rows){final model=SystemSettingModel.fromMap(row);_cache[model.key]=model.decodedValue;}
  if(_cache.length!=35)throw StateError('يجب تحميل الإعدادات الـ35 كاملة؛ الموجود '+_cache.length.toString());
  _loaded=true;
  final mode=getString(SettingKey.partnerDistributionMode);
  final db=await _helper.database;
  await db.transaction((txn)=>_applyPartnerStateLock(txn,mode));
 }
 void _ensureLoaded(){if(!_loaded)throw StateError('يجب تحميل الإعدادات قبل القراءة');}
 Object? getValue(SettingKey key){_ensureLoaded();return _cache[SettingKeys.byKey(key).name];}
 bool getBool(SettingKey key)=>getValue(key) as bool;
 int getInt(SettingKey key)=>getValue(key) as int;
 double getDouble(SettingKey key)=>(getValue(key) as num).toDouble();
 String getString(SettingKey key)=>getValue(key) as String;
 Map<String,Object?> getJson(SettingKey key)=>Map<String,Object?>.from(getValue(key) as Map);
 Future<void> setSetting(SettingKey key,Object value,{String? managerPin,required int? userId,int branchId=1,String? reason}) async {
  _ensureLoaded(); final spec=SettingKeys.byKey(key);
  if(key==SettingKey.lahAlayhTermsOnly&&value!=true)throw StateError('هذا الإعداد مقفول ولا يمكن تعطيله');
  _validate(spec,value);
  if(spec.requiresManager){if(managerPin==null||!await _verifyManagerPin(managerPin))throw StateError('رمز المدير غير صحيح أو غير متوفر');}
  final old=_cache[spec.name]; final encoded=_encode(value);
  final db=await _helper.database;
  await db.transaction((txn)async{
   await txn.update('system_settings',{'setting_value':encoded,'updated_at':DateTime.now().toIso8601String(),'updated_by':userId},where:'setting_key=?',whereArgs:[spec.name]);
   if(key==SettingKey.partnerDistributionMode)await _applyPartnerStateLock(txn,value as String);
  });
  _cache[spec.name]=value;
  await AuditService(helper:_helper).record(action:'SETTING_CHANGE',userId:userId,branchId:branchId,entityType:'system_settings',entityId:spec.number,entityLabel:spec.name,oldValues:{'value':old},newValues:{'value':value},reason:reason,severity:'WARNING');
 }
 Future<void> _applyPartnerStateLock(DatabaseExecutor txn,String mode) async {
  if(mode!='shares'&&mode!='percentage')throw ArgumentError('نمط توزيع الشركاء غير صالح');
  final partnerTables=await txn.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='partners'");
  if(partnerTables.isNotEmpty){
   if(mode=='shares')await txn.update('partners',{'percentage':null});
   else await txn.update('partners',{'shares_count':null});
  }
  final settingsTable=await txn.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='app_settings'");
  if(settingsTable.isNotEmpty){
   final existing=await txn.query('app_settings',where:'setting_key=?',whereArgs:['accounting.partner_distribution_mode'],limit:1);
   if(existing.isEmpty){
    await txn.insert('app_settings',{'setting_key':'accounting.partner_distribution_mode','value_text':mode});
   }else{
    await txn.update('app_settings',{'value_text':mode},where:'setting_key=?',whereArgs:['accounting.partner_distribution_mode']);
   }
  }
 }
 void _validate(SettingSpec s,Object value){
  final valid=switch(s.type){SettingValueType.boolean=>value is bool,SettingValueType.integer=>value is int,SettingValueType.real=>value is num,SettingValueType.string=>value is String,SettingValueType.json=>value is Map||value is List};
  if(!valid)throw ArgumentError('نوع قيمة الإعداد غير صحيح: '+s.name);
  if(s.allowedValues.isNotEmpty&&!s.allowedValues.contains(value))throw ArgumentError('قيمة غير مسموحة للإعداد '+s.name);
  if(s.key==SettingKey.maxCashierDiscountPct&&(value as num)<0||s.key==SettingKey.maxCashierDiscountPct&&(value as num)>100)throw RangeError('نسبة الخصم يجب أن تكون بين 0 و100');
  if(s.key==SettingKey.expiryWarningDays&&((value as int)<0||(value as int)>3650))throw RangeError('أيام التنبيه خارج النطاق');
  if(s.type==SettingValueType.json)jsonEncode(value);
 }
 String _encode(Object value)=>value is String?value:value is bool?(value?'1':'0'):value is Map||value is List?jsonEncode(value):value.toString();
 List<SystemSettingModel> get allSettings=>SettingKeys.all.map((s)=>SystemSettingModel(settingNo:s.number,key:s.name,group:s.groupName,valueType:s.typeName,value:_encode(_cache[s.name]??s.defaultValue),defaultValue:s.defaultJson,descriptionAr:s.descriptionAr,requiresManager:s.requiresManager)).toList(growable:false);
}

class PeriodGuard {
 PeriodGuard({DatabaseHelper? helper}):_helper=helper??DatabaseHelper.instance;
 final DatabaseHelper _helper;
 Future<void> assertWritable(DateTime date) async {
  final iso=date.toIso8601String().substring(0,10);
  final setting=await _helper.query('system_settings',where:'setting_no=29',limit:1);
  if(setting.isNotEmpty){final value=jsonDecode(setting.first['setting_value'] as String) as Map;final locked=value['locked_through'];if(locked is String&&iso.compareTo(locked)<=0)throw StateError('الفترة مقفلة حتى '+locked);}
  final rows=await _helper.rawQuery("SELECT period_code FROM fiscal_periods WHERE status='CLOSED' AND start_date<=? AND end_date>=? LIMIT 1",[iso,iso]);
  if(rows.isNotEmpty)throw StateError('لا يمكن التعديل داخل الفترة المالية المغلقة '+rows.first['period_code'].toString());
 }
 Future<int> closePeriod({required String periodCode,required int userId,required Future<void> Function() createPreCloseBackup,required Future<bool> Function() hasOpenShiftsOrStocktakes}) async {
  if(await hasOpenShiftsOrStocktakes())throw StateError('توجد ورديات أو جلسات جرد مفتوحة');
  await createPreCloseBackup();
  final db=await _helper.database;
  final rows=await db.query('fiscal_periods',where:'period_code=? AND status=?',whereArgs:[periodCode,'OPEN'],limit:1);
  if(rows.isEmpty)throw StateError('الفترة غير موجودة أو مغلقة مسبقاً');
  final id=rows.first['id'] as int;
  await db.transaction((txn)async{
   await txn.update('fiscal_periods',{'status':'CLOSED','closed_at':DateTime.now().toIso8601String(),'closed_by':userId},where:'id=?',whereArgs:[id]);
   final period=rows.first;
   final lock=jsonEncode({'locked_through':period['end_date']});
   await txn.update('system_settings',{'setting_value':lock,'updated_at':DateTime.now().toIso8601String(),'updated_by':userId},where:'setting_no=29');
  });
  await AuditService(helper:_helper).record(action:'PERIOD_CLOSE',userId:userId,entityType:'fiscal_periods',entityId:id,entityLabel:periodCode,newValues:{'status':'CLOSED'});
  return id;
 }
}

class AuditService {
 AuditService({DatabaseHelper? helper}):_helper=helper??DatabaseHelper.instance;
 final DatabaseHelper _helper;
 static String _hash(String value)=>sha256.convert(utf8.encode(value)).toString();
 String _canonical({required String prevHash,required String eventAt,required int? userId,required String action,required String? entityType,required int? entityId,required String? oldValues,required String? newValues})=>[prevHash,eventAt,userId?.toString()??'',action,entityType??'',entityId?.toString()??'',oldValues??'',newValues??''].join('|');
 Future<int> record({required String action,int? userId,int branchId=1,String? deviceId,String? entityType,int? entityId,String? entityLabel,Map<String,Object?>? oldValues,Map<String,Object?>? newValues,String? reason,String severity='INFO'}) async {
  const actions={'LOGIN','LOGOUT','LOGIN_FAILED','CREATE','UPDATE','DELETE','VOID','PRICE_CHANGE','DISCOUNT_OVERRIDE','CLINICAL_OVERRIDE','SETTING_CHANGE','PERIOD_CLOSE','BACKUP','RESTORE','PRINT','EXPORT','MANAGER_PIN_USED'};
  if(!actions.contains(action))throw ArgumentError('حدث رقابي غير مدعوم');
  final db=await _helper.database;final eventAt=DateTime.now().toUtc().toIso8601String();
  final previous=await db.query('audit_logs',columns:['row_hash'],orderBy:'id DESC',limit:1);
  final prev=previous.isEmpty?'GENESIS':previous.first['row_hash'] as String;
  final oldJson=oldValues==null?null:jsonEncode(oldValues),newJson=newValues==null?null:jsonEncode(newValues);
  final rowHash=_hash(_canonical(prevHash:prev,eventAt:eventAt,userId:userId,action:action,entityType:entityType,entityId:entityId,oldValues:oldJson,newValues:newJson));
  return db.insert('audit_logs',{'event_at':eventAt,'user_id':userId,'branch_id':branchId,'device_id':deviceId,'action':action,'entity_type':entityType,'entity_id':entityId,'entity_label':entityLabel,'old_values_json':oldJson,'new_values_json':newJson,'reason':reason,'severity':severity,'prev_hash':prev,'row_hash':rowHash});
 }
 Future<ChainVerificationResult> verifyChainIntegrity() async {
  final rows=await _helper.query('audit_logs',orderBy:'id');
  var previous='GENESIS';var checked=0;
  for(final row in rows){
   final expected=_hash(_canonical(prevHash:previous,eventAt:row['event_at'] as String,userId:row['user_id'] as int?,action:row['action'] as String,entityType:row['entity_type'] as String?,entityId:row['entity_id'] as int?,oldValues:row['old_values_json'] as String?,newValues:row['new_values_json'] as String?));
   final actual=row['row_hash'] as String?;
   if(row['prev_hash']!=previous||actual!=expected)return ChainVerificationResult(isValid:false,checkedRows:checked,firstInvalidId:row['id'] as int,expectedHash:expected,actualHash:actual);
   previous=actual!;checked++;
  }
  return ChainVerificationResult(isValid:true,checkedRows:checked);
 }
}
