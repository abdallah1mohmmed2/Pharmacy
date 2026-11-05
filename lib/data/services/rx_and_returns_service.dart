// lib/data/services/rx_and_returns_service.dart
import 'dart:math';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/clinical_and_rx_models.dart';
import '../models/drug_model.dart';
import 'clinical_guard_service.dart';
import 'fefo_allocator_service.dart';

class CopayLine {
  const CopayLine({required this.gross,required this.insuranceShare,required this.patientShare,required this.limitExceeded,required this.excluded});
  final double gross,insuranceShare,patientShare;
  final bool limitExceeded,excluded;
}
class RxAndReturnsService {
  RxAndReturnsService({DatabaseHelper? helper,ClinicalGuardService? guard}):_helper=helper??DatabaseHelper.instance,_guard=guard??ClinicalGuardService();
  final DatabaseHelper _helper;
  final ClinicalGuardService _guard;
  String _number(String prefix)=>'$prefix-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(999).toString().padLeft(3,'0')}';

  Future<List<AlternativeDrugModel>> findAlternatives(int drugId,{bool inStockOnly=false,bool cheapestFirst=false}) async {
    final db=await _helper.database;
    final rows=await db.query('v_drug_alternatives',where:'source_drug_id=?'+(inStockOnly?' AND available_units>0':''),whereArgs:[drugId],orderBy:cheapestFirst?'sell_price_pack ASC,match_type ASC':'CASE match_type WHEN \'EXACT\' THEN 0 ELSE 1 END,available_units DESC,sell_price_pack ASC');
    return rows.map(AlternativeDrugModel.fromMap).toList();
  }
  Future<({double coveragePct,double copayPct,double remainingLimit})> policySummary(int policyId) async {
    final rows=await (await _helper.database).query('insurance_policies',where:'id=?',whereArgs:[policyId],limit:1);
    if(rows.isEmpty)throw StateError('بوليصة التأمين غير موجودة');
    final r=rows.first;return (coveragePct:(r['coverage_pct'] as num).toDouble(),copayPct:(r['copay_pct'] as num).toDouble(),remainingLimit:((r['annual_limit'] as num).toDouble()-(r['used_limit'] as num).toDouble()).clamp(0,double.infinity).toDouble());
  }
  Future<CopayLine> calculateCopay({required double lineTotal,required InsurancePolicyModel policy,required String category}) async {
    if(lineTotal<0)throw ArgumentError('قيمة البند غير صحيحة');
    final excluded=(jsonDecodeSafe(policy.excludedCategoriesJson)).contains(category);
    final wanted=excluded?0:lineTotal*policy.coveragePct/100;
    final insurance=wanted.clamp(0,policy.remainingLimit).toDouble();
    return CopayLine(gross:lineTotal,insuranceShare:insurance,patientShare:lineTotal-insurance,limitExceeded:wanted>insurance+0.005,excluded:excluded);
  }
  Future<int> dispensePrescription({required int prescriptionId,required Map<int,int> quantitiesByItemId,required int patientPartyId,required int? policyId,required List<({double amount,int? cashAccountId,String method,String? walletRef})> patientPayments,required int pharmacistUserId,Map<int,({String patientName,String patientNationalId,String receiverName,String receiverNationalId,String doctorName,int? batchId})> controlledDetails=const {},required Map<int,double> lineTotalsByItemId,int branchId=1,ClinicalVerdict? clinicalVerdict}) async {
    if(clinicalVerdict?.hasUnresolvedCritical==true)throw StateError('لا يمكن صرف الوصفة قبل حسم التنبيهات السريرية الحرجة');
    final db=await _helper.database;
    final fefo=FefoAllocator(helper:_helper);
    return db.transaction((txn) async {
      final rxRows=await txn.query('prescriptions',where:'id=?',whereArgs:[prescriptionId],limit:1);
      if(rxRows.isEmpty)throw StateError('الوصفة غير موجودة');
      final rx=rxRows.first;
      if(rx['rx_type']=='CHRONIC_REFILL'&&(rx['refills_used'] as int)>=(rx['refills_allowed'] as int))throw StateError('استنفدت مرات إعادة الصرف المسموحة للوصفة');
      final now=DateTime.now();
      if(DateTime.parse(rx['valid_until'] as String).isBefore(now))throw StateError('انتهت صلاحية الوصفة');
      if((rx['customer_party_id'] as int?)!=null&&(rx['customer_party_id'] as int)!=patientPartyId)throw StateError('الوصفة لا تخص حساب العميل المحدد');
      final items=await txn.query('prescription_items',where:'prescription_id=?',whereArgs:[prescriptionId]);
      if(items.isEmpty)throw StateError('لا توجد بنود في الوصفة');
      Map<String,Object?>? policy;
      if(policyId!=null){
        final rows=await txn.query('insurance_policies',where:'id=? AND customer_party_id=?',whereArgs:[policyId,patientPartyId],limit:1);
        if(rows.isEmpty)throw StateError('البوليصة لا تخص هذا العميل');
        policy=Map<String,Object?>.from(rows.first);
        final from=policy['valid_from'] as String?,to=policy['valid_to'] as String?;
        if(from!=null&&DateTime.parse(from).isAfter(now))throw StateError('لم تبدأ صلاحية بوليصة التأمين بعد');
        if(to!=null&&DateTime.parse(to).isBefore(now))throw StateError('انتهت صلاحية بوليصة التأمين');
      }
      final invoiceNo=_number('RX');
      final invoiceId=await txn.insert('sales_invoices',{'uuid':_number('UUID'),'branch_id':branchId,'created_at':now.toIso8601String(),'updated_at':now.toIso8601String(),'is_deleted':0,'sync_status':'LOCAL','sync_version':1,'invoice_no':invoiceNo,'invoice_date':now.toIso8601String(),'cashier_user_id':pharmacistUserId,'customer_party_id':patientPartyId,'sale_type':'MIXED','status':'COMPLETED','subtotal':0,'discount_pct':0,'discount_amount':0,'rounding_diff':0,'net_total':0,'paid_total':0,'remaining_alayh':0,'total_cost':0});
      var grossTotal=0.0,totalPatient=0.0,totalInsurance=0.0,totalCost=0.0;
      for(final item in items){
        final itemId=item['id'] as int;final qty=quantitiesByItemId[itemId]??0;if(qty<=0)continue;
        final remaining=(item['prescribed_qty_units'] as int)-(item['dispensed_qty_units'] as int);
        if(qty>remaining)throw StateError('الكمية تتجاوز المتبقي في الوصفة');
        final drugRows=await txn.query('drugs',where:'id=?',whereArgs:[item['drug_id']],limit:1);
        if(drugRows.isEmpty)throw StateError('دواء الوصفة غير موجود');
        final drug=DrugModel.fromMap(drugRows.first);
        final line=(lineTotalsByItemId[itemId]??(drug.sellPriceUnit*qty)).toDouble();
        if(line<0)throw StateError('قيمة بند الوصفة غير صحيحة');
        final invoiceItemId=await txn.insert('sales_invoice_items',{'uuid':_number('RXI'),'branch_id':branchId,'created_at':now.toIso8601String(),'updated_at':now.toIso8601String(),'is_deleted':0,'sync_status':'LOCAL','sync_version':1,'invoice_id':invoiceId,'drug_id':drug.id,'sell_unit':'UNIT','qty_in_sell_unit':qty,'qty_units':qty,'unit_price_sell_unit':line/qty,'line_discount_amount':0,'line_total':line,'line_cost':0,'is_substitute':0,'substituted_for_drug_id':null});
        final allocations=await fefo.allocateAndApply(txn:txn,drugId:drug.id!,needUnits:qty,unitsPerPack:drug.unitsPerPack??drug.effectiveUnitsPerPack,invoiceItemId:invoiceItemId,unitPrice:line/qty,docType:'PRESCRIPTION',docId:invoiceId);
        final cost=allocations.fold<double>(0,(s,a)=>s+a.qtyUnits*a.unitCost);
        totalCost+=cost;grossTotal+=line;
        await txn.update('sales_invoice_items',{'line_cost':cost},where:'id=?',whereArgs:[invoiceItemId]);
        var insurance=0.0;
        if(policy!=null){
          final excluded=jsonDecodeSafe(policy['excluded_categories_json'] as String? ?? '[]').contains(drug.categoryId?.toString()??'');
          final requested=excluded?0:line*(policy['coverage_pct'] as num).toDouble()/100;
          final remainingLimit=((policy['annual_limit'] as num).toDouble()-(policy['used_limit'] as num).toDouble()).clamp(0,double.infinity).toDouble();
          insurance=requested.clamp(0,remainingLimit).toDouble();
          policy['used_limit']=(policy['used_limit'] as num).toDouble()+insurance;
        }
        totalInsurance+=insurance;totalPatient+=line-insurance;
        await txn.update('prescription_items',{'dispensed_qty_units':(item['dispensed_qty_units'] as int)+qty},where:'id=?',whereArgs:[itemId]);
        if(drug.isControlled){
          final details=controlledDetails[itemId];
          if(details==null||details.patientName.trim().isEmpty||details.patientNationalId.trim().isEmpty||details.receiverName.trim().isEmpty||details.receiverNationalId.trim().isEmpty||details.doctorName.trim().isEmpty)throw StateError('بيانات الدواء المراقب والهوية والمستلم إلزامية');
          final previous=await txn.rawQuery('SELECT COALESCE(SUM(qty_units),0) AS q FROM controlled_drug_log WHERE drug_id=?',[drug.id]);
          var running=(previous.first['q'] as num).toInt();
          for(final allocation in allocations){
            running+=allocation.qtyUnits;
            await txn.insert('controlled_drug_log',{'invoice_item_id':invoiceItemId,'drug_id':drug.id,'batch_id':allocation.batchId,'qty_units':allocation.qtyUnits,'patient_name':details.patientName,'patient_national_id':details.patientNationalId,'receiver_name':details.receiverName,'receiver_national_id':details.receiverNationalId,'prescription_id':prescriptionId,'doctor_name':details.doctorName,'pharmacist_user_id':pharmacistUserId,'running_balance_units':running});
          }
        }
      }
      if(grossTotal<=0)throw StateError('حدد كمية واحدة على الأقل لصرفها');
      if(policy!=null&&totalInsurance>0){
        await txn.update('insurance_policies',{'used_limit':policy['used_limit']},where:'id=?',whereArgs:[policyId]);
        final company=await txn.query('insurance_companies',where:'id=?',whereArgs:[policy['insurance_company_id']],limit:1);
        if(company.isEmpty)throw StateError('شركة التأمين غير موجودة');
        final insurerParty=company.first['party_id'] as int;
        await txn.insert('lah_alayh_ledger',{'uuid':_number('INS'),'branch_id':branchId,'created_at':now.toIso8601String(),'updated_at':now.toIso8601String(),'is_deleted':0,'sync_status':'LOCAL','sync_version':1,'party_id':insurerParty,'entry_date':now.toIso8601String(),'entry_type':'INSURANCE_CLAIM','alayh_amount':totalInsurance,'lah_amount':0,'doc_type':'PRESCRIPTION','doc_id':invoiceId,'statement_ar':'حصة شركة التأمين عن الوصفة ${rx['rx_no']}','journal_entry_id':null});
      }
      final paid=patientPayments.fold<double>(0,(s,p)=>s+p.amount);
      if(paid-totalPatient>0.005)throw StateError('المبلغ المحصل أكبر من حصة المريض');
      final journalLines=<({int accountId,double debit,double credit,int? partyId,String memo})>[];
      for(final payment in patientPayments){
        if(payment.amount<=0)continue;
        if(payment.cashAccountId==null)throw StateError('اختر الصندوق أو المحفظة لتحصيل حصة المريض');
        if(payment.method=='WALLET'&&(payment.walletRef??'').trim().length<6)throw StateError('رقم إشعار المحفظة إلزامي');
        final cash=await txn.query('cash_accounts',where:'id=?',whereArgs:[payment.cashAccountId],limit:1);
        if(cash.isEmpty)throw StateError('حساب التحصيل غير موجود');
        final kind=cash.first['account_kind'] as String;
        if(payment.method=='WALLET'&&kind!='WALLET')throw StateError('اختر محفظة إلكترونية لطريقة الدفع');
        if(payment.method=='CASH'&&kind=='WALLET')throw StateError('اختر الصندوق النقدي لطريقة الدفع');
        final gl=int.tryParse(cash.first['gl_account_id'].toString());
        if(gl==null)throw StateError('اربط حساب التحصيل بدليل الحسابات');
        await txn.insert('sales_payments',{'uuid':_number('PAY'),'branch_id':branchId,'created_at':now.toIso8601String(),'updated_at':now.toIso8601String(),'is_deleted':0,'sync_status':'LOCAL','sync_version':1,'invoice_id':invoiceId,'cash_account_id':payment.cashAccountId,'method':payment.method,'amount':payment.amount,'wallet_ref_no':payment.walletRef});
        await txn.rawUpdate('UPDATE cash_accounts SET current_balance=current_balance+? WHERE id=?',[payment.amount,payment.cashAccountId]);
        journalLines.add((accountId:gl,debit:payment.amount,credit:0,partyId:null,memo:'تحصيل حصة المريض'));
      }
      final remainingPatient=(totalPatient-paid).clamp(0,double.infinity).toDouble();
      if(remainingPatient>0.005)journalLines.add((accountId:await _accountId(txn,'1201'),debit:remainingPatient,credit:0,partyId:patientPartyId,memo:'المتبقي على المريض عن الوصفة'));
      if(totalInsurance>0&&policy!=null){
        final insurer=await txn.query('insurance_companies',where:'id=?',whereArgs:[policy['insurance_company_id']],limit:1);
        journalLines.add((accountId:await _accountId(txn,'1201'),debit:totalInsurance,credit:0,partyId:insurer.first['party_id'] as int,memo:'مطالبة شركة التأمين'));
      }
      journalLines.add((accountId:await _accountId(txn,'4101'),debit:0,credit:grossTotal,partyId:null,memo:'إيراد صرف وصفة'));
      if(totalCost>0){journalLines.add((accountId:await _accountId(txn,'5101'),debit:totalCost,credit:0,partyId:null,memo:'تكلفة البضاعة المصروفة'));journalLines.add((accountId:await _accountId(txn,'1301'),debit:0,credit:totalCost,partyId:null,memo:'صرف من المخزون'));}
      final journalId=await _postJournalLines(txn,branchId:branchId,description:'صرف الوصفة ${rx['rx_no']}',sourceType:'PRESCRIPTION',sourceId:invoiceId,lines:journalLines);
      if(totalInsurance>0)await txn.update('lah_alayh_ledger',{'journal_entry_id':journalId},where:"doc_type='PRESCRIPTION' AND doc_id=?",whereArgs:[invoiceId]);
      if(remainingPatient>0.005)await txn.insert('lah_alayh_ledger',{'uuid':_number('PAT'),'branch_id':branchId,'created_at':now.toIso8601String(),'updated_at':now.toIso8601String(),'is_deleted':0,'sync_status':'LOCAL','sync_version':1,'party_id':patientPartyId,'entry_date':now.toIso8601String(),'entry_type':'PRESCRIPTION','alayh_amount':remainingPatient,'lah_amount':0,'doc_type':'PRESCRIPTION','doc_id':invoiceId,'journal_entry_id':journalId,'statement_ar':'المتبقي على المريض عن الوصفة ${rx['rx_no']}'});
      await txn.update('sales_invoices',{'subtotal':grossTotal,'net_total':grossTotal,'paid_total':paid,'remaining_alayh':remainingPatient,'total_cost':totalCost,'journal_entry_id':journalId},where:'id=?',whereArgs:[invoiceId]);
      final updated=await txn.query('prescription_items',where:'prescription_id=?',whereArgs:[prescriptionId]);
      final allDispensed=updated.every((r)=>(r['dispensed_qty_units'] as int)>=(r['prescribed_qty_units'] as int));
      final anyDispensed=updated.any((r)=>(r['dispensed_qty_units'] as int)>0);
      await txn.update('prescriptions',{'status':allDispensed?'DISPENSED':anyDispensed?'PARTIAL':'OPEN','refills_used':(rx['rx_type']=='CHRONIC_REFILL'&&allDispensed)?(rx['refills_used'] as int)+1:rx['refills_used']},where:'id=?',whereArgs:[prescriptionId]);
      return invoiceId;
    });
  }

