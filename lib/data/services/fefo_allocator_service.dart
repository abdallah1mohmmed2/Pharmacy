import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';

class FefoAllocation {
  const FefoAllocation({required this.batchId,required this.qtyUnits,required this.unitCost,required this.packsOpened});
  final int batchId,qtyUnits,packsOpened;
  final double unitCost;
}

class FefoAllocator {
  FefoAllocator({DatabaseHelper? helper}):_helper=helper??DatabaseHelper.instance;
  final DatabaseHelper _helper;

  Future<List<FefoAllocation>> plan({required int drugId,required int needUnits,required int unitsPerPack,int? warehouseId}) async {
    if(needUnits<=0||unitsPerPack<=0)throw ArgumentError('الكمية ووحدات الباكت يجب أن تكون موجبة');
    final db=await _helper.database;
    final today=DateTime.now().toIso8601String().substring(0,10);
    final rows=await db.rawQuery("SELECT * FROM batches_fefo WHERE drug_id=? AND status='ACTIVE' AND total_units>0 AND expiry_date>=? \${warehouseId==null?'':'AND warehouse_id=?'} ORDER BY expiry_date ASC,id ASC",warehouseId==null?[drugId,today]:[drugId,today,warehouseId]);
    var remaining=needUnits;final result=<FefoAllocation>[];
    for(final row in rows){
      if(remaining<=0)break;
      final available=row['total_units'] as int;final take=available<remaining?available:remaining;
      final loose=row['loose_units'] as int;
      final opened=take>loose?(take-loose+unitsPerPack-1)~/unitsPerPack:0;
      result.add(FefoAllocation(batchId:row['id'] as int,qtyUnits:take,unitCost:(row['unit_cost'] as num).toDouble(),packsOpened:opened));
      remaining-=take;
    }
    if(remaining>0)throw StateError('المخزون الصالح غير كافٍ؛ الكمية الناقصة $remaining حبة');
    return result;
  }

  Future<void> deductFromBatch(Transaction txn,{required int batchId,required int needUnits,required int unitsPerPack,required int invoiceItemId,required int drugId,required int warehouseId,double unitPrice=0,String docType='SALE',int? docId}) async {
    if(needUnits<=0||unitsPerPack<=0)throw ArgumentError('كمية الخصم غير صالحة');
    final rows=await txn.rawQuery("SELECT * FROM batches_fefo WHERE id=? AND status='ACTIVE' AND expiry_date>=?",[batchId,DateTime.now().toIso8601String().substring(0,10)]);
    if(rows.isEmpty)throw StateError('التشغيلة غير متاحة أو منتهية الصلاحية');
    final batch=rows.first;final sealed=batch['sealed_packs'] as int;final loose=batch['loose_units'] as int;final available=batch['total_units'] as int;
    if(needUnits>available)throw StateError('الكمية المطلوبة أكبر من رصيد التشغيلة');
    final shortfall=needUnits-loose;final opened=shortfall>0?(shortfall+unitsPerPack-1)~/unitsPerPack:0;
    final newSealed=sealed-opened;final newLoose=loose+(opened*unitsPerPack)-needUnits;
    if(newSealed<0||newLoose<0||newLoose>=unitsPerPack)throw StateError('بيانات الباكت المفتوح غير متوافقة مع وحدات التعبئة');
    final balance=available-needUnits;final now=DateTime.now().toIso8601String();final cost=(batch['unit_cost'] as num).toDouble();
    if(opened>0){
      await txn.insert('stock_movements',{'drug_id':drugId,'batch_id':batchId,'warehouse_id':warehouseId,'movement_type':'PACK_OPEN','qty_units':0,'unit_cost':cost,'balance_after_units':available,'movement_at':now,'doc_type':docType,'doc_id':docId,'note':'فتح $opened باكت'});
    }
    await txn.update('batches_fefo',{'sealed_packs':newSealed,'loose_units':newLoose,'total_units':balance,'status':balance==0?'DEPLETED':'ACTIVE'},where:'id=?',whereArgs:[batchId]);
    await txn.insert('stock_movements',{'drug_id':drugId,'batch_id':batchId,'warehouse_id':warehouseId,'movement_type':'SALE_OUT','qty_units':-needUnits,'unit_cost':cost,'unit_price':unitPrice,'balance_after_units':balance,'movement_at':now,'doc_type':docType,'doc_id':docId});
    await txn.insert('sales_invoice_item_batches',{'invoice_item_id':invoiceItemId,'batch_id':batchId,'qty_units':needUnits,'unit_cost':cost});
    await txn.rawUpdate('UPDATE drugs SET stock_total_units=MAX(0,stock_total_units-?),updated_at=? WHERE id=?',[needUnits,now,drugId]);
  }

