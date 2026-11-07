import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import 'posting_and_sales_service.dart';

class PurchaseLineInput {
  const PurchaseLineInput({required this.drugId,required this.batchNo,required this.expiryDate,required this.warehouseId,required this.qtyPacksPaid,required this.bonusPacks,required this.packPrice,this.locationId,this.lineDiscountPct=0,this.newSellPricePack=0});
  final int drugId,warehouseId,qtyPacksPaid,bonusPacks; final int? locationId;
  final String batchNo,expiryDate; final double packPrice,lineDiscountPct,newSellPricePack;
}

class PurchaseAndBonusService {
  PurchaseAndBonusService({DatabaseHelper? helper,PostingAndSalesService? posting}):_db=helper??DatabaseHelper.instance,_posting=posting??PostingAndSalesService(helper:helper);
  final DatabaseHelper _db; final PostingAndSalesService _posting;
  String _number(String prefix)=>prefix+'-'+DateTime.now().microsecondsSinceEpoch.toString();
  static double calculateWeightedAverage({required double currentPacks,required double currentAverage,required double incomingPacks,required double incomingTotalCost}){
    final total=currentPacks+incomingPacks;
    return total<=0?0:((currentPacks*currentAverage)+incomingTotalCost)/total;
  }

  Future<int> postInvoice({required int branchId,required int supplierPartyId,required int warehouseId,required String invoiceNo,required String paymentType,required double paidTotal,required List<PurchaseLineInput> items,int? cashAccountId,bool includeBonusInCost=true,double discountAmount=0,double taxAmount=0,String? supplierInvoiceNo,int? purchaseOrderId}) async {
    if(items.isEmpty)throw ArgumentError('أضف صنفاً واحداً على الأقل');
    if(!['CASH','CREDIT','PARTIAL'].contains(paymentType))throw ArgumentError('نوع الدفع غير صالح');
    return (await _db.database).transaction((txn)async{
      final supplier=await txn.query('parties',where:"id=? AND party_type='SUPPLIER' AND is_deleted=0",whereArgs:[supplierPartyId]);
      if(supplier.isEmpty)throw StateError('المورد غير موجود');
      Map<int,Map<String,Object?>> orderItemsByDrug={};
      if(purchaseOrderId!=null){
        final orders=await txn.query('purchase_orders',where:"id=? AND supplier_party_id=? AND status IN('DRAFT','PARTIALLY_RECEIVED')",whereArgs:[purchaseOrderId,supplierPartyId],limit:1);
        if(orders.isEmpty)throw StateError('أمر الشراء غير موجود أو تم استلامه بالكامل');
        final orderItems=await txn.query('purchase_order_items',where:'po_id=?',whereArgs:[purchaseOrderId]);
        if(orderItems.isEmpty)throw StateError('أمر الشراء لا يحتوي على أصناف');
        orderItemsByDrug={for(final row in orderItems) row['drug_id'] as int:row};
      }
      final warehouseRows=await txn.query('warehouses',where:'id=?',whereArgs:[warehouseId],limit:1);if(warehouseRows.isEmpty)throw StateError('المستودع المحدد غير موجود');
      final now=DateTime.now().toIso8601String();final today=now.substring(0,10);final prepared=<Map<String,Object?>>[];double subtotal=0;int totalBonus=0;
      for(final item in items){
        if(item.warehouseId!=warehouseId||item.batchNo.trim().isEmpty||item.qtyPacksPaid<=0||item.bonusPacks<0||item.packPrice<0||item.lineDiscountPct<0||item.lineDiscountPct>100)throw ArgumentError('بيانات بند الشراء غير صحيحة');
        if(purchaseOrderId!=null){
          final orderItem=orderItemsByDrug[item.drugId];
          if(orderItem==null)throw StateError('الصنف غير موجود في أمر الشراء');
          final ordered=orderItem['qty_packs'] as int;
          final received=orderItem['received_packs'] as int;
          if(item.qtyPacksPaid>ordered-received)throw StateError('الكمية المستلمة تتجاوز الكمية المتبقية في أمر الشراء');
        }
        final expiry=DateTime.tryParse(item.expiryDate);if(expiry==null||expiry.toIso8601String().substring(0,10)!=item.expiryDate||item.expiryDate.compareTo(today)<0)throw ArgumentError('لا يمكن توريد تشغيلة بصلاحية غير صحيحة أو منتهية');
        final rows=await txn.query('drugs',columns:['units_per_pack','cost_price_pack','stock_total_units','sell_price_pack','requires_refrigeration'],where:'id=? AND is_deleted=0',whereArgs:[item.drugId]);
        if(rows.isEmpty)throw StateError('الصنف غير موجود');
        final drug=rows.first;final units=(drug['units_per_pack'] as int?)??1;if(units<=0)throw StateError('وحدات الباكت غير صالحة');
        if(item.locationId!=null){final shelf=await txn.query('shelf_locations',where:'id=? AND warehouse_id=?',whereArgs:[item.locationId,warehouseId],limit:1);if(shelf.isEmpty)throw StateError('موقع الرف لا يتبع المستودع المحدد');}
        if((drug['requires_refrigeration'] as int? ?? 0)==1){final shelf=item.locationId==null?[]:await txn.query('shelf_locations',where:'id=? AND warehouse_id=? AND is_fridge=1',whereArgs:[item.locationId,warehouseId],limit:1);if(warehouseRows.first['wh_type']!='FRIDGE'||shelf.isEmpty)throw StateError('الدواء المبرد يتطلب مستودعاً ورفاً مبردين');}
        final packs=item.qtyPacksPaid+item.bonusPacks;final lineTotal=item.qtyPacksPaid*item.packPrice*(1-item.lineDiscountPct/100);
        final effective=includeBonusInCost?lineTotal/packs:item.packPrice*(1-item.lineDiscountPct/100);
        final currentPacks=(drug['stock_total_units'] as int)/units;final oldAverage=(drug['cost_price_pack'] as num).toDouble();
        final newAverage=calculateWeightedAverage(currentPacks:currentPacks,currentAverage:oldAverage,incomingPacks:packs.toDouble(),incomingTotalCost:lineTotal);
        subtotal+=lineTotal;totalBonus+=item.bonusPacks;
        prepared.add({'item':item,'units':units,'packs':packs,'lineTotal':lineTotal,'effective':effective,'unitCost':effective/units,'currentPacks':currentPacks,'oldAverage':oldAverage,'newAverage':newAverage,'oldSell':(drug['sell_price_pack'] as num).toDouble()});
      }
      final aggregateByDrug=<int,Map<String,double>>{};
      for(final entry in prepared){
        final item=entry['item'] as PurchaseLineInput;
        final aggregate=aggregateByDrug.putIfAbsent(item.drugId,()=>{'packs':0,'cost':0,'currentPacks':entry['currentPacks'] as double,'oldAverage':entry['oldAverage'] as double});
        aggregate['packs']=(aggregate['packs']??0)+(entry['packs'] as int).toDouble();
        aggregate['cost']=(aggregate['cost']??0)+(entry['lineTotal'] as double);
      }
      for(final entry in prepared){
        final item=entry['item'] as PurchaseLineInput;
        final aggregate=aggregateByDrug[item.drugId]!;
        final oldPacks=aggregate['currentPacks']!;
        final incomingPacks=aggregate['packs']!;
        final denominator=oldPacks+incomingPacks;
        entry['newAverage']=calculateWeightedAverage(currentPacks:oldPacks,currentAverage:aggregate['oldAverage']!,incomingPacks:incomingPacks,incomingTotalCost:aggregate['cost']!);
      }
      if(discountAmount<0||discountAmount>subtotal||taxAmount<0)throw ArgumentError('خصم وضريبة الفاتورة غير صحيحين');
      final net=(subtotal-discountAmount+taxAmount).clamp(0,double.infinity).toDouble();
      if(!['CASH','CREDIT','PARTIAL'].contains(paymentType))throw ArgumentError('نوع الدفع غير مدعوم');
      if(paidTotal<0||paidTotal>net+0.005)throw StateError('المبلغ المدفوع غير صحيح');
      if(paymentType=='PARTIAL'&&(paidTotal<=0||paidTotal>=net))throw StateError('الدفع الجزئي يجب أن يكون أكبر من صفر وأقل من صافي الفاتورة');
      if(paidTotal>0&&cashAccountId==null)throw StateError('حدد الصندوق أو المحفظة');
      if(paymentType=='CASH'&&(paidTotal-net).abs()>0.005)throw StateError('الفاتورة النقدية يجب سدادها بالكامل');
      if(paymentType=='CREDIT'&&paidTotal>0)throw StateError('الفاتورة الآجلة لا تسجل دفعة فورية؛ اختر دفعاً جزئياً');
      final generatedNo=invoiceNo.trim().isEmpty?_number('PINV'):invoiceNo.trim();
      if((await txn.query('purchase_invoices',where:'invoice_no=?',whereArgs:[generatedNo],limit:1)).isNotEmpty)throw StateError('رقم فاتورة الشراء مستخدم مسبقاً');
      if(supplierInvoiceNo!=null&&supplierInvoiceNo.trim().isNotEmpty&&(await txn.query('purchase_invoices',where:'supplier_party_id=? AND supplier_invoice_no=?',whereArgs:[supplierPartyId,supplierInvoiceNo.trim()],limit:1)).isNotEmpty)throw StateError('رقم فاتورة المورد مسجل مسبقاً');
      final remaining=net-paidTotal;
      final invoiceId=await txn.insert('purchase_invoices',{'invoice_no':generatedNo,'supplier_invoice_no':supplierInvoiceNo?.trim(),'supplier_party_id':supplierPartyId,'po_id':purchaseOrderId,'warehouse_id':warehouseId,'invoice_date':now,'payment_type':paymentType,'subtotal':subtotal,'discount_amount':discountAmount,'tax_amount':taxAmount,'net_total':net,'paid_total':paidTotal,'remaining_lah':remaining,'status':'POSTED'});
      for(final p in prepared){
        final item=p['item'] as PurchaseLineInput;final units=p['units'] as int;final packs=p['packs'] as int;final lineTotal=p['lineTotal'] as double;final effective=p['effective'] as double;final unitCost=p['unitCost'] as double;
        final lineId=await txn.insert('purchase_invoice_items',{'invoice_id':invoiceId,'drug_id':item.drugId,'batch_no':item.batchNo,'expiry_date':item.expiryDate,'location_id':item.locationId,'qty_packs_paid':item.qtyPacksPaid,'bonus_packs':item.bonusPacks,'qty_packs_total':packs,'pack_price':item.packPrice,'line_discount_pct':item.lineDiscountPct,'line_total':lineTotal,'effective_pack_cost':effective,'new_sell_price_pack':item.newSellPricePack});
        final oldBatch=await txn.query('batches_fefo',where:'drug_id=? AND warehouse_id=? AND batch_no=? AND expiry_date=?',whereArgs:[item.drugId,warehouseId,item.batchNo,item.expiryDate]);
        int batchId;int balance;final oldBalance=oldBatch.isEmpty?0:(oldBatch.first['total_units'] as int);final paidBalance=oldBalance+item.qtyPacksPaid*units;
        if(oldBatch.isEmpty){balance=packs*units;batchId=await txn.insert('batches_fefo',{'drug_id':item.drugId,'warehouse_id':warehouseId,'location_id':item.locationId,'batch_no':item.batchNo,'expiry_date':item.expiryDate,'sealed_packs':packs,'loose_units':0,'total_units':balance,'unit_cost':unitCost,'pack_cost':effective,'purchase_invoice_item_id':lineId,'status':'ACTIVE'});}
        else{final b=oldBatch.first;batchId=b['id'] as int;balance=(b['total_units'] as int)+packs*units;await txn.update('batches_fefo',{'sealed_packs':(b['sealed_packs'] as int)+packs,'total_units':balance,'unit_cost':unitCost,'pack_cost':effective,'location_id':item.locationId??b['location_id'],'status':'ACTIVE'},where:'id=?',whereArgs:[batchId]);}
        if(item.qtyPacksPaid>0)await _movement(txn,item.drugId,batchId,warehouseId,'PURCHASE_IN',item.qtyPacksPaid*units,unitCost,paidBalance,invoiceId,'توريد مدفوع');
        if(item.bonusPacks>0)await _movement(txn,item.drugId,batchId,warehouseId,'BONUS_IN',item.bonusPacks*units,unitCost,balance,invoiceId,'بونص مجاني');
        final oldAvg=p['oldAverage'] as double;final newAvg=p['newAverage'] as double;final oldSell=p['oldSell'] as double;
        await txn.rawUpdate('UPDATE drugs SET stock_total_units=stock_total_units+?,cost_price_pack=?,last_purchase_cost_pack=?,updated_at=? WHERE id=?',[packs*units,newAvg,effective,now,item.drugId]);
        await txn.insert('price_history',{'drug_id':item.drugId,'change_type':'COST_AVG','old_value':oldAvg,'new_value':newAvg,'source_doc_type':'PURCHASE_INVOICE','source_doc_id':invoiceId,'created_at':now});
        if(item.newSellPricePack>0&&item.newSellPricePack!=oldSell){await txn.update('drugs',{'sell_price_pack':item.newSellPricePack,'updated_at':now},where:'id=?',whereArgs:[item.drugId]);await txn.insert('price_history',{'drug_id':item.drugId,'change_type':'SELL_PRICE','old_value':oldSell,'new_value':item.newSellPricePack,'source_doc_type':'PURCHASE_INVOICE','source_doc_id':invoiceId,'created_at':now});}
      }
      final base={'branch_id':branchId,'created_at':now,'updated_at':now,'is_deleted':0,'sync_status':'LOCAL','sync_version':1};
      await txn.insert('lah_alayh_ledger',{...base,'uuid':'purchase-ledger-'+invoiceId.toString(),'party_id':supplierPartyId,'entry_date':now,'entry_type':'PURCHASE','alayh_amount':0,'lah_amount':net,'doc_type':'PURCHASE_INVOICE','doc_id':invoiceId,'statement_ar':'فاتورة شراء '+generatedNo+' — بونص '+totalBonus.toString()+' باكت'});
      if(paidTotal>0)await txn.insert('lah_alayh_ledger',{...base,'uuid':'purchase-payment-'+invoiceId.toString(),'party_id':supplierPartyId,'entry_date':now,'entry_type':'PAYMENT','alayh_amount':paidTotal,'lah_amount':0,'doc_type':'PURCHASE_INVOICE','doc_id':invoiceId,'statement_ar':'دفعة مسددة لفاتورة المشتريات'});
      final inventory=await _accountId(txn,'1301');final supplierAccount=await _accountId(txn,'2101');
      final lines=<({int accountId,double debit,double credit,int? partyId,String memo})>[(accountId:inventory,debit:net,credit:0,partyId:null,memo:'مخزون مشتريات')];
      if(remaining>0)lines.add((accountId:supplierAccount,debit:0,credit:remaining,partyId:supplierPartyId,memo:'المتبقي للمورد'));
      if(paidTotal>0){final cash=await txn.query('cash_accounts',columns:['gl_account_id'],where:'id=?',whereArgs:[cashAccountId]);if(cash.isEmpty||cash.first['gl_account_id']==null)throw StateError('اربط الصندوق بدليل الحسابات أولاً');lines.add((accountId:cash.first['gl_account_id'] as int,debit:0,credit:paidTotal,partyId:null,memo:'سداد فاتورة مشتريات'));await txn.rawUpdate('UPDATE cash_accounts SET current_balance=current_balance-?,updated_at=? WHERE id=?',[paidTotal,now,cashAccountId]);
        final cashAfterRows=await txn.query('cash_accounts',columns:['current_balance'],where:'id=?',whereArgs:[cashAccountId],limit:1);
        final openShiftRows=await txn.query('cashier_shifts',columns:['id'],where:"branch_id=? AND status='OPEN'",whereArgs:[branchId],orderBy:'id DESC',limit:1);
        await txn.insert('cash_transactions',{'cash_account_id':cashAccountId,'tx_date':now,'direction':'OUT','amount':paidTotal,'tx_type':'PURCHASE_PAYMENT','doc_type':'PURCHASE','doc_id':invoiceId,'cashier_shift_id':openShiftRows.isEmpty?null:openShiftRows.first['id'],'balance_after':(cashAfterRows.first['current_balance'] as num).toDouble(),'note':'سداد فاتورة مشتريات','branch_id':branchId});}
      final journal=await _posting.postBalancedEntry(txn,branchId:branchId,description:'فاتورة مشتريات '+generatedNo,sourceType:'PURCHASE',sourceId:invoiceId,lines:lines);
      await txn.update('purchase_invoices',{'journal_entry_id':journal},where:'id=?',whereArgs:[invoiceId]);
      if(purchaseOrderId!=null){
        for(final entry in prepared){
          final item=entry['item'] as PurchaseLineInput;
          final orderItem=orderItemsByDrug[item.drugId]!;
          await txn.update('purchase_order_items',{'received_packs':(orderItem['received_packs'] as int)+item.qtyPacksPaid},where:'id=?',whereArgs:[orderItem['id']]);
        }
        final pending=await txn.rawQuery('SELECT COUNT(*) pending FROM purchase_order_items WHERE po_id=? AND received_packs<qty_packs',[purchaseOrderId]);
        await txn.update('purchase_orders',{'status':(pending.first['pending'] as int)==0?'RECEIVED':'PARTIALLY_RECEIVED'},where:'id=?',whereArgs:[purchaseOrderId]);
      }
      return invoiceId;
    });
  }

