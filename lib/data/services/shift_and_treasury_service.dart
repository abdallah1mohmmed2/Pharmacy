// lib/data/services/shift_and_treasury_service.dart
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';

class ShiftAndTreasuryService {
  ShiftAndTreasuryService({DatabaseHelper? helper}) : _helper=helper??DatabaseHelper.instance;
  final DatabaseHelper _helper;
  String _uuid(String prefix)=>'$prefix-${DateTime.now().microsecondsSinceEpoch}';
  String _now()=>DateTime.now().toIso8601String();
  double _n(Object? v)=>v is num?v.toDouble():double.tryParse('$v')??0;

  Future<List<Map<String,Object?>>> cashAccounts(int branchId)=>_helper.query('cash_accounts',where:'branch_id=? AND is_deleted=0',whereArgs:[branchId],orderBy:'id');
  Future<List<Map<String,Object?>>> transactions(int branchId,{int? accountId,String? from,String? to}) async {
    final clauses=<String>['branch_id=?'];final args=<Object?>[branchId];
    if(accountId!=null){clauses.add('cash_account_id=?');args.add(accountId);}
    if(from!=null){clauses.add('date(tx_date)>=date(?)');args.add(from);}
    if(to!=null){clauses.add('date(tx_date)<=date(?)');args.add(to);}
    return _helper.rawQuery('SELECT t.*,c.name_ar AS account_name FROM cash_transactions t JOIN cash_accounts c ON c.id=t.cash_account_id WHERE ${clauses.join(' AND ')} ORDER BY t.tx_date DESC,t.id DESC',args);
  }

  Future<int> _cashMove(Transaction tx,{required int branchId,required int accountId,required String direction,required double amount,required String type,String? docType,int? docId,String? ref,int? shiftId,String? note}) async {
    if(amount<=0)throw ArgumentError('يجب أن يكون المبلغ أكبر من صفر');
    final rows=await tx.query('cash_accounts',columns:['current_balance'],where:'id=? AND branch_id=?',whereArgs:[accountId,branchId],limit:1);
    if(rows.isEmpty)throw StateError('حساب الصندوق أو المحفظة غير موجود');
    final before=_n(rows.first['current_balance']);final after=before+(direction=='IN'?amount:-amount);
    await tx.update('cash_accounts',{'current_balance':after,'updated_at':_now()},where:'id=?',whereArgs:[accountId]);
    return tx.insert('cash_transactions',{'cash_account_id':accountId,'tx_date':_now(),'direction':direction,'amount':amount,'tx_type':type,'doc_type':docType,'doc_id':docId,'wallet_ref_no':ref,'cashier_shift_id':shiftId,'balance_after':after,'note':note,'branch_id':branchId});
  }

