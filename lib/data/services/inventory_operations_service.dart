import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';

class InventoryOperationsService {
  InventoryOperationsService({DatabaseHelper? helper}):_db=helper??DatabaseHelper.instance;
  final DatabaseHelper _db;
  String _number(String prefix)=>prefix+'-'+DateTime.now().microsecondsSinceEpoch.toString();

  Future<int> createStocktaking({required int warehouseId,bool blind=false,String scope='WAREHOUSE'}) async {
    final db=await _db.database;
    return db.transaction((txn)async{
      final now=DateTime.now().toIso8601String();
      final id=await txn.insert('stocktaking_sessions',{'session_no':_number('STK'),'warehouse_id':warehouseId,'scope_type':scope,'blind_count':blind?1:0,'status':'COUNTING','created_at':now});
      final batches=await txn.query('batches_fefo',where:'warehouse_id=? AND total_units>0',whereArgs:[warehouseId]);
      for(final batch in batches){await txn.insert('stocktaking_lines',{'session_id':id,'batch_id':batch['id'],'system_units':batch['total_units'],'counted_packs':0,'counted_loose_units':0,'counted_units':0,'diff_units':0,'unit_cost':batch['unit_cost']});}
      return id;
    });
  }

  Future<void> countBatch({required int sessionId,required int batchId,required int countedPacks,required int countedLooseUnits,required int unitsPerPack,String reason=''}) async {
    if(countedPacks<0||countedLooseUnits<0||unitsPerPack<=0||countedLooseUnits>=unitsPerPack)throw ArgumentError('العد الفعلي غير صحيح');
    final db=await _db.database;
    final rows=await db.rawQuery("SELECT l.id,l.system_units,l.unit_cost FROM stocktaking_lines l JOIN stocktaking_sessions s ON s.id=l.session_id WHERE l.session_id=? AND l.batch_id=? AND s.status='COUNTING'",[sessionId,batchId]);
    if(rows.isEmpty)throw StateError('جلسة الجرد أو التشغيلة غير متاحة');
    final counted=countedPacks*unitsPerPack+countedLooseUnits;final diff=counted-(rows.first['system_units'] as int);final cost=(rows.first['unit_cost'] as num).toDouble();
    await db.update('stocktaking_lines',{'counted_packs':countedPacks,'counted_loose_units':countedLooseUnits,'counted_units':counted,'diff_units':diff,'diff_value':diff*cost,'reason_code':reason},where:'id=?',whereArgs:[rows.first['id']]);
  }

  Future<void> approveStocktaking({required int sessionId,required int managerUserId,int branchId=1}) async {
    final db=await _db.database;
    await db.transaction((txn)async{
      final sessions=await txn.query('stocktaking_sessions',where:"id=? AND status IN('COUNTING','REVIEW')",whereArgs:[sessionId]);
      if(sessions.isEmpty)throw StateError('جلسة الجرد غير قابلة للاعتماد');
      final lines=await txn.query('stocktaking_lines',where:'session_id=?',whereArgs:[sessionId]);final now=DateTime.now().toIso8601String();
      double surplus=0,shortage=0;
      for(final line in lines){
        final diff=line['diff_units'] as int;if(diff==0)continue;
        final batchRows=await txn.query('batches_fefo',where:'id=?',whereArgs:[line['batch_id']]);if(batchRows.isEmpty)throw StateError('تشغيلة الجرد غير موجودة');final batch=batchRows.first;
        final newUnits=line['counted_units'] as int;final cost=(line['unit_cost'] as num).toDouble();
        await txn.update('batches_fefo',{'sealed_packs':line['counted_packs'],'loose_units':line['counted_loose_units'],'total_units':newUnits,'status':newUnits==0?'DEPLETED':'ACTIVE'},where:'id=?',whereArgs:[line['batch_id']]);
        await txn.insert('stock_movements',{'drug_id':batch['drug_id'],'batch_id':batch['id'],'warehouse_id':batch['warehouse_id'],'movement_type':diff>0?'STOCKTAKE_SURPLUS':'STOCKTAKE_SHORTAGE','qty_units':diff,'unit_cost':cost,'balance_after_units':newUnits,'movement_at':now,'doc_type':'STOCKTAKING','doc_id':sessionId,'note':line['reason_code']});
        await txn.rawUpdate('UPDATE drugs SET stock_total_units=MAX(0,stock_total_units+?),updated_at=? WHERE id=?',[diff,now,batch['drug_id']]);
        if(diff>0)surplus+=diff*cost;else shortage+=(-diff)*cost;
      }
      if(surplus>0||shortage>0){
        final inventory=await _accountId(txn,'1301');final variance=await _accountId(txn,'5303');
        final linesJournal=<Map<String,Object?>>[];
        if(surplus>0){linesJournal.add({'account_id':inventory,'dr_amount':surplus,'cr_amount':0,'memo':'زيادة جرد'});linesJournal.add({'account_id':variance,'dr_amount':0,'cr_amount':surplus,'memo':'فروقات جرد زيادة'});}
        if(shortage>0){linesJournal.add({'account_id':variance,'dr_amount':shortage,'cr_amount':0,'memo':'عجز جرد'});linesJournal.add({'account_id':inventory,'dr_amount':0,'cr_amount':shortage,'memo':'تخفيض مخزون بالعجز'});}
        await _insertJournal(txn,branchId:branchId,sourceType:'STOCKTAKING',sourceId:sessionId,description:'اعتماد جلسة الجرد',lines:linesJournal);
      }
      await txn.update('stocktaking_sessions',{'status':'APPROVED','approved_at':now,'approved_by':managerUserId},where:'id=?',whereArgs:[sessionId]);
    });
  }

