// lib/data/models/clinical_and_rx_models.dart
import 'dart:convert';

enum ClinicalLevel { info, caution, warning, block }

class DrugInteractionModel {
  const DrugInteractionModel({this.id,this.drugAIngredientId,this.drugAId,this.interactantType='DRUG',this.drugBIngredientId,this.drugBId,this.interactantName='',required this.severity,this.severityRank=1,this.mechanism='',this.clinicalEffect='',this.management='',this.evidenceLevel='UNVERIFIED'});
  final int? id,drugAIngredientId,drugAId,drugBIngredientId,drugBId,severityRank;
  final String interactantType,interactantName,severity,mechanism,clinicalEffect,management,evidenceLevel;
  factory DrugInteractionModel.fromMap(Map<String,Object?> m)=>DrugInteractionModel(id:m['id'] as int?,drugAIngredientId:m['drug_a_ingredient_id'] as int?,drugAId:m['drug_a_id'] as int?,interactantType:m['interactant_type'] as String? ?? 'DRUG',drugBIngredientId:m['drug_b_ingredient_id'] as int?,drugBId:m['drug_b_id'] as int?,interactantName:m['interactant_name'] as String? ?? '',severity:m['severity'] as String,severityRank:(m['severity_rank'] as num?)?.toInt() ?? 1,mechanism:m['mechanism'] as String? ?? '',clinicalEffect:m['clinical_effect'] as String? ?? '',management:m['management'] as String? ?? '',evidenceLevel:m['evidence_level'] as String? ?? 'UNVERIFIED');
}

class RenalRuleModel {
  const RenalRuleModel({this.id,required this.drugId,required this.crclMin,required this.crclMax,required this.action,this.doseFactor,this.intervalHours,this.maxDailyMg,this.noteAr=''});
  final int? id,intervalHours;
  final int drugId;
  final double crclMin,crclMax;
  final String action,noteAr;
  final double? doseFactor,maxDailyMg;
  factory RenalRuleModel.fromMap(Map<String,Object?> m)=>RenalRuleModel(id:m['id'] as int?,drugId:m['drug_id'] as int,crclMin:(m['crcl_min'] as num).toDouble(),crclMax:(m['crcl_max'] as num).toDouble(),action:m['action'] as String,doseFactor:(m['dose_factor'] as num?)?.toDouble(),intervalHours:(m['interval_hours'] as num?)?.toInt(),maxDailyMg:(m['max_daily_mg'] as num?)?.toDouble(),noteAr:m['note_ar'] as String? ?? '');
}

class HepaticRuleModel {
  const HepaticRuleModel({this.id,required this.drugId,required this.childPughClass,required this.action,this.doseFactor,this.maxDailyMg,this.noteAr=''});
  final int? id;
  final int drugId;
  final String childPughClass,action,noteAr;
  final double? doseFactor,maxDailyMg;
  factory HepaticRuleModel.fromMap(Map<String,Object?> m)=>HepaticRuleModel(id:m['id'] as int?,drugId:m['drug_id'] as int,childPughClass:m['child_pugh_class'] as String,action:m['action'] as String,doseFactor:(m['dose_factor'] as num?)?.toDouble(),maxDailyMg:(m['max_daily_mg'] as num?)?.toDouble(),noteAr:m['note_ar'] as String? ?? '');
}

class PediatricRuleModel {
  const PediatricRuleModel({this.id,required this.drugId,this.ageMinMonths=0,this.ageMaxMonths=216,this.weightMinKg=0,this.weightMaxKg=200,this.mgPerKgDoseMin=0,this.mgPerKgDoseMax=0,this.mgPerKgDayMax=0,this.dosesPerDay=1,this.absoluteMaxDoseMg=double.infinity,this.action='DOSE_BY_WEIGHT',this.noteAr=''});
  final int? id;
  final int drugId,ageMinMonths,ageMaxMonths,dosesPerDay;
  final double weightMinKg,weightMaxKg,mgPerKgDoseMin,mgPerKgDoseMax,mgPerKgDayMax,absoluteMaxDoseMg;
  final String action,noteAr;
  factory PediatricRuleModel.fromMap(Map<String,Object?> m)=>PediatricRuleModel(id:m['id'] as int?,drugId:m['drug_id'] as int,ageMinMonths:(m['age_min_months'] as num?)?.toInt() ?? 0,ageMaxMonths:(m['age_max_months'] as num?)?.toInt() ?? 216,weightMinKg:(m['weight_min_kg'] as num?)?.toDouble() ?? 0,weightMaxKg:(m['weight_max_kg'] as num?)?.toDouble() ?? 200,mgPerKgDoseMin:(m['mg_per_kg_dose_min'] as num?)?.toDouble() ?? 0,mgPerKgDoseMax:(m['mg_per_kg_dose_max'] as num?)?.toDouble() ?? 0,mgPerKgDayMax:(m['mg_per_kg_day_max'] as num?)?.toDouble() ?? 0,dosesPerDay:(m['doses_per_day'] as num?)?.toInt() ?? 1,absoluteMaxDoseMg:(m['absolute_max_dose_mg'] as num?)?.toDouble() ?? double.infinity,action:m['action'] as String? ?? 'DOSE_BY_WEIGHT',noteAr:m['note_ar'] as String? ?? '');
}