  Future<void> transfer({required int branchId,required int fromAccountId,required int toAccountId,required double amount,double fee=0,String? walletRefNo,String note=''}) async {
    if(fromAccountId==toAccountId)throw ArgumentError('اختر حسابين مختلفين');
    if(amount<=0||fee<0)throw ArgumentError('تحقق من مبلغ التحويل والرسوم');
    final db=await _helper.database;
    await db.transaction((tx)async{
      final source=await tx.query('cash_accounts',columns:['current_balance'],where:'id=? AND branch_id=?',whereArgs:[fromAccountId,branchId],limit:1);
      if(source.isEmpty)throw StateError('حساب المصدر غير موجود');
      if(_n(source.first['current_balance'])<amount+fee)throw StateError('رصيد حساب المصدر لا يكفي');
      final transferId=DateTime.now().microsecondsSinceEpoch;
      final sourceShiftRows=await tx.query('cashier_shifts',columns:['id'],where:"branch_id=? AND drawer_account_id=? AND status='OPEN'",whereArgs:[branchId,fromAccountId],orderBy:'id DESC',limit:1);
      final destinationShiftRows=await tx.query('cashier_shifts',columns:['id'],where:"branch_id=? AND drawer_account_id=? AND status='OPEN'",whereArgs:[branchId,toAccountId],orderBy:'id DESC',limit:1);
      final int? sourceShiftId=sourceShiftRows.isEmpty?null:sourceShiftRows.first['id'] as int;
      final int? destinationShiftId=destinationShiftRows.isEmpty?null:destinationShiftRows.first['id'] as int;
      final sourceRows=await tx.query('cash_accounts',columns:['gl_account_id'],where:'id=?',whereArgs:[fromAccountId],limit:1);
      final destinationRows=await tx.query('cash_accounts',columns:['gl_account_id'],where:'id=?',whereArgs:[toAccountId],limit:1);
      final sourceGl=sourceRows.first['gl_account_id'] as int?;final destinationGl=destinationRows.first['gl_account_id'] as int?;
      if(sourceGl==null||destinationGl==null)throw StateError('يجب ربط حسابي التحويل بدليل الحسابات');
      final je=await _journal(tx,branchId:branchId,source:'CASH_TRANSFER',sourceId:transferId,description:note.isEmpty?'تحويل بين حسابين':note);
      await _journalLine(tx,branchId:branchId,entryId:je,accountId:destinationGl,dr:amount,memo:'تحويل وارد');
      await _journalLine(tx,branchId:branchId,entryId:je,accountId:sourceGl,cr:amount+fee,memo:'تحويل صادر ورسوم');
      if(fee>0){final feeGl=await _glId(tx,'5301');await _journalLine(tx,branchId:branchId,entryId:je,accountId:feeGl,dr:fee,memo:'رسوم تحويل');}
      await _cashMove(tx,branchId:branchId,accountId:fromAccountId,direction:'OUT',amount:amount,type:'TRANSFER_BETWEEN_ACCOUNTS',docType:'CASH_TRANSFER',docId:transferId,ref:walletRefNo,note:note);
      await _cashMove(tx,branchId:branchId,accountId:toAccountId,direction:'IN',amount:amount,type:'TRANSFER_BETWEEN_ACCOUNTS',docType:'CASH_TRANSFER',docId:transferId,ref:walletRefNo,note:note);
      if(fee>0)await _cashMove(tx,branchId:branchId,accountId:fromAccountId,direction:'OUT',amount:fee,type:'EXPENSE',docType:'TRANSFER_FEE',docId:transferId,ref:walletRefNo,shiftId:sourceShiftId,note:'رسوم تحويل: $note');
    });
  }

  Future<double> reconcileWallet({required int branchId,required int accountId,required double actualBalance,String? walletRefNo,String note='مطابقة رصيد محفظة'}) async {
    if(actualBalance<0)throw ArgumentError('الرصيد الفعلي لا يمكن أن يكون سالباً');
    final db=await _helper.database;double difference=0;
    await db.transaction((tx)async{
      final rows=await tx.query('cash_accounts',columns:['current_balance'],where:'id=? AND branch_id=?',whereArgs:[accountId,branchId],limit:1);
      if(rows.isEmpty)throw StateError('المحفظة غير موجودة');
      difference=actualBalance-_n(rows.first['current_balance']);
      if(difference.abs()<0.005)return;
      final account=await tx.query('cash_accounts',columns:['gl_account_id'],where:'id=?',whereArgs:[accountId],limit:1);
      final cashGl=account.first['gl_account_id'] as int?;
      final adjustment=await _glId(tx,'5304');
      final revenue=await _glId(tx,'4102');
      final now=_now();
      final je=await _journal(tx,branchId:branchId,source:'WALLET_RECONCILIATION',sourceId:accountId,description:note);
      final positive=difference>0;final amount=difference.abs();
      await _journalLine(tx,branchId:branchId,entryId:je,accountId:positive?cashGl!:adjustment,dr:amount,memo:note);
      await _journalLine(tx,branchId:branchId,entryId:je,accountId:positive?revenue:cashGl!,cr:amount,memo:note);
      await _cashMove(tx,branchId:branchId,accountId:accountId,direction:positive?'IN':'OUT',amount:amount,type:'WALLET_RECONCILIATION',docType:'JOURNAL',docId:je,ref:walletRefNo,note:note);
      await tx.update('journal_entries',{'updated_at':now},where:'id=?',whereArgs:[je]);
    });
    return difference;
  }

