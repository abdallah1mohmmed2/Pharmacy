// lib/data/services/drug_import_export_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/drug_model.dart';
import '../models/settings_audit_sync_models.dart';
import 'settings_and_audit_service.dart';

class ImportRowIssue {
 const ImportRowIssue(this.rowNumber,this.message);
 final int rowNumber; final String message;
}
class ImportDryRunResult {
 const ImportDryRunResult({required this.totalRows,required this.validRows,required this.errors,required this.duplicates});
 final int totalRows,validRows,duplicates; final List<ImportRowIssue> errors;
}
class ImportExecutionResult {
 const ImportExecutionResult({required this.jobId,required this.inserted,required this.updated,required this.skipped,required this.errors});
 final int jobId,inserted,updated,skipped,errors;
}
class DrugImportExportService {
 DrugImportExportService({DatabaseHelper? helper,http.Client? client}):_helper=helper??DatabaseHelper.instance,_client=client??http.Client();
 final DatabaseHelper _helper; final http.Client _client;
 static const List<String> clinicalPointColumns=[
  'trade_name_ar','trade_name_en','scientific_name','ingredients_json','therapeutic_class','indications','dosage_administration','contraindications','warnings_precautions','interactions_summary','side_effects_common','side_effects_serious','geriatric_notes','pediatric_notes','pregnancy_notes','min_age_months','pregnancy_category','lactation_notes','storage_conditions'
 ];
 static const List<ColumnMappingTemplate> templates=[
  ColumnMappingTemplate(name:'قالب CSV عربي',columns:{'الاسم التجاري':'trade_name_ar','الاسم العلمي':'scientific_name','الشركة':'manufacturer_id','الفئة':'category_id','التركيز':'strength_text','الشكل':'dosage_form','دواعي الاستعمال':'indications','الجرعة':'dosage_administration','موانع الاستعمال':'contraindications','التحذيرات':'warnings_precautions','التفاعلات':'interactions_summary','الأعراض الجانبية':'side_effects_common','الحمل':'pregnancy_category','التخزين':'storage_conditions'}),
  ColumnMappingTemplate(name:'قالب قياسي',columns:{'brand_name':'trade_name_en','generic_name':'scientific_name','indications_and_usage':'indications','dosage_and_administration':'dosage_administration','contraindications':'contraindications','warnings':'warnings_precautions','drug_interactions':'interactions_summary','adverse_reactions':'side_effects_common','pregnancy':'pregnancy_notes','pediatric_use':'pediatric_notes','geriatric_use':'geriatric_notes','storage_and_handling':'storage_conditions'}),
 ];
 Future<List<Map<String,Object?>>> parse(String source,{required String format,Map<String,String> mapping=const {}}) async {
  final normalized=format.toUpperCase();
  if(normalized=='JSON'){
   final decoded=jsonDecode(source);
   final rows=decoded is List?decoded:(decoded is Map&&decoded['drugs'] is List?decoded['drugs'] as List:throw FormatException('يجب أن يحتوي JSON على قائمة أدوية'));
   return rows.map((e){if(e is! Map)throw const FormatException('كل صف JSON يجب أن يكون كائناً');return _mapFields(Map<String,Object?>.from(e),mapping);}).toList();
  }
  if(normalized=='CSV'){
   final rows=const CsvToListConverter(shouldParseNumbers:false).convert(source);
   if(rows.isEmpty)return [];
   final headers=rows.first.map((e)=>e.toString().trim()).toList();
   return rows.skip(1).where((r)=>r.any((e)=>e.toString().trim().isNotEmpty)).map((r){
    final sourceRow=<String,Object?>{};for(var i=0;i<headers.length&&i<r.length;i++){sourceRow[headers[i]]=r[i];}
    return _mapFields(sourceRow,mapping);
   }).toList();
  }
  throw ArgumentError('الصيغة المدعومة CSV أو JSON فقط');
 }
 Map<String,Object?> _mapFields(Map<String,Object?> source,Map<String,String> mapping){
  final result=<String,Object?>{};
  if(mapping.isEmpty){for(final e in source.entries){if(_knownColumns.contains(e.key))result[e.key]=e.value;}}
  else{for(final e in mapping.entries){if(source.containsKey(e.key))result[e.value]=source[e.key];}}
  const intFields=['manufacturer_id','active_ingredient_id','category_id','strips_per_pack','units_per_strip','units_per_pack','min_age_months','max_age_months','geriatric_age_threshold','min_stock_units','reorder_qty_packs','stock_total_units'];
  const doubleFields=['strength_value','adult_dose_min_mg','adult_dose_max_mg_per_day','ped_dose_mg_per_kg_min','ped_dose_mg_per_kg_max','ped_max_daily_mg_per_kg','storage_temp_min_c','storage_temp_max_c','cost_price_pack','last_purchase_cost_pack','sell_price_pack','sell_price_strip','sell_price_unit','profit_margin_pct','public_price_pack','tax_rate_pct'];
  const boolFields=['is_active','is_strip_based','has_critical_interactions','is_nephrotoxic','neonate_allowed','requires_refrigeration','protect_from_light','is_controlled','requires_prescription','prescription_restricted','is_antibiotic'];
  for(final key in intFields){if(result[key]!=null){final parsed=int.tryParse(result[key].toString());if(parsed==null)throw FormatException('قيمة عددية غير صحيحة للحقل '+key);result[key]=parsed;}}
  for(final key in doubleFields){if(result[key]!=null){final parsed=double.tryParse(result[key].toString());if(parsed==null)throw FormatException('قيمة عشرية غير صحيحة للحقل '+key);result[key]=parsed;}}
  for(final key in boolFields){if(result[key]!=null){final raw=result[key].toString().toLowerCase();if(!{'1','0','true','false','yes','no'}.contains(raw))throw FormatException('قيمة منطقية غير صحيحة للحقل '+key);result[key]={'1','true','yes'}.contains(raw)?1:0;}}
  for(final key in result.keys.toList()){
   final value=result[key];
   if(value is Map||value is List){result[key]=jsonEncode(value);}
   else if(value!=null&&value is! num)result[key]=value.toString();
  }
  return result;
 }
 static const Set<String> _knownColumns={
  internal_code','trade_name_ar','trade_name_en','scientific_name','ingredients_json','chemical_composition','category_id','therapeutic_class','pharmacologic_class','atc_code','dosage_form','strength_text','strength_value','strength_unit','route','indications','dosage_administration','adult_dose_min_mg','adult_dose_max_mg_per_day','dose_frequency_text','take_with_food','label_dose_text_ar','contraindications','contraindications_json','warnings_precautions','black_box_warning','warnings_json','interactions_summary','has_critical_interactions','side_effects_common','side_effects_serious','min_age_months','max_age_months','allowed_populations_json','hepatic_status','hepatic_notes','renal_status','renal_notes','is_nephrotoxic','geriatric_status','geriatric_notes','beers_criteria','geriatric_age_threshold','pediatric_status','pediatric_notes','ped_dose_mg_per_kg_min','ped_dose_mg_per_kg_max','ped_max_daily_mg_per_kg','ped_doses_per_day','neonate_allowed','pregnancy_category','pregnancy_notes','pregnancy_trimester_json','lactation_risk','lactation_notes','storage_conditions','storage_temp_min_c','storage_temp_max_c','requires_refrigeration','protect_from_light','barcode_international','barcode_local','registration_no','is_controlled','controlled_schedule','requires_prescription','prescription_restricted','is_antibiotic','cost_price_pack','last_purchase_cost_pack','sell_price_pack','sell_price_strip','sell_price_unit','profit_margin_pct','public_price_pack','tax_rate_pct','strips_per_pack','units_per_strip','units_per_pack','min_stock_units','reorder_qty_packs','stock_total_units'
 };
 Future<ImportDryRunResult> dryRunImport({required String source,required String format,Map<String,String> mapping=const {}}) async {
  final rows=parse(source,format:format,mapping:mapping);final parsed=await rows;final errors=<ImportRowIssue>[];var valid=0,duplicates=0;final seen=<String>{};
  for(var i=0;i<parsed.length;i++){
   final row=parsed[i];final name=(row['trade_name_ar']??row['trade_name_en']??'').toString().trim();final scientific=(row['scientific_name']??'').toString().trim();
   if(name.isEmpty&&scientific.isEmpty){errors.add(ImportRowIssue(i+2,'الاسم التجاري أو العلمي مطلوب'));continue;}
   final key=(row['internal_code']??scientific+'|'+name).toString().toLowerCase();
   if(!seen.add(key)){duplicates++;errors.add(ImportRowIssue(i+2,'تكرار داخل ملف الاستيراد'));continue;}
   if(row['category_id']!=null&&int.tryParse(row['category_id'].toString())==null){errors.add(ImportRowIssue(i+2,'معرف الفئة يجب أن يكون رقماً'));continue;}
   valid++;
  }
  return ImportDryRunResult(totalRows:parsed.length,validRows:valid,errors:errors,duplicates:duplicates);
 }
 Future<ImportExecutionResult> executeImport({required String source,required String format,Map<String,String> mapping=const {},String conflictPolicy='SKIP',String? fileName,int batchSize=100,void Function(int done,int total)? onProgress}) async {
  if(!{'SKIP','UPDATE_EMPTY_ONLY','OVERWRITE'}.contains(conflictPolicy))throw ArgumentError('سياسة تعارض غير معروفة');
  final rows=await parse(source,format:format,mapping:mapping);final db=await _helper.database;
  final jobId=await db.insert('import_jobs',{'source_type':format.toUpperCase(),'file_name':fileName,'mapping_json':jsonEncode(mapping),'conflict_policy':conflictPolicy,'total_rows':rows.length,'status':'RUNNING','started_at':DateTime.now().toIso8601String()});
  var inserted=0,updated=0,skipped=0,errors=0,done=0;
  try{
   for(var start=0;start<rows.length;start+=batchSize){
    final batch=rows.skip(start).take(batchSize).toList();
    await db.transaction((txn)async{
     for(final row in batch){
      try{
       final now=DateTime.now().toIso8601String();
       final drug=DrugModel.fromMap(row).toMap();
       drug.remove('id');
       drug['uuid']=row['uuid']??'drug-import-'+DateTime.now().microsecondsSinceEpoch.toString()+'-'+done.toString();
       if((drug['internal_code'] as String? ?? '').trim().isEmpty)drug['internal_code']='IMP-'+DateTime.now().microsecondsSinceEpoch.toString()+'-'+done.toString();
       if((drug['trade_name_ar'] as String? ?? '').trim().isEmpty)drug['trade_name_ar']=(drug['trade_name_en']??drug['scientific_name']??'دواء مستورد').toString();
       final dosage=drug['dosage_form']?.toString().toUpperCase();
       const dosageForms={'TABLET','CAPSULE','SYRUP','SUSPENSION','DROPS','INJECTION','CREAM','OINTMENT','INHALER','SUPPOSITORY','SACHET','OTHER'};
       if(dosage!=null)drug['dosage_form']=dosageForms.contains(dosage)?dosage:'OTHER';
       final route=drug['route']?.toString().toUpperCase();
       const routes={'ORAL','IV','IM','SC','TOPICAL','OPHTHALMIC','INHALATION','RECTAL','OTHER'};
       if(route!=null)drug['route']=routes.contains(route)?route:'OTHER';
       final pregnancy=drug['pregnancy_category']?.toString().toUpperCase();
       if(pregnancy!=null&&!{'A','B','C','D','X','N','UNKNOWN'}.contains(pregnancy))drug['pregnancy_category']='UNKNOWN';
       final lactation=drug['lactation_risk']?.toString().toUpperCase();
       if(lactation!=null&&!{'L1','L2','L3','L4','L5','UNKNOWN'}.contains(lactation))drug['lactation_risk']='UNKNOWN';
       drug['created_at']=now;drug['updated_at']=now;
       final code=(row['internal_code']??'').toString();
       final name=(row['trade_name_ar']??'').toString();
       final scientific=(row['scientific_name']??'').toString();
       final existing=await txn.rawQuery('SELECT * FROM drugs WHERE is_deleted=0 AND ((?<>\'\' AND internal_code=?) OR (trade_name_ar=? AND scientific_name=?)) LIMIT 1',[code,code,name,scientific]);
       if(existing.isEmpty){await txn.insert('drugs',drug,conflictAlgorithm:ConflictAlgorithm.abort);inserted++;}
       else if(conflictPolicy=='SKIP'){skipped++;}
       else{
        final old=existing.first;
        final updates=<String,Object?>{};
        for(final e in drug.entries){if(e.key=='uuid'||e.key=='branch_id'||e.key=='created_at'||e.key=='sync_status'||e.key=='sync_version')continue;if(conflictPolicy=='OVERWRITE'||old[e.key]==null||old[e.key]==''||(old[e.key] is num&&old[e.key]==0))updates[e.key]=e.value;}
        if(updates.isEmpty){skipped++;}else{await txn.update('drugs',updates,where:'id=?',whereArgs:[old['id']]);updated++;}
       }
      }catch(_){errors++;}
      done++;
     }
    });
    onProgress?.call(done,rows.length);
   }
   await db.update('import_jobs',{'inserted_rows':inserted,'updated_rows':updated,'skipped_rows':skipped,'error_rows':errors,'status':errors==0?'COMPLETED':'COMPLETED_WITH_ERRORS','finished_at':DateTime.now().toIso8601String()},where:'id=?',whereArgs:[jobId]);
   await _refreshFts(db);
   await AuditService(helper:_helper).record(action:'CREATE',entityType:'drugs',entityId:jobId,entityLabel:'Import job #'+jobId.toString(),newValues:{'source_type':format.toUpperCase(),'inserted':inserted,'updated':updated,'skipped':skipped,'errors':errors},severity:errors==0?'INFO':'WARNING');
   return ImportExecutionResult(jobId:jobId,inserted:inserted,updated:updated,skipped:skipped,errors:errors);
  }catch(e){
   await db.update('import_jobs',{'inserted_rows':inserted,'updated_rows':updated,'skipped_rows':skipped,'error_rows':errors+1,'status':'FAILED','finished_at':DateTime.now().toIso8601String()},where:'id=?',whereArgs:[jobId]);
   rethrow;
  }
 }
 Future<void> _refreshFts(DatabaseExecutor db) async {
  final exists=await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='drugs_fts'");
  if(exists.isEmpty)return;
  final cols=await db.rawQuery('PRAGMA table_info(drugs_fts)');
  final names=cols.map((e)=>e['name'] as String).toSet();
  if(names.contains('rowid'))return;
  await db.execute('INSERT INTO drugs_fts(drugs_fts) VALUES(\'rebuild\')');
 }
 Future<List<OpenFdaDrugResult>> searchOpenFda(String query,{int limit=20}) async {
  if(query.trim().isEmpty)throw ArgumentError('أدخل اسم الدواء للبحث');
  final uri=Uri.https('api.fda.gov','/drug/label.json',{'search':'openfda.brand_name:"${query.trim()}" OR openfda.generic_name:"${query.trim()}"','limit':'${limit.clamp(1,100)}'});
  final response=await _client.get(uri).timeout(const Duration(seconds:20));
  if(response.statusCode==404)return [];
  if(response.statusCode!=200)throw HttpException('OpenFDA HTTP ${response.statusCode}');
  final decoded=jsonDecode(response.body) as Map<String,Object?>;
  final results=(decoded['results'] as List? ?? const []);
  return results.whereType<Map>().map((e)=>OpenFdaDrugResult.fromMap(Map<String,Object?>.from(e))).toList();
 }
 DrugModel openFdaToDrug(OpenFdaDrugResult result){
  String field(String key)=>result.fields[key]??'';
  return DrugModel(isActive:false,tradeNameAr:result.brandName,tradeNameEn:result.brandName,scientificName:result.genericName,indications:field('indications_and_usage'),dosageAdministration:field('dosage_and_administration'),contraindications:field('contraindications'),warningsPrecautions:field('warnings'),interactionsSummary:field('drug_interactions'),sideEffectsCommon:field('adverse_reactions'),pregnancyNotes:field('pregnancy'),pediatricNotes:field('pediatric_use'),geriatricNotes:field('geriatric_use'),storageConditions:field('storage_and_handling'),pregnancyCategory:'UNKNOWN');
 }
 Future<File> exportDrugs({required String format,bool hideCostPrices=true,int? categoryId}) async {
  final db=await _helper.database;
  final rows=await db.query('drugs',where:categoryId==null?'is_deleted=0':'is_deleted=0 AND category_id=?',whereArgs:categoryId==null?null:[categoryId],orderBy:'trade_name_ar');
  final fields=rows.map((r){final m=Map<String,Object?>.from(r);if(hideCostPrices){m.remove('cost_price_pack');m.remove('last_purchase_cost_pack');}return m;}).toList();
  final normalized=format.toUpperCase();late String data,extension,sourceType;
  if(normalized=='CSV'){
   final headers=fields.isEmpty?<String>[]:fields.first.keys.toList();
   data='\uFEFF'+const ListToCsvConverter().convert([headers,...fields.map((m)=>headers.map((h)=>m[h]??'').toList())]);extension='csv';sourceType='EXPORT_CSV';
  }else if(normalized=='JSON'){data=jsonEncode(fields);extension='json';sourceType='EXPORT_JSON';}
  else{throw ArgumentError('صيغة التصدير يجب أن تكون CSV أو JSON');}
  final directory=await getTemporaryDirectory();final file=File('${directory.path}/drug_export_${DateTime.now().millisecondsSinceEpoch}.$extension');
  await file.writeAsString(data,encoding:utf8,flush:true);
  await db.insert('import_jobs',{'source_type':sourceType,'file_name':file.path,'total_rows':fields.length,'status':'COMPLETED','started_at':DateTime.now().toIso8601String(),'finished_at':DateTime.now().toIso8601String()});
  await AuditService(helper:_helper).record(action:'EXPORT',entityType:'drugs',entityLabel:file.path,newValues:{'format':normalized,'rows':fields.length,'hide_cost_prices':hideCostPrices});
  return file;
 }
 Future<List<ImportJobModel>> listJobs() async=>(await _helper.query('import_jobs',orderBy:'id DESC')).map(ImportJobModel.fromMap).toList();
}