class PatientClinicalModel {
  const PatientClinicalModel({this.id,this.partyId,required this.fullName,this.birthDate,this.sex='M',this.weightKg,this.heightCm,this.isPregnant=false,this.pregnancyTrimester,this.isLactating=false,this.serumCreatinine,this.egfrMlMin,this.renalStage,this.childPughClass,this.allergiesJson='[]',this.chronicConditionsJson='[]',this.currentMedsJson='[]'});
  final int? id,partyId,pregnancyTrimester;
  final String fullName,sex,allergiesJson,chronicConditionsJson,currentMedsJson;
  final DateTime? birthDate;
  final double? weightKg,heightCm,serumCreatinine,egfrMlMin;
  final bool isPregnant,isLactating;
  final String? renalStage,childPughClass;
  int? get ageYears {final b=birthDate;if(b==null)return null;final n=DateTime.now();var a=n.year-b.year;if(n.month<b.month||(n.month==b.month&&n.day<b.day))a--;return a;}
  int? get ageMonths {final b=birthDate;if(b==null)return null;final n=DateTime.now();var m=(n.year-b.year)*12+n.month-b.month;if(n.day<b.day)m--;return m;}
  double? get crcl {final age=ageYears,w=weightKg,sc=serumCreatinine;if(egfrMlMin!=null)return egfrMlMin;if(age==null||w==null||sc==null||sc<=0)return null;final value=((140-age)*w)/(72*sc);return sex=='F'?value*.85:value;}
  List<String> get allergies => _decodeStrings(allergiesJson);
  List<int> get currentDrugIds => _decodeStrings(currentMedsJson).map(int.tryParse).whereType<int>().toList();
  factory PatientClinicalModel.fromMap(Map<String,Object?> m)=>PatientClinicalModel(id:m['id'] as int?,partyId:m['party_id'] as int?,fullName:m['full_name'] as String? ?? '',birthDate:m['birth_date']==null?null:DateTime.tryParse(m['birth_date'].toString()),sex:m['sex'] as String? ?? 'M',weightKg:(m['weight_kg'] as num?)?.toDouble(),heightCm:(m['height_cm'] as num?)?.toDouble(),isPregnant:(m['is_pregnant'] as num?)==1,pregnancyTrimester:(m['pregnancy_trimester'] as num?)?.toInt(),isLactating:(m['is_lactating'] as num?)==1,serumCreatinine:(m['serum_creatinine'] as num?)?.toDouble(),egfrMlMin:(m['egfr_ml_min'] as num?)?.toDouble(),renalStage:m['renal_stage'] as String?,childPughClass:m['child_pugh_class'] as String?,allergiesJson:m['allergies_json'] as String? ?? '[]',chronicConditionsJson:m['chronic_conditions_json'] as String? ?? '[]',currentMedsJson:m['current_meds_json'] as String? ?? '[]');
  static List<String> _decodeStrings(String s){try{return (jsonDecode(s) as List).map((e)=>e.toString()).toList();}catch(_){return [];}}
}

class ClinicalAlertModel {
  const ClinicalAlertModel({this.id,required this.category,required this.level,required this.messageAr,this.drugId,this.otherDrugId,this.ruleRef,this.recommendation='',this.patientId,this.invoiceId,this.userDecision,this.overrideReason});
  final int? id,drugId,otherDrugId,patientId,invoiceId;
  final String category,messageAr,recommendation;
  final ClinicalLevel level;
  final String? ruleRef,userDecision,overrideReason;
  Map<String,Object?> toLogMap({required int? decidedBy,int? managerUserId})=>{'alert_at':DateTime.now().toIso8601String(),'invoice_id':invoiceId,'drug_id':drugId,'other_drug_id':otherDrugId,'patient_id':patientId,'alert_category':category,'level':level.name.toUpperCase(),'message_ar':messageAr,'rule_ref':ruleRef,'user_decision':userDecision,'decided_by':decidedBy,'override_reason':overrideReason,'manager_user_id':managerUserId};
}

