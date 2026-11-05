// lib/providers/clinical_and_rx_provider.dart
import 'package:flutter/foundation.dart';
import '../data/database/database_helper.dart';
import '../data/models/clinical_and_rx_models.dart';
import '../data/models/drug_model.dart';
import '../data/services/clinical_guard_service.dart';
import '../data/services/rx_and_returns_service.dart';

class ClinicalAndRxProvider extends ChangeNotifier {
  ClinicalAndRxProvider({DatabaseHelper? helper,ClinicalGuardService? guard,RxAndReturnsService? rx}):_helper=helper??DatabaseHelper.instance,_guard=guard??ClinicalGuardService(helper:helper),_rx=rx??RxAndReturnsService(helper:helper,guard:guard);
  final DatabaseHelper _helper;
  final ClinicalGuardService _guard;
  final RxAndReturnsService _rx;
  List<PatientClinicalModel> patients=[];
  List<InsuranceCompanyModel> companies=[];
  List<InsurancePolicyModel> policies=[];
  List<AlternativeDrugModel> alternatives=[];
  PatientClinicalModel? currentPatient;
  ClinicalVerdict verdict=ClinicalVerdict([]);
  bool loading=false;
  String? error;
  List<String> currentFoods=[];
  final Set<String> quickFlags={};

  Future<void> loadAll() async {
    loading=true;error=null;notifyListeners();
    try{
      final db=await _helper.database;
      patients=(await db.query('patients',orderBy:'full_name COLLATE NOCASE')).map(PatientClinicalModel.fromMap).toList();
      companies=(await db.query('insurance_companies',orderBy:'name_ar')).map((r)=>InsuranceCompanyModel(id:r['id'] as int,partyId:r['party_id'] as int,nameAr:r['name_ar'] as String,defaultCoveragePct:(r['default_coverage_pct'] as num).toDouble(),claimCycleDays:(r['claim_cycle_days'] as num).toInt())).toList();
      policies=(await db.query('insurance_policies',orderBy:'policy_no')).map((r)=>InsurancePolicyModel(id:r['id'] as int,insuranceCompanyId:r['insurance_company_id'] as int,customerPartyId:r['customer_party_id'] as int,policyNo:r['policy_no'] as String,coveragePct:(r['coverage_pct'] as num).toDouble(),copayPct:(r['copay_pct'] as num).toDouble(),annualLimit:(r['annual_limit'] as num).toDouble(),usedLimit:(r['used_limit'] as num).toDouble(),validFrom:r['valid_from'] as String?,validTo:r['valid_to'] as String?,excludedCategoriesJson:r['excluded_categories_json'] as String? ?? '[]')).toList();
    }catch(e){error=e.toString();}
    loading=false;notifyListeners();
  }
  void setFoodIntake(List<String> foods){currentFoods=foods;notifyListeners();}
  void setQuickFlag(String flag,bool enabled){if(enabled){quickFlags.add(flag);}else{quickFlags.remove(flag);}notifyListeners();}
  Future<void> updatePatient(PatientClinicalModel patient) async {
    if(patient.id==null)throw ArgumentError('معرف المريض مطلوب');
    await _helper.update('patients',{
      'party_id':patient.partyId,'full_name':patient.fullName,'birth_date':patient.birthDate?.toIso8601String().substring(0,10),
      'sex':patient.sex,'weight_kg':patient.weightKg,'height_cm':patient.heightCm,
      'is_pregnant':patient.isPregnant?1:0,'pregnancy_trimester':patient.pregnancyTrimester,
      'is_lactating':patient.isLactating?1:0,'serum_creatinine':patient.serumCreatinine,
      'egfr_ml_min':patient.egfrMlMin,'renal_stage':patient.renalStage,'child_pugh_class':patient.childPughClass,
      'allergies_json':patient.allergiesJson,'chronic_conditions_json':patient.chronicConditionsJson,
      'current_meds_json':patient.currentMedsJson,'updated_at':DateTime.now().toIso8601String(),
    },where:'id=?',whereArgs:[patient.id]);
    await loadAll();
    currentPatient=patients.firstWhere((p)=>p.id==patient.id);
    notifyListeners();
  }
  void selectPatient(PatientClinicalModel? patient){currentPatient=patient;verdict=ClinicalVerdict([]);notifyListeners();}
  Future<ClinicalVerdict> evaluateCart(List<DrugModel> drugs,{Map<int,double> doses=const {}}) async {
    verdict=await _guard.evaluate(cart:drugs,patient:currentPatient,prescribedDoseMgByDrugId:doses,foodIntake:currentFoods,quickFlags:quickFlags);notifyListeners();return verdict;
  }
  Future<void> decideAlert(ClinicalAlertModel alert,{required String decision,required int? userId,String? reason,int? managerUserId}) async {
    await _guard.recordDecision(alert,decision:decision,userId:userId,reason:reason,managerUserId:managerUserId);
    final updated=verdict.alerts.map((a)=>identical(a,alert)?ClinicalAlertModel(id:a.id,category:a.category,level:a.level,messageAr:a.messageAr,drugId:a.drugId,otherDrugId:a.otherDrugId,ruleRef:a.ruleRef,recommendation:a.recommendation,patientId:a.patientId,invoiceId:a.invoiceId,userDecision:decision,overrideReason:reason):a).toList();
    verdict=ClinicalVerdict(updated);notifyListeners();
  }
  Future<ClinicalVerdict> evaluateCandidate(DrugModel drug) => _guard.evaluate(cart:[drug],patient:currentPatient,foodIntake:currentFoods,quickFlags:quickFlags);
  Future<List<AlternativeDrugModel>> loadAlternatives(int drugId,{bool inStockOnly=false,bool cheapestFirst=false}) async {
    alternatives=await _rx.findAlternatives(drugId,inStockOnly:inStockOnly,cheapestFirst:cheapestFirst);notifyListeners();return alternatives;
  }
  Future<int> dispensePrescription({required int prescriptionId,required Map<int,int> quantitiesByItemId,required int patientPartyId,required int? policyId,required List<({double amount,int? cashAccountId,String method,String? walletRef})> patientPayments,required int pharmacistUserId,Map<int,({String patientName,String patientNationalId,String receiverName,String receiverNationalId,String doctorName,int? batchId})> controlledDetails=const {},required Map<int,double> lineTotalsByItemId,int branchId=1,ClinicalVerdict? clinicalVerdict}) =>
    _rx.dispensePrescription(prescriptionId:prescriptionId,quantitiesByItemId:quantitiesByItemId,patientPartyId:patientPartyId,policyId:policyId,patientPayments:patientPayments,pharmacistUserId:pharmacistUserId,controlledDetails:controlledDetails,lineTotalsByItemId:lineTotalsByItemId,branchId:branchId,clinicalVerdict:clinicalVerdict);
  Future<int> completeReturn({required int invoiceId,required int invoiceItemId,required int qtyUnits,required double refundAmount,required String reasonCode,required String reasonText,required String refundMethod,required String disposition,required int? approvedBy,required int? cashAccountId,int? batchId,bool openedLiquid=false,String? walletRef}) async {
    final id=await _rx.createSalesReturn(invoiceId:invoiceId,invoiceItemId:invoiceItemId,qtyUnits:qtyUnits,refundAmount:refundAmount,reasonCode:reasonCode,reasonText:reasonText,refundMethod:refundMethod,disposition:disposition,approvedBy:approvedBy,cashAccountId:cashAccountId,batchId:batchId,openedLiquid:openedLiquid,walletRef:walletRef);
    notifyListeners();return id;
  }
}
