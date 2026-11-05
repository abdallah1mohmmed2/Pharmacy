import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/drug_model.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/security_hash_service.dart';

void main(){
 group('DrugModel',(){
  test('converts pack, strip and unit quantities to base units',(){
   const drug=DrugModel(stripsPerPack:3,unitsPerStrip:10);
   expect(drug.toBaseUnits('PACK',2),60);
   expect(drug.toBaseUnits('STRIP',2),20);
   expect(drug.toBaseUnits('UNIT',2),2);
  });
  test('rejects non-positive sale quantities',(){
   const drug=DrugModel();
   expect(()=>drug.toBaseUnits('UNIT',0),throwsArgumentError);
  });
  test('completeness is bounded from zero to one hundred',(){
   const drug=DrugModel();
   expect(drug.calculateCompletenessPct(),inInclusiveRange(0,100));
  });
 });
 group('SecurityHashService',(){
  test('hashes secrets with a unique salt and verifies the original value',(){
   final first=SecurityHashService.hash('123456');
   final second=SecurityHashService.hash('123456');
   expect(first, isNot(second));
   expect(SecurityHashService.verify('123456',first),isTrue);
   expect(SecurityHashService.verify('wrong',first),isFalse);
   expect(SecurityHashService.verify('123456',second),isTrue);
  });
 });
}
