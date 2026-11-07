// lib/data/services/clinical_guard_service.dart
import 'dart:convert';
import '../database/database_helper.dart';
import '../models/drug_model.dart';
import '../models/clinical_and_rx_models.dart';

class ClinicalGuardService {
  ClinicalGuardService({DatabaseHelper? helper}):_helper=helper??DatabaseHelper.instance;
  final DatabaseHelper _helper;

  Future<ClinicalVerdict> evaluate({required List<DrugModel> cart,required PatientClinicalModel? patient,Map<int,double> prescribedDoseMgByDrugId=const {},List<String> foodIntake=const [],Set<String> quickFlags=const {},int? invoiceId}) async {
    final db=await _helper.database;
    final assessmentPatient=patient==null?_quickPatient(quickFlags):_mergeQuickFlags(patient,quickFlags);
    final alerts=<ClinicalAlertModel>[];
    final currentIds=assessmentPatient?.currentDrugIds.toSet()??<int>{};
    final currentRows=currentIds.isEmpty?<Map<String,Object?>>[]:await db.query('drugs',where:'id IN (${List.filled(currentIds.length,'?').join(',')})',whereArgs:currentIds.toList());
    final currentDrugs=currentRows.map(DrugModel.fromMap).toList();
    for(final drug in cart){
      final id=drug.id;
      if(id==null)continue;
      alerts.addAll(await _ageRules(drug,assessmentPatient));
      alerts.addAll(await _renal(drug,assessmentPatient));
      alerts.addAll(await _hepatic(drug,assessmentPatient));
      alerts.addAll(await _pediatricDose(drug,assessmentPatient,prescribedDoseMgByDrugId[id]));
      alerts.addAll(_pregnancyLactation(drug,assessmentPatient));
      alerts.addAll(await _allergyRules(drug,assessmentPatient));
      alerts.addAll(await _foodInteractions(drug,foodIntake,assessmentPatient?.id));
      if(quickFlags.contains('KIDNEY')&&(drug.isNephrotoxic||drug.renalStatus=='ADJUST'||drug.renalStatus=='AVOID'||drug.renalStatus=='CONTRAINDICATED'))alerts.add(ClinicalAlertModel(category:'RENAL',level:ClinicalLevel.caution,drugId:id,messageAr:'المريض محدد كحالة كلوية؛ يلزم التحقق من CrCl والجرعة قبل الصرف.',recommendation:drug.renalNotes));
      if(quickFlags.contains('LIVER')&&(drug.hepaticStatus=='ADJUST'||drug.hepaticStatus=='AVOID'||drug.hepaticStatus=='CONTRAINDICATED'))alerts.add(ClinicalAlertModel(category:'HEPATIC',level:ClinicalLevel.caution,drugId:id,messageAr:'المريض محدد كحالة كبدية؛ يلزم التحقق من Child-Pugh قبل الصرف.',recommendation:drug.hepaticNotes));
      if(quickFlags.contains('CHILD')&&(drug.pediatricStatus!='SAFE'&&drug.pediatricStatus!='UNKNOWN'))alerts.add(ClinicalAlertModel(category:'PEDIATRIC',level:ClinicalLevel.caution,drugId:id,messageAr:'تحقق من العمر والوزن والتركيز لحساب جرعة الأطفال.',recommendation:drug.pediatricNotes));
      if(quickFlags.contains('ELDERLY')&&(drug.geriatricStatus=='ADJUST'||drug.geriatricStatus=='AVOID'))alerts.add(ClinicalAlertModel(category:'GERIATRIC',level:ClinicalLevel.caution,drugId:id,messageAr:'تحذير خاص بكبار السن وفق بيانات الدواء.',recommendation:drug.geriatricNotes));
      if(drug.isControlled)alerts.add(ClinicalAlertModel(category:'CONTROLLED',level:ClinicalLevel.warning,drugId:id,messageAr:'هذا دواء خاضع للرقابة؛ يلزم توثيق بيانات المريض والمستلم والوصفة قبل الصرف.',recommendation:'تحقق من الوصفة والهوية وسجل الصرف.'));
      if(drug.requiresPrescription||drug.prescriptionRestricted||drug.isAntibiotic)alerts.add(ClinicalAlertModel(category:'RX_REQUIRED',level:ClinicalLevel.caution,drugId:id,messageAr:'يتطلب هذا الصنف التحقق من الوصفة الطبية والقيود المحلية.',recommendation:'راجع الوصفة قبل اعتماد البيع.'));
      alerts.addAll(await _interactions(drug,[...cart.where((x)=>x.id!=id),...currentDrugs],assessmentPatient?.id));
      final geriatricAge=drug.geriatricAgeThreshold;
      if(geriatricAge!=null&&geriatricAge>0&&(assessmentPatient?.ageYears??0)>=geriatricAge&&drug.geriatricStatus=='AVOID')alerts.add(ClinicalAlertModel(category:'GERIATRIC',level:ClinicalLevel.warning,drugId:id,messageAr:drug.geriatricNotes.isEmpty?'تنبيه خاص بكبار السن لهذا الدواء.':drug.geriatricNotes));
      final dose=prescribedDoseMgByDrugId[id];
      if(dose!=null&&drug.adultDoseMaxMgPerDay!=null&&dose>drug.adultDoseMaxMgPerDay!*1.1)alerts.add(ClinicalAlertModel(category:'DOSE_EXCEEDED',level:ClinicalLevel.warning,drugId:id,messageAr:'الجرعة المدخلة تتجاوز الحد اليومي المرجعي بأكثر من 10%.',recommendation:'تحقق من الجرعة والوحدة والمدة.'));
    }
    alerts.addAll(_duplicateTherapy([...cart,...currentDrugs]));
    final unique=<String,ClinicalAlertModel>{};
    for(final a in alerts){final key='${a.category}:${a.drugId}:${a.otherDrugId}:${a.ruleRef}:${a.messageAr}';unique.putIfAbsent(key,()=>a);}
    return ClinicalVerdict(unique.values);
  }

