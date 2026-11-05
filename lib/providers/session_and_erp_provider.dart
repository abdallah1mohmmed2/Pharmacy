import 'package:flutter/foundation.dart';
import '../data/database/database_helper.dart';
import '../data/models/erp_models.dart';
import '../data/services/posting_and_sales_service.dart';

class SessionAndErpProvider extends ChangeNotifier {
  SessionAndErpProvider({DatabaseHelper? database,PostingAndSalesService? posting}):_db=database??DatabaseHelper.instance,_posting=posting??PostingAndSalesService(helper:database);
  final DatabaseHelper _db;
  final PostingAndSalesService _posting;
  Map<String,Object?>? currentUser;
  int branchId=1;
  List<PartyModel> parties=[];
  List<CashAccountModel> cashAccounts=[];
  Map<String,double> dashboard={};
  bool loading=false;
  String? lastError;

  Future<bool> login(String username,String password) async {
    final rows=await _db.rawQuery('SELECT * FROM users WHERE username=? AND password_hash=? AND is_active=1 AND is_deleted=0',[username.trim(),password]);
    if(rows.isEmpty)return false;
    currentUser=rows.first;branchId=rows.first['branch_id'] as int;notifyListeners();await refresh();return true;
  }
  void logout(){currentUser=null;notifyListeners();}
  Future<void> refresh() async {
    loading=true;notifyListeners();
    try{
      final db=await _db.database;
      parties=(await db.rawQuery('SELECT p.*,v.total_alayh,v.total_lah,v.net,v.balance_side,v.balance_abs FROM parties p LEFT JOIN v_party_balance v ON v.party_id=p.id WHERE p.is_deleted=0 ORDER BY p.name_ar')).map(PartyModel.fromMap).toList();
      final cash=await db.query('cash_accounts',where:'branch_id=? AND is_deleted=0',whereArgs:[branchId],orderBy:'id');
      cashAccounts=cash.map((m)=>CashAccountModel(id:m['id'] as int,uuid:m['uuid'] as String?,branchId:m['branch_id'] as int,code:m['code'] as String,nameAr:m['name_ar'] as String,accountKind:m['account_kind'] as String,walletProvider:m['wallet_provider'] as String?,walletPhone:m['wallet_phone'] as String?,glAccountId:m['gl_account_id'] as int?,currentBalance:(m['current_balance'] as num).toDouble())).toList();
      final today=DateTime.now().toIso8601String().substring(0,10);
      final sales=await db.rawQuery("SELECT COALESCE(SUM(net_total),0) total, COALESCE(SUM(total_cost),0) cost, COUNT(*) count FROM sales_invoices WHERE status='COMPLETED' AND substr(invoice_date,1,10)=?",[today]);
      final stock=await db.rawQuery('SELECT COUNT(*) count, SUM(CASE WHEN stock_total_units<=min_stock_units THEN 1 ELSE 0 END) low FROM drugs WHERE is_deleted=0 AND is_active=1');
      final balances=await db.rawQuery('SELECT COALESCE(SUM(CASE WHEN net>0 THEN net ELSE 0 END),0) alayh, COALESCE(SUM(CASE WHEN net<0 THEN -net ELSE 0 END),0) lah FROM v_party_balance');
      dashboard={'sales':(sales.first['total'] as num).toDouble(),'profit':((sales.first['total'] as num)-(sales.first['cost'] as num)).toDouble(),'invoiceCount':(sales.first['count'] as num).toDouble(),'drugCount':(stock.first['count'] as num).toDouble(),'lowStock':(stock.first['low'] as num).toDouble(),'totalAlayh':(balances.first['alayh'] as num).toDouble(),'totalLah':(balances.first['lah'] as num).toDouble(),'cashTotal':cashAccounts.fold<double>(0,(s,a)=>s+a.currentBalance)};
      lastError=null;
    }catch(e){lastError=e.toString();}
    loading=false;notifyListeners();
  }
  Future<List<Map<String,Object?>>> ledger(int partyId)=>_db.query('lah_alayh_ledger',where:'party_id=? AND is_deleted=0',whereArgs:[partyId],orderBy:'entry_date,id');
  Future<int> createParty(PartyModel party,{double openingAlayh=0,double openingLah=0}) async {
    if(openingAlayh>0 && openingLah>0)throw ArgumentError('اختر رصيداً افتتاحياً في جهة واحدة');
    final db=await _db.database;
    final id=await db.transaction((txn)async{
      final now=DateTime.now().toIso8601String();
      final id=await txn.insert('parties',{'uuid':'party-'+DateTime.now().microsecondsSinceEpoch.toString(),'branch_id':branchId,'created_at':now,'updated_at':now,'party_type':party.partyType,'code':party.code,'name_ar':party.nameAr,'phone':party.phone,'address':party.address,'national_id':party.nationalId,'credit_limit':party.creditLimit,'payment_terms_days':party.paymentTermsDays,'is_chronic_patient':party.isChronicPatient?1:0,'is_blocked':party.isBlocked?1:0,'opening_alayh':openingAlayh,'opening_lah':openingLah});
      return id;
    });
    await refresh();
    return id;
  }
  Future<int> issueVoucher({required String voucherNo,required String type,required int partyId,required int cashAccountId,required double amount,required String method,String? walletRef,String description=''}) async {
    final id=await _posting.postVoucher(branchId:branchId,voucherNo:voucherNo,voucherType:type,partyId:partyId,cashAccountId:cashAccountId,amount:amount,method:method,walletRefNo:walletRef,description:description);
    await refresh();return id;
  }
}