class ClinicalVerdict {
  ClinicalVerdict(Iterable<ClinicalAlertModel> alerts):alerts=List.unmodifiable(alerts.toList()..sort((a,b)=>_rank(b.level).compareTo(_rank(a.level))));
  final List<ClinicalAlertModel> alerts;
  bool get hasUnresolvedCritical=>alerts.any((a)=>(a.level==ClinicalLevel.warning||a.level==ClinicalLevel.block)&&a.userDecision==null);
  bool get blocked=>alerts.any((a)=>a.level==ClinicalLevel.block&&a.userDecision==null);
  static int _rank(ClinicalLevel l)=>switch(l){ClinicalLevel.block=>4,ClinicalLevel.warning=>3,ClinicalLevel.caution=>2,ClinicalLevel.info=>1};
}

class AlternativeDrugModel {
  const AlternativeDrugModel({required this.drugId,required this.nameAr,required this.strengthText,required this.dosageForm,required this.matchType,this.sellPricePack=0,this.sellPriceStrip=0,this.availableUnits=0,this.nearestExpiry,this.priceDiffPack=0});
  final int drugId,availableUnits;
  final String nameAr,strengthText,dosageForm,matchType;
  final double sellPricePack,sellPriceStrip,priceDiffPack;
  final String? nearestExpiry;
  factory AlternativeDrugModel.fromMap(Map<String,Object?> m)=>AlternativeDrugModel(drugId:m['drug_id'] as int,nameAr:m['trade_name_ar'] as String? ?? '',strengthText:m['strength_text'] as String? ?? '',dosageForm:m['dosage_form'] as String? ?? '',matchType:m['match_type'] as String,sellPricePack:(m['sell_price_pack'] as num?)?.toDouble() ?? 0,sellPriceStrip:(m['sell_price_strip'] as num?)?.toDouble() ?? 0,availableUnits:(m['available_units'] as num?)?.toInt() ?? 0,nearestExpiry:m['nearest_expiry'] as String?,priceDiffPack:(m['price_diff_pack'] as num?)?.toDouble() ?? 0);
}

class InsuranceCompanyModel {const InsuranceCompanyModel({this.id,this.partyId,required this.nameAr,this.defaultCoveragePct=0,this.claimCycleDays=30});final int? id,partyId,claimCycleDays;final String nameAr;final double defaultCoveragePct;}
class InsurancePolicyModel {const InsurancePolicyModel({this.id,required this.insuranceCompanyId,required this.customerPartyId,required this.policyNo,this.coveragePct=0,this.copayPct=100,this.annualLimit=0,this.usedLimit=0,this.validFrom,this.validTo,this.excludedCategoriesJson='[]'});final int? id,insuranceCompanyId,customerPartyId;final String policyNo,excludedCategoriesJson;final double coveragePct,copayPct,annualLimit,usedLimit;final String? validFrom,validTo;double get remainingLimit=>(annualLimit-usedLimit).clamp(0,double.infinity).toDouble();bool get isValid{final n=DateTime.now();return (validFrom==null||!n.isBefore(DateTime.parse(validFrom!)))&&(validTo==null||!n.isAfter(DateTime.parse(validTo!)));}}
class PrescriptionModel {const PrescriptionModel({this.id,required this.rxNo,required this.patientId,this.customerPartyId,this.doctorName='',this.doctorLicenseNo='',this.facilityName='',required this.rxDate,required this.validUntil,this.rxType='NORMAL',this.insurancePolicyId,this.refillsAllowed=0,this.refillsUsed=0,this.status='OPEN'});final int? id,customerPartyId,insurancePolicyId;
  final int patientId,refillsAllowed,refillsUsed;final String rxNo,doctorName,doctorLicenseNo,facilityName,rxDate,validUntil,rxType,status;}
class PrescriptionItemModel {const PrescriptionItemModel({this.id,required this.prescriptionId,required this.drugId,this.prescribedQtyUnits=0,this.dispensedQtyUnits=0,this.doseInstruction='',this.durationDays=0});final int? id;final int prescriptionId,drugId,prescribedQtyUnits,dispensedQtyUnits,durationDays;final String doseInstruction;int get remainingUnits=>(prescribedQtyUnits-dispensedQtyUnits).clamp(0,1<<30);}
class SalesReturnModel {const SalesReturnModel({this.id,required this.returnNo,required this.returnDate,required this.originalInvoiceId,this.customerPartyId,this.refundMethod='CASH',this.reasonCode='OTHER',this.reasonText='',this.totalRefund=0,this.approvedBy,this.journalEntryId});final int? id,customerPartyId,approvedBy,journalEntryId;final int originalInvoiceId;final String returnNo,returnDate,refundMethod,reasonCode,reasonText;final double totalRefund;}
