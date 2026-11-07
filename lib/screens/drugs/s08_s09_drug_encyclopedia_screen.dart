import 'package:flutter/material.dart';
import 'central_medicine_picker_screen.dart';
import 'package:provider/provider.dart';
import '../../providers/pos_and_drugs_provider.dart';
import '../../data/models/drug_model.dart';
import '../../core/theme/enterprise_dark_theme.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/database/database_helper.dart';
import '../pos/s05_drug_alternatives_sheet.dart';
import '../../providers/session_and_erp_provider.dart';
import '../../reports_pdf/registry/report_registry_and_provider.dart';

class S08S09DrugEncyclopediaScreen extends StatefulWidget{const S08S09DrugEncyclopediaScreen({super.key});@override State<S08S09DrugEncyclopediaScreen> createState()=>_S08S09DrugEncyclopediaScreenState();}
class _S08S09DrugEncyclopediaScreenState extends State<S08S09DrugEncyclopediaScreen>{
 String filter='ALL';
 DrugModel? selected;
 final searchController=TextEditingController();

 @override
 void dispose(){
  searchController.dispose();
  super.dispose();
 }

 @override
 Widget build(BuildContext context){
  final p=context.watch<PosAndDrugsProvider>();
  final list=p.drugs.where((d)=>switch(filter){
   'ANTIBIOTIC'=>d.isAntibiotic,
   'CONTROLLED'=>d.isControlled,
   'COLD'=>d.requiresRefrigeration,
   'PREG_X'=>d.pregnancyCategory=='X',
   _=>true,
  }).toList();

  final filters=const [
   ('ALL','الكل'),
   ('ANTIBIOTIC','مضادات حيوية'),
   ('CONTROLLED','مراقبة'),
   ('COLD','ثلاجة'),
   ('PREG_X','حمل X'),
  ];

  return Scaffold(
   backgroundColor:Colors.transparent,
   floatingActionButton:Column(
    mainAxisSize:MainAxisSize.min,
    crossAxisAlignment:CrossAxisAlignment.end,
    children:[
     FloatingActionButton.extended(
      heroTag:'central-catalog-picker',
      onPressed:()=>Navigator.of(context).push(MaterialPageRoute(
       builder:(_)=>const CentralMedicinePickerScreen(),
      )),
      icon:const Icon(Icons.library_books_outlined),
      label:const Text('اختيار من الموسوعة'),
     ),
     const SizedBox(height:10),
     FloatingActionButton.extended(
      heroTag:'manual-drug-create',
      onPressed:()=>_edit(context),
      icon:const Icon(Icons.add),
      label:const Text('إضافة دواء يدوياً'),
     ),
    ],
   ),
   body:Padding(
    padding:const EdgeInsets.all(12),
    child:Column(
     children:[
      CompactSearchAndFilterBar(
       controller:searchController,
       hintText:'ابحث بالاسم التجاري أو العلمي أو الباركود',
       onChanged:p.searchDrugs,
       activeFilterCount:filter=='ALL'?0:1,
       onFilter:()=>_showFilters(filters),
      ),
      const SizedBox(height:8),
      Expanded(
       child:ResponsiveLayout(
        mobile:selected==null
         ?_drugList(list)
         :Column(
          children:[
           Align(
            alignment:AlignmentDirectional.centerStart,
            child:TextButton.icon(
             onPressed:()=>setState(()=>selected=null),
             icon:const Icon(Icons.arrow_back),
             label:const Text('العودة إلى قائمة الأدوية'),
            ),
           ),
           Expanded(child:_details(selected!)),
          ],
         ),
        desktop:Row(
         children:[
          SizedBox(width:330,child:_drugList(list)),
          const VerticalDivider(width:12),
          Expanded(
           child:selected==null
            ?const Center(child:Text('اختر دواء لعرض التفاصيل'))
            :_details(selected!),
          ),
         ],
        ),
       ),
      ),
     ],
    ),
   ),
  );
 }