  PatientClinicalModel _mergeQuickFlags(PatientClinicalModel p,Set<String> flags)=>PatientClinicalModel(
    id:p.id,partyId:p.partyId,fullName:p.fullName,birthDate:p.birthDate,
    sex:flags.contains('PREGNANT')||flags.contains('BREASTFEEDING')?'F':p.sex,
    weightKg:p.weightKg,heightCm:p.heightCm,isPregnant:p.isPregnant||flags.contains('PREGNANT'),
    pregnancyTrimester:p.pregnancyTrimester,pregnancyStatusKnown:p.pregnancyStatusKnown||flags.contains('PREGNANT'),isLactating:p.isLactating||flags.contains('BREASTFEEDING'),
    serumCreatinine:p.serumCreatinine,egfrMlMin:p.egfrMlMin,renalStage:p.renalStage,
    childPughClass:p.childPughClass,allergiesJson:p.allergiesJson,
    chronicConditionsJson:p.chronicConditionsJson,currentMedsJson:p.currentMedsJson);
  PatientClinicalModel? _quickPatient(Set<String> flags){
    if(flags.isEmpty)return null;
    return PatientClinicalModel(fullName:'حالة سريعة من الكاشير',sex:flags.contains('PREGNANT')||flags.contains('BREASTFEEDING')?'F':'M',isPregnant:flags.contains('PREGNANT'),pregnancyStatusKnown:flags.contains('PREGNANT'),isLactating:flags.contains('BREASTFEEDING'));
  }
  List<ClinicalAlertModel> _ageRules(DrugModel d,PatientClinicalModel? p){
    if(p==null||p.ageMonths==null)return [];
    final months=p.ageMonths!;
    if(d.minAgeMonths!=null&&months<d.minAgeMonths!)return [ClinicalAlertModel(category:'PEDIATRIC',level:ClinicalLevel.warning,drugId:d.id,messageAr:'عمر المريض أقل من الحد الأدنى المسجل لهذا الدواء.')];
    if(d.maxAgeMonths!=null&&months>d.maxAgeMonths!)return [ClinicalAlertModel(category:'PEDIATRIC',level:ClinicalLevel.caution,drugId:d.id,messageAr:'عمر المريض خارج الفئة العمرية المسجلة لهذا الدواء.')];
    if(months<1&&!d.neonateAllowed)return [ClinicalAlertModel(category:'PEDIATRIC',level:ClinicalLevel.block,drugId:d.id,messageAr:'لا توجد موافقة مسجلة لاستخدام هذا الدواء لحديثي الولادة.')];
    return [];
  }