  Future<List<FefoAllocation>> allocateAndApply({required Transaction txn,required int drugId,required int needUnits,required int unitsPerPack,required int invoiceItemId,int? warehouseId,double unitPrice=0,String docType='SALE',int? docId}) async {
    final today=DateTime.now().toIso8601String().substring(0,10);
    final rows=await txn.rawQuery("SELECT b.* FROM batches_fefo b JOIN warehouses w ON w.id=b.warehouse_id WHERE b.drug_id=? AND b.status='ACTIVE' AND b.total_units>0 AND b.expiry_date>=? AND w.is_sellable=1 ${warehouseId==null?'':'AND b.warehouse_id=?'} ORDER BY b.expiry_date ASC,b.id ASC",warehouseId==null?[drugId,today]:[drugId,today,warehouseId]);
    var remaining=needUnits;final allocations=<FefoAllocation>[];
    for(final row in rows){
      if(remaining==0)break;
      final available=row['total_units'] as int;final take=available<remaining?available:remaining;final loose=row['loose_units'] as int;
      final opened=take>loose?(take-loose+unitsPerPack-1)~/unitsPerPack:0;
      allocations.add(FefoAllocation(batchId:row['id'] as int,qtyUnits:take,unitCost:(row['unit_cost'] as num).toDouble(),packsOpened:opened));
      await deductFromBatch(txn,batchId:row['id'] as int,needUnits:take,unitsPerPack:unitsPerPack,invoiceItemId:invoiceItemId,drugId:drugId,warehouseId:row['warehouse_id'] as int,unitPrice:unitPrice,docType:docType,docId:docId);
      remaining-=take;
    }
    if(remaining>0)throw StateError('المخزون الصالح غير كافٍ؛ المتبقي $remaining حبة');
    return allocations;
  }

  Future<void> reverseReturnAllocation(Transaction txn,{required int invoiceItemId,required int qtyUnits,String docType='SALE_RETURN',int? docId}) async {
    if(qtyUnits<=0)throw ArgumentError('كمية المرتجع غير صالحة');
    final rows=await txn.query('sales_invoice_item_batches',where:'invoice_item_id=? AND returned_qty_units<qty_units',whereArgs:[invoiceItemId],orderBy:'id DESC');
    var remaining=qtyUnits;final now=DateTime.now().toIso8601String();
    for(final row in rows){
      if(remaining==0)break;
      final available=(row['qty_units'] as int)-(row['returned_qty_units'] as int);final give=available<remaining?available:remaining;
      final batchId=row['batch_id'] as int;final batches=await txn.query('batches_fefo',where:'id=?',whereArgs:[batchId]);
      if(batches.isEmpty)throw StateError('التشغيلة الأصلية غير موجودة');
      final batch=batches.first;final newTotal=(batch['total_units'] as int)+give;final unitCost=(row['unit_cost'] as num).toDouble();
      final units=await txn.query('drugs',columns:['units_per_pack'],where:'id=?',whereArgs:[batch['drug_id']]);final upp=(units.first['units_per_pack'] as int?)??1;
      final loose=(batch['loose_units'] as int)+give;final sealed=(batch['sealed_packs'] as int)+(loose~/upp);final normalizedLoose=loose%upp;
      await txn.update('batches_fefo',{'total_units':newTotal,'loose_units':normalizedLoose,'sealed_packs':sealed,'status':'ACTIVE'},where:'id=?',whereArgs:[batchId]);
      await txn.update('sales_invoice_item_batches',{'returned_qty_units':(row['returned_qty_units'] as int)+give},where:'id=?',whereArgs:[row['id']]);
      await txn.insert('stock_movements',{'drug_id':batch['drug_id'],'batch_id':batchId,'warehouse_id':batch['warehouse_id'],'movement_type':'SALE_RETURN_IN','qty_units':give,'unit_cost':unitCost,'balance_after_units':newTotal,'doc_type':docType,'doc_id':docId,'movement_at':now});
      await txn.rawUpdate('UPDATE drugs SET stock_total_units=stock_total_units+?,updated_at=? WHERE id=?',[give,now,batch['drug_id']]);
      remaining-=give;
    }
    if(remaining>0)throw StateError('كمية المرتجع تتجاوز الكمية المباعة غير المرتجعة');
  }
}