 Widget _drugList(List<DrugModel> list)=>ListView.builder(
  keyboardDismissBehavior:ScrollViewKeyboardDismissBehavior.onDrag,
  itemCount:list.length,
  itemBuilder:(context,index){
   final drug=list[index];
   return SmartExpandableCard(
    title:drug.tradeNameAr,
    primary:drug.scientificName,
    secondary:'اكتمال البيانات: ${drug.calculateCompletenessPct().toStringAsFixed(0)}%',
    leading:const CircleAvatar(
     backgroundColor:Color(0x224DB6AC),
     child:Icon(Icons.medication,color:AppColors.primary),
    ),
    trailing:IconButton(
     tooltip:'عرض التفاصيل',
     onPressed:()=>setState(()=>selected=drug),
     icon:const Icon(Icons.arrow_forward_ios,size:16),
    ),
    details:[
     LinearProgressIndicator(
      value:drug.calculateCompletenessPct()/100,
      color:AppColors.primary,
     ),
     const SizedBox(height:8),
     Text('السعر: ${MoneyFormatter.format(drug.sellPricePack)} • المخزون: ${drug.stockTotalUnits} حبة'),
    ],
    actions:[
     OutlinedButton.icon(
      onPressed:()=>setState(()=>selected=drug),
      icon:const Icon(Icons.visibility_outlined),
      label:const Text('التفاصيل السريرية'),
     ),
     OutlinedButton.icon(
      onPressed:()=>_edit(context,drug),
      icon:const Icon(Icons.edit_outlined),
      label:const Text('تعديل'),
     ),
    ],
   );
  },
 );

 Future<void> _showFilters(List<(String,String)> filters)async{
  await KeyboardSafeModalSheet.show<void>(
   context:context,
   builder:(sheetContext)=>Column(
    crossAxisAlignment:CrossAxisAlignment.stretch,
    children:[
     const Text('تصفية الموسوعة الدوائية',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
     const SizedBox(height:12),
     for(final entry in filters)
      RadioListTile<String>(
       value:entry.$1,
       groupValue:filter,
       title:Text(entry.$2),
       onChanged:(value){
        setState(()=>filter=value??'ALL');
        Navigator.pop(sheetContext);
       },
      ),
    ],
   ),
  );
 }

 Widget _details(DrugModel d)=>DefaultTabController(length:5,child:Column(children:[
  Row(children:[Expanded(child:Text(d.tradeNameAr,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold))),IconButton(tooltip:'البدائل',onPressed:()=>S05DrugAlternativesSheet.show(context,d,(_){ }),icon:const Icon(Icons.swap_horiz)),IconButton(tooltip:'طباعة البطاقة السريرية PDF - تقرير 46',onPressed:()=>_printClinicalCard(d),icon:const Icon(Icons.picture_as_pdf)),IconButton(onPressed:()=>_edit(context,d),icon:const Icon(Icons.edit))]),
  const TabBar(isScrollable:true,tabs:[Tab(text:'الهوية والتسعير'),Tab(text:'الاستعمال والسلامة'),Tab(text:'الفئات الخاصة'),Tab(text:'التخزين والرقابة'),Tab(text:'القواعد السريرية')]),
  Expanded(child:TabBarView(children:[
   _group([('الاسم التجاري',d.tradeNameAr),('الاسم العلمي',d.scientificName),('الشركة',d.manufacturerId?.toString()??'غير محدد'),('التصنيف ATC',d.atcCode),('الشكل والتركيز',d.dosageForm+' • '+d.strengthText),('طريقة الإعطاء',d.route),('التعبئة',d.stripsPerPack.toString()+' × '+d.unitsPerStrip.toString()),('التكلفة',MoneyFormatter.format(d.costPricePack)),('سعر الباكت',MoneyFormatter.format(d.sellPricePack)),('سعر الشريط',MoneyFormatter.format(d.sellPriceStrip)),('سعر الحبة',MoneyFormatter.format(d.sellPriceUnit)),('المخزون بالحبة',d.stockTotalUnits.toString())]),
   _group([('دواعي الاستعمال',d.indications),('الجرعة وطريقة الاستخدام',d.dosageAdministration),('جرعة البالغين',d.adultDoseMinMg?.toString()??''),('موانع الاستعمال',d.contraindications),('التحذيرات',d.warningsPrecautions),('تحذير الصندوق الأسود',d.blackBoxWarning),('التفاعلات',d.interactionsSummary),('آثار شائعة',d.sideEffectsCommon),('آثار خطيرة',d.sideEffectsSerious)]),
   _group([('الكبد',d.hepaticStatus+' • '+d.hepaticNotes),('الكلى',d.renalStatus+' • '+d.renalNotes),('سمية كلوية',d.isNephrotoxic.toString()),('كبار السن',d.geriatricStatus+' • '+d.geriatricNotes),('معايير Beers',d.beersCriteria),('الأطفال',d.pediatricStatus+' • '+d.pediatricNotes),('حديثو الولادة',d.neonateAllowed.toString()),('الحمل',d.pregnancyCategory+' • '+d.pregnancyNotes),('الرضاعة',d.lactationRisk+' • '+d.lactationNotes)]),
   _group([('التخزين',d.storageConditions),('درجة الحرارة',d.storageTempMinC.toString()+' - '+d.storageTempMaxC.toString()),('تبريد',d.requiresRefrigeration.toString()),('حماية من الضوء',d.protectFromLight.toString()),('باركود عالمي',d.barcodeInternational),('باركود محلي',d.barcodeLocal),('رقم التسجيل',d.registrationNo),('دواء مراقب',d.isControlled.toString()),('جدول الرقابة',d.controlledSchedule),('يتطلب وصفة',d.requiresPrescription.toString()),('مضاد حيوي',d.isAntibiotic.toString())]),
   _clinicalRules(d),
  ])),
 ]));