  Future<List<ClinicalAlertModel>> _pediatricDose(DrugModel d,PatientClinicalModel? p,double? prescribed) async {
    if(p==null||(p.ageYears??18)>=18||p.weightKg==null||d.id==null)return [];
    final rows=await (await _helper.database).query('drug_pediatric_rules',where:'drug_id=? AND age_min_months<=? AND age_max_months>=? AND weight_min_kg<=? AND weight_max_kg>=?',whereArgs:[d.id,p.ageMonths??0,p.ageMonths??0,p.weightKg,p.weightKg],limit:1);
    if(rows.isEmpty)return [ClinicalAlertModel(category:'PEDIATRIC',level:ClinicalLevel.caution,drugId:d.id,messageAr:'لا توجد قاعدة جرعة أطفال موثقة لهذا العمر والوزن؛ لا تعتمد جرعة آلية.')];
    final r=PediatricRuleModel.fromMap(rows.first);
    if(r.action=='CONTRAINDICATED'||r.action=='AVOID')return [ClinicalAlertModel(category:'PEDIATRIC',level:r.action=='CONTRAINDICATED'?ClinicalLevel.block:ClinicalLevel.warning,drugId:d.id,messageAr:r.noteAr.isEmpty?'الدواء غير موصى به لهذه الفئة العمرية.':r.noteAr)];
    final min=r.mgPerKgDoseMin*p.weightKg!,max=(r.mgPerKgDoseMax*p.weightKg!).clamp(0,r.absoluteMaxDoseMg).toDouble(),daily=r.mgPerKgDayMax*p.weightKg!;
    final alerts=[ClinicalAlertModel(category:'PEDIATRIC',level:ClinicalLevel.caution,drugId:d.id,ruleRef:'drug_pediatric_rules:${r.id}',messageAr:'جرعة إرشادية بحسب الوزن: ${min.toStringAsFixed(1)}–${max.toStringAsFixed(1)} ملغ/جرعة، والحد اليومي ${daily.toStringAsFixed(1)} ملغ؛ عدد الجرعات المرجعي ${r.dosesPerDay}.',recommendation:'تحقق من التركيز والشكل والجرعة المكتوبة من الطبيب.')];
    if(prescribed!=null&&prescribed>max*1.1)alerts.add(ClinicalAlertModel(category:'DOSE_EXCEEDED',level:ClinicalLevel.warning,drugId:d.id,messageAr:'الجرعة المدخلة أعلى من الحد الأعلى المحسوب للوزن بأكثر من 10%.'));
    return alerts;
  }