  Future<void> _movement(Transaction txn,int drug,int batch,int warehouse,String type,int qty,double cost,int balance,int invoice,String note) async {
    await txn.insert('stock_movements',{'drug_id':drug,'batch_id':batch,'warehouse_id':warehouse,'movement_type':type,'qty_units':qty,'unit_cost':cost,'balance_after_units':balance,'doc_type':'PURCHASE_INVOICE','doc_id':invoice,'movement_at':DateTime.now().toIso8601String(),'note':note});
  }
  Future<int> _accountId(Transaction txn,String code) async {final rows=await txn.query('chart_of_accounts',columns:['id'],where:'code=?',whereArgs:[code],limit:1);if(rows.isEmpty)throw StateError('الحساب '+code+' غير موجود');return rows.first['id'] as int;}

  Future<int> postPurchaseReturn({required int branchId,required int supplierPartyId,required int batchId,required int qtyUnits,required String reason,required String settlementType,required double agreedCreditValue,int? cashAccountId}) async {
    if(qtyUnits<=0||agreedCreditValue<0||!['CREDIT_NOTE','CASH_REFUND','EXCHANGE_GOODS'].contains(settlementType))throw ArgumentError('بيانات المرتجع غير صحيحة');
    final int cashId=cashAccountId??-1;
    if(settlementType=='CASH_REFUND'&&cashId<0)throw StateError('حدد الصندوق الذي استلم قيمة الاسترداد');
    final db=await _db.database;
    return db.transaction((txn)async{
      final rows=await txn.query('batches_fefo',where:'id=?',whereArgs:[batchId]);
      if(rows.isEmpty)throw StateError('التشغيلة غير موجودة');
      final batch=rows.first;
      if(qtyUnits>(batch['total_units'] as int))throw StateError('كمية المرتجع أكبر من الرصيد المتاح');
      final sourceItem=batch['purchase_invoice_item_id'];
      if(sourceItem!=null){
        final source=await txn.rawQuery('SELECT supplier_party_id FROM purchase_invoice_items i JOIN purchase_invoices p ON p.id=i.invoice_id WHERE i.id=?',[sourceItem]);
        if(source.isNotEmpty&&(source.first['supplier_party_id'] as int)!=supplierPartyId)throw StateError('هذه التشغيلة مرتبطة بمورد آخر');
      }
      final unitCost=(batch['unit_cost'] as num).toDouble();
      final costValue=unitCost*qtyUnits;
      final difference=costValue-agreedCreditValue;
      final creditUnit=agreedCreditValue/qtyUnits;
      final now=DateTime.now().toIso8601String();
      final returnId=await txn.insert('purchase_returns',{
        'return_no':_number('PR'),'supplier_party_id':supplierPartyId,'return_date':now,'reason':reason,
        'settlement_type':settlementType,'total_value':agreedCreditValue,'cost_value':costValue,
        'settlement_difference':difference,'status':settlementType=='EXCHANGE_GOODS'?'PENDING_EXCHANGE':'POSTED'
      });
      await txn.insert('purchase_return_items',{'return_id':returnId,'batch_id':batchId,'qty_units':qtyUnits,'credit_unit_value':creditUnit,'cost_unit_value':unitCost});
      final newTotal=(batch['total_units'] as int)-qtyUnits;
      final drugRows=await txn.query('drugs',columns:['units_per_pack'],where:'id=?',whereArgs:[batch['drug_id']]);
      final units=(drugRows.first['units_per_pack'] as int?)??1;
      final packUnits=(batch['sealed_packs'] as int)*units+(batch['loose_units'] as int)-qtyUnits;
      if(packUnits<0)throw StateError('الرصيد غير كافٍ');
      await txn.update('batches_fefo',{'total_units':newTotal,'sealed_packs':packUnits~/units,'loose_units':packUnits%units,'status':newTotal==0?'DEPLETED':'ACTIVE'},where:'id=?',whereArgs:[batchId]);
      await txn.rawUpdate('UPDATE drugs SET stock_total_units=MAX(0,stock_total_units-?),updated_at=? WHERE id=?',[qtyUnits,now,batch['drug_id']]);
      await txn.insert('stock_movements',{'drug_id':batch['drug_id'],'batch_id':batchId,'warehouse_id':batch['warehouse_id'],'movement_type':'PURCHASE_RETURN_OUT','qty_units':-qtyUnits,'unit_cost':unitCost,'balance_after_units':newTotal,'doc_type':'PURCHASE_RETURN','doc_id':returnId,'movement_at':now,'note':reason});
      int? journalId;
      if(settlementType!='EXCHANGE_GOODS'){
        final supplierAccount=await _accountId(txn,'2101');
        final inventoryAccount=await _accountId(txn,'1301');
        final varianceAccount=await _accountId(txn,'5304');
        int settlementAccount=supplierAccount;
        if(settlementType=='CASH_REFUND'){
          final cashRows=await txn.query('cash_accounts',columns:['gl_account_id'],where:'id=?',whereArgs:[cashId]);
          if(cashRows.isEmpty||cashRows.first['gl_account_id']==null)throw StateError('اربط الصندوق بدليل الحسابات أولاً');
          settlementAccount=(cashRows.first['gl_account_id'] as num).toInt();
          await txn.rawUpdate('UPDATE cash_accounts SET current_balance=current_balance+?,updated_at=? WHERE id=?',[agreedCreditValue,now,cashId]);
          final afterRows=await txn.query('cash_accounts',columns:['current_balance'],where:'id=?',whereArgs:[cashId],limit:1);
          final openShiftRows=await txn.query('cashier_shifts',columns:['id'],where:"branch_id=? AND status='OPEN'",whereArgs:[branchId],orderBy:'id DESC',limit:1);
          await txn.insert('cash_transactions',{'cash_account_id':cashId,'tx_date':now,'direction':'IN','amount':agreedCreditValue,'tx_type':'PURCHASE_PAYMENT','doc_type':'PURCHASE_RETURN','doc_id':returnId,'cashier_shift_id':openShiftRows.isEmpty?null:openShiftRows.first['id'],'balance_after':(afterRows.first['current_balance'] as num).toDouble(),'note':'استرداد نقدي من المورد','branch_id':branchId});
        }
        final lines=<({int accountId,double debit,double credit,int? partyId,String memo})>[];
        lines.add((accountId:settlementAccount,debit:agreedCreditValue,credit:0,partyId:settlementType=='CREDIT_NOTE'?supplierPartyId:null,memo:settlementType=='CREDIT_NOTE'?'إشعار خصم مورد':'استرداد نقدي من المورد'));
        lines.add((accountId:inventoryAccount,debit:0,credit:costValue,partyId:null,memo:'إخراج بضاعة مرتجعة بالتكلفة'));
        if(difference>0)lines.add((accountId:varianceAccount,debit:difference,credit:0,partyId:null,memo:'فرق تكلفة المرتجع'));
        if(difference<0)lines.add((accountId:varianceAccount,debit:0,credit:-difference,partyId:null,memo:'فرق تسوية لصالح المحطة'));
        journalId=await _posting.postBalancedEntry(txn,branchId:branchId,description:'مرتجع مشتريات '+returnId.toString(),sourceType:'PURCHASE_RETURN',sourceId:returnId,lines:lines);
        final base={'branch_id':branchId,'created_at':now,'updated_at':now,'is_deleted':0,'sync_status':'LOCAL','sync_version':1};
        await txn.insert('lah_alayh_ledger',{...base,'uuid':'purchase-return-'+returnId.toString(),'party_id':supplierPartyId,'entry_date':now,'entry_type':'PURCHASE_RETURN','alayh_amount':agreedCreditValue,'lah_amount':0,'doc_type':'PURCHASE_RETURN','doc_id':returnId,'statement_ar':settlementType=='CREDIT_NOTE'?'إشعار خصم مرتجع مشتريات':'استرداد نقدي من المورد'});
        await txn.update('purchase_returns',{'journal_entry_id':journalId},where:'id=?',whereArgs:[returnId]);
      }
      return returnId;
    });
  }

