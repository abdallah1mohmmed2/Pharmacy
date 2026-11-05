import 'package:flutter/foundation.dart';
import '../data/database/database_helper.dart';
import '../data/models/inventory_and_purchase_models.dart';
import '../data/services/fefo_allocator_service.dart';
import '../data/services/inventory_operations_service.dart';
import '../data/services/purchase_and_bonus_service.dart';

class InventoryAndPurchaseProvider extends ChangeNotifier {
  InventoryAndPurchaseProvider({DatabaseHelper? database,FefoAllocator? fefo,InventoryOperationsService? operations,PurchaseAndBonusService? purchases})
      :_db=database??DatabaseHelper.instance,_fefo=fefo??FefoAllocator(helper:database),_operations=operations??InventoryOperationsService(helper:database),_purchases=purchases??PurchaseAndBonusService(helper:database);
  final DatabaseHelper _db;final FefoAllocator _fefo;final InventoryOperationsService _operations;final PurchaseAndBonusService _purchases;
  int branchId=1;bool loading=false;String? error;
  List<WarehouseModel> warehouses=[];List<ShelfLocationModel> shelves=[];List<BatchFefoModel> batches=[];
  List<StocktakingSessionModel> stocktaking=[];List<DisposalModel> disposals=[];List<StockTransferModel> transfers=[];
  List<PurchaseInvoiceModel> purchaseInvoices=[];List<ShortageItemModel> shortages=[];List<Map<String,Object?>> movements=[];List<Map<String,Object?>> coldChain=[];
  List<Map<String,Object?>> radar=[];
  Future<void> loadAll() async {
    loading=true;error=null;notifyListeners();
    try{
      final db=await _db.database;
      warehouses=(await db.query('warehouses',orderBy:'name_ar')).map(WarehouseModel.fromMap).toList();
      shelves=(await db.query('shelf_locations',orderBy:'code')).map(ShelfLocationModel.fromMap).toList();
      batches=(await db.rawQuery('SELECT * FROM v_fefo_batch_balances ORDER BY expiry_date,id')).map(BatchFefoModel.fromMap).toList();
      stocktaking=(await db.query('stocktaking_sessions',orderBy:'id DESC')).map(StocktakingSessionModel.fromMap).toList();
      disposals=(await db.query('disposals',orderBy:'id DESC')).map(DisposalModel.fromMap).toList();
      transfers=(await db.query('stock_transfers',orderBy:'id DESC')).map(StockTransferModel.fromMap).toList();
      purchaseInvoices=(await db.query('purchase_invoices',orderBy:'id DESC',limit:100)).map(PurchaseInvoiceModel.fromMap).toList();
      shortages=(await _purchases.shortages()).map((r)=>ShortageItemModel(drugId:r['drug_id'] as int,drugName:r['drug_name'] as String,currentUnits:r['current_units'] as int,minimumUnits:r['minimum_units'] as int,suggestedPacks:r['suggested_packs'] as int,averageDailySales:(r['average_daily_sales'] as num).toDouble())).toList();
      radar=await db.rawQuery("SELECT b.*,d.trade_name_ar,d.sell_price_pack,COALESCE((SELECT SUM(-m.qty_units)/30.0 FROM stock_movements m WHERE m.drug_id=b.drug_id AND m.movement_type='SALE_OUT' AND m.movement_at>=datetime('now','-30 day')),0) average_daily_units FROM batches_fefo b JOIN drugs d ON d.id=b.drug_id WHERE b.total_units>0 ORDER BY b.expiry_date");
      movements=await db.rawQuery('SELECT m.*,d.trade_name_ar,b.batch_no FROM stock_movements m JOIN drugs d ON d.id=m.drug_id JOIN batches_fefo b ON b.id=m.batch_id ORDER BY m.id DESC LIMIT 200');
      coldChain=await db.rawQuery('SELECT c.*,w.name_ar warehouse_name FROM cold_chain_log c JOIN warehouses w ON w.id=c.warehouse_id ORDER BY c.id DESC LIMIT 100');
    }catch(e){error=e.toString();}
    loading=false;notifyListeners();
  }
  Future<void> setBranch(int id)async{branchId=id;await loadAll();}
  Future<void> recordTemperature({required int warehouseId,required double tempC,double? humidity,int? userId,String action=''})async{await _operations.recordTemperature(warehouseId:warehouseId,tempC:tempC,humidityPct:humidity,userId:userId,correctiveAction:action);await loadAll();}
  Future<int> createStocktaking(int warehouseId,{bool blind=false})async{final id=await _operations.createStocktaking(warehouseId:warehouseId,blind:blind);await loadAll();return id;}
  Future<void> countBatch({required int sessionId,required int batchId,required int packs,required int loose,required int unitsPerPack,String reason=''})async{await _operations.countBatch(sessionId:sessionId,batchId:batchId,countedPacks:packs,countedLooseUnits:loose,unitsPerPack:unitsPerPack,reason:reason);await loadAll();}
  Future<void> approveStocktaking(int sessionId,int managerId)async{await _operations.approveStocktaking(sessionId:sessionId,managerUserId:managerId);await loadAll();}
  Future<int> createDisposal({required String reason,required String method,required String witness,String authority='',required List<({int batchId,int qtyUnits})> items})async{final id=await _operations.createDisposal(branchId:branchId,reason:reason,method:method,witnessName:witness,authorityRef:authority,items:items);await loadAll();return id;}
  Future<int> createTransfer({required int fromWarehouse,required int toWarehouse,required List<({int batchId,int qtyUnits})> items})async{final id=await _operations.createTransfer(fromWarehouseId:fromWarehouse,toWarehouseId:toWarehouse,items:items);await loadAll();return id;}
  Future<void> dispatchTransfer(int id)async{await _operations.dispatchTransfer(id);await loadAll();}
  Future<void> receiveTransfer(int id,{Map<int,int>? received})async{await _operations.receiveTransfer(id,receivedByItem:received);await loadAll();}
  Future<int> postPurchase({required int supplierId,required int warehouseId,required String invoiceNo,required String paymentType,required double paid,List<PurchaseLineInput> items=const [],int? cashAccountId,bool bonusIncluded=true,double discount=0,double tax=0,String? supplierInvoiceNo})async{final id=await _purchases.postInvoice(branchId:branchId,supplierPartyId:supplierId,warehouseId:warehouseId,invoiceNo:invoiceNo,paymentType:paymentType,paidTotal:paid,items:items,cashAccountId:cashAccountId,includeBonusInCost:bonusIncluded,discountAmount:discount,taxAmount:tax,supplierInvoiceNo:supplierInvoiceNo);await loadAll();return id;}
  Future<int> postPurchaseReturn({required int supplierId,required int batchId,required int units,required String reason,required String settlement,double agreedValue=0})async{final id=await _purchases.postPurchaseReturn(branchId:branchId,supplierPartyId:supplierId,batchId:batchId,qtyUnits:units,reason:reason,settlementType:settlement,agreedCreditValue:agreedValue);await loadAll();return id;}
  Future<int> createShortageOrder({required int supplierId,required List<({int drugId,int packs,double cost,int bonus})> items})async{final id=await _purchases.createAutoPurchaseOrder(supplierPartyId:supplierId,items:items);await loadAll();return id;}
  Future<List<FefoAllocation>> planSale({required int drugId,required int units,required int unitsPerPack,int? warehouseId})=>_fefo.plan(drugId:drugId,needUnits:units,unitsPerPack:unitsPerPack,warehouseId:warehouseId);
}