  Future<int> createDisposal({required int branchId,required String reason,required String method,required String witnessName,String authorityRef='',required List<({int batchId,int qtyUnits})> items}) async {
    if(items.isEmpty)throw ArgumentError('اختر تشغيلات للإعدام');
    final db=await _db.database;
    return db.transaction((txn)async{
      final now=DateTime.now().toIso8601String();double total=0;final prepared=<Map<String,Object?>>[];
      for(final item in items){
        if(item.qtyUnits<=0)throw ArgumentError('كمية الإعدام غير صحيحة');
        final rows=await txn.query('batches_fefo',where:'id=?',whereArgs:[item.batchId]);if(rows.isEmpty||item.qtyUnits>(rows.first['total_units'] as int))throw StateError('كمية الإعدام تتجاوز المتاح');
        final batch=rows.first;final cost=(batch['unit_cost'] as num).toDouble();total+=item.qtyUnits*cost;prepared.add({'input':item,'batch':batch,'cost':cost});
      }
      final id=await txn.insert('disposals',{'disposal_no':_number('DSP'),'disposal_date':now,'reason':reason,'method':method,'authority_ref':authorityRef,'witness_name':witnessName,'status':'APPROVED','total_cost_value':total});
      for(final p in prepared){
        final item=p['input'] as ({int batchId,int qtyUnits});final batch=p['batch'] as Map<String,Object?>;final qty=item.qtyUnits;final cost=p['cost'] as double;final remain=(batch['total_units'] as int)-qty;
        final drugRows=await txn.query('drugs',columns:['units_per_pack'],where:'id=?',whereArgs:[batch['drug_id']]);final upp=(drugRows.first['units_per_pack'] as int?)??1;
        final totalPacks=(batch['sealed_packs'] as int)*upp+(batch['loose_units'] as int)-qty;if(totalPacks<0)throw StateError('رصيد التشغيلة غير كافٍ');
        await txn.insert('disposal_items',{'disposal_id':id,'batch_id':item.batchId,'qty_units':qty,'unit_cost':cost});
        await txn.update('batches_fefo',{'total_units':remain,'sealed_packs':totalPacks~/upp,'loose_units':totalPacks%upp,'status':remain==0?'DISPOSED':'ACTIVE'},where:'id=?',whereArgs:[item.batchId]);
        await txn.insert('stock_movements',{'drug_id':batch['drug_id'],'batch_id':item.batchId,'warehouse_id':batch['warehouse_id'],'movement_type':'DISPOSAL_OUT','qty_units':-qty,'unit_cost':cost,'balance_after_units':remain,'movement_at':now,'doc_type':'DISPOSAL','doc_id':id});
        await txn.rawUpdate('UPDATE drugs SET stock_total_units=MAX(0,stock_total_units-?),updated_at=? WHERE id=?',[qty,now,batch['drug_id']]);
      }
      final inventory=await _accountId(txn,'1301');final loss=await _accountId(txn,'5102');
      final journal=await _insertJournal(txn,branchId:branchId,sourceType:'DISPOSAL',sourceId:id,description:'محضر إعدام '+id.toString(),lines:[{'account_id':loss,'dr_amount':total,'cr_amount':0,'memo':'خسارة إعدام'}, {'account_id':inventory,'dr_amount':0,'cr_amount':total,'memo':'تخفيض مخزون تالف'}]);
      await txn.update('disposals',{'journal_entry_id':journal},where:'id=?',whereArgs:[id]);
      return id;
    });
  }