  Future<int> recordExpense({required int branchId,required int categoryId,required int cashAccountId,required double amount,required String description,String paidTo='',int? cashierShiftId,String? attachmentPath}) async {
    if(amount<=0)throw ArgumentError('مبلغ المصروف يجب أن يكون أكبر من صفر');
    final db=await _helper.database;int expenseId=0;
    await db.transaction((tx)async{
      final category=await tx.query('expense_categories',columns:['gl_account_id','name_ar'],where:'id=? AND branch_id=?',whereArgs:[categoryId,branchId],limit:1);
      if(category.isEmpty)throw StateError('بند المصروف غير موجود');
      final account=await tx.query('cash_accounts',columns:['gl_account_id','current_balance'],where:'id=? AND branch_id=?',whereArgs:[cashAccountId,branchId],limit:1);
      if(account.isEmpty)throw StateError('حساب الدفع غير موجود');
      if(_n(account.first['current_balance'])<amount)throw StateError('رصيد حساب الدفع غير كافٍ');
      final now=_now();final no='EXP-${DateTime.now().millisecondsSinceEpoch}';
      final je=await _journal(tx,branchId:branchId,source:'EXPENSE',description:description);
      final expenseGl=category.first['gl_account_id'] as int? ?? await _glId(tx,'5201');
      final cashGl=account.first['gl_account_id'] as int;
      await _journalLine(tx,branchId:branchId,entryId:je,accountId:expenseGl,dr:amount,memo:description);
      await _journalLine(tx,branchId:branchId,entryId:je,accountId:cashGl,cr:amount,memo:description);
      expenseId=await tx.insert('expenses',{'expense_no':no,'category_id':categoryId,'expense_date':now,'amount':amount,'cash_account_id':cashAccountId,'paid_to':paidTo,'description':description,'attachment_path':attachmentPath,'is_recurring_instance':0,'cashier_shift_id':cashierShiftId,'journal_entry_id':je,'branch_id':branchId});
      await _cashMove(tx,branchId:branchId,accountId:cashAccountId,direction:'OUT',amount:amount,type:'EXPENSE',docType:'EXPENSE',docId:expenseId,shiftId:cashierShiftId,note:description);
    });
    return expenseId;
  }

  Future<int> openShift({required int branchId,required int userId,required int drawerAccountId,double openingCash=0,int? cashierPartyId,int? workShiftId}) async {
    if(openingCash<0)throw ArgumentError('العهدة الافتتاحية لا يمكن أن تكون سالبة');
    final db=await _helper.database;final existing=await db.query('cashier_shifts',columns:['id'],where:"branch_id=? AND status='OPEN'",whereArgs:[branchId],limit:1);
    if(existing.isNotEmpty)throw StateError('توجد وردية مفتوحة بالفعل');
    return db.insert('cashier_shifts',{'shift_no':'SH-${DateTime.now().millisecondsSinceEpoch}','user_id':userId,'cashier_party_id':cashierPartyId,'drawer_account_id':drawerAccountId,'work_shift_id':workShiftId,'opened_at':_now(),'opening_cash':openingCash,'status':'OPEN','branch_id':branchId});
  }

  Future<double> expectedCash(int shiftId) async {
    final db=await _helper.database;final rows=await db.query('cashier_shifts',where:'id=?',whereArgs:[shiftId],limit:1);
    if(rows.isEmpty)throw StateError('الوردية غير موجودة');
    final shift=rows.first;final opening=_n(shift['opening_cash']);
    final totals=await db.rawQuery("SELECT COALESCE(SUM(CASE WHEN direction='IN' THEN amount ELSE -amount END),0) movement FROM cash_transactions WHERE cashier_shift_id=? AND cash_account_id=?",[shiftId,shift['drawer_account_id']]);
    return opening+_n(totals.first['movement']);
  }

