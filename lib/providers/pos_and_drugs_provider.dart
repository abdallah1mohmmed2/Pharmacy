import 'package:flutter/foundation.dart';
import '../data/database/database_helper.dart';
import '../data/models/drug_model.dart';
import '../data/models/erp_models.dart';
import '../data/services/posting_and_sales_service.dart';

class PosAndDrugsProvider extends ChangeNotifier {
  PosAndDrugsProvider({DatabaseHelper? database,PostingAndSalesService? posting}):_db=database??DatabaseHelper.instance,_posting=posting??PostingAndSalesService(helper:database);
  final DatabaseHelper _db;
  final PostingAndSalesService _posting;
  List<DrugModel> drugs=[];
  final List<PosTabSession> tabs=[PosTabSession(id:'tab-1',label:'فاتورة 1',createdAt:DateTime.now())];
  int activeTab=0;
  String search='';
  bool loading=false;
  final Set<String> patientFlags={};
  String? clinicalBlock;
  PosTabSession get currentTab=>tabs[activeTab];
  List<CartItemModel> get cart=>currentTab.items;
  double get total=>currentTab.total;

  Future<void> loadDrugs() async {loading=true;notifyListeners();final rows=await _db.query('drugs',where:'is_deleted=0 AND is_active=1',orderBy:'trade_name_ar');drugs=rows.map(DrugModel.fromMap).toList();loading=false;notifyListeners();}
  Future<void> searchDrugs(String value) async {search=value;final rows=await _db.rawQuery("SELECT * FROM drugs WHERE is_deleted=0 AND is_active=1 AND (trade_name_ar LIKE ? OR trade_name_en LIKE ? OR scientific_name LIKE ? OR barcode_local LIKE ? OR barcode_international LIKE ?) ORDER BY trade_name_ar LIMIT 100",['%'+value+'%','%'+value+'%','%'+value+'%','%'+value+'%','%'+value+'%']);drugs=rows.map(DrugModel.fromMap).toList();notifyListeners();}
  bool createTab(){if(tabs.length>=8)return false;tabs.add(PosTabSession(id:'tab-'+DateTime.now().microsecondsSinceEpoch.toString(),label:'فاتورة '+(tabs.length+1).toString(),createdAt:DateTime.now()));activeTab=tabs.length-1;notifyListeners();return true;}
  void selectTab(int index){if(index<0||index>=tabs.length)return;activeTab=index;clinicalBlock=null;notifyListeners();}
  void holdCurrent(){currentTab.held=true;notifyListeners();}
  bool restoreCurrent(){if(!currentTab.held)return false;currentTab.held=false;notifyListeners();return true;}
  void closeCurrent(){if(tabs.length==1){currentTab.items.clear();currentTab.held=false;}else{tabs.removeAt(activeTab);activeTab=activeTab.clamp(0,tabs.length-1);}clinicalBlock=null;notifyListeners();}
  void setPatientFlag(String flag,bool enabled){if(enabled){patientFlags.add(flag);}else{patientFlags.remove(flag);}clinicalBlock=null;for(final item in cart){_checkDrug(item.drug);}notifyListeners();}
  void addDrug(DrugModel drug,{String unit='UNIT'}){_checkDrug(drug);cart.add(CartItemModel(drug:drug,sellUnit:unit));notifyListeners();}
  void removeItem(CartItemModel item){cart.remove(item);clinicalBlock=null;for(final i in cart){_checkDrug(i.drug);}notifyListeners();}
  void changeQuantity(CartItemModel item,double qty){if(qty<=0){removeItem(item);}else{item.quantity=qty;notifyListeners();}}
  void changeUnit(CartItemModel item,String unit){item.sellUnit=unit;notifyListeners();}
  void _checkDrug(DrugModel d){
    if(patientFlags.contains('PREGNANT') && d.pregnancyCategory=='X')clinicalBlock='تحذير حمل حرج: '+d.tradeNameAr+' مصنف ضمن الفئة X.';
    if(patientFlags.contains('KIDNEY') && ['AVOID','CONTRAINDICATED'].contains(d.renalStatus))clinicalBlock='تحذير كلوي: '+d.tradeNameAr+' — '+d.renalNotes;
    if(patientFlags.contains('LIVER') && ['AVOID','CONTRAINDICATED'].contains(d.hepaticStatus))clinicalBlock='تحذير كبدي: '+d.tradeNameAr+' — '+d.hepaticNotes;
    if(patientFlags.contains('CHILD') && ['AVOID','CONTRAINDICATED'].contains(d.pediatricStatus))clinicalBlock='تحذير للأطفال: '+d.tradeNameAr+' — '+d.pediatricNotes;
    if(patientFlags.contains('ELDERLY') && d.geriatricStatus=='AVOID')clinicalBlock='تحذير لكبار السن: '+d.tradeNameAr+' — '+d.geriatricNotes;
    if(patientFlags.contains('BREASTFEEDING') && ['L4','L5'].contains(d.lactationRisk))clinicalBlock='تحذير رضاعة: '+d.tradeNameAr+' — '+d.lactationNotes;
  }
  Future<int> checkout({required int cashierId,required String saleType,required List<({int cashAccountId,double amount,String method,String? walletRef})> payments,int? customerId,double discount=0}) async {
    if(clinicalBlock!=null)throw StateError('يلزم حذف الدواء المتعارض أو اعتماد المدير');
    final id=await _posting.postSale(branchId:1,cashierUserId:cashierId,items:List<CartItemModel>.from(cart),saleType:saleType,payments:payments,customerPartyId:customerId,discountAmount:discount);
    currentTab.items.clear();currentTab.held=false;await loadDrugs();notifyListeners();return id;
  }
}