  Future<int> _postJournalLines(Transaction txn,{required int branchId,required String description,required String sourceType,required int sourceId,required List<({int accountId,double debit,double credit,int? partyId,String memo})> lines}) async {
    final debit=lines.fold<double>(0,(s,l)=>s+l.debit),credit=lines.fold<double>(0,(s,l)=>s+l.credit);
    if((debit-credit).abs()>0.005||debit<=0)throw StateError('قيد صرف الوصفة غير متوازن');
    final now=DateTime.now().toIso8601String();
    final id=await txn.insert('journal_entries',{'uuid':_number('RXJE'),'branch_id':branchId,'created_at':now,'updated_at':now,'is_deleted':0,'sync_status':'LOCAL','sync_version':1,'entry_no':_number('RX-JE'),'entry_date':now,'description':description,'source_type':sourceType,'source_id':sourceId,'is_posted':1});
    for(final line in lines){await txn.insert('journal_lines',{'uuid':_number('RXJL'),'branch_id':branchId,'created_at':now,'updated_at':now,'is_deleted':0,'sync_status':'LOCAL','sync_version':1,'journal_entry_id':id,'account_id':line.accountId,'party_id':line.partyId,'dr_amount':line.debit,'cr_amount':line.credit,'memo':line.memo});}
    return id;
  }