  List<ClinicalAlertModel> _pregnancyLactation(DrugModel d,PatientClinicalModel? p){
    if(p==null)return [];
    final out=<ClinicalAlertModel>[];
    final category=d.pregnancyCategory.toUpperCase();
    final reproductive=(p.sex=='F'&&(p.ageYears??0)>=12&&(p.ageYears??0)<=50);
    if(p.isPregnant){
      if(blocksPregnancyX(d,p))out.add(ClinicalAlertModel(category:'PREGNANCY',level:ClinicalLevel.block,drugId:d.id,messageAr:'الدواء مصنف ضمن فئة الحمل X ويُمنع استخدامه أثناء الحمل.',recommendation:'لا تصرفه دون تقييم اختصاصي وإجراء تجاوز إداري موثق.'));
      if(category=='D')out.add(ClinicalAlertModel(category:'PREGNANCY',level:ClinicalLevel.warning,drugId:d.id,messageAr:'توجد مخاطر جنينية مثبتة؛ يلزم تقييم المنفعة والمخاطر.'));
      if(category=='C')out.add(ClinicalAlertModel(category:'PREGNANCY',level:ClinicalLevel.caution,drugId:d.id,messageAr:'بيانات الحمل تستلزم موازنة المنفعة والمخاطر.'));
    }else if(reproductive&&!p.pregnancyStatusKnown&&(category=='X'||category=='D'))out.add(ClinicalAlertModel(category:'PREGNANCY',level:ClinicalLevel.warning,drugId:d.id,messageAr:'حالة الحمل غير محددة؛ اسأل المريضة قبل صرف هذا الدواء.',ruleRef:'PREG_ASK'));
    if(p.isLactating){final risk=d.lactationRisk.toUpperCase();if(risk=='L5')out.add(ClinicalAlertModel(category:'LACTATION',level:ClinicalLevel.block,drugId:d.id,messageAr:'الدواء غير متوافق مع الرضاعة وفق تصنيف الخطر المسجل.'));if(risk=='L4')out.add(ClinicalAlertModel(category:'LACTATION',level:ClinicalLevel.warning,drugId:d.id,messageAr:'يوجد خطر محتمل على الرضيع أثناء الرضاعة.'));if(risk=='L3')out.add(ClinicalAlertModel(category:'LACTATION',level:ClinicalLevel.caution,drugId:d.id,messageAr:'يلزم تقييم الاستخدام أثناء الرضاعة ومراقبة الرضيع.'));}
    return out;
  }

