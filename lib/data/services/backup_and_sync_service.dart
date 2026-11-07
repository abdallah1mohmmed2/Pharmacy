// lib/data/services/backup_and_sync_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import 'settings_and_audit_service.dart';

class BackupResult {
 const BackupResult({required this.file,required this.sha256,required this.sizeBytes,required this.compressed});
 final File file; final String sha256; final int sizeBytes; final bool compressed;
}
class BackupAndSyncService {
 BackupAndSyncService({DatabaseHelper? helper,http.Client? client}):_helper=helper??DatabaseHelper.instance,_client=client??http.Client();
 final DatabaseHelper _helper; final http.Client _client;
 Future<BackupResult> createBackup({String triggerType='MANUAL',int? userId,int? keepLast,bool compress=true,String? preserveFilePath}) async {
  const triggers={'MANUAL','ON_SHIFT_CLOSE','ON_APP_CLOSE','BEFORE_RESTORE','BEFORE_PERIOD_CLOSE'};
  if(!triggers.contains(triggerType))throw ArgumentError('نوع النسخ الاحتياطي غير صحيح');
  final db=await _helper.database;final rows=await db.query('system_settings',where:'setting_no=34',limit:1);
  if(rows.isNotEmpty){final cfg=jsonDecode(rows.first['setting_value'] as String) as Map;keepLast??=(cfg['keep_last'] as num?)?.toInt()??10;compress=cfg['compress'] is bool?cfg['compress'] as bool:compress;}
  keepLast??=10;
  await db.execute('PRAGMA wal_checkpoint(FULL)');
  final directory=Directory(p.join((await getApplicationSupportDirectory()).path,'backups'));
  await directory.create(recursive:true);
  final stamp=DateTime.now().toIso8601String().replaceAll(':','-').replaceAll('.','-');
  final raw=File(p.join(directory.path,'pharmacy_backup_$stamp.db'));
  final escaped=raw.path.replaceAll("'","''");
  await db.execute("VACUUM INTO '$escaped'");
  File finalFile=raw;
  if(compress){final bytes=await raw.readAsBytes();final compressed=GZipCodec().encode(bytes);finalFile=File(raw.path+'.gz');await finalFile.writeAsBytes(compressed,flush:true);await raw.delete();}
  final bytes=await finalFile.readAsBytes();final digest=sha256.convert(bytes).toString();
  await db.insert('backup_log',{'backup_at':DateTime.now().toIso8601String(),'trigger_type':triggerType,'file_path':finalFile.path,'size_bytes':bytes.length,'sha256':digest,'encrypted':0,'result':'SUCCESS','user_id':userId});
  await AuditService(helper:_helper).record(action:'BACKUP',userId:userId,entityType:'backup_log',entityLabel:finalFile.path,newValues:{'sha256':digest,'size_bytes':bytes.length});
  final files=directory.listSync().whereType<File>().where((f)=>f.path.contains('pharmacy_backup_')).toList()..sort((a,b)=>b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  for(final old in files.skip(keepLast)){if(old.path!=finalFile.path&&old.path!=preserveFilePath)await old.delete();}
  return BackupResult(file:finalFile,sha256:digest,sizeBytes:bytes.length,compressed:compress);
 }
 Future<void> restoreBackup({required File backup,int? userId}) async {
  if(!await backup.exists())throw FileSystemException('ملف النسخة غير موجود',backup.path);
  final bytes=await backup.readAsBytes();final digest=sha256.convert(bytes).toString();
  final rows=await _helper.query('backup_log',where:'file_path=? AND result=?',whereArgs:[backup.path,'SUCCESS'],limit:1);
  if(rows.isEmpty)throw StateError('لا توجد بصمة موثوقة مسجلة لهذه النسخة');
  if(rows.first['sha256']!=digest)throw StateError('فشل التحقق من بصمة SHA-256 للنسخة');
  final preRestore=await createBackup(triggerType:'BEFORE_RESTORE',userId:userId,preserveFilePath:backup.path);
  final source=backup.path.endsWith('.gz')?GZipCodec().decode(bytes):bytes;
  final destination=await _helper.databaseFilePath;
  await _helper.close();
  await File(destination).writeAsBytes(source,flush:true);
  final restoredDb=await _helper.database;
  await restoredDb.insert('backup_log',{'backup_at':DateTime.now().toIso8601String(),'trigger_type':'BEFORE_RESTORE','file_path':preRestore.file.path,'size_bytes':preRestore.sizeBytes,'sha256':preRestore.sha256,'encrypted':0,'result':'SUCCESS','user_id':userId});
  await AuditService(helper:_helper).record(action:'BACKUP',userId:userId,entityType:'backup_log',entityLabel:preRestore.file.path,newValues:{'sha256':preRestore.sha256,'size_bytes':preRestore.sizeBytes});
  await AuditService(helper:_helper).record(action:'RESTORE',userId:userId,entityType:'database',entityLabel:backup.path,newValues:{'sha256':digest});
 }
 Future<int> enqueue({required String tableName,required String rowUuid,required String operation,required Map<String,Object?> payload,int syncVersion=1}) async {
  if(!{'INSERT','UPDATE','SOFT_DELETE'}.contains(operation))throw ArgumentError('عملية مزامنة غير مدعومة');
  final db=await _helper.database;
  return db.insert('sync_queue',{'table_name':tableName,'row_uuid':rowUuid,'operation':operation,'payload_json':jsonEncode(payload),'sync_version':syncVersion,'status':'PENDING'},conflictAlgorithm:ConflictAlgorithm.replace);
 }
 Future<List<Map<String,Object?>>> queueSummary() async=>_helper.rawQuery('SELECT status,COUNT(*) AS count FROM sync_queue GROUP BY status');
 Future<bool> ping(String baseUrl,{String? apiKey}) async {
  final base=Uri.tryParse(baseUrl.trim());if(base==null||!base.hasScheme||base.host.isEmpty)return false;
  final headers=<String,String>{'Accept':'application/json'};if(apiKey!=null&&apiKey.isNotEmpty)headers['Authorization']='Bearer $apiKey';
  try{final response=await _client.get(base.resolve('/ping'),headers:headers).timeout(const Duration(seconds:12));return response.statusCode>=200&&response.statusCode<300;}catch(_){return false;}
 }
 Future<int> collectLocalChanges({int maxRows=1000}) async {
  final db=await _helper.database;var collected=0;
  final tableRows=await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT IN ('audit_logs','sync_queue','backup_log')");
  for(final tableRow in tableRows){
   final table=tableRow['name'] as String;
   final columns=await db.rawQuery('PRAGMA table_info('+table+')');
   final names=columns.map((e)=>e['name'] as String).toSet();
   if(!names.contains('uuid')||!names.contains('sync_status')||!names.contains('sync_version'))continue;
   final rows=await db.query(table,where:"CAST(sync_status AS TEXT) IN ('LOCAL','PENDING','0')",limit:(maxRows-collected).clamp(0,maxRows).toInt());
   for(final row in rows){
    final uuid=row['uuid'];if(uuid==null)continue;
    final deleted=(row['is_deleted'] as num? ?? 0)==1;
    await db.insert('sync_queue',{'table_name':table,'row_uuid':uuid.toString(),'operation':deleted?'SOFT_DELETE':'INSERT','payload_json':jsonEncode(row),'sync_version':row['sync_version'],'status':'PENDING'},conflictAlgorithm:ConflictAlgorithm.ignore);
    await db.update(table,{'sync_status':'QUEUED'},where:'uuid=?',whereArgs:[uuid]);
    collected++;if(collected>=maxRows)return collected;
   }
  }
  return collected;
 }
 Future<int> syncNow({required String baseUrl,String? apiKey,int batchSize=100}) async {
  final base=Uri.tryParse(baseUrl.trim());if(base==null||base.host.isEmpty)throw ArgumentError('رابط خادم المزامنة غير صحيح');
  await collectLocalChanges(maxRows:batchSize*10);
  final db=await _helper.database;final pending=await db.query('sync_queue',where:'status IN (?,?)',whereArgs:['PENDING','FAILED'],orderBy:'id',limit:batchSize);
  if(pending.isEmpty)return 0;
  final ids=pending.map((e)=>e['id'] as int).toList();
  await db.update('sync_queue',{'status':'SENDING'},where:'id IN ('+List.filled(ids.length,'?').join(',')+')',whereArgs:ids);
  final headers=<String,String>{'Content-Type':'application/json','Accept':'application/json'};if(apiKey!=null&&apiKey.isNotEmpty)headers['Authorization']='Bearer $apiKey';
  try{
   final response=await _client.post(base.resolve('/sync/batch'),headers:headers,body:jsonEncode({'items':pending.map((e)=>{'id':e['id'],'table':e['table_name'],'uuid':e['row_uuid'],'operation':e['operation'],'version':e['sync_version'],'payload':jsonDecode(e['payload_json'] as String)}).toList()})).timeout(const Duration(seconds:30));
   if(response.statusCode<200||response.statusCode>=300)throw HttpException('Sync HTTP '+response.statusCode.toString());
   final body=jsonDecode(response.body) as Map<String,Object?>;
   final results=(body['results'] as List? ?? const []);
   for(final item in results.whereType<Map>()){
    final id=(item['id'] as num?)?.toInt();if(id==null)continue;
    final status=switch(item['status']){'DONE'=>'DONE','CONFLICT'=>'CONFLICT',_=>'FAILED'};
    await db.update('sync_queue',{'status':status,'last_error':item['message']?.toString(),'attempts':1},where:'id=?',whereArgs:[id]);
   }
   final processed=results.length;
   if(processed==0)await db.update('sync_queue',{'status':'FAILED','last_error':'الخادم لم يرجع نتائج للعناصر المرسلة'},where:'id IN ('+List.filled(ids.length,'?').join(',')+')',whereArgs:ids);
   return processed;
  }catch(e){
   await db.update('sync_queue',{'status':'FAILED','last_error':e.toString(),'attempts':1},where:'id IN ('+List.filled(ids.length,'?').join(',')+')',whereArgs:ids);
   rethrow;
  }
 }
 Future<List<Map<String,Object?>>> backups() async=>(await _helper.query('backup_log',orderBy:'id DESC'));
}
typedef SyncService = BackupAndSyncService;
