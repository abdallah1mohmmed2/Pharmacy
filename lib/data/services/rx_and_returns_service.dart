// lib/data/services/rx_and_returns_service.dart
import 'dart:math';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/clinical_and_rx_models.dart';
import '../models/drug_model.dart';
import 'clinical_guard_service.dart';

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
  Future<int> dispensePrescription({required int prescriptionId,required Map<int,int> quantitiesByItemId,required int patientPartyId,required int? policyId,required List<({double amount,int? cashAccountId,String method,String? walletRef})> patientPayments,required int pharmacistUserId,Map<int,({String patientName,String patientNationalId,String receiverName,String receiverNationalId,String doctorName,int? batchId})> controlledDetails=const {},required Map<int,double> lineTotalsByItemId}) async {
    final db=await _helper.database;
    return db.transaction((txn) async {
      final rxRows=await txn.query('prescriptions',where:'id=?',whereArgs:[prescriptionId],limit:1);
      if(rxRows.isEmpty)throw StateError('الوصفة غير موجودة');
      final rx=rxRows.first;
      if(DateTime.parse(rx['valid_until'] as String).isBefore(DateTime.now()))throw StateError('انتهت صلاحية الوصفة');
      final items=await txn.query('prescription_items',where:'prescription_id=?',whereArgs:[prescriptionId]);
      var totalPatient=0.0,totalInsurance=0.0;
      Map<String,Object?>? policy;
      if(policyId!=null){final rows=await txn.query('insurance_policies',where:'id=? AND customer_party_id=?',whereArgs:[policyId,patientPartyId],limit:1);if(rows.isEmpty)throw StateError('البوليصة لا تخص هذا العميل');policy=rows.first;if((policy['valid_to'] as String?)!=null&&DateTime.parse(policy['valid_to'] as String).isBefore(DateTime.now()))throw StateError('انتهت صلاحية بوليصة التأمين');}
      for(final item in items){
        final itemId=item['id'] as int;final qty=quantitiesByItemId[itemId]??0;if(qty<=0)continue;
        final remaining=(item['prescribed_qty_units'] as int)-(item['dispensed_qty_units'] as int);if(qty>remaining)throw StateError('الكمية تتجاوز المتبقي في الوصفة');
        final drugRows=await txn.query('drugs',where:'id=?',whereArgs:[item['drug_id']],limit:1);final drug=DrugModel.fromMap(drugRows.first);
        final line=(lineTotalsByItemId[itemId]??0).toDouble();if(line<0)throw StateError('قيمة بند الوصفة غير صحيحة');
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
          final details=controlledDetails[itemId];if(details==null||details.patientName.trim().isEmpty||details.patientNationalId.trim().isEmpty||details.receiverName.trim().isEmpty||details.receiverNationalId.trim().isEmpty||details.doctorName.trim().isEmpty)throw StateError('بيانات الدواء المراقب والهوية والمستلم إلزامية');
          await txn.insert('controlled_drug_log',{'invoice_item_id':null,'drug_id':drug.id,'batch_id':details.batchId,'qty_units':qty,'patient_name':details.patientName,'patient_national_id':details.patientNationalId,'receiver_name':details.receiverName,'receiver_national_id':details.receiverNationalId,'prescription_id':prescriptionId,'doctor_name':details.doctorName,'pharmacist_user_id':pharmacistUserId,'running_balance_units':0});
        }
      }
      if(totalInsurance>0&&policy!=null){
        await txn.update('insurance_policies',{'used_limit':policy['used_limit']},where:'id=?',whereArgs:[policyId]);
        final company=await txn.query('insurance_companies',where:'id=?',whereArgs:[policy['insurance_company_id']],limit:1);final partyId=company.first['party_id'] as int;
        await txn.insert('lah_alayh_ledger',{'uuid':_number('INS'),'branch_id':1,'created_at':DateTime.now().toIso8601String(),'updated_at':DateTime.now().toIso8601String(),'is_deleted':0,'sync_status':'LOCAL','sync_version':1,'party_id':partyId,'entry_date':DateTime.now().toIso8601String(),'entry_type':'INSURANCE_CLAIM','alayh_amount':totalInsurance,'lah_amount':0,'doc_type':'PRESCRIPTION','doc_id':prescriptionId,'statement_ar':'حصة شركة التأمين عن الوصفة ${rx['rx_no']}','journal_entry_id':null});
      }
      final paid=patientPayments.fold<double>(0,(s,p)=>s+p.amount);
      if(paid-totalPatient>0.005)throw StateError('المبلغ المحصل أكبر من حصة المريض');
      for(final payment in patientPayments){
        if(payment.amount<=0)continue;
        if(payment.method=='WALLET'&&(payment.walletRef??'').trim().length<6)throw StateError('رقم إشعار المحفظة إلزامي');
        if(payment.cashAccountId!=null){await txn.rawUpdate('UPDATE cash_accounts SET current_balance=current_balance+? WHERE id=?',[payment.amount,payment.cashAccountId]);}
      }
      final updated=await txn.query('prescription_items',where:'prescription_id=?',whereArgs:[prescriptionId]);
      final allDispensed=updated.every((r)=>(r['dispensed_qty_units'] as int)>=(r['prescribed_qty_units'] as int));
      final anyDispensed=updated.any((r)=>(r['dispensed_qty_units'] as int)>0);
      await txn.update('prescriptions',{'status':allDispensed?'DISPENSED':anyDispensed?'PARTIAL':'OPEN'},where:'id=?',whereArgs:[prescriptionId]);
      return prescriptionId;
    });
  }

  Future<int> createSalesReturn({required int invoiceId,required int invoiceItemId,required int qtyUnits,required double refundAmount,required String reasonCode,required String reasonText,required String refundMethod,required String disposition,required int? approvedBy,required int? cashAccountId,int? batchId,bool openedLiquid=false,String? walletRef}) async {
    if(qtyUnits<=0||refundAmount<0)throw ArgumentError('بيانات المرتجع غير صحيحة');
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
      final actualBatchId=allocation['batch_id'] as int;
      if(disposition=='RESTOCK'&&(drug.requiresRefrigeration||((drug.dosageForm=='SYRUP'||drug.dosageForm=='DROPS')&&openedLiquid)))throw StateError('لا يمكن إعادة الدواء المبرّد أو السائل المفتوح إلى المخزون الصالح؛ اختر الحجر أو الإتلاف');
      final customerId=invoiceRows.first['customer_party_id'] as int?;
      if(refundMethod=='CREDIT_TO_ACCOUNT'&&customerId==null)throw StateError('الفاتورة لا ترتبط بعميل لحساب المرتجع');
      if(refundMethod=='WALLET'&&(walletRef??'').trim().length<6)throw StateError('رقم إشعار المحفظة إلزامي');
      final returnNo=_number('RET');
      final returnId=await txn.insert('sales_returns',{'return_no':returnNo,'return_date':DateTime.now().toIso8601String(),'original_invoice_id':invoiceId,'customer_party_id':customerId,'refund_method':refundMethod,'reason_code':reasonCode,'reason_text':reasonText,'total_refund':refundAmount,'approved_by':approvedBy,'status':'POSTED'});
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
        await txn.update('batches_fefo',{'status':'QUARANTINED','warehouse_id':wh.first['id']},where:'id=?',whereArgs:[actualBatchId]);
        await txn.insert('stock_movements',{'drug_id':drug.id,'batch_id':actualBatchId,'warehouse_id':batch['warehouse_id'],'movement_type':'TRANSFER_OUT','qty_units':-qtyUnits,'unit_cost':batch['unit_cost'],'unit_price':0,'balance_after_units':oldTotal-qtyUnits,'doc_type':'SALES_RETURN','doc_id':returnId,'doc_line_id':invoiceItemId,'movement_at':DateTime.now().toIso8601String(),'note':'تحويل مرتجع إلى الحجر'});
        await txn.insert('stock_movements',{'drug_id':drug.id,'batch_id':actualBatchId,'warehouse_id':wh.first['id'],'movement_type':'TRANSFER_IN','qty_units':qtyUnits,'unit_cost':batch['unit_cost'],'unit_price':0,'balance_after_units':oldTotal,'doc_type':'SALES_RETURN','doc_id':returnId,'doc_line_id':invoiceItemId,'movement_at':DateTime.now().toIso8601String(),'note':'استلام المرتجع في الحجر'});
      }else{
        final newTotal=(oldTotal-qtyUnits).clamp(0,1<<30);
        final unitsPerPack=drug.unitsPerPack??drug.effectiveUnitsPerPack;
        await txn.update('batches_fefo',{'sealed_packs':newTotal~/unitsPerPack,'loose_units':newTotal%unitsPerPack,'total_units':newTotal,'status':newTotal==0?'DISPOSED':'ACTIVE'},where:'id=?',whereArgs:[actualBatchId]);
        await txn.insert('stock_movements',{'drug_id':drug.id,'batch_id':actualBatchId,'warehouse_id':batch['warehouse_id'],'movement_type':'DISPOSAL_OUT','qty_units':-qtyUnits,'unit_cost':batch['unit_cost'],'unit_price':0,'balance_after_units':oldTotal-qtyUnits,'doc_type':'SALES_RETURN','doc_id':returnId,'doc_line_id':invoiceItemId,'movement_at':DateTime.now().toIso8601String(),'note':'إتلاف مرتجع مبيعات'});
        await txn.rawUpdate('UPDATE drugs SET stock_total_units=MAX(0,stock_total_units-?) WHERE id=?',[qtyUnits,drug.id]);
      }
      if(refundMethod=='CREDIT_TO_ACCOUNT'){
        await txn.insert('lah_alayh_ledger',{'uuid':_number('LEDGER'),'branch_id':1,'created_at':DateTime.now().toIso8601String(),'updated_at':DateTime.now().toIso8601String(),'is_deleted':0,'sync_status':'LOCAL','sync_version':1,'party_id':customerId,'entry_date':DateTime.now().toIso8601String(),'entry_type':'SALES_RETURN','alayh_amount':0,'lah_amount':refundAmount,'doc_type':'SALES_RETURN','doc_id':returnId,'journal_entry_id':null,'statement_ar':'إضافة مبلغ لصالح العميل عن مرتجع $returnNo'});
      }else{
        if(cashAccountId==null)throw StateError('اختر الصندوق أو المحفظة لرد المبلغ');
        if(refundMethod=='WALLET'&&walletRef==null)throw StateError('رقم إشعار المحفظة مطلوب');
        await txn.rawUpdate('UPDATE cash_accounts SET current_balance=current_balance-? WHERE id=?',[refundAmount,cashAccountId]);
      }
      return returnId;
    });
  }
  List<String> jsonDecodeSafe(String raw){try{return (jsonDecode(raw) as List).map((e)=>e.toString()).toList();}catch(_){return [];}}
}