  Future<int> createTransfer({required int fromWarehouseId,required int toWarehouseId,required List<({int batchId,int qtyUnits})> items}) async {
    if(fromWarehouseId==toWarehouseId||items.isEmpty)throw ArgumentError('بيانات التحويل غير صحيحة');
    final db=await _db.database;
    return db.transaction((txn)async{
      final now=DateTime.now().toIso8601String();final id=await txn.insert('stock_transfers',{'transfer_no':_number('TRF'),'transfer_type':'WAREHOUSE','from_warehouse_id':fromWarehouseId,'to_warehouse_id':toWarehouseId,'status':'DRAFT','created_at':now});
      for(final item in items){final rows=await txn.query('batches_fefo',where:'id=? AND warehouse_id=?',whereArgs:[item.batchId,fromWarehouseId]);if(rows.isEmpty||item.qtyUnits<=0||item.qtyUnits>(rows.first['total_units'] as int))throw StateError('كمية التحويل غير متاحة');final drugRows=await txn.query('drugs',columns:['requires_refrigeration'],where:'id=?',whereArgs:[rows.first['drug_id']]);final cold=(drugRows.first['requires_refrigeration'] as int? ?? 0)==1;final destination=await txn.query('warehouses',columns:['wh_type'],where:'id=?',whereArgs:[toWarehouseId]);if(destination.isEmpty||(cold&&destination.first['wh_type']!='FRIDGE'))throw StateError('لا يمكن نقل الدواء المبرد إلا إلى مستودع ثلاجة');await txn.insert('stock_transfer_items',{'transfer_id':id,'from_batch_id':item.batchId,'qty_units':item.qtyUnits,'unit_cost':rows.first['unit_cost']});}
      return id;
    });
  }

  Future<void> dispatchTransfer(int transferId) async {
    final db=await _db.database;
    await db.transaction((txn)async{
      final transfers=await txn.query('stock_transfers',where:"id=? AND status='DRAFT'",whereArgs:[transferId]);if(transfers.isEmpty)throw StateError('التحويل غير جاهز للإرسال');
      final items=await txn.query('stock_transfer_items',where:'transfer_id=?',whereArgs:[transferId]);final now=DateTime.now().toIso8601String();
      for(final item in items){final rows=await txn.query('batches_fefo',where:'id=?',whereArgs:[item['from_batch_id']]);final batch=rows.first;final qty=item['qty_units'] as int;final remaining=(batch['total_units'] as int)-qty;if(remaining<0)throw StateError('رصيد التشغيلة غير كافٍ');final drugRows=await txn.query('drugs',columns:['units_per_pack'],where:'id=?',whereArgs:[batch['drug_id']]);final upp=(drugRows.first['units_per_pack'] as int?)??1;final total=(batch['sealed_packs'] as int)*upp+(batch['loose_units'] as int)-qty;await txn.update('batches_fefo',{'total_units':remaining,'sealed_packs':total~/upp,'loose_units':total%upp,'status':remaining==0?'DEPLETED':'ACTIVE'},where:'id=?',whereArgs:[batch['id']]);await txn.insert('stock_movements',{'drug_id':batch['drug_id'],'batch_id':batch['id'],'warehouse_id':batch['warehouse_id'],'movement_type':'TRANSFER_OUT','qty_units':-qty,'unit_cost':item['unit_cost'],'balance_after_units':remaining,'movement_at':now,'doc_type':'TRANSFER','doc_id':transferId});await txn.rawUpdate('UPDATE drugs SET stock_total_units=stock_total_units-?,updated_at=? WHERE id=?',[qty,now,batch['drug_id']]);}
      await txn.update('stock_transfers',{'status':'IN_TRANSIT'},where:'id=?',whereArgs:[transferId]);
    });
  }

