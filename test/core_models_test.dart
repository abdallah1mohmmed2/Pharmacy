import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/drug_model.dart';

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
}