  Future<int> createSalesReturn({required int invoiceId,required int invoiceItemId,required int qtyUnits,required double refundAmount,required String reasonCode,required String reasonText,required String refundMethod,required String disposition,required int? approvedBy,required int? cashAccountId,int? batchId,bool openedLiquid=false,String? walletRef}) async {
    if(qtyUnits<=0||refundAmount<=0)throw ArgumentError('يجب أن تكون كمية وقيمة المرتجع أكبر من صفر');
    if(!['CASH','WALLET','CREDIT_TO_ACCOUNT'].contains(refundMethod))throw ArgumentError('طريقة الرد غير مدعومة');
    if(!['RESTOCK','QUARANTINE','DISPOSE'].contains(disposition))throw ArgumentError('قرار فحص التشغيلة غير صحيح');
    final db=await _helper.database;
    return db.transaction((txn) async {
      final invoiceRows=await txn.query('sales_invoices',where:'id=?',whereArgs:[invoiceId],limit:1);if(invoiceRows.isEmpty)throw StateError('الفاتورة الأصلية غير موجودة');
      final itemRows=await txn.query('sales_invoice_items',where:'id=? AND invoice_id=?',whereArgs:[invoiceItemId,invoiceId],limit:1);if(itemRows.isEmpty)throw StateError('بند الفاتورة غير موجود');
      final item=itemRows.first;final drugRows=await txn.query('drugs',where:'id=?',whereArgs:[item['drug_id']],limit:1);if(drugRows.isEmpty)throw StateError('الدواء غير موجود');
      final drug=DrugModel.fromMap(drugRows.first);
      final allocations=await txn.query('sales_invoice_item_batches',where:'invoice_item_id=?'+(batchId==null?'':' AND batch_id=?'),whereArgs:batchId==null?[invoiceItemId]:[invoiceItemId,batchId]);
      if(allocations.isEmpty)throw StateError('لا توجد تشغيلة مرتبطة بهذا البند المباع');
      final allocation=allocations.firstWhere((r)=>(r['qty_units'] as int)>(r['returned_qty_units'] as int),orElse:()=>throw StateError('لا توجد كمية متبقية للإرجاع من هذه التشغيلة'));
      final eligible=(allocation['qty_units'] as int)-(allocation['returned_qty_units'] as int);
      if(qtyUnits>eligible)throw StateError('الكمية المرتجعة تتجاوز الكمية المباعة المتبقية من التشغيلة المحددة');
      final priorRefundRows=await txn.rawQuery('SELECT COALESCE(SUM(refund_amount),0) AS refunded FROM sales_return_items WHERE invoice_item_id=?',[invoiceItemId]);
      final alreadyRefunded=(priorRefundRows.first['refunded'] as num).toDouble();
      final remainingRefund=((item['line_total'] as num).toDouble()-alreadyRefunded).clamp(0,double.infinity).toDouble();
      if(refundAmount>remainingRefund+0.005)throw StateError('قيمة الرد تتجاوز صافي قيمة البند المتبقية بعد المرتجعات السابقة');
      final actualBatchId=allocation['batch_id'] as int;
      if(disposition=='RESTOCK'&&(drug.requiresRefrigeration||((drug.dosageForm=='SYRUP'||drug.dosageForm=='DROPS')&&openedLiquid)))throw StateError('لا يمكن إعادة الدواء المبرّد أو السائل المفتوح إلى المخزون الصالح؛ اختر الحجر أو الإتلاف');
      final customerId=invoiceRows.first['customer_party_id'] as int?;
      if(refundMethod=='CREDIT_TO_ACCOUNT'&&customerId==null)throw StateError('الفاتورة لا ترتبط بعميل لحساب المرتجع');
      if(refundMethod=='WALLET'&&(walletRef??'').trim().length<6)throw StateError('رقم إشعار المحفظة إلزامي');
      final returnNo=_number('RET');
      final returnId=await txn.insert('sales_returns',{'return_no':returnNo,'return_date':DateTime.now().toIso8601String(),'original_invoice_id':invoiceId,'customer_party_id':customerId,'refund_method':refundMethod,'reason_code':reasonCode,'reason_text':reasonText,'total_refund':refundAmount,'approved_by':approvedBy,'wallet_ref_no':walletRef,'status':'POSTED'});
      await txn.insert('sales_return_items',{'sales_return_id':returnId,'invoice_item_id':invoiceItemId,'batch_id':actualBatchId,'qty_units':qtyUnits,'refund_amount':refundAmount,'disposition':disposition,'inspection_note':reasonText});
      await txn.rawUpdate('UPDATE sales_invoice_item_batches SET returned_qty_units=returned_qty_units+? WHERE id=?',[qtyUnits,allocation['id']]);
      final batchRows=await txn.query('batches_fefo',where:'id=?',whereArgs:[actualBatchId],limit:1);final batch=batchRows.first;final oldTotal=(batch['total_units'] as num).toInt();final newTotal=oldTotal+(disposition=='RESTOCK'?qtyUnits:0);
      if(disposition=='RESTOCK'){
        final unitsPerPack=(drug.unitsPerPack??drug.effectiveUnitsPerPack);final newSealed=newTotal~/unitsPerPack;final newLoose=newTotal%unitsPerPack;
        await txn.update('batches_fefo',{'sealed_packs':newSealed,'loose_units':newLoose,'total_units':newTotal,'status':'ACTIVE'},where:'id=?',whereArgs:[actualBatchId]);
        await txn.insert('stock_movements',{'drug_id':drug.id,'batch_id':actualBatchId,'warehouse_id':batch['warehouse_id'],'movement_type':'SALE_RETURN_IN','qty_units':qtyUnits,'unit_cost':batch['unit_cost'],'unit_price':refundAmount/qtyUnits,'balance_after_units':newTotal,'doc_type':'SALES_RETURN','doc_id':returnId,'doc_line_id':invoiceItemId,'movement_at':DateTime.now().toIso8601String(),'note':'إرجاع صالح من فاتورة $invoiceId'});
        await txn.rawUpdate('UPDATE drugs SET stock_total_units=stock_total_units+? WHERE id=?',[qtyUnits,drug.id]);
      }else if(disposition=='QUARANTINE'){
        final wh=await txn.query('warehouses',where:"wh_type='QUARANTINE'",limit:1);if(wh.isEmpty)throw StateError('مستودع الحجر غير موجود');
        final remainingUnits=oldTotal;final unitsPerPack=drug.unitsPerPack??drug.effectiveUnitsPerPack;
        await txn.insert('stock_movements',{'drug_id':drug.id,'batch_id':actualBatchId,'warehouse_id':batch['warehouse_id'],'movement_type':'SALE_RETURN_IN','qty_units':qtyUnits,'unit_cost':batch['unit_cost'],'unit_price':refundAmount/qtyUnits,'balance_after_units':oldTotal+qtyUnits,'doc_type':'SALES_RETURN','doc_id':returnId,'doc_line_id':invoiceItemId,'movement_at':DateTime.now().toIso8601String(),'note':'إثبات استلام المرتجع قبل الحجر'});
        final quarantineBatch=Map<String,Object?>.from(batch)..remove('id');
        quarantineBatch['warehouse_id']=wh.first['id'];quarantineBatch['location_id']=null;quarantineBatch['batch_no']='${batch['batch_no']}-RET-$returnId';quarantineBatch['sealed_packs']=qtyUnits~/unitsPerPack;quarantineBatch['loose_units']=qtyUnits%unitsPerPack;quarantineBatch['total_units']=qtyUnits;quarantineBatch['status']='QUARANTINED';
        final quarantineBatchId=await txn.insert('batches_fefo',quarantineBatch);
        await txn.update('sales_return_items',{'batch_id':quarantineBatchId},where:'sales_return_id=? AND invoice_item_id=?',whereArgs:[returnId,invoiceItemId]);
        await txn.insert('stock_movements',{'drug_id':drug.id,'batch_id':actualBatchId,'warehouse_id':batch['warehouse_id'],'movement_type':'TRANSFER_OUT','qty_units':-qtyUnits,'unit_cost':batch['unit_cost'],'unit_price':0,'balance_after_units':remainingUnits,'doc_type':'SALES_RETURN','doc_id':returnId,'doc_line_id':invoiceItemId,'movement_at':DateTime.now().toIso8601String(),'note':'تحويل الكمية المرتجعة من التشغيلة الأصلية إلى الحجر'});
        await txn.insert('stock_movements',{'drug_id':drug.id,'batch_id':quarantineBatchId,'warehouse_id':wh.first['id'],'movement_type':'TRANSFER_IN','qty_units':qtyUnits,'unit_cost':batch['unit_cost'],'unit_price':0,'balance_after_units':qtyUnits,'doc_type':'SALES_RETURN','doc_id':returnId,'doc_line_id':invoiceItemId,'movement_at':DateTime.now().toIso8601String(),'note':'استلام المرتجع في الحجر'});
        await txn.rawUpdate('UPDATE drugs SET stock_total_units=stock_total_units+? WHERE id=?',[qtyUnits,drug.id]);
      }else{
        await txn.insert('stock_movements',{'drug_id':drug.id,'batch_id':actualBatchId,'warehouse_id':batch['warehouse_id'],'movement_type':'SALE_RETURN_IN','qty_units':qtyUnits,'unit_cost':batch['unit_cost'],'unit_price':refundAmount/qtyUnits,'balance_after_units':oldTotal+qtyUnits,'doc_type':'SALES_RETURN','doc_id':returnId,'doc_line_id':invoiceItemId,'movement_at':DateTime.now().toIso8601String(),'note':'إثبات استلام المرتجع قبل الإتلاف'});
        await txn.insert('stock_movements',{'drug_id':drug.id,'batch_id':actualBatchId,'warehouse_id':batch['warehouse_id'],'movement_type':'DISPOSAL_OUT','qty_units':-qtyUnits,'unit_cost':batch['unit_cost'],'unit_price':0,'balance_after_units':oldTotal,'doc_type':'SALES_RETURN','doc_id':returnId,'doc_line_id':invoiceItemId,'movement_at':DateTime.now().toIso8601String(),'note':'إتلاف مرتجع مبيعات'});
      }
      int? creditAccountId;
      int? refundGlAccountId;
      if(refundMethod=='CREDIT_TO_ACCOUNT'){
        creditAccountId=await _accountId(txn,'1201');
        await txn.insert('lah_alayh_ledger',{'uuid':_number('LEDGER'),'branch_id':1,'created_at':DateTime.now().toIso8601String(),'updated_at':DateTime.now().toIso8601String(),'is_deleted':0,'sync_status':'LOCAL','sync_version':1,'party_id':customerId,'entry_date':DateTime.now().toIso8601String(),'entry_type':'SALES_RETURN','alayh_amount':0,'lah_amount':refundAmount,'doc_type':'SALES_RETURN','doc_id':returnId,'journal_entry_id':null,'statement_ar':'إضافة مبلغ لصالح العميل عن مرتجع $returnNo'});
      }else{
        if(cashAccountId==null)throw StateError('اختر الصندوق أو المحفظة لرد المبلغ');
        if(refundMethod=='WALLET'&&(walletRef??'').trim().length<6)throw StateError('رقم إشعار المحفظة مطلوب');
        final cash=await txn.query('cash_accounts',where:'id=?',whereArgs:[cashAccountId],limit:1);if(cash.isEmpty)throw StateError('حساب رد المبلغ غير موجود');
        final kind=cash.first['account_kind'] as String;
        if(refundMethod=='WALLET'&&kind!='WALLET')throw StateError('اختر محفظة إلكترونية لرد المبلغ');
        if(refundMethod=='CASH'&&kind=='WALLET')throw StateError('اختر صندوقاً نقدياً لرد المبلغ');
        refundGlAccountId=int.tryParse(cash.first['gl_account_id'].toString());
        if(refundGlAccountId==null)throw StateError('اربط حساب الصندوق بدليل الحسابات');
        await txn.rawUpdate('UPDATE cash_accounts SET current_balance=current_balance-? WHERE id=?',[refundAmount,cashAccountId]);
      }
      final jeId=await _postReturnJournal(txn,returnId:returnId,returnNo:returnNo,refundAmount:refundAmount,refundAccountId:creditAccountId??refundGlAccountId!,refundPartyId:creditAccountId==null?null:customerId,inventoryCost:(disposition=='DISPOSE'?0:(batch['unit_cost'] as num).toDouble()*qtyUnits));
      await txn.update('sales_returns',{'journal_entry_id':jeId},where:'id=?',whereArgs:[returnId]);
      await txn.update('lah_alayh_ledger',{'journal_entry_id':jeId},where:"doc_type='SALES_RETURN' AND doc_id=?",whereArgs:[returnId]);
      return returnId;
    });
  }