  Future<void> receiveTransfer(int transferId,{Map<int,int>? receivedByItem}) async {
    final db=await _db.database;
    await db.transaction((txn)async{
      final rows=await txn.query('stock_transfers',where:"id=? AND status='IN_TRANSIT'",whereArgs:[transferId]);
      if(rows.isEmpty)throw StateError('التحويل ليس قيد النقل');
      final destination=rows.first['to_warehouse_id'] as int;
      final items=await txn.query('stock_transfer_items',where:'transfer_id=?',whereArgs:[transferId]);
      final now=DateTime.now().toIso8601String();
      for(final item in items){
        final qty=receivedByItem?[item['id'] as int]??(item['qty_units'] as int);
        if(qty<0||qty>(item['qty_units'] as int))throw StateError('كمية الاستلام غير صحيحة');
        final source=(await txn.query('batches_fefo',where:'id=?',whereArgs:[item['from_batch_id']])).first;
        final drugRows=await txn.query('drugs',columns:['units_per_pack'],where:'id=?',whereArgs:[source['drug_id']]);
        final units=(drugRows.first['units_per_pack'] as int?)??1;
        int? batchId;
        int balance=0;
        if(qty>0){
          final existing=await txn.query('batches_fefo',where:'drug_id=? AND warehouse_id=? AND batch_no=? AND expiry_date=?',whereArgs:[source['drug_id'],destination,source['batch_no'],source['expiry_date']]);
          final total=(existing.isEmpty?0:(existing.first['total_units'] as int))+qty;
          balance=total;
          final shelf=await txn.query('shelf_locations',columns:['id'],where:'warehouse_id=?',whereArgs:[destination],limit:1);
          if(existing.isEmpty){
            batchId=await txn.insert('batches_fefo',{'drug_id':source['drug_id'],'warehouse_id':destination,'location_id':shelf.isEmpty?null:shelf.first['id'],'batch_no':source['batch_no'],'expiry_date':source['expiry_date'],'manufacture_date':source['manufacture_date'],'sealed_packs':total~/units,'loose_units':total%units,'total_units':total,'unit_cost':item['unit_cost'],'pack_cost':source['pack_cost'],'status':'ACTIVE'});
          }else{
            batchId=existing.first['id'] as int;
            await txn.update('batches_fefo',{'sealed_packs':total~/units,'loose_units':total%units,'total_units':total,'status':'ACTIVE'},where:'id=?',whereArgs:[batchId]);
          }
          await txn.insert('stock_movements',{'drug_id':source['drug_id'],'batch_id':batchId,'warehouse_id':destination,'movement_type':'TRANSFER_IN','qty_units':qty,'unit_cost':item['unit_cost'],'balance_after_units':balance,'movement_at':now,'doc_type':'TRANSFER','doc_id':transferId});
          await txn.rawUpdate('UPDATE drugs SET stock_total_units=stock_total_units+?,updated_at=? WHERE id=?',[qty,now,source['drug_id']]);
        }
        await txn.update('stock_transfer_items',{'to_batch_id':batchId,'received_qty_units':qty},where:'id=?',whereArgs:[item['id']]);
      }
      await txn.update('stock_transfers',{'status':'RECEIVED','received_at':now},where:'id=?',whereArgs:[transferId]);
    });
  }
  Future<int> recordTemperature({required int warehouseId,required double tempC,double? humidityPct,int? userId,String correctiveAction=''}) async {
    final db=await _db.database;return db.insert('cold_chain_log',{'warehouse_id':warehouseId,'reading_at':DateTime.now().toIso8601String(),'temp_c':tempC,'humidity_pct':humidityPct,'is_out_of_range':tempC<2||tempC>8?1:0,'corrective_action':correctiveAction,'recorded_by':userId});
  }

  Future<int> _accountId(Transaction txn,String code) async {final rows=await txn.query('chart_of_accounts',columns:['id'],where:'code=?',whereArgs:[code],limit:1);if(rows.isEmpty)throw StateError('الحساب '+code+' غير موجود');return rows.first['id'] as int;}
  Future<int> _insertJournal(Transaction txn,{required int branchId,required String sourceType,required int sourceId,required String description,required List<Map<String,Object?>> lines}) async {
    final now=DateTime.now().toIso8601String();final debit=lines.fold<double>(0,(sum,line)=>sum+(line['dr_amount'] as num).toDouble());final credit=lines.fold<double>(0,(sum,line)=>sum+(line['cr_amount'] as num).toDouble());if((debit-credit).abs()>0.005||debit<=0)throw StateError('القيد المحاسبي غير متوازن');
    final id=await txn.insert('journal_entries',{'uuid':'inv-je-'+DateTime.now().microsecondsSinceEpoch.toString(),'branch_id':branchId,'created_at':now,'updated_at':now,'entry_no':_number('JE'),'entry_date':now,'description':description,'source_type':sourceType,'source_id':sourceId,'is_posted':1});
    for(final line in lines){await txn.insert('journal_lines',{'uuid':'inv-jl-'+DateTime.now().microsecondsSinceEpoch.toString(),'branch_id':branchId,'created_at':now,'updated_at':now,'journal_entry_id':id,'account_id':line['account_id'],'dr_amount':line['dr_amount'],'cr_amount':line['cr_amount'],'memo':line['memo']});}
    return id;
  }
}