  double? crcl(PatientClinicalModel p)=>p.crcl;
  static bool blocksPregnancyX(DrugModel drug,PatientClinicalModel? patient)=>patient?.isPregnant==true&&drug.pregnancyCategory.toUpperCase()=='X';
  Future<List<ClinicalAlertModel>> _renal(DrugModel d,PatientClinicalModel? p) async {
    final value=p?.crcl;if(value==null||d.id==null)return [];
    final rows=await (await _helper.database).query('drug_renal_rules',where:'drug_id=? AND crcl_min<=? AND crcl_max>=?',whereArgs:[d.id,value,value],limit:1);
    if(rows.isEmpty)return [];
    final r=RenalRuleModel.fromMap(rows.first);
    final level=switch(r.action){'CONTRAINDICATED'=>ClinicalLevel.block,'AVOID'=>ClinicalLevel.warning,'REDUCE_DOSE'||'EXTEND_INTERVAL'=>ClinicalLevel.caution,_=>ClinicalLevel.info};
    final details=<String>[];if(r.doseFactor!=null)details.add('معامل الجرعة ${r.doseFactor}');if(r.intervalHours!=null)details.add('الفاصل ${r.intervalHours} ساعة');if(r.maxDailyMg!=null)details.add('الحد اليومي ${r.maxDailyMg} ملغ');
    return [ClinicalAlertModel(category:'RENAL',level:level,drugId:d.id,ruleRef:'drug_renal_rules:${r.id}',messageAr:r.noteAr.isEmpty?'قاعدة وظائف الكلى: ${r.action}.':r.noteAr,recommendation:details.join(' • '))];
  }
  Future<List<ClinicalAlertModel>> _hepatic(DrugModel d,PatientClinicalModel? p) async {
    final child=p?.childPughClass;if(child==null||d.id==null)return [];
    final rows=await (await _helper.database).query('drug_hepatic_rules',where:'drug_id=? AND child_pugh_class=?',whereArgs:[d.id,child],limit:1);if(rows.isEmpty)return [];
    final r=HepaticRuleModel.fromMap(rows.first);final level=switch(r.action){'CONTRAINDICATED'=>ClinicalLevel.block,'AVOID'=>ClinicalLevel.warning,'REDUCE_DOSE'=>ClinicalLevel.caution,_=>ClinicalLevel.info};
    return [ClinicalAlertModel(category:'HEPATIC',level:level,drugId:d.id,ruleRef:'drug_hepatic_rules:${r.id}',messageAr:r.noteAr.isEmpty?'قاعدة الكبد Child-Pugh ${child}: ${r.action}.':r.noteAr,recommendation:r.doseFactor==null?'': 'معامل الجرعة ${r.doseFactor}')];
  }
  Future<List<ClinicalAlertModel>> _interactions(DrugModel drug,List<DrugModel> others,int? patientId) async {
    final db=await _helper.database;final out=<ClinicalAlertModel>[];
    for(final other in others){if(other.id==null||drug.id==other.id)continue;
      final rows=await db.rawQuery('SELECT * FROM drug_interactions WHERE ((drug_a_id=? OR drug_a_ingredient_id=?) AND (drug_b_id=? OR drug_b_ingredient_id=?)) OR ((drug_b_id=? OR drug_b_ingredient_id=?) AND (drug_a_id=? OR drug_a_ingredient_id=?))',[drug.id,drug.activeIngredientId,other.id,other.activeIngredientId,other.id,other.activeIngredientId,drug.id,drug.activeIngredientId]);
      for(final r in rows){final severity=r['severity'] as String;final level=switch(severity){'CONTRAINDICATED'=>ClinicalLevel.block,'MAJOR'=>ClinicalLevel.warning,'MODERATE'=>ClinicalLevel.caution,_=>ClinicalLevel.info};out.add(ClinicalAlertModel(category:'INTERACTION',level:level,drugId:drug.id,otherDrugId:other.id,patientId:patientId,ruleRef:'drug_interactions:${r['id']}',messageAr:'تفاعل بين ${drug.tradeNameAr} و${other.tradeNameAr}: ${r['clinical_effect']??r['interactant_name']}',recommendation:'${r['management']??''}'));}
    }
    return out;
  }
  Future<List<ClinicalAlertModel>> _foodInteractions(DrugModel drug,List<String> foods,int? patientId) async {
    if(foods.isEmpty||drug.id==null)return [];
    final out=<ClinicalAlertModel>[];
    for(final food in foods.where((x)=>x.trim().isNotEmpty)){
      final rows=await (await _helper.database).rawQuery("SELECT * FROM drug_interactions WHERE interactant_type='FOOD' AND ((drug_a_id=? OR drug_a_ingredient_id=?) OR (drug_b_id=? OR drug_b_ingredient_id=?)) AND lower(interactant_name) LIKE ?",[drug.id,drug.activeIngredientId,drug.id,drug.activeIngredientId,'%'+food.toLowerCase()+'%']);
      for(final r in rows){final severity=r['severity'] as String;final level=switch(severity){'CONTRAINDICATED'=>ClinicalLevel.block,'MAJOR'=>ClinicalLevel.warning,'MODERATE'=>ClinicalLevel.caution,_=>ClinicalLevel.info};out.add(ClinicalAlertModel(category:'INTERACTION',level:level,drugId:drug.id,patientId:patientId,ruleRef:'drug_interactions:${r['id']}',messageAr:'تفاعل غذائي محتمل بين ${drug.tradeNameAr} و${r['interactant_name']}: ${r['clinical_effect']}',recommendation:r['management'] as String? ?? 'تحقق من النشرة الدوائية.'));}
    }
    return out;
  }
  Future<List<ClinicalAlertModel>> _allergyRules(DrugModel d,PatientClinicalModel? p) async {
    if(p==null||p.allergies.isEmpty)return [];
    final names=<String>{d.scientificName.toLowerCase(),d.chemicalComposition.toLowerCase(),..._ingredientNames(d.ingredientsJson)};
    if(d.activeIngredientId!=null){final rows=await (await _helper.database).query('active_ingredients',columns:['inn_name','name_ar'],where:'id=?',whereArgs:[d.activeIngredientId],limit:1);if(rows.isNotEmpty){names.add((rows.first['inn_name'] as String? ?? '').toLowerCase());names.add((rows.first['name_ar'] as String? ?? '').toLowerCase());}}
    final allergyGroups=<String,String>{'penicillin':'amoxicillin clavulanic acid','البنسلين':'أموكسيسيلين حمض كلافولانيك','sulfa':'sulfonamide','السلفا':'sulfonamide'};
    final expanded=p.allergies.expand((a)=>[a,if(allergyGroups.containsKey(a.toLowerCase()))allergyGroups[a.toLowerCase()]!]).toList();
    final matches=expanded.where((a)=>names.any((n)=>n.isNotEmpty&&(n.contains(a.toLowerCase())||a.toLowerCase().contains(n)))).toSet().toList();
    return matches.isEmpty?[]:[ClinicalAlertModel(category:'ALLERGY',level:ClinicalLevel.block,drugId:d.id,messageAr:'حساسية مسجلة لدى المريض قد تتطابق مع مكونات الدواء: ${matches.join('، ')}.',recommendation:'لا تصرف قبل التحقق من الحساسية وتحديد بديل آمن.')];
  }
  List<String> _ingredientNames(String raw){try{return (jsonDecode(raw) as List).map((e)=>(e as Map)['name'].toString().toLowerCase()).toList();}catch(_){return [];}}
  List<ClinicalAlertModel> _duplicateTherapy(List<DrugModel> cart){
    final out=<ClinicalAlertModel>[];final byIngredient=<int,DrugModel>{};final byClass=<String,DrugModel>{};
    for(final d in cart){final ingredient=d.activeIngredientId;if(ingredient!=null&&byIngredient.containsKey(ingredient))out.add(ClinicalAlertModel(category:'DUPLICATE_THERAPY',level:ClinicalLevel.warning,drugId:d.id,otherDrugId:byIngredient[ingredient]!.id,messageAr:'تكرار المادة الفعالة بين ${byIngredient[ingredient]!.tradeNameAr} و${d.tradeNameAr}.'));else if(ingredient!=null)byIngredient[ingredient]=d;
      final cls=d.therapeuticClass.trim().toLowerCase();if(cls.isNotEmpty&&byClass.containsKey(cls))out.add(ClinicalAlertModel(category:'DUPLICATE_THERAPY',level:ClinicalLevel.caution,drugId:d.id,otherDrugId:byClass[cls]!.id,messageAr:'تكرار محتمل ضمن الفئة العلاجية ${d.therapeuticClass}.'));else if(cls.isNotEmpty)byClass[cls]=d;
    }return out;
  }
  static void validateDecision(ClinicalAlertModel alert,{required String decision,String? reason,int? managerUserId}) {
    const allowed={'ACKNOWLEDGED','CANCELLED_ITEM','SUBSTITUTED','OVERRIDDEN_WITH_PIN'};
    if(!allowed.contains(decision))throw StateError('قرار سريري غير مدعوم');
    if(alert.level==ClinicalLevel.block){
      if(decision=='ACKNOWLEDGED')throw StateError('لا يمكن تجاوز الحظر السريري بمجرد الإقرار');
      if(decision=='OVERRIDDEN_WITH_PIN'&&(managerUserId==null||(reason??'').trim().length<5))throw StateError('يلزم تحقق رمز المدير وسبب واضح لتجاوز الحظر');
      if(decision!='CANCELLED_ITEM'&&decision!='SUBSTITUTED'&&decision!='OVERRIDDEN_WITH_PIN')throw StateError('يجب حذف الصنف أو استبداله أو اعتماد تجاوز المدير');
    }
    if(alert.level==ClinicalLevel.warning&&decision=='ACKNOWLEDGED'&&(reason??'').trim().length<5)throw StateError('سبب التجاوز يجب ألا يقل عن خمسة أحرف');
    if(alert.level==ClinicalLevel.warning&&decision=='OVERRIDDEN_WITH_PIN')throw StateError('تنبيه التحذير يوثق بسبب الصيدلي ولا يحتاج تجاوز حظر المدير');
  }

  Future<void> recordDecision(ClinicalAlertModel alert,{required String decision,required int? userId,String? reason,int? managerUserId,int? invoiceId}) async {
    validateDecision(alert,decision:decision,reason:reason,managerUserId:managerUserId);
    await (await _helper.database).insert('clinical_alert_logs',alert.toLogMap(decidedBy:userId,managerUserId:managerUserId)..['user_decision']=decision..['override_reason']=reason..['invoice_id']=invoiceId??alert.invoiceId);
  }
}
