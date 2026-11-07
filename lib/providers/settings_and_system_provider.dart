// lib/providers/settings_and_system_provider.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/constants/setting_keys.dart';
import '../data/database/database_helper.dart';
import '../data/models/settings_audit_sync_models.dart';
import '../data/services/settings_and_audit_service.dart';
import '../data/services/drug_import_export_service.dart';
import '../data/services/backup_and_sync_service.dart';

class SettingsAndSystemProvider extends ChangeNotifier {
 SettingsAndSystemProvider({required Future<bool> Function(String) verifyManagerPin,DatabaseHelper? helper})
  :_helper=helper??DatabaseHelper.instance,
   settings=SettingsService(helper:helper,verifyManagerPin:verifyManagerPin),
   importer=DrugImportExportService(helper:helper),
   backup=BackupAndSyncService(helper:helper),
   audit=AuditService(helper:helper),
   periods=PeriodGuard(helper:helper);
 final DatabaseHelper _helper;
 final SettingsService settings;
 final DrugImportExportService importer;
 final BackupAndSyncService backup;
 final AuditService audit;
 final PeriodGuard periods;
 bool loading=false,busy=false;
 String? error;
 List<ImportJobModel> importJobs=[];
 List<AuditLogModel> auditLogs=[];
 List<Map<String,Object?>> backupLogs=[],syncSummary=[],roleRows=[],periodRows=[];
 ChainVerificationResult? chainResult;
 ImportDryRunResult? dryRunResult;
 ImportExecutionResult? importResult;
 int importProgress=0,importTotal=0;

 Future<void> initialize() async {
  loading=true;error=null;notifyListeners();
  try{await settings.load();await refreshSystemData();}
  catch(e){error=e.toString();}
  loading=false;notifyListeners();
 }
 Future<void> refreshSystemData() async {
  importJobs=await importer.listJobs();
  auditLogs=(await _helper.query('audit_logs',orderBy:'id DESC',limit:500)).map(AuditLogModel.fromMap).toList();
  backupLogs=await backup.backups();
  syncSummary=await backup.queueSummary();
  roleRows=await _helper.rawQuery('SELECT rp.role_code,r.role_name_ar,rp.permission_code,rp.is_allowed FROM role_permissions rp JOIN roles r ON r.role_code=rp.role_code ORDER BY rp.role_code,rp.permission_code');
  periodRows=await _helper.query('fiscal_periods',orderBy:'start_date DESC');
 }
 Future<void> changeSetting(SettingKey key,Object value,{String? managerPin,required int? userId,int branchId=1,String? reason}) async {
  await settings.setSetting(key,value,managerPin:managerPin,userId:userId,branchId:branchId,reason:reason);
  notifyListeners();
 }
 Future<ImportDryRunResult> dryRun({required String source,required String format,Map<String,String> mapping=const {}}) async {
  dryRunResult=await importer.dryRunImport(source:source,format:format,mapping:mapping);notifyListeners();return dryRunResult!;
 }
 Future<ImportExecutionResult> executeImport({required String source,required String format,Map<String,String> mapping=const {},String conflictPolicy='SKIP',String? fileName}) async {
  busy=true;importProgress=0;importTotal=0;notifyListeners();
  try{final result=await importer.executeImport(source:source,format:format,mapping:mapping,conflictPolicy:conflictPolicy,fileName:fileName,onProgress:(done,total){importProgress=done;importTotal=total;notifyListeners();});importResult=result;await refreshSystemData();return result;}
  finally{busy=false;notifyListeners();}
 }
 Future<List<OpenFdaDrugResult>> searchOpenFda(String query)=>importer.searchOpenFda(query);
 Future<File> exportDrugs({required String format,bool hideCostPrices=true,int? categoryId}) async {
  final file=await importer.exportDrugs(format:format,hideCostPrices:hideCostPrices,categoryId:categoryId);await refreshSystemData();return file;
 }
 Future<BackupResult> createBackup({String triggerType='MANUAL',int? userId}) async {
  final result=await backup.createBackup(triggerType:triggerType,userId:userId);await refreshSystemData();return result;
 }
 Future<void> restoreBackup(File file,{int? userId}) async {await backup.restoreBackup(backup:file,userId:userId);await initialize();}
 Future<bool> testCloudConnection() async {
  final cfg=settings.getJson(SettingKey.cloudSync);
  return backup.ping((cfg['base_url']??'').toString(),apiKey:cfg['api_key']?.toString());
 }
 Future<int> syncNow() async {
  final cfg=settings.getJson(SettingKey.cloudSync);
  final count=await backup.syncNow(baseUrl:(cfg['base_url']??'').toString(),apiKey:cfg['api_key']?.toString(),batchSize:(cfg['batch_size'] as num?)?.toInt()??100);
  await refreshSystemData();return count;
 }
 Future<ChainVerificationResult> verifyAuditChain() async {chainResult=await audit.verifyChainIntegrity();notifyListeners();return chainResult!;}
 Future<int> closeFiscalPeriod(String code,{required int userId,required Future<void> Function() createPreCloseBackup}) async {
  final id=await periods.closePeriod(periodCode:code,userId:userId,createPreCloseBackup:createPreCloseBackup,hasOpenShiftsOrStocktakes:_hasOpenOperationalSessions);
  await refreshSystemData();notifyListeners();return id;
 }
 Future<bool> _hasOpenOperationalSessions() async {
  final tables=await _helper.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
  for(final row in tables){
   final name=row['name'] as String;
   if(!RegExp(r'(shift|stocktake|stock_taking)',caseSensitive:false).hasMatch(name))continue;
   final columns=await _helper.rawQuery('PRAGMA table_info('+name+')');
   final names=columns.map((e)=>e['name'] as String).toSet();
   final statusColumn=names.contains('status')?'status':names.contains('state')?'state':null;
   if(statusColumn==null)continue;
   final open=await _helper.rawQuery('SELECT COUNT(*) AS n FROM '+name+' WHERE upper('+statusColumn+') IN (\'OPEN\',\'ACTIVE\',\'IN_PROGRESS\')');
   if((open.first['n'] as num)>0)return true;
  }
  return false;
 }
 Future<void> setRolePermission(String role,String permission,bool allowed) async {
  final db=await _helper.database;
  await db.update('role_permissions',{'is_allowed':allowed?1:0},where:'role_code=? AND permission_code=?',whereArgs:[role,permission]);
  await refreshSystemData();notifyListeners();
 }
}