  Future<double> closeShiftBlind({required int shiftId,required Map<String,int> denominations,required String diffHandling,Map<String,double> countedWallets=const {},int? handoverToUserId,bool revealExpectedToManager=false}) async {
    final actual=denominations.entries.fold<double>(0,(sum,e)=>sum+(double.tryParse(e.key)??0)*e.value);
    if(denominations.values.any((v)=>v<0))throw ArgumentError('عدد الفئات لا يمكن أن يكون سالباً');
    final db=await _helper.database;double difference=0;
    await db.transaction((tx)async{
      final rows=await tx.query('cashier_shifts',where:"id=? AND status='OPEN'",whereArgs:[shiftId],limit:1);
      if(rows.isEmpty)throw StateError('الوردية غير مفتوحة');
      final shift=rows.first;
      final movement=await tx.rawQuery("SELECT COALESCE(SUM(CASE WHEN direction='IN' THEN amount ELSE -amount END),0) movement FROM cash_transactions WHERE cashier_shift_id=? AND cash_account_id=?",[shiftId,shift['drawer_account_id']]);
      final expected=_n(shift['opening_cash'])+_n(movement.first['movement']);
      difference=((actual-expected)*100).roundToDouble()/100;
      final walletRows=await tx.query('cash_accounts',columns:['id','current_balance'],where:"branch_id=? AND account_kind='WALLET'",whereArgs:[shift['branch_id']]);
      final expectedWallets={for(final wallet in walletRows)(wallet['id'] as int).toString():_n(wallet['current_balance'])};
      for(final entry in countedWallets.entries){
        final walletId=int.tryParse(entry.key);if(walletId==null)continue;
        final expectedWallet=expectedWallets[entry.key];if(expectedWallet==null)continue;
        final walletDiff=entry.value-expectedWallet;if(walletDiff.abs()<0.005)continue;
        final gl=await tx.query('cash_accounts',columns:['gl_account_id'],where:'id=?',whereArgs:[walletId],limit:1);
        final cashGl=gl.first['gl_account_id'] as int;final adjustment=await _glId(tx,walletDiff>0?'4102':'5304');
        final je=await _journal(tx,branchId:shift['branch_id'] as int,source:'SHIFT_WALLET_RECONCILIATION',sourceId:shiftId,description:'مطابقة محفظة أثناء إغلاق الوردية');
        if(walletDiff>0){await _journalLine(tx,branchId:shift['branch_id'] as int,entryId:je,accountId:cashGl,dr:walletDiff,memo:'زيادة رصيد محفظة');await _journalLine(tx,branchId:shift['branch_id'] as int,entryId:je,accountId:adjustment,cr:walletDiff,memo:'زيادة رصيد محفظة');}
        else{await _journalLine(tx,branchId:shift['branch_id'] as int,entryId:je,accountId:adjustment,dr:walletDiff.abs(),memo:'عجز رصيد محفظة');await _journalLine(tx,branchId:shift['branch_id'] as int,entryId:je,accountId:cashGl,cr:walletDiff.abs(),memo:'عجز رصيد محفظة');}
        await _cashMove(tx,branchId:shift['branch_id'] as int,accountId:walletId,direction:walletDiff>0?'IN':'OUT',amount:walletDiff.abs(),type:'WALLET_RECONCILIATION',docType:'CASHIER_SHIFT',docId:shiftId,shiftId:shiftId,note:'مطابقة رصيد المحفظة عند إغلاق الوردية');
      }
      await tx.update('cashier_shifts',{'expected_cash':expected,'counted_cash':actual,'diff_amount':difference,'expected_wallets_json':jsonEncode(expectedWallets),'counted_wallets_json':jsonEncode(countedWallets),'counted_denominations_json':jsonEncode(denominations),'diff_handling':diffHandling,'closed_at':_now(),'status':handoverToUserId==null?'CLOSED':'HANDED_OVER','handover_to_user_id':handoverToUserId},where:'id=?',whereArgs:[shiftId]);
      if(difference.abs()>=0.005){await _postShiftDiff(tx,shift:shift,shiftId:shiftId,difference:difference,handling:diffHandling);}
      if(handoverToUserId!=null){final drawerId=shift['drawer_account_id'] as int;await tx.insert('cashier_shifts',{'shift_no':'SH-${DateTime.now().millisecondsSinceEpoch}','user_id':handoverToUserId,'cashier_party_id':shift['cashier_party_id'],'drawer_account_id':drawerId,'work_shift_id':shift['work_shift_id'],'opened_at':_now(),'opening_cash':actual,'status':'OPEN','branch_id':shift['branch_id']});final current=await tx.query('cash_accounts',columns:['current_balance'],where:'id=?',whereArgs:[drawerId],limit:1);await tx.insert('cash_transactions',{'cash_account_id':drawerId,'tx_date':_now(),'direction':'IN','amount':actual,'tx_type':'SHIFT_HANDOVER','doc_type':'CASHIER_SHIFT','doc_id':shiftId,'balance_after':_n(current.first['current_balance']),'note':'تسليم عهدة الوردية إلى كاشير الوردية التالية','branch_id':shift['branch_id']});}
    });
    return difference;
  }

