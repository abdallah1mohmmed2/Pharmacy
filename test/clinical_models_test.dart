// test/clinical_models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/clinical_and_rx_models.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/clinical_guard_service.dart';

void main(){
  test('Cockcroft-Gault uses sex factor and manual eGFR override',(){
    final now=DateTime.now();
    final birth=DateTime(now.year-50,now.month,now.day);
    final male=PatientClinicalModel(fullName:'M',birthDate:birth,sex:'M',weightKg:72,serumCreatinine:1);
    final female=PatientClinicalModel(fullName:'F',birthDate:birth,sex:'F',weightKg:72,serumCreatinine:1);
    expect(male.crcl,closeTo(90,0.01));
    expect(female.crcl,closeTo(76.5,0.01));
    final override=PatientClinicalModel(fullName:'O',birthDate:birth,sex:'M',weightKg:72,serumCreatinine:1,egfrMlMin:42);
    expect(override.crcl,42);
  });
  test('pregnancy status distinguishes unknown from confirmed negative',(){
    final unknown=PatientClinicalModel(fullName:'Unknown',sex:'F');
    final negative=PatientClinicalModel(fullName:'Negative',sex:'F',pregnancyStatusKnown:true,isPregnant:false);
    expect(unknown.pregnancyStatusKnown,isFalse);
    expect(negative.pregnancyStatusKnown,isTrue);
    expect(negative.isPregnant,isFalse);
  });
  test('a clinical BLOCK cannot be resolved by acknowledgement',(){
    const alert=ClinicalAlertModel(category:'ALLERGY',level:ClinicalLevel.block,messageAr:'حظر');
    expect(
      ()=>ClinicalGuardService.validateDecision(alert,decision:'ACKNOWLEDGED'),
      throwsA(isA<StateError>()),
    );
  });
  test('a clinical BLOCK override requires a verified manager and reason',(){
    const alert=ClinicalAlertModel(category:'ALLERGY',level:ClinicalLevel.block,messageAr:'حظر');
    expect(
      ()=>ClinicalGuardService.validateDecision(alert,decision:'OVERRIDDEN_WITH_PIN',reason:'سبب واضح'),
      throwsA(isA<StateError>()),
    );
    expect(
      ()=>ClinicalGuardService.validateDecision(alert,decision:'OVERRIDDEN_WITH_PIN',reason:'سبب واضح',managerUserId:7),
      returnsNormally,
    );
  });
  test('a WARNING acknowledgement requires a reason of at least five characters',(){
    const alert=ClinicalAlertModel(category:'RENAL',level:ClinicalLevel.warning,messageAr:'تحذير');
    expect(
      ()=>ClinicalGuardService.validateDecision(alert,decision:'ACKNOWLEDGED',reason:'لا'),
      throwsA(isA<StateError>()),
    );
    expect(
      ()=>ClinicalGuardService.validateDecision(alert,decision:'ACKNOWLEDGED',reason:'سبب موثق'),
      returnsNormally,
    );
  });
  test('clinical verdict sorts block and warning before caution and info',(){
    final verdict=ClinicalVerdict([
      const ClinicalAlertModel(category:'I',level:ClinicalLevel.info,messageAr:'i'),
      const ClinicalAlertModel(category:'C',level:ClinicalLevel.caution,messageAr:'c'),
      const ClinicalAlertModel(category:'W',level:ClinicalLevel.warning,messageAr:'w'),
      const ClinicalAlertModel(category:'B',level:ClinicalLevel.block,messageAr:'b'),
    ]);
    expect(verdict.alerts.map((e)=>e.level).toList(),[ClinicalLevel.block,ClinicalLevel.warning,ClinicalLevel.caution,ClinicalLevel.info]);
    expect(verdict.hasUnresolvedCritical,isTrue);
    expect(verdict.blocked,isTrue);
  });
}
