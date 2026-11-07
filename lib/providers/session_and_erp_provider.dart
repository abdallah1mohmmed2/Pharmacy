import '../data/services/security_hash_service.dart';
import 'package:flutter/foundation.dart';
import '../data/database/database_helper.dart';
import '../data/models/erp_models.dart';
import '../data/services/posting_and_sales_service.dart';
import '../data/services/settings_and_audit_service.dart';

class SessionAndErpProvider extends ChangeNotifier {
  SessionAndErpProvider({DatabaseHelper? database,PostingAndSalesService? posting}):_db=database??DatabaseHelper.instance,_posting=posting??PostingAndSalesService(helper:database);
  final DatabaseHelper _db;
  final PostingAndSalesService _posting;
  Map<String,Object?>? currentUser;
  int branchId=1;
  List<PartyModel> parties=[];
  List<CashAccountModel> cashAccounts=[];
  List<Map<String,Object?>> recentInvoices=[];
  List<Map<String,Object?>> recentVouchers=[];
  List<Map<String,Object?>> lowStockDrugs=[];
  List<Map<String,Object?>> criticalDrugs=[];
  Map<String,double> dashboard={};
  bool loading=false;
  String? lastError;

  Future<bool> login(String username,String password) async {
    final rows=await _db.rawQuery('SELECT * FROM users WHERE username=? AND is_active=1 AND is_deleted=0',[username.trim()]);
    if(rows.isEmpty || !SecurityHashService.verify(password,rows.first['password_hash'] as String)){
      await AuditService(helper:_db).record(action:'LOGIN_FAILED',branchId:branchId,entityType:'users',entityLabel:username.trim(),severity:'WARNING');
      return false;
    }
    currentUser=Map<String,Object?>.from(rows.first)..['role_code']=rows.first['system_role_code']??rows.first['role_code'];branchId=rows.first['branch_id'] as int;
    await AuditService(helper:_db).record(action:'LOGIN',userId:currentUser?['id'] as int?,branchId:branchId,entityType:'users',entityId:currentUser?['id'] as int?,entityLabel:username.trim());
    notifyListeners();await refresh();return true;
  }
  int? _verifiedManagerUserId;
  int? consumeVerifiedManagerUserId(){final id=_verifiedManagerUserId;_verifiedManagerUserId=null;return id;}
  Future<bool> verifyManagerPin(String pin) async {
    _verifiedManagerUserId=null;
    final rows=await _db.rawQuery("SELECT id,manager_pin_hash FROM users WHERE branch_id=? AND role_code IN('OWNER','MANAGER') AND is_active=1 AND is_deleted=0",[branchId]);
    for(final row in rows){
      final hash=row['manager_pin_hash'];
      if(hash is String&&SecurityHashService.verify(pin,hash)){
        _verifiedManagerUserId=row['id'] as int;
        await AuditService(helper:_db).record(action:'MANAGER_PIN_USED',userId:_verifiedManagerUserId,branchId:branchId,entityType:'users',entityId:_verifiedManagerUserId,severity:'WARNING');
        return true;
      }
    }
    return false;
  }
  void logout(){
    final user=currentUser;
    if(user!=null){AuditService(helper:_db).record(action:'LOGOUT',userId:user['id'] as int?,branchId:branchId,entityType:'users',entityId:user['id'] as int?,entityLabel:user['username']?.toString());}
    currentUser=null;notifyListeners();
  }
  Future<void> refresh() async {
    loading=true;notifyListeners();
    try{
      final db=await _db.database;
      parties=(await db.rawQuery('SELECT p.*,v.total_alayh,v.total_lah,v.net,v.balance_side,v.balance_abs FROM parties p LEFT JOIN v_party_balance v ON v.party_id=p.id WHERE p.branch_id=? AND p.is_deleted=0 ORDER BY p.name_ar',[branchId])).map(PartyModel.fromMap).toList();
      final cash=await db.query('cash_accounts',where:'branch_id=? AND is_deleted=0',whereArgs:[branchId],orderBy:'id');
      recentInvoices=await db.query('sales_invoices',where:'branch_id=? AND is_deleted=0',whereArgs:[branchId],orderBy:'id DESC',limit:5);
      recentVouchers=await db.query('vouchers',where:'branch_id=? AND is_deleted=0',whereArgs:[branchId],orderBy:'id DESC',limit:5);
      lowStockDrugs=await db.rawQuery('SELECT id,trade_name_ar,stock_total_units,min_stock_units FROM drugs WHERE branch_id=? AND is_deleted=0 AND is_active=1 AND stock_total_units<=min_stock_units ORDER BY stock_total_units LIMIT 10',[branchId]);
      criticalDrugs=await db.rawQuery("SELECT id,trade_name_ar,pregnancy_category,is_controlled,is_nephrotoxic,has_critical_interactions FROM drugs WHERE branch_id=? AND is_deleted=0 AND is_active=1 AND (pregnancy_category='X' OR is_controlled=1 OR is_nephrotoxic=1 OR has_critical_interactions=1) ORDER BY trade_name_ar LIMIT 10",[branchId]);
      cashAccounts=cash.map((m)=>CashAccountModel(id:m['id'] as int,uuid:m['uuid'] as String?,branchId:m['branch_id'] as int,code:m['code'] as String,nameAr:m['name_ar'] as String,accountKind:m['account_kind'] as String,walletProvider:m['wallet_provider'] as String?,walletPhone:m['wallet_phone'] as String?,glAccountId:m['gl_account_id'] as int?,currentBalance:(m['current_balance'] as num).toDouble())).toList();
      final today=DateTime.now().toIso8601String().substring(0,10);
      final sales=await db.rawQuery("SELECT COALESCE(SUM(net_total),0) total, COALESCE(SUM(total_cost),0) cost, COUNT(*) count FROM sales_invoices WHERE branch_id=? AND status='COMPLETED' AND substr(invoice_date,1,10)=?",[branchId,today]);
      final stock=await db.rawQuery('SELECT COUNT(*) count, SUM(CASE WHEN stock_total_units<=min_stock_units THEN 1 ELSE 0 END) low FROM drugs WHERE branch_id=? AND is_deleted=0 AND is_active=1',[branchId]);
      final balances=await db.rawQuery('SELECT COALESCE(SUM(CASE WHEN net>0 THEN net ELSE 0 END),0) alayh, COALESCE(SUM(CASE WHEN net<0 THEN -net ELSE 0 END),0) lah FROM v_party_balance WHERE branch_id=?',[branchId]);
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
      final openingAmount=openingAlayh+openingLah;
      if(openingAmount>0){
        final partyAccountCode=party.partyType=='SUPPLIER'&&openingLah>0?'2101':'1201';
        final partyAccountRows=await txn.query('chart_of_accounts',columns:['id'],where:'code=?',whereArgs:[partyAccountCode],limit:1);
        final equityRows=await txn.query('chart_of_accounts',columns:['id'],where:'code=?',whereArgs:['3101'],limit:1);
        final partyAccountId=partyAccountRows.first['id'] as int;
        final equityAccountId=equityRows.first['id'] as int;
        final journalId=await txn.insert('journal_entries',{'uuid':'party-opening-je-'+id.toString(),'branch_id':branchId,'created_at':now,'updated_at':now,'entry_no':'OPENING-PTY-'+party.code,'entry_date':now,'description':'الرصيد الافتتاحي للطرف '+party.nameAr,'source_type':'OPENING_PARTY','source_id':id,'is_posted':1});
        final isAlayh=openingAlayh>0;
        final amount=isAlayh?openingAlayh:openingLah;
        await txn.insert('journal_lines',{'uuid':'party-opening-jl-'+id.toString()+'-1','branch_id':branchId,'created_at':now,'updated_at':now,'journal_entry_id':journalId,'account_id':isAlayh?partyAccountId:equityAccountId,'party_id':isAlayh?id:null,'dr_amount':amount,'cr_amount':0,'memo':'رصيد افتتاحي'});
        await txn.insert('journal_lines',{'uuid':'party-opening-jl-'+id.toString()+'-2','branch_id':branchId,'created_at':now,'updated_at':now,'journal_entry_id':journalId,'account_id':isAlayh?equityAccountId:partyAccountId,'party_id':isAlayh?null:id,'dr_amount':0,'cr_amount':amount,'memo':'رصيد افتتاحي'});
      }
      return id;
    });
    await refresh();
    return id;
  }
  Future<int> issueVoucher({required String voucherNo,required String type,required int partyId,int? cashAccountId,required double amount,required String method,String? walletRef,String description=''}) async {
    final id=await _posting.postVoucher(branchId:branchId,voucherNo:voucherNo,voucherType:type,partyId:partyId,cashAccountId:cashAccountId??-1,amount:amount,method:method,walletRefNo:walletRef,description:description);
    await refresh();return id;
  }
}