  Future<List<Map<String,Object?>>> shortages() async => _db.rawQuery("""SELECT d.id drug_id,d.trade_name_ar drug_name,d.stock_total_units current_units,d.min_stock_units minimum_units,d.units_per_pack units_per_pack,CASE WHEN COALESCE(d.units_per_pack,1)>0 THEN CAST((MAX(d.min_stock_units*2-d.stock_total_units,0)+d.units_per_pack-1)/d.units_per_pack AS INTEGER) ELSE 0 END suggested_packs,COALESCE((SELECT SUM(-qty_units)*1.0/30 FROM stock_movements m WHERE m.drug_id=d.id AND m.movement_type='SALE_OUT' AND m.movement_at>=datetime('now','-30 day')),0) average_daily_sales,(SELECT pi.supplier_party_id FROM purchase_invoice_items pii JOIN purchase_invoices pi ON pi.id=pii.invoice_id WHERE pii.drug_id=d.id ORDER BY pii.effective_pack_cost ASC LIMIT 1) best_supplier_id,(SELECT p.name_ar FROM purchase_invoice_items pii JOIN purchase_invoices pi ON pi.id=pii.invoice_id JOIN parties p ON p.id=pi.supplier_party_id WHERE pii.drug_id=d.id ORDER BY pii.effective_pack_cost ASC LIMIT 1) best_supplier_name,(SELECT pii.effective_pack_cost FROM purchase_invoice_items pii WHERE pii.drug_id=d.id ORDER BY pii.effective_pack_cost ASC LIMIT 1) effective_pack_cost FROM drugs d WHERE d.is_deleted=0 AND d.is_active=1 AND d.stock_total_units<=d.min_stock_units ORDER BY d.stock_total_units""");
  Future<int> createAutoPurchaseOrder({required int supplierPartyId,required List<({int drugId,int packs,double cost,int bonus})> items}) async {
    if(items.isEmpty)throw ArgumentError('لا توجد أصناف ناقصة لإنشاء أمر شراء');
    final db=await _db.database;
    return db.transaction((txn)async{final now=DateTime.now().toIso8601String();final estimate=items.fold<double>(0,(sum,item)=>sum+item.packs*item.cost);final id=await txn.insert('purchase_orders',{'po_no':_number('PO'),'supplier_party_id':supplierPartyId,'po_date':now,'origin':'AUTO_SHORTAGE','status':'DRAFT','estimated_total':estimate});for(final item in items){if(item.packs<=0)throw ArgumentError('كمية أمر الشراء يجب أن تكون موجبة');await txn.insert('purchase_order_items',{'po_id':id,'drug_id':item.drugId,'qty_packs':item.packs,'expected_cost_pack':item.cost,'expected_bonus_packs':item.bonus});}return id;});
  }
}