  Future<void> _postShiftDiff(Transaction tx,{required Map<String,Object?> shift,required int shiftId,required double difference,required String handling}) async {
    final branchId=shift['branch_id'] as int;final partyId=shift['cashier_party_id'] as int?;
    final amount=difference.abs();final drawerId=shift['drawer_account_id'] as int;
    if(difference<0&&handling=='POST_TO_CASHIER'){
      if(partyId==null)throw StateError('لا يمكن تحميل العجز دون ربط طرف الكاشير');
      final drawer=await tx.query('cash_accounts',columns:['gl_account_id'],where:'id=?',whereArgs:[drawerId],limit:1);
      final cashGl=drawer.first['gl_account_id'] as int;final receivable=await _glId(tx,'1202');
      final je=await _journal(tx,branchId:branchId,source:'CASHIER_SHORTAGE',sourceId:shiftId,description:'عجز صندوق وردية رقم ${shift['shift_no']}');
      await _journalLine(tx,branchId:branchId,entryId:je,accountId:receivable,dr:amount,partyId:partyId,memo:'عجز صندوق');
      await _journalLine(tx,branchId:branchId,entryId:je,accountId:cashGl,cr:amount,memo:'عجز صندوق');
      await tx.insert('lah_alayh_ledger',{'uuid':_uuid('shift-shortage'),'branch_id':branchId,'created_at':_now(),'updated_at':_now(),'party_id':partyId,'entry_date':_now(),'entry_type':'CASHIER_SHORTAGE','alayh_amount':amount,'lah_amount':0,'doc_type':'CASHIER_SHIFT','doc_id':shiftId,'journal_entry_id':je,'statement_ar':'عجز صندوق وردية رقم ${shift['shift_no']}'});
      await _cashMove(tx,branchId:branchId,accountId:drawerId,direction:'OUT',amount:amount,type:'SHIFT_DIFF',docType:'CASHIER_SHIFT',docId:shiftId,note:'ترحيل عجز الوردية');
    }else if(difference<0&&handling=='EXPENSE'){
      final drawer=await tx.query('cash_accounts',columns:['gl_account_id'],where:'id=?',whereArgs:[drawerId],limit:1);final cashGl=drawer.first['gl_account_id'] as int;final expense=await _glId(tx,'5304');final je=await _journal(tx,branchId:branchId,source:'SHIFT_SHORTAGE_EXPENSE',sourceId:shiftId,description:'عجز صندوق الوردية');await _journalLine(tx,branchId:branchId,entryId:je,accountId:expense,dr:amount,memo:'عجز صندوق');await _journalLine(tx,branchId:branchId,entryId:je,accountId:cashGl,cr:amount,memo:'عجز صندوق');await _cashMove(tx,branchId:branchId,accountId:drawerId,direction:'OUT',amount:amount,type:'SHIFT_DIFF',docType:'CASHIER_SHIFT',docId:shiftId,note:'عجز مسجل كمصروف');
    }else if(difference>0&&handling=='POST_TO_CASHIER'&&partyId!=null){
      final drawer=await tx.query('cash_accounts',columns:['gl_account_id'],where:'id=?',whereArgs:[drawerId],limit:1);
      final cashGl=drawer.first['gl_account_id'] as int;final revenue=await _glId(tx,'4102');
      final je=await _journal(tx,branchId:branchId,source:'CASHIER_SURPLUS',sourceId:shiftId,description:'زيادة صندوق وردية رقم ${shift['shift_no']}');
      await _journalLine(tx,branchId:branchId,entryId:je,accountId:cashGl,dr:amount,memo:'زيادة صندوق');
      await _journalLine(tx,branchId:branchId,entryId:je,accountId:revenue,cr:amount,memo:'زيادة صندوق');
      await tx.insert('lah_alayh_ledger',{'uuid':_uuid('shift-surplus'),'branch_id':branchId,'created_at':_now(),'updated_at':_now(),'party_id':partyId,'entry_date':_now(),'entry_type':'CASHIER_SURPLUS','alayh_amount':0,'lah_amount':amount,'doc_type':'CASHIER_SHIFT','doc_id':shiftId,'journal_entry_id':je,'statement_ar':'زيادة صندوق وردية رقم ${shift['shift_no']}'});
      await _cashMove(tx,branchId:branchId,accountId:drawerId,direction:'IN',amount:amount,type:'SHIFT_DIFF',docType:'CASHIER_SHIFT',docId:shiftId,note:'ترحيل زيادة الوردية');
    }else if(difference<0&&handling=='SUSPENSE'){
      final drawer=await tx.query('cash_accounts',columns:['gl_account_id'],where:'id=?',whereArgs:[drawerId],limit:1);final cashGl=drawer.first['gl_account_id'] as int;final suspense=await _glId(tx,'5304');final je=await _journal(tx,branchId:branchId,source:'SHIFT_SHORTAGE_SUSPENSE',sourceId:shiftId,description:'عجز معلق للوردية ${shift['shift_no']}');await _journalLine(tx,branchId:branchId,entryId:je,accountId:suspense,dr:amount,memo:'عجز معلق');await _journalLine(tx,branchId:branchId,entryId:je,accountId:cashGl,cr:amount,memo:'عجز معلق');await _cashMove(tx,branchId:branchId,accountId:drawerId,direction:'OUT',amount:amount,type:'SHIFT_DIFF',docType:'CASHIER_SHIFT',docId:shiftId,note:'عجز معلق');
    }else if(difference>0&&handling=='EXPENSE'){
      final drawer=await tx.query('cash_accounts',columns:['gl_account_id'],where:'id=?',whereArgs:[drawerId],limit:1);final cashGl=drawer.first['gl_account_id'] as int;final revenue=await _glId(tx,'4102');final je=await _journal(tx,branchId:branchId,source:'SHIFT_SURPLUS_REVENUE',sourceId:shiftId,description:'زيادة صندوق الوردية');await _journalLine(tx,branchId:branchId,entryId:je,accountId:cashGl,dr:amount,memo:'زيادة صندوق');await _journalLine(tx,branchId:branchId,entryId:je,accountId:revenue,cr:amount,memo:'زيادة صندوق');await _cashMove(tx,branchId:branchId,accountId:drawerId,direction:'IN',amount:amount,type:'SHIFT_DIFF',docType:'CASHIER_SHIFT',docId:shiftId,note:'زيادة صندوق');
    }
  }

  Future<int> _glId(DatabaseExecutor tx,String code) async {final r=await tx.query('chart_of_accounts',columns:['id'],where:'code=?',whereArgs:[code],limit:1);if(r.isEmpty)throw StateError('الحساب المحاسبي $code غير موجود');return r.first['id'] as int;}
  Future<int> _journal(DatabaseExecutor tx,{required int branchId,required String source,String? description,int? sourceId}) async=>tx.insert('journal_entries',{'uuid':_uuid('je'),'branch_id':branchId,'created_at':_now(),'updated_at':_now(),'entry_no':'AUTO-${DateTime.now().microsecondsSinceEpoch}','entry_date':_now(),'description':description??source,'source_type':source,'source_id':sourceId,'is_posted':1});
  Future<void> _journalLine(DatabaseExecutor tx,{required int branchId,required int entryId,required int accountId,double dr=0,double cr=0,int? partyId,String? memo}) async {await tx.insert('journal_lines',{'uuid':_uuid('jl'),'branch_id':branchId,'created_at':_now(),'updated_at':_now(),'journal_entry_id':entryId,'account_id':accountId,'party_id':partyId,'dr_amount':dr,'cr_amount':cr,'memo':memo});}
}