  Future<int> _accountId(Transaction txn,String code) async {
    final rows=await txn.query('chart_of_accounts',columns:['id'],where:'code=?',whereArgs:[code],limit:1);
    if(rows.isEmpty)throw StateError('الحساب المحاسبي $code غير موجود');
    return rows.first['id'] as int;
  }
  Future<int> _postReturnJournal(Transaction txn,{required int returnId,required String returnNo,required double refundAmount,required int refundAccountId,int? refundPartyId,required double inventoryCost}) async {
    final now=DateTime.now().toIso8601String();
    final je=await txn.insert('journal_entries',{'uuid':_number('JE'),'branch_id':1,'created_at':now,'updated_at':now,'is_deleted':0,'sync_status':'LOCAL','sync_version':1,'entry_no':_number('RET-JE'),'entry_date':now,'description':'قيد مرتجع المبيعات $returnNo','source_type':'SALES_RETURN','source_id':returnId,'is_posted':1});
    final salesReturns=await _accountId(txn,'4101');
    final lines=<({int account,int? party,double dr,double cr,String memo})>[
      (account:salesReturns,party:null,dr:refundAmount,cr:0,memo:'عكس إيراد البيع'),
      (account:refundAccountId,party:refundPartyId,dr:0,cr:refundAmount,memo:'رد قيمة المرتجع'),
    ];
    if(inventoryCost>0){lines.add((account:await _accountId(txn,'1301'),party:null,dr:inventoryCost,cr:0,memo:'إعادة تكلفة البضاعة للمخزون'));lines.add((account:await _accountId(txn,'5101'),party:null,dr:0,cr:inventoryCost,memo:'عكس تكلفة البضاعة المباعة'));}
    for(final line in lines){await txn.insert('journal_lines',{'uuid':_number('JL'),'branch_id':1,'created_at':now,'updated_at':now,'is_deleted':0,'sync_status':'LOCAL','sync_version':1,'journal_entry_id':je,'account_id':line.account,'party_id':line.party,'dr_amount':line.dr,'cr_amount':line.cr,'memo':line.memo});}
    return je;
  }
  List<String> jsonDecodeSafe(String raw){try{return (jsonDecode(raw) as List).map((e)=>e.toString()).toList();}catch(_){return [];}}
}

class SalesReturnService {
  SalesReturnService({DatabaseHelper? helper}):_delegate=RxAndReturnsService(helper:helper);
  final RxAndReturnsService _delegate;
  Future<int> createReturn({required int invoiceId,required int invoiceItemId,required int qtyUnits,required double refundAmount,required String reasonCode,required String reasonText,required String refundMethod,required String disposition,required int? approvedBy,required int? cashAccountId,int? batchId,bool openedLiquid=false,String? walletRef}) =>
    _delegate.createSalesReturn(invoiceId:invoiceId,invoiceItemId:invoiceItemId,qtyUnits:qtyUnits,refundAmount:refundAmount,reasonCode:reasonCode,reasonText:reasonText,refundMethod:refundMethod,disposition:disposition,approvedBy:approvedBy,cashAccountId:cashAccountId,batchId:batchId,openedLiquid:openedLiquid,walletRef:walletRef);
}