 Widget _clinicalRules(DrugModel d)=>FutureBuilder<List<List<Map<String,Object?>>>>(
  future:Future.wait([DatabaseHelper.instance.rawQuery('SELECT * FROM drug_interactions WHERE drug_a_id=? OR drug_a_ingredient_id=? OR drug_b_id=? OR drug_b_ingredient_id=?',[d.id,d.activeIngredientId,d.id,d.activeIngredientId]),...['drug_renal_rules','drug_hepatic_rules','drug_pediatric_rules'].map((t)=>DatabaseHelper.instance.query(t,where:'drug_id=?',whereArgs:[d.id??-1]))]),
  builder:(context,snapshot){
   if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
   final tables=snapshot.data!;
   const names=['التفاعلات الدوائية','قواعد الكلى','قواعد الكبد','جرعات الأطفال'];
   const keys=['interaction','renal','hepatic','pediatric'];
   return ListView(padding:const EdgeInsets.all(8),children:[
    for(var i=0;i<tables.length;i++)Card(child:Padding(padding:const EdgeInsets.all(10),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
     Row(children:[Expanded(child:Text(names[i],style:const TextStyle(fontWeight:FontWeight.bold,color:AppColors.primary))),IconButton(tooltip:'إضافة قاعدة',onPressed:()=>_addClinicalRule(d,keys[i]),icon:const Icon(Icons.add_circle_outline))]),
     if(tables[i].isEmpty)const Text('لا توجد قواعد مسجلة.') else for(final row in tables[i])Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Text(row.entries.where((e)=>e.key!='id'&&e.key!='drug_id').map((e)=>'${e.key}: ${e.value??'—'}').join(' • '))),
    ]))),
   ]);
  });

 Future<void> _printClinicalCard(DrugModel drug) async {
  if(drug.id==null)return;
  final session=context.read<SessionAndErpProvider>();
  final user=session.currentUser;
  if(user==null)return;
  final reports=context.read<ReportsCenterProvider>();
  try {
   await reports.initialize(userId:user['id'] as int,userName:user['full_name'] as String? ?? '',branchId:session.branchId);
   reports.selectReport(46);
   reports.updateParams({'drug_id':drug.id});
   final data=await reports.runSelected();
   final definition=reports.selected;
   if(data!=null&&definition!=null) {
    await reports.engine.preview(definition:definition,data:data,params:reports.params);
   }
  } catch(e) {
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));
  }
 }

 Future<void> _addClinicalRule(DrugModel drug,String kind)async{
  final fields=switch(kind){
   'interaction'=>['interactant_type','interactant_name','severity','management'],
   'renal'=>['crcl_min','crcl_max','action','dose_factor','interval_hours','max_daily_mg','note_ar'],
   'hepatic'=>['child_pugh_class','action','dose_factor','max_daily_mg','note_ar'],
   _=>['age_min_months','age_max_months','weight_min_kg','weight_max_kg','mg_per_kg_dose_min','mg_per_kg_dose_max','mg_per_kg_day_max','doses_per_day','absolute_max_dose_mg','action','note_ar'],
  };
  final controllers={for(final key in fields)key:TextEditingController(text:switch(key){'interactant_type'=>'DRUG','severity'=>'MODERATE','action'=>kind=='renal'?'REDUCE_DOSE':kind=='hepatic'?'NO_CHANGE':'DOSE_BY_WEIGHT','crcl_min'=>'0','crcl_max'=>'30','age_min_months'=>'0','age_max_months'=>'216','weight_min_kg'=>'0','weight_max_kg'=>'100','doses_per_day'=>'2','absolute_max_dose_mg'=>'1000',_=>''})};
  final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text('إضافة قاعدة سريرية — ${drug.tradeNameAr}'),content:SizedBox(width:500,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[for(final key in fields)Padding(padding:const EdgeInsets.only(bottom:8),child:TextField(controller:controllers[key],decoration:InputDecoration(labelText:key)))]))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('حفظ'))]));
  if(ok==true){
   final values=<String,Object?>{'drug_id':drug.id};
   for(final key in fields){final raw=controllers[key]!.text.trim();if(key=='interactant_type'||key=='interactant_name'||key=='severity'||key=='management'||key=='action'||key=='child_pugh_class'||key=='note_ar'){values[key]=raw;}else{values[key]=raw.isEmpty?null:num.tryParse(raw);}}
   if(kind=='interaction'){values.remove('drug_id');values['drug_a_id']=drug.id;values['drug_a_ingredient_id']=drug.activeIngredientId;values['evidence_level']='REVIEW_REQUIRED';values['severity_rank']=switch(values['severity']){'CONTRAINDICATED'=>4,'MAJOR'=>3,'MODERATE'=>2,_=>1};}
   await DatabaseHelper.instance.insert(switch(kind){'interaction'=>'drug_interactions','renal'=>'drug_renal_rules','hepatic'=>'drug_hepatic_rules',_=>'drug_pediatric_rules'},values);
   if(mounted)setState(()=>{});
  }
  for(final controller in controllers.values){controller.dispose();}
 }

 Widget _group(List<(String, String)> values) => ListView(
  padding: const EdgeInsets.all(8),
  children: values.map((entry) => Card(
   child: Padding(
    padding: const EdgeInsets.all(10),
    child: Column(
     crossAxisAlignment: CrossAxisAlignment.start,
     children: [
      Text(
       entry.$1,
       style: const TextStyle(
        color: AppColors.primary,
        fontWeight: FontWeight.bold,
       ),
      ),
      const SizedBox(height: 4),
      Text(entry.$2.isEmpty ? 'غير مدخل' : entry.$2),
     ],
    ),
   ),
  )).toList(),
 );
 Future<void> _edit(BuildContext context,[DrugModel? drug]) async {
  const labels=<String,String>{
   'internal_code':'1. الرمز الداخلي SKU','is_active':'حالة الصنف (1 فعال / 0 متوقف)',
   'trade_name_ar':'1. الاسم التجاري بالعربية','trade_name_en':'1. الاسم التجاري بالإنجليزية','manufacturer_id':'1. رقم الشركة المصنعة',
   'scientific_name':'2. الاسم العلمي / INN','active_ingredient_id':'2. رقم المادة الفعالة','ingredients_json':'2. تركيب الدواء المركب JSON','chemical_composition':'2. التركيب الكيميائي',
   'category_id':'3. رقم التصنيف','therapeutic_class':'3. الفئة العلاجية','pharmacologic_class':'3. الفئة الدوائية','atc_code':'3. تصنيف ATC',
   'dosage_form':'4. الشكل الصيدلاني','strength_text':'4. التركيز النصي','strength_value':'4. قيمة التركيز','strength_unit':'4. وحدة التركيز','route':'4. طريق الإعطاء','is_strip_based':'4. يباع بالأشرطة (1/0)',
   'indications':'5. دواعي الاستعمال',
   'dosage_administration':'6. الجرعة وطريقة الاستخدام','adult_dose_min_mg':'6. أقل جرعة للبالغين mg','adult_dose_max_mg_per_day':'6. الحد اليومي الأعلى mg','dose_frequency_text':'6. تكرار الجرعة','take_with_food':'6. علاقته بالطعام','label_dose_text_ar':'6. تعليمات الجرعة بالعربية',
   'contraindications':'7. موانع الاستعمال','contraindications_json':'7. موانع إضافية JSON',
   'warnings_precautions':'8. التحذيرات والاحتياطات','black_box_warning':'8. تحذير الصندوق الأسود','warnings_json':'8. تحذيرات إضافية JSON',
   'interactions_summary':'9. التفاعلات الدوائية','has_critical_interactions':'9. تداخلات حرجة (1/0)',
   'side_effects_common':'10. الآثار الجانبية الشائعة','side_effects_serious':'10. الآثار الجانبية الخطيرة',
   'strips_per_pack':'11. عدد الأشرطة في الباكت','units_per_strip':'11. عدد الحبات في الشريط','cost_price_pack':'11. تكلفة الباكت','last_purchase_cost_pack':'11. آخر تكلفة شراء','sell_price_pack':'11. سعر بيع الباكت','sell_price_strip':'11. سعر بيع الشريط','sell_price_unit':'11. سعر بيع الحبة','strip_price_mode':'11. نمط سعر الشريط AUTO / MANUAL','profit_margin_pct':'11. هامش الربح %','public_price_pack':'11. السعر العام للباكت','tax_rate_pct':'11. الضريبة %','min_stock_units':'11. حد إعادة الطلب بالحبة','reorder_qty_packs':'11. كمية إعادة الطلب بالباكت',
   'min_age_months':'12. أقل عمر بالأشهر','max_age_months':'12. أكبر عمر بالأشهر','allowed_populations_json':'12. الفئات السكانية المسموحة JSON',
   'hepatic_status':'13. حالة القصور الكبدي SAFE / ADJUST / AVOID / CONTRAINDICATED / UNKNOWN','hepatic_notes':'13. ملاحظات الكبد',
   'renal_status':'14. حالة القصور الكلوي SAFE / ADJUST / AVOID / CONTRAINDICATED / UNKNOWN','renal_notes':'14. ملاحظات الكلى GFR / CrCl','is_nephrotoxic':'14. سام للكلى (1/0)',
   'geriatric_status':'15. حالة كبار السن SAFE / ADJUST / AVOID / UNKNOWN','geriatric_notes':'15. ملاحظات كبار السن','beers_criteria':'15. معايير Beers','geriatric_age_threshold':'15. حد عمر كبار السن',
   'pediatric_status':'16. حالة الأطفال SAFE / ADJUST / AVOID / CONTRAINDICATED / UNKNOWN','pediatric_notes':'16. ملاحظات الأطفال وحديثي الولادة','ped_dose_mg_per_kg_min':'16. أقل جرعة mg/kg','ped_dose_mg_per_kg_max':'16. أعلى جرعة mg/kg','ped_max_daily_mg_per_kg':'16. الحد اليومي mg/kg','ped_doses_per_day':'16. عدد الجرعات يومياً','neonate_allowed':'16. يسمح لحديثي الولادة (1/0)',
   'pregnancy_category':'17. تصنيف الحمل A / B / C / D / X / N / UNKNOWN','pregnancy_notes':'17. ملاحظات الحمل','pregnancy_trimester_json':'17. أمان الأثلاث JSON',
   'lactation_risk':'18. خطر الرضاعة L1 / L2 / L3 / L4 / L5 / UNKNOWN','lactation_notes':'18. ملاحظات الرضاعة',
   'storage_conditions':'19. شروط التخزين','storage_temp_min_c':'19. أدنى حرارة مئوية','storage_temp_max_c':'19. أعلى حرارة مئوية','requires_refrigeration':'19. يتطلب تبريداً (1/0)','protect_from_light':'19. يحفظ بعيداً عن الضوء (1/0)','barcode_international':'19. الباركود العالمي','barcode_local':'19. الباركود المحلي','registration_no':'19. رقم التسجيل','is_controlled':'19. دواء مراقب (1/0)','controlled_schedule':'19. جدول الرقابة','requires_prescription':'19. يتطلب وصفة (1/0)','prescription_restricted':'19. وصفة مقيدة (1/0)','is_antibiotic':'19. مضاد حيوي (1/0)'
  };
  const boolKeys={'is_active','is_strip_based','has_critical_interactions','is_nephrotoxic','neonate_allowed','requires_refrigeration','protect_from_light','is_controlled','requires_prescription','prescription_restricted','is_antibiotic'};
  const intKeys={'manufacturer_id','active_ingredient_id','category_id','strips_per_pack','units_per_strip','min_stock_units','reorder_qty_packs','min_age_months','max_age_months','geriatric_age_threshold','ped_doses_per_day'};
  const numberKeys={'strength_value','adult_dose_min_mg','adult_dose_max_mg_per_day','cost_price_pack','last_purchase_cost_pack','sell_price_pack','sell_price_strip','sell_price_unit','profit_margin_pct','public_price_pack','tax_rate_pct','ped_dose_mg_per_kg_min','ped_dose_mg_per_kg_max','ped_max_daily_mg_per_kg','storage_temp_min_c','storage_temp_max_c'};
  final initial=(drug??const DrugModel()).toMap();
  final controllers=<String,TextEditingController>{
   for(final key in labels.keys) key:TextEditingController(text:initial[key]?.toString()??'')
  };
  final form=GlobalKey<FormState>();
  const enumValues=<String,Set<String>>{
   'dosage_form':{'TABLET','CAPSULE','SYRUP','SUSPENSION','DROPS','INJECTION','CREAM','OINTMENT','INHALER','SUPPOSITORY','SACHET','OTHER'},
   'route':{'ORAL','IV','IM','SC','TOPICAL','OPHTHALMIC','INHALATION','RECTAL','OTHER'},
   'take_with_food':{'BEFORE','WITH','AFTER','ANY'},
   'strip_price_mode':{'AUTO','MANUAL'},
   'hepatic_status':{'SAFE','ADJUST','AVOID','CONTRAINDICATED','UNKNOWN'},
   'renal_status':{'SAFE','ADJUST','AVOID','CONTRAINDICATED','UNKNOWN'},
   'geriatric_status':{'SAFE','ADJUST','AVOID','UNKNOWN'},
   'pediatric_status':{'SAFE','ADJUST','AVOID','CONTRAINDICATED','UNKNOWN'},
   'pregnancy_category':{'A','B','C','D','X','N','UNKNOWN'},
   'lactation_risk':{'L1','L2','L3','L4','L5','UNKNOWN'},
  };
  List<String> groupFor(List<int> points)=>labels.keys.where((key){if(key=='is_active')return points.contains(1);final point=int.tryParse(labels[key]!.split('.').first);return point!=null&&points.contains(point);}).toList();
  final tabGroups=<List<String>>[groupFor([1,2,3,4]),groupFor([5,6,7,8,9,10]),groupFor([11,12]),groupFor([13,14,15,16,17,18,19])];
  Widget buildField(String key){
   final controller=controllers[key]!;
   final longText=key.contains('notes')||key.contains('warning')||key.contains('indication')||key.contains('contraindication')||key.contains('json')||key.contains('administration')||key.contains('composition');
   return Padding(padding:const EdgeInsets.only(bottom:8),child:TextFormField(
    controller:controller,
    textDirection:key.contains('barcode')||key.contains('code')||key.endsWith('_id')||key.endsWith('_json')?TextDirection.ltr:TextDirection.rtl,
    keyboardType:boolKeys.contains(key)||intKeys.contains(key)||numberKeys.contains(key)?const TextInputType.numberWithOptions(decimal:true):TextInputType.multiline,
    minLines:longText?2:1,maxLines:longText?4:1,
    decoration:InputDecoration(labelText:labels[key],helperText:boolKeys.contains(key)?'اكتب 1 للتفعيل أو 0 للإيقاف':null),
    validator:key=='trade_name_ar'||key=='internal_code'?(v)=>v==null||v.trim().isEmpty?'هذا الحقل مطلوب':null:null,
   ));
  }
  Widget tabFields(List<String> keys)=>ListView(padding:const EdgeInsets.all(10),children:[
   if(keys==tabGroups.first)const ClinicalAlertBanner(message:'أدخل البيانات من النشرة الرسمية المعتمدة. الحقول التي تحمل حالة مراجعة يجب التحقق منها قبل الاستخدام السريري.',level:ClinicalAlertLevel.warning),
   ...keys.map(buildField),
  ]);
  final provider = context.read<PosAndDrugsProvider>();
  await showDialog<void>(context:context,builder:(dialogContext)=>AlertDialog(
   insetPadding:const EdgeInsets.all(8),
   scrollable:true,
   title:Text(drug==null?'إضافة دواء — جميع النقاط الـ19':'تعديل بيانات الدواء — جميع النقاط الـ19'),
   content:SizedBox(width:MediaQuery.sizeOf(context).width<700?double.infinity:900,height:(MediaQuery.sizeOf(context).height-MediaQuery.viewInsetsOf(context).bottom-190).clamp(240.0,720.0).toDouble(),child:Form(key:form,child:DefaultTabController(length:4,child:Column(children:[
    const TabBar(isScrollable:true,tabs:[Tab(text:'1–4 الهوية والتركيب'),Tab(text:'5–10 الاستعمال والسلامة'),Tab(text:'11–12 التسعير والفئات'),Tab(text:'13–19 الحالات الخاصة')]),
    Expanded(child:TabBarView(children:[for(final keys in tabGroups)tabFields(keys)])),
   ])))),
   actions:[
    TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('إلغاء')),
    FilledButton(onPressed:()async{
     if(controllers['trade_name_ar']!.text.trim().isEmpty||controllers['internal_code']!.text.trim().isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('الاسم التجاري والرمز الداخلي مطلوبان')));return;}
     for(final entry in enumValues.entries){if(!entry.value.contains(controllers[entry.key]!.text.trim())){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('قيمة غير معتمدة في: '+labels[entry.key]!)));return;}}
     for(final key in intKeys){final raw=controllers[key]!.text.trim();if(raw.isNotEmpty&&int.tryParse(raw)==null){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('أدخل رقماً صحيحاً في: '+labels[key]!)));return;}}
     for(final key in numberKeys){final raw=controllers[key]!.text.trim();if(raw.isNotEmpty&&double.tryParse(raw)==null){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('أدخل قيمة رقمية صحيحة في: '+labels[key]!)));return;}}
     final map=Map<String,Object?>.from(initial);
     for(final entry in controllers.entries){
      final key=entry.key;final raw=entry.value.text.trim();
      if(boolKeys.contains(key)){map[key]=(raw=='1'||raw.toLowerCase()=='true')?1:0;}
      else if(intKeys.contains(key)){map[key]=raw.isEmpty?null:int.tryParse(raw);}
      else if(numberKeys.contains(key)){map[key]=raw.isEmpty?null:double.tryParse(raw);}
      else{map[key]=raw.isEmpty?null:raw;}
     }
     final strips=(map['strips_per_pack'] as int?)??1;
     final units=(map['units_per_strip'] as int?)??1;
     if(strips<1||units<1){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('يجب أن يكون عدد الأشرطة والحبات أكبر من صفر')));return;}
     map['units_per_pack']=strips*units;
     final packPrice=(map['sell_price_pack'] as num?)?.toDouble()??0;
     if(map['strip_price_mode']=='AUTO')map['sell_price_strip']=packPrice/strips;
     map['sell_price_unit']=packPrice/(strips*units);
     final model=DrugModel.fromMap(map);
      await provider.saveDrug(model);
      if (!mounted) return;
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      setState(() => selected = model);
      await provider.loadDrugs();
     },child:const Text('حفظ جميع البيانات')),
    ],
  ));
  for(final controller in controllers.values){controller.dispose();}
 }
}
