import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/pos_and_drugs_provider.dart';
import '../../data/models/drug_model.dart';
import '../../core/theme/enterprise_dark_theme.dart';
import '../../core/widgets/shared_widgets.dart';

class S08S09DrugEncyclopediaScreen extends StatefulWidget{const S08S09DrugEncyclopediaScreen({super.key});@override State<S08S09DrugEncyclopediaScreen> createState()=>_S08S09DrugEncyclopediaScreenState();}
class _S08S09DrugEncyclopediaScreenState extends State<S08S09DrugEncyclopediaScreen>{
 String filter='ALL';DrugModel? selected;
 @override Widget build(BuildContext context){final p=context.watch<PosAndDrugsProvider>();final list=p.drugs.where((d)=>switch(filter){'ANTIBIOTIC'=>d.isAntibiotic,'CONTROLLED'=>d.isControlled,'COLD'=>d.requiresRefrigeration,'PREG_X'=>d.pregnancyCategory=='X',_=>true}).toList();
  return Scaffold(backgroundColor:Colors.transparent,floatingActionButton:FloatingActionButton.extended(onPressed:()=>_edit(context),icon:const Icon(Icons.add),label:const Text('إضافة دواء')),body:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
   TextField(decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'ابحث بالاسم التجاري أو العلمي أو الباركود'),onChanged:p.searchDrugs),
   const SizedBox(height:8),
   Wrap(spacing:6,children:[for(final f in const [('ALL','الكل'),('ANTIBIOTIC','مضادات حيوية'),('CONTROLLED','مراقبة'),('COLD','ثلاجة'),('PREG_X','حمل X')])ChoiceChip(label:Text(f.$2),selected:filter==f.$1,onSelected:(_)=>setState(()=>filter=f.$1))]),
   Expanded(child:LayoutBuilder(builder:(context,c)=>Row(children:[
     SizedBox(
      width: c.maxWidth > 800 ? 330 : c.maxWidth * .42,
      child: ListView(
       children: list.map((d) => Card(
        child: ListTile(
         selected: selected?.id == d.id,
         title: Text(d.tradeNameAr),
         subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
           Text(d.scientificName),
           LinearProgressIndicator(
            value: d.calculateCompletenessPct() / 100,
            color: AppColors.primary,
           ),
           Text('اكتمال البيانات: ${d.calculateCompletenessPct().toStringAsFixed(0)}%'),
          ],
         ),
         onTap: () => setState(() => selected = d),
        ),
       )).toList(),
      ),
     ),
    const VerticalDivider(width:12),Expanded(child:selected==null?const Center(child:Text('اختر دواء لعرض التفاصيل')):_details(selected!)),
   ]))),
  ])));
 }
 Widget _details(DrugModel d)=>DefaultTabController(length:4,child:Column(children:[
  Row(children:[Expanded(child:Text(d.tradeNameAr,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold))),IconButton(onPressed:()=>_edit(context,d),icon:const Icon(Icons.edit))]),
  const TabBar(isScrollable:true,tabs:[Tab(text:'الهوية والتسعير'),Tab(text:'الاستعمال والسلامة'),Tab(text:'الفئات الخاصة'),Tab(text:'التخزين والرقابة')]),
  Expanded(child:TabBarView(children:[
   _group([('الاسم التجاري',d.tradeNameAr),('الاسم العلمي',d.scientificName),('الشركة',d.manufacturerId?.toString()??'غير محدد'),('التصنيف ATC',d.atcCode),('الشكل والتركيز',d.dosageForm+' • '+d.strengthText),('طريقة الإعطاء',d.route),('التعبئة',d.stripsPerPack.toString()+' × '+d.unitsPerStrip.toString()),('التكلفة',MoneyFormatter.format(d.costPricePack)),('سعر الباكت',MoneyFormatter.format(d.sellPricePack)),('سعر الشريط',MoneyFormatter.format(d.sellPriceStrip)),('سعر الحبة',MoneyFormatter.format(d.sellPriceUnit)),('المخزون بالحبة',d.stockTotalUnits.toString())]),
   _group([('دواعي الاستعمال',d.indications),('الجرعة وطريقة الاستخدام',d.dosageAdministration),('جرعة البالغين',d.adultDoseMinMg?.toString()??''),('موانع الاستعمال',d.contraindications),('التحذيرات',d.warningsPrecautions),('تحذير الصندوق الأسود',d.blackBoxWarning),('التفاعلات',d.interactionsSummary),('آثار شائعة',d.sideEffectsCommon),('آثار خطيرة',d.sideEffectsSerious)]),
   _group([('الكبد',d.hepaticStatus+' • '+d.hepaticNotes),('الكلى',d.renalStatus+' • '+d.renalNotes),('سمية كلوية',d.isNephrotoxic.toString()),('كبار السن',d.geriatricStatus+' • '+d.geriatricNotes),('معايير Beers',d.beersCriteria),('الأطفال',d.pediatricStatus+' • '+d.pediatricNotes),('حديثو الولادة',d.neonateAllowed.toString()),('الحمل',d.pregnancyCategory+' • '+d.pregnancyNotes),('الرضاعة',d.lactationRisk+' • '+d.lactationNotes)]),
   _group([('التخزين',d.storageConditions),('درجة الحرارة',d.storageTempMinC.toString()+' - '+d.storageTempMaxC.toString()),('تبريد',d.requiresRefrigeration.toString()),('حماية من الضوء',d.protectFromLight.toString()),('باركود عالمي',d.barcodeInternational),('باركود محلي',d.barcodeLocal),('رقم التسجيل',d.registrationNo),('دواء مراقب',d.isControlled.toString()),('جدول الرقابة',d.controlledSchedule),('يتطلب وصفة',d.requiresPrescription.toString()),('مضاد حيوي',d.isAntibiotic.toString())]),
  ])),
 ]));
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
   'strips_per_pack':'11. عدد الأشرطة في الباكت','units_per_strip':'11. عدد الحبات في الشريط','cost_price_pack':'11. تكلفة الباكت','last_purchase_cost_pack':'11. آخر تكلفة شراء','sell_price_pack':'11. سعر بيع الباكت','sell_price_strip':'11. سعر بيع الشريط','sell_price_unit':'11. سعر بيع الحبة','strip_price_mode':'11. نمط سعر الشريط AUTO / MANUAL','profit_margin_pct':'11. هامش الربح %','public_price_pack':'11. السعر العام للباكت','tax_rate_pct':'11. الضريبة %','min_stock_units':'11. حد إعادة الطلب بالحبة','reorder_qty_packs':'11. كمية إعادة الطلب بالباكت','stock_total_units':'11. المخزون الحالي بالحبة',
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
  const intKeys={'manufacturer_id','active_ingredient_id','category_id','strips_per_pack','units_per_strip','min_stock_units','reorder_qty_packs','stock_total_units','min_age_months','max_age_months','geriatric_age_threshold','ped_doses_per_day'};
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
  List<String> groupFor(List<int> points)=>labels.keys.where((key){final point=int.tryParse(labels[key]!.split('.').first);return point!=null&&points.contains(point);}).toList();
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
  await showDialog<void>(context:context,builder:(dialogContext)=>AlertDialog(
   title:Text(drug==null?'إضافة دواء — جميع النقاط الـ19':'تعديل بيانات الدواء — جميع النقاط الـ19'),
   content:SizedBox(width:720,height:MediaQuery.sizeOf(context).height*.76,child:Form(key:form,child:DefaultTabController(length:4,child:Column(children:[
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
     await context.read<PosAndDrugsProvider>().saveDrug(model);
     if(dialogContext.mounted)Navigator.pop(dialogContext);
     if(mounted){setState(()=>selected=model);await context.read<PosAndDrugsProvider>().loadDrugs();}
    },child:const Text('حفظ جميع البيانات')),
   ],
  ));
  for(final controller in controllers.values){controller.dispose();}
 }
}
