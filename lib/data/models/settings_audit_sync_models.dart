// lib/data/models/settings_audit_sync_models.dart
import 'dart:convert';
class SystemSettingModel {
 const SystemSettingModel({required this.settingNo,required this.key,required this.group,required this.valueType,required this.value,required this.defaultValue,required this.descriptionAr,this.requiresManager=false,this.updatedAt});
 final int settingNo; final String key,group,valueType,value,defaultValue,descriptionAr; final bool requiresManager; final String? updatedAt;
 factory SystemSettingModel.fromMap(Map<String,Object?> m)=>SystemSettingModel(settingNo:(m['setting_no'] as num).toInt(),key:m['setting_key'] as String,group:m['group_name'] as String,valueType:m['value_type'] as String,value:m['setting_value'] as String,defaultValue:m['default_value'] as String,descriptionAr:m['description_ar'] as String? ?? '',requiresManager:(m['requires_manager'] as num? ?? 0)==1,updatedAt:m['updated_at'] as String?);
 Map<String,Object?> toMap()=>{'setting_no':settingNo,'setting_key':key,'group_name':group,'value_type':valueType,'setting_value':value,'default_value':defaultValue,'description_ar':descriptionAr,'requires_manager':requiresManager?1:0,'updated_at':updatedAt};
 Object? get decodedValue=>switch(valueType){'BOOL'=>value=='true'||value=='1','INT'=>int.tryParse(value),'REAL'=>double.tryParse(value),'JSON'=>jsonDecode(value),_=>value};
}
class ImportJobModel {
 const ImportJobModel({this.id,required this.sourceType,this.fileName,this.mappingJson='{}',this.conflictPolicy='SKIP',this.totalRows=0,this.insertedRows=0,this.updatedRows=0,this.skippedRows=0,this.errorRows=0,this.status='PENDING',this.startedAt,this.finishedAt});
 final int? id,totalRows,insertedRows,updatedRows,skippedRows,errorRows; final String sourceType,mappingJson,conflictPolicy,status; final String? fileName,startedAt,finishedAt;
 factory ImportJobModel.fromMap(Map<String,Object?> m)=>ImportJobModel(id:m['id'] as int?,sourceType:m['source_type'] as String,fileName:m['file_name'] as String?,mappingJson:m['mapping_json'] as String? ?? '{}',conflictPolicy:m['conflict_policy'] as String? ?? 'SKIP',totalRows:(m['total_rows'] as num? ?? 0).toInt(),insertedRows:(m['inserted_rows'] as num? ?? 0).toInt(),updatedRows:(m['updated_rows'] as num? ?? 0).toInt(),skippedRows:(m['skipped_rows'] as num? ?? 0).toInt(),errorRows:(m['error_rows'] as num? ?? 0).toInt(),status:m['status'] as String? ?? 'PENDING',startedAt:m['started_at'] as String?,finishedAt:m['finished_at'] as String?);
 Map<String,Object?> toMap()=>{'id':id,'source_type':sourceType,'file_name':fileName,'mapping_json':mappingJson,'conflict_policy':conflictPolicy,'total_rows':totalRows,'inserted_rows':insertedRows,'updated_rows':updatedRows,'skipped_rows':skippedRows,'error_rows':errorRows,'status':status,'started_at':startedAt,'finished_at':finishedAt};
}
class ColumnMappingTemplate {
 const ColumnMappingTemplate({required this.name,required this.columns}); final String name; final Map<String,String> columns;
 Map<String,Object?> toMap()=>{'name':name,'columns':columns};
 factory ColumnMappingTemplate.fromMap(Map<String,Object?> m)=>ColumnMappingTemplate(name:m['name'] as String,columns:Map<String,String>.from(m['columns'] as Map));
}
class OpenFdaDrugResult {
 const OpenFdaDrugResult({required this.brandName,required this.genericName,required this.manufacturer,required this.fields,required this.rawJson});
 final String brandName,genericName,manufacturer; final Map<String,String> fields; final Map<String,Object?> rawJson;
 factory OpenFdaDrugResult.fromMap(Map<String,Object?> m)=>OpenFdaDrugResult(brandName:m['brand_name'] as String? ?? '',genericName:m['generic_name'] as String? ?? '',manufacturer:m['manufacturer_name'] as String? ?? '',fields:{for(final e in m.entries)if(e.value is List&&(e.value as List).isNotEmpty)e.key:(e.value as List).first.toString()},rawJson:m);
}
class AuditLogModel {
 const AuditLogModel({this.id,required this.eventAt,this.userId,this.branchId=1,this.deviceId,required this.action,this.entityType,this.entityId,this.entityLabel,this.oldValuesJson,this.newValuesJson,this.reason,this.severity='INFO',this.prevHash,this.rowHash});
 final int? id,userId,branchId,entityId; final String eventAt,action,severity; final String? deviceId,entityType,entityLabel,oldValuesJson,newValuesJson,reason,prevHash,rowHash;
 factory AuditLogModel.fromMap(Map<String,Object?> m)=>AuditLogModel(id:m['id'] as int?,eventAt:m['event_at'] as String,userId:m['user_id'] as int?,branchId:(m['branch_id'] as num? ?? 1).toInt(),deviceId:m['device_id'] as String?,action:m['action'] as String,entityType:m['entity_type'] as String?,entityId:m['entity_id'] as int?,entityLabel:m['entity_label'] as String?,oldValuesJson:m['old_values_json'] as String?,newValuesJson:m['new_values_json'] as String?,reason:m['reason'] as String?,severity:m['severity'] as String? ?? 'INFO',prevHash:m['prev_hash'] as String?,rowHash:m['row_hash'] as String?);
 Map<String,Object?> toMap()=>{'id':id,'event_at':eventAt,'user_id':userId,'branch_id':branchId,'device_id':deviceId,'action':action,'entity_type':entityType,'entity_id':entityId,'entity_label':entityLabel,'old_values_json':oldValuesJson,'new_values_json':newValuesJson,'reason':reason,'severity':severity,'prev_hash':prevHash,'row_hash':rowHash};
}
class ChainVerificationResult {
 const ChainVerificationResult({required this.isValid,required this.checkedRows,this.firstInvalidId,this.expectedHash,this.actualHash});
 final bool isValid; final int checkedRows; final int? firstInvalidId; final String? expectedHash,actualHash;
}
class BackupLogModel {
 const BackupLogModel({this.id,required this.backupAt,required this.triggerType,required this.filePath,this.sizeBytes=0,required this.sha256,this.encrypted=false,required this.result,this.errorText,this.userId});
 final int? id,userId; final String backupAt,triggerType,filePath,sha256,result; final int sizeBytes; final bool encrypted; final String? errorText;
 factory BackupLogModel.fromMap(Map<String,Object?> m)=>BackupLogModel(id:m['id'] as int?,backupAt:m['backup_at'] as String,triggerType:m['trigger_type'] as String,filePath:m['file_path'] as String,sizeBytes:(m['size_bytes'] as num? ?? 0).toInt(),sha256:m['sha256'] as String,encrypted:(m['encrypted'] as num? ?? 0)==1,result:m['result'] as String,errorText:m['error_text'] as String?,userId:m['user_id'] as int?);
}
class SyncQueueItemModel {
 const SyncQueueItemModel({this.id,required this.tableName,required this.rowUuid,required this.operation,required this.payloadJson,this.syncVersion=1,this.attempts=0,this.lastError,this.status='PENDING',required this.queuedAt});
 final int? id,syncVersion,attempts; final String tableName,rowUuid,operation,payloadJson,status,queuedAt; final String? lastError;
 factory SyncQueueItemModel.fromMap(Map<String,Object?> m)=>SyncQueueItemModel(id:m['id'] as int?,tableName:m['table_name'] as String,rowUuid:m['row_uuid'] as String,operation:m['operation'] as String,payloadJson:m['payload_json'] as String,syncVersion:(m['sync_version'] as num? ?? 1).toInt(),attempts:(m['attempts'] as num? ?? 0).toInt(),lastError:m['last_error'] as String?,status:m['status'] as String? ?? 'PENDING',queuedAt:m['queued_at'] as String);
}
class FiscalPeriodModel {
 const FiscalPeriodModel({this.id,required this.periodCode,required this.periodType,required this.startDate,required this.endDate,this.status='OPEN',this.closedAt,this.closedBy});
 final int? id,closedBy; final String periodCode,periodType,startDate,endDate,status; final String? closedAt;
 factory FiscalPeriodModel.fromMap(Map<String,Object?> m)=>FiscalPeriodModel(id:m['id'] as int?,periodCode:m['period_code'] as String,periodType:m['period_type'] as String,startDate:m['start_date'] as String,endDate:m['end_date'] as String,status:m['status'] as String? ?? 'OPEN',closedAt:m['closed_at'] as String?,closedBy:m['closed_by'] as int?);
}
class RolePermissionModel {
 const RolePermissionModel({required this.roleCode,required this.permissionCode,this.isAllowed=false}); final String roleCode,permissionCode; final bool isAllowed;
 factory RolePermissionModel.fromMap(Map<String,Object?> m)=>RolePermissionModel(roleCode:m['role_code'] as String,permissionCode:m['permission_code'] as String,isAllowed:(m['is_allowed'] as num? ?? 0)==1);
 Map<String,Object?> toMap()=>{'role_code':roleCode,'permission_code':permissionCode,'is_allowed':isAllowed?1:0};
}
