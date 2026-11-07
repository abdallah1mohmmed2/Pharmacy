// lib/screens/drugs/s10_drug_import_export_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/settings_and_system_provider.dart';
import '../../data/models/settings_audit_sync_models.dart';

class S10DrugImportExportScreen extends StatefulWidget {
 const S10DrugImportExportScreen({super.key});
 @override State<S10DrugImportExportScreen> createState()=>_S10DrugImportExportScreenState();
}
class _S10DrugImportExportScreenState extends State<S10DrugImportExportScreen> {
 final sourceController=TextEditingController(),mappingController=TextEditingController();
 final searchController=TextEditingController();
 String format='CSV',policy='SKIP';String? fileName;bool hideCosts=true;int? exportCategoryId;
 List<OpenFdaDrugResult> fdaResults=[];bool searching=false;
 @override void dispose(){sourceController.dispose();mappingController.dispose();searchController.dispose();super.dispose();}
 Map<String,String> get mapping {
  try{return Map<String,String>.from(jsonDecode(mappingController.text) as Map);}catch(_){return {};}
 }
 Future<void> pickFile() async {
  final result=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['csv','json'],withData:true);
  if(result==null||result.files.isEmpty)return;
  final file=result.files.single;
  final bytes=file.bytes??(file.path==null?null:await File(file.path!).readAsBytes());
  if(bytes==null)return;
  setState((){sourceController.text=utf8.decode(bytes,allowMalformed:true);fileName=file.name;format=file.extension?.toUpperCase()=='JSON'?'JSON':'CSV';});
 }
 Future<void> dryRun() async {
  final p=context.read<SettingsAndSystemProvider>();
  try{final result=await p.dryRun(source:sourceController.text,format:format,mapping:mapping);if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('الفحص: ${result.validRows} سليم، ${result.errors.length} خطأ، ${result.duplicates} تكرار')));}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
 }
 Future<void> execute() async {
  final p=context.read<SettingsAndSystemProvider>();
  try{final r=await p.executeImport(source:sourceController.text,format:format,mapping:mapping,conflictPolicy:policy,fileName:fileName);if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('اكتمل الاستيراد: ${r.inserted} إضافة، ${r.updated} تحديث، ${r.skipped} تخطي، ${r.errors} خطأ')));}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
 }
 Future<void> searchFda() async {
  setState(()=>searching=true);
  try{final results=await context.read<SettingsAndSystemProvider>().searchOpenFda(searchController.text);if(mounted)setState(()=>fdaResults=results);}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  finally{if(mounted)setState(()=>searching=false);}
 }
 Future<void> importFda(OpenFdaDrugResult result) async {
  final provider=context.read<SettingsAndSystemProvider>();
  final drug=provider.importer.openFdaToDrug(result);
  final payload=jsonEncode([drug.toMap()]);
  try{await provider.executeImport(source:payload,format:'JSON',conflictPolicy:'UPDATE_EMPTY_ONLY',fileName:'OpenFDA: ${result.brandName}');if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('أضيفت بطاقة الدواء للمراجعة في الموسوعة')));}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
 }
 Future<void> export(String kind) async {
  try{final file=await context.read<SettingsAndSystemProvider>().exportDrugs(format:kind,hideCostPrices:hideCosts,categoryId:exportCategoryId);await Share.shareXFiles([XFile(file.path)],text:'تصدير الموسوعة الدوائية');}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
 }
 @override Widget build(BuildContext context)=>DefaultTabController(length:4,child:Scaffold(
  appBar:AppBar(title:const Text('استيراد وتصدير الموسوعة الدوائية'),bottom:const TabBar(isScrollable:true,tabs:[Tab(text:'استيراد CSV / JSON'),Tab(text:'OpenFDA العالمي'),Tab(text:'تصدير الموسوعة'),Tab(text:'سجل العمليات')])),
  body:TabBarView(children:[_importTab(),_fdaTab(),_exportTab(),_jobsTab()]),
 ));
 Widget _importTab()=>Consumer<SettingsAndSystemProvider>(builder:(context,p,_)=>ListView(padding:const EdgeInsets.all(16),children:[
  Row(children:[Expanded(child:DropdownButtonFormField<String>(value:format,decoration:const InputDecoration(labelText:'صيغة المصدر'),items:const [DropdownMenuItem(value:'CSV',child:Text('CSV')),DropdownMenuItem(value:'JSON',child:Text('JSON'))],onChanged:(v)=>setState(()=>format=v??'CSV'))),const SizedBox(width:12),OutlinedButton.icon(onPressed:pickFile,icon:const Icon(Icons.attach_file),label:const Text('اختيار ملف'))]),
  const SizedBox(height:12),TextField(controller:sourceController,minLines:8,maxLines:14,decoration:const InputDecoration(labelText:'محتوى الملف أو البيانات الملصقة',alignLabelWithHint:true,border:OutlineInputBorder())),
  const SizedBox(height:12),TextField(controller:mappingController,minLines:2,maxLines:5,decoration:const InputDecoration(labelText:'ربط الأعمدة بصيغة JSON (اختياري)',hintText:'{"اسم الدواء":"trade_name_ar"}',border:OutlineInputBorder())),
  const SizedBox(height:12),DropdownButtonFormField<String>(value:policy,decoration:const InputDecoration(labelText:'سياسة التعارض'),items:const [DropdownMenuItem(value:'SKIP',child:Text('تخطي السجل الموجود')),DropdownMenuItem(value:'UPDATE_EMPTY_ONLY',child:Text('تحديث الحقول الفارغة فقط')),DropdownMenuItem(value:'OVERWRITE',child:Text('استبدال البيانات الموجودة'))],onChanged:(v)=>setState(()=>policy=v??'SKIP')),
  const SizedBox(height:16),Wrap(spacing:8,runSpacing:8,children:[OutlinedButton.icon(onPressed:dryRun,icon:const Icon(Icons.fact_check),label:const Text('فحص مسبق (Dry-Run)')),FilledButton.icon(onPressed:p.busy||sourceController.text.trim().isEmpty?null:execute,icon:const Icon(Icons.file_download_done),label:const Text('بدء الاستيراد الفعلي'))]),
  if(p.dryRunResult case final result?)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('إجمالي الصفوف: ${result.totalRows} • السليم: ${result.validRows} • التكرارات: ${result.duplicates}'),...result.errors.take(30).map((e)=>Text('صف ${e.rowNumber}: ${e.message}',style:const TextStyle(color:Colors.orangeAccent)))]))),
  if(p.busy)...[const SizedBox(height:12),LinearProgressIndicator(value:p.importTotal==0?null:p.importProgress/p.importTotal),Text('تمت معالجة ${p.importProgress} من ${p.importTotal}')],
 ]));
 Widget _fdaTab()=>ListView(padding:const EdgeInsets.all(16),children:[
  Row(children:[Expanded(child:TextField(controller:searchController,decoration:const InputDecoration(labelText:'الاسم التجاري أو العلمي',border:OutlineInputBorder()),onSubmitted:(_)=>searchFda())),const SizedBox(width:8),IconButton.filled(onPressed:searching?null:searchFda,icon:searching?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.search))]),
  const SizedBox(height:12),...fdaResults.map((result)=>Card(child:ExpansionTile(title:Text(result.brandName.isEmpty?result.genericName:result.brandName),subtitle:Text('الاسم العلمي: ${result.genericName} • ${result.manufacturer}'),children:[
   for(final field in ['indications_and_usage','dosage_and_administration','contraindications','warnings','drug_interactions','adverse_reactions','pregnancy','pediatric_use','geriatric_use','storage_and_handling'])if(result.fields[field]!=null)ListTile(dense:true,title:Text(_arabicField(field)),subtitle:Text(result.fields[field]!,maxLines:4,overflow:TextOverflow.ellipsis)),
   Padding(padding:const EdgeInsets.all(12),child:FilledButton.icon(onPressed:()=>importFda(result),icon:const Icon(Icons.playlist_add),label:const Text('استيراد للموسوعة كمراجعة'))),
  ]))),
 ]);
 String _arabicField(String field)=>switch(field){'indications_and_usage'=>'دواعي الاستعمال','dosage_and_administration'=>'الجرعة وطريقة الاستخدام','contraindications'=>'موانع الاستعمال','warnings'=>'التحذيرات','drug_interactions'=>'التفاعلات الدوائية','adverse_reactions'=>'الأعراض الجانبية','pregnancy'=>'الحمل','pediatric_use'=>'استخدام الأطفال','geriatric_use'=>'استخدام كبار السن','storage_and_handling'=>'التخزين',_=>field};
 Widget _exportTab()=>Consumer<SettingsAndSystemProvider>(builder:(context,p,_)=>ListView(padding:const EdgeInsets.all(16),children:[
  DropdownButtonFormField<int?>(value:exportCategoryId,decoration:const InputDecoration(labelText:'تصفية حسب الفئة'),items:[const DropdownMenuItem<int?>(value:null,child:Text('كل الفئات')),...p.drugCategories.map((row)=>DropdownMenuItem<int?>(value:row['id'] as int,child:Text(row['name_ar'].toString())))],onChanged:(v)=>setState(()=>exportCategoryId=v)),
  SwitchListTile(value:hideCosts,onChanged:(v)=>setState(()=>hideCosts=v),title:const Text('إخفاء أسعار التكلفة من الملف')),
  const SizedBox(height:8),Card(child:ListTile(leading:const Icon(Icons.table_chart),title:const Text('تصدير CSV'),subtitle:const Text('UTF-8 مع BOM لدعم العربية في Excel'),trailing:IconButton(onPressed:()=>export('CSV'),icon:const Icon(Icons.ios_share)))),
  Card(child:ListTile(leading:const Icon(Icons.data_object),title:const Text('تصدير JSON'),subtitle:const Text('بيانات منظمة مع حقول الموسوعة'),trailing:IconButton(onPressed:()=>export('JSON'),icon:const Icon(Icons.ios_share)))),
 ]));
 Widget _jobsTab()=>Consumer<SettingsAndSystemProvider>(builder:(context,p,_)=>RefreshIndicator(onRefresh:p.refreshSystemData,child:ListView(padding:const EdgeInsets.all(12),children:[
  for(final job in p.importJobs)Card(child:ListTile(title:Text('${job.sourceType} • ${job.fileName??'بدون اسم ملف'}'),subtitle:Text('الحالة: ${job.status} • إجمالي: ${job.totalRows} • إضافة: ${job.insertedRows} • تحديث: ${job.updatedRows} • أخطاء: ${job.errorRows}'),trailing:Text('#${job.id}'))),
 ])));
}
