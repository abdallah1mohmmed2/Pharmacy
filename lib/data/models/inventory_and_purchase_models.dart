import 'package:flutter/foundation.dart';

int _asInt(Object? value,[int fallback=0]) => value is num ? value.toInt() : fallback;
double _asDouble(Object? value,[double fallback=0]) => value is num ? value.toDouble() : fallback;
String _asString(Object? value,[String fallback='']) => value?.toString() ?? fallback;

@immutable
class WarehouseModel {
  const WarehouseModel({required this.id,required this.code,required this.nameAr,required this.whType,this.isSellable=true});
  final int id; final String code,nameAr,whType; final bool isSellable;
  factory WarehouseModel.fromMap(Map<String,Object?> m)=>WarehouseModel(id:_asInt(m['id']),code:_asString(m['code']),nameAr:_asString(m['name_ar']),whType:_asString(m['wh_type']),isSellable:_asInt(m['is_sellable'])==1);
}
@immutable
class ShelfLocationModel {
  const ShelfLocationModel({required this.id,required this.warehouseId,required this.code,this.description='',this.isFridge=false});
  final int id,warehouseId; final String code,description; final bool isFridge;
  factory ShelfLocationModel.fromMap(Map<String,Object?> m)=>ShelfLocationModel(id:_asInt(m['id']),warehouseId:_asInt(m['warehouse_id']),code:_asString(m['code']),description:_asString(m['description']),isFridge:_asInt(m['is_fridge'])==1);
}
@immutable
class BatchFefoModel {
  const BatchFefoModel({required this.id,required this.drugId,required this.warehouseId,this.locationId,required this.batchNo,required this.expiryDate,this.manufactureDate,this.sealedPacks=0,this.looseUnits=0,required this.totalUnits,this.unitCost=0,this.packCost=0,this.status='ACTIVE',this.drugName='',this.shelfCode=''});
  final int id,drugId,warehouseId,sealedPacks,looseUnits,totalUnits; final int? locationId;
  final String batchNo,expiryDate,status,drugName,shelfCode; final String? manufactureDate; final double unitCost,packCost;
  int get daysUntilExpiry => DateTime.parse(expiryDate).difference(DateTime(DateTime.now().year,DateTime.now().month,DateTime.now().day)).inDays;
  String get expiryState => daysUntilExpiry<0?'EXPIRED':daysUntilExpiry<=30?'CRITICAL':daysUntilExpiry<=60?'WARNING':daysUntilExpiry<=90?'WATCH':'SAFE';
  factory BatchFefoModel.fromMap(Map<String,Object?> m)=>BatchFefoModel(id:_asInt(m['id']),drugId:_asInt(m['drug_id']),warehouseId:_asInt(m['warehouse_id']),locationId:m['location_id'] as int?,batchNo:_asString(m['batch_no']),expiryDate:_asString(m['expiry_date']),manufactureDate:m['manufacture_date'] as String?,sealedPacks:_asInt(m['sealed_packs']),looseUnits:_asInt(m['loose_units']),totalUnits:_asInt(m['total_units']),unitCost:_asDouble(m['unit_cost']),packCost:_asDouble(m['pack_cost']),status:_asString(m['status'],'ACTIVE'),drugName:_asString(m['trade_name_ar']),shelfCode:_asString(m['shelf_code']));
}
@immutable
class StockMovementModel {
  const StockMovementModel({required this.id,required this.drugId,required this.batchId,required this.warehouseId,required this.movementType,required this.qtyUnits,required this.balanceAfterUnits,required this.movementAt,this.unitCost=0,this.unitPrice=0,this.docType='',this.docId,this.note=''});
  final int id,drugId,batchId,warehouseId,qtyUnits,balanceAfterUnits; final String movementType,movementAt,docType,note; final int? docId; final double unitCost,unitPrice;
  factory StockMovementModel.fromMap(Map<String,Object?> m)=>StockMovementModel(id:_asInt(m['id']),drugId:_asInt(m['drug_id']),batchId:_asInt(m['batch_id']),warehouseId:_asInt(m['warehouse_id']),movementType:_asString(m['movement_type']),qtyUnits:_asInt(m['qty_units']),balanceAfterUnits:_asInt(m['balance_after_units']),movementAt:_asString(m['movement_at']),unitCost:_asDouble(m['unit_cost']),unitPrice:_asDouble(m['unit_price']),docType:_asString(m['doc_type']),docId:m['doc_id'] as int?,note:_asString(m['note']));
}
@immutable
class StocktakingSessionModel {
  const StocktakingSessionModel({required this.id,required this.sessionNo,required this.warehouseId,required this.scopeType,required this.status,this.blindCount=false,this.createdAt='' });
  final int id,warehouseId; final String sessionNo,scopeType,status,createdAt; final bool blindCount;
  factory StocktakingSessionModel.fromMap(Map<String,Object?> m)=>StocktakingSessionModel(id:_asInt(m['id']),sessionNo:_asString(m['session_no']),warehouseId:_asInt(m['warehouse_id']),scopeType:_asString(m['scope_type']),status:_asString(m['status']),blindCount:_asInt(m['blind_count'])==1,createdAt:_asString(m['created_at']));
}
@immutable
class StocktakingLineModel {
  const StocktakingLineModel({required this.id,required this.sessionId,required this.batchId,required this.systemUnits,required this.countedPacks,required this.countedLooseUnits,required this.countedUnits,required this.diffUnits,this.unitCost=0,this.diffValue=0,this.reasonCode=''});
  final int id,sessionId,batchId,systemUnits,countedPacks,countedLooseUnits,countedUnits,diffUnits; final double unitCost,diffValue; final String reasonCode;
  factory StocktakingLineModel.fromMap(Map<String,Object?> m)=>StocktakingLineModel(id:_asInt(m['id']),sessionId:_asInt(m['session_id']),batchId:_asInt(m['batch_id']),systemUnits:_asInt(m['system_units']),countedPacks:_asInt(m['counted_packs']),countedLooseUnits:_asInt(m['counted_loose_units']),countedUnits:_asInt(m['counted_units']),diffUnits:_asInt(m['diff_units']),unitCost:_asDouble(m['unit_cost']),diffValue:_asDouble(m['diff_value']),reasonCode:_asString(m['reason_code']));
}
@immutable
class DisposalModel {
  const DisposalModel({required this.id,required this.disposalNo,required this.disposalDate,required this.reason,required this.status,this.method='',this.witnessName='',this.authorityRef='',this.totalCostValue=0});
  final int id; final String disposalNo,disposalDate,reason,status,method,witnessName,authorityRef; final double totalCostValue;
  factory DisposalModel.fromMap(Map<String,Object?> m)=>DisposalModel(id:_asInt(m['id']),disposalNo:_asString(m['disposal_no']),disposalDate:_asString(m['disposal_date']),reason:_asString(m['reason']),status:_asString(m['status']),method:_asString(m['method']),witnessName:_asString(m['witness_name']),authorityRef:_asString(m['authority_ref']),totalCostValue:_asDouble(m['total_cost_value']));
}
@immutable
class StockTransferModel {
  const StockTransferModel({required this.id,required this.transferNo,required this.transferType,required this.fromWarehouseId,required this.toWarehouseId,required this.status,this.createdAt=''});
  final int id,fromWarehouseId,toWarehouseId; final String transferNo,transferType,status,createdAt;
  factory StockTransferModel.fromMap(Map<String,Object?> m)=>StockTransferModel(id:_asInt(m['id']),transferNo:_asString(m['transfer_no']),transferType:_asString(m['transfer_type']),fromWarehouseId:_asInt(m['from_warehouse_id']),toWarehouseId:_asInt(m['to_warehouse_id']),status:_asString(m['status']),createdAt:_asString(m['created_at']));
}
@immutable
class PurchaseInvoiceModel {
  const PurchaseInvoiceModel({required this.id,required this.invoiceNo,required this.supplierPartyId,required this.warehouseId,required this.invoiceDate,required this.paymentType,this.supplierInvoiceNo='',this.subtotal=0,this.discountAmount=0,this.taxAmount=0,this.netTotal=0,this.paidTotal=0,this.remainingLah=0,this.status='DRAFT'});
  final int id,supplierPartyId,warehouseId; final String invoiceNo,supplierInvoiceNo,invoiceDate,paymentType,status; final double subtotal,discountAmount,taxAmount,netTotal,paidTotal,remainingLah;
  factory PurchaseInvoiceModel.fromMap(Map<String,Object?> m)=>PurchaseInvoiceModel(id:_asInt(m['id']),invoiceNo:_asString(m['invoice_no']),supplierPartyId:_asInt(m['supplier_party_id']),warehouseId:_asInt(m['warehouse_id']),invoiceDate:_asString(m['invoice_date']),paymentType:_asString(m['payment_type']),supplierInvoiceNo:_asString(m['supplier_invoice_no']),subtotal:_asDouble(m['subtotal']),discountAmount:_asDouble(m['discount_amount']),taxAmount:_asDouble(m['tax_amount']),netTotal:_asDouble(m['net_total']),paidTotal:_asDouble(m['paid_total']),remainingLah:_asDouble(m['remaining_lah']),status:_asString(m['status']));
}
@immutable
class PurchaseItemModel {
  const PurchaseItemModel({required this.id,required this.invoiceId,required this.drugId,required this.batchNo,required this.expiryDate,required this.qtyPacksPaid,required this.bonusPacks,required this.packPrice,this.lineDiscountPct=0,this.lineTotal=0,this.effectivePackCost=0,this.newSellPricePack=0});
  final int id,invoiceId,drugId,qtyPacksPaid,bonusPacks; final String batchNo,expiryDate; final double packPrice,lineDiscountPct,lineTotal,effectivePackCost,newSellPricePack;
  int get qtyPacksTotal=>qtyPacksPaid+bonusPacks;
  factory PurchaseItemModel.fromMap(Map<String,Object?> m)=>PurchaseItemModel(id:_asInt(m['id']),invoiceId:_asInt(m['invoice_id']),drugId:_asInt(m['drug_id']),batchNo:_asString(m['batch_no']),expiryDate:_asString(m['expiry_date']),qtyPacksPaid:_asInt(m['qty_packs_paid']),bonusPacks:_asInt(m['bonus_packs']),packPrice:_asDouble(m['pack_price']),lineDiscountPct:_asDouble(m['line_discount_pct']),lineTotal:_asDouble(m['line_total']),effectivePackCost:_asDouble(m['effective_pack_cost']),newSellPricePack:_asDouble(m['new_sell_price_pack']));
}
@immutable
class PurchaseReturnModel {
  const PurchaseReturnModel({required this.id,required this.returnNo,required this.supplierPartyId,required this.returnDate,required this.reason,required this.settlementType,this.totalValue=0,this.status='DRAFT'});
  final int id,supplierPartyId; final String returnNo,returnDate,reason,settlementType,status; final double totalValue;
  factory PurchaseReturnModel.fromMap(Map<String,Object?> m)=>PurchaseReturnModel(id:_asInt(m['id']),returnNo:_asString(m['return_no']),supplierPartyId:_asInt(m['supplier_party_id']),returnDate:_asString(m['return_date']),reason:_asString(m['reason']),settlementType:_asString(m['settlement_type']),totalValue:_asDouble(m['total_value']),status:_asString(m['status']));
}
@immutable
class ShortageItemModel {
  const ShortageItemModel({required this.drugId,required this.drugName,required this.currentUnits,required this.minimumUnits,required this.suggestedPacks,this.averageDailySales=0,this.bestSupplierName='',this.effectivePackCost=0});
  final int drugId,currentUnits,minimumUnits,suggestedPacks; final String drugName,bestSupplierName; final double averageDailySales,effectivePackCost;
}
