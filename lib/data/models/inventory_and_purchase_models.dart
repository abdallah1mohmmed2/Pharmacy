// lib/data/models/inventory_and_purchase_models.dart
import 'package:flutter/foundation.dart';

int _asInt(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? fallback;

double _asDouble(Object? value, [double fallback = 0]) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? fallback;

String _asString(Object? value, [String fallback = '']) =>
    value == null ? fallback : value.toString();

int? _asNullableInt(Object? value) => value == null ? null : _asInt(value);

String? _asNullableString(Object? value) => value == null ? null : value.toString();

DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

@immutable
class WarehouseModel {
  const WarehouseModel({
    required this.id,
    required this.code,
    required this.nameAr,
    required this.whType,
    this.isSellable = true,
  });

  final int id;
  final String code;
  final String nameAr;
  final String whType;
  final bool isSellable;

  bool get isFridge => whType == 'FRIDGE';

  factory WarehouseModel.fromMap(Map<String, Object?> map) =>
      WarehouseModel(
        id: _asInt(map['id']),
        code: _asString(map['code']),
        nameAr: _asString(map['name_ar']),
        whType: _asString(map['wh_type']),
        isSellable: _asInt(map['is_sellable']) == 1,
      );
}

@immutable
class ShelfLocationModel {
  const ShelfLocationModel({
    required this.id,
    required this.warehouseId,
    required this.code,
    this.description = '',
    this.isFridge = false,
  });

  final int id;
  final int warehouseId;
  final String code;
  final String description;
  final bool isFridge;

  factory ShelfLocationModel.fromMap(Map<String, Object?> map) =>
      ShelfLocationModel(
        id: _asInt(map['id']),
        warehouseId: _asInt(map['warehouse_id']),
        code: _asString(map['code']),
        description: _asString(map['description']),
        isFridge: _asInt(map['is_fridge']) == 1,
      );
}

@immutable
class BatchFefoModel {
  const BatchFefoModel({
    required this.id,
    required this.drugId,
    required this.warehouseId,
    required this.batchNo,
    required this.expiryDate,
    required this.totalUnits,
    this.locationId,
    this.manufactureDate,
    this.sealedPacks = 0,
    this.looseUnits = 0,
    this.unitCost = 0,
    this.packCost = 0,
    this.purchaseInvoiceItemId,
    this.status = 'ACTIVE',
    this.drugName = '',
    this.shelfCode = '',
    this.unitsPerPack = 1,
    this.sellPricePack = 0,
    this.averageDailyUnits = 0,
  });

  final int id;
  final int drugId;
  final int warehouseId;
  final int? locationId;
  final String batchNo;
  final String expiryDate;
  final String? manufactureDate;
  final int sealedPacks;
  final int looseUnits;
  final int totalUnits;
  final double unitCost;
  final double packCost;
  final int? purchaseInvoiceItemId;
  final String status;
  final String drugName;
  final String shelfCode;
  final int unitsPerPack;
  final double sellPricePack;
  final double averageDailyUnits;

  DateTime get expiry => DateTime.parse(expiryDate);

  int get daysUntilExpiry =>
      _dateOnly(expiry).difference(_dateOnly(DateTime.now())).inDays;

  bool get isExpired => daysUntilExpiry < 0;

  bool get isSellable => status == 'ACTIVE' && totalUnits > 0 && !isExpired;

  String get expiryState {
    if (isExpired) return 'EXPIRED';
    if (daysUntilExpiry <= 30) return 'CRITICAL';
    if (daysUntilExpiry <= 60) return 'WARNING';
    if (daysUntilExpiry <= 90) return 'WATCH';
    return 'SAFE';
  }

  String get expiryLabel {
    if (isExpired) return 'منتهي';
    if (daysUntilExpiry == 0) return 'ينتهي اليوم';
    return 'متبقي $daysUntilExpiry يوم';
  }

  factory BatchFefoModel.fromMap(Map<String, Object?> map) =>
      BatchFefoModel(
        id: _asInt(map['id']),
        drugId: _asInt(map['drug_id']),
        warehouseId: _asInt(map['warehouse_id']),
        locationId: _asNullableInt(map['location_id']),
        batchNo: _asString(map['batch_no']),
        expiryDate: _asString(map['expiry_date']),
        manufactureDate: _asNullableString(map['manufacture_date']),
        sealedPacks: _asInt(map['sealed_packs']),
        looseUnits: _asInt(map['loose_units']),
        totalUnits: _asInt(map['total_units']),
        unitCost: _asDouble(map['unit_cost']),
        packCost: _asDouble(map['pack_cost']),
        purchaseInvoiceItemId: _asNullableInt(map['purchase_invoice_item_id']),
        status: _asString(map['status'], 'ACTIVE'),
        drugName: _asString(map['trade_name_ar']),
        shelfCode: _asString(map['shelf_code']),
        unitsPerPack: _asInt(map['units_per_pack'], 1),
        sellPricePack: _asDouble(map['sell_price_pack']),
        averageDailyUnits: _asDouble(map['average_daily_units']),
      );
}

@immutable
class StockMovementModel {
  const StockMovementModel({
    required this.id,
    required this.drugId,
    required this.batchId,
    required this.warehouseId,
    required this.movementType,
    required this.qtyUnits,
    required this.balanceAfterUnits,
    required this.movementAt,
    this.unitCost = 0,
    this.unitPrice = 0,
    this.docType = '',
    this.docId,
    this.docLineId,
    this.note = '',
  });

  final int id;
  final int drugId;
  final int batchId;
  final int warehouseId;
  final String movementType;
  final int qtyUnits;
  final int balanceAfterUnits;
  final String movementAt;
  final double unitCost;
  final double unitPrice;
  final String docType;
  final int? docId;
  final int? docLineId;
  final String note;

  double get movementCost => qtyUnits.abs() * unitCost;

  factory StockMovementModel.fromMap(Map<String, Object?> map) =>
      StockMovementModel(
        id: _asInt(map['id']),
        drugId: _asInt(map['drug_id']),
        batchId: _asInt(map['batch_id']),
        warehouseId: _asInt(map['warehouse_id']),
        movementType: _asString(map['movement_type']),
        qtyUnits: _asInt(map['qty_units']),
        balanceAfterUnits: _asInt(map['balance_after_units']),
        movementAt: _asString(map['movement_at']),
        unitCost: _asDouble(map['unit_cost']),
        unitPrice: _asDouble(map['unit_price']),
        docType: _asString(map['doc_type']),
        docId: _asNullableInt(map['doc_id']),
        docLineId: _asNullableInt(map['doc_line_id']),
        note: _asString(map['note']),
      );
}

@immutable
class StocktakingSessionModel {
  const StocktakingSessionModel({
    required this.id,
    required this.sessionNo,
    required this.warehouseId,
    required this.scopeType,
    required this.status,
    this.blindCount = false,
    this.createdAt = '',
    this.approvedAt,
    this.approvedBy,
  });

  final int id;
  final String sessionNo;
  final int warehouseId;
  final String scopeType;
  final String status;
  final bool blindCount;
  final String createdAt;
  final String? approvedAt;
  final int? approvedBy;

  bool get canCount => status == 'COUNTING';
  bool get isApproved => status == 'APPROVED';

  factory StocktakingSessionModel.fromMap(Map<String, Object?> map) =>
      StocktakingSessionModel(
        id: _asInt(map['id']),
        sessionNo: _asString(map['session_no']),
        warehouseId: _asInt(map['warehouse_id']),
        scopeType: _asString(map['scope_type']),
        status: _asString(map['status']),
        blindCount: _asInt(map['blind_count']) == 1,
        createdAt: _asString(map['created_at']),
        approvedAt: _asNullableString(map['approved_at']),
        approvedBy: _asNullableInt(map['approved_by']),
      );
}

@immutable
class StocktakingLineModel {
  const StocktakingLineModel({
    required this.id,
    required this.sessionId,
    required this.batchId,
    required this.systemUnits,
    required this.countedPacks,
    required this.countedLooseUnits,
    required this.countedUnits,
    required this.diffUnits,
    this.unitCost = 0,
    this.diffValue = 0,
    this.reasonCode = '',
    this.batchNo = '',
    this.drugName = '',
    this.unitsPerPack = 1,
  });

  final int id;
  final int sessionId;
  final int batchId;
  final int systemUnits;
  final int countedPacks;
  final int countedLooseUnits;
  final int countedUnits;
  final int diffUnits;
  final double unitCost;
  final double diffValue;
  final String reasonCode;
  final String batchNo;
  final String drugName;
  final int unitsPerPack;

  bool get isShortage => diffUnits < 0;
  bool get isSurplus => diffUnits > 0;

  factory StocktakingLineModel.fromMap(Map<String, Object?> map) =>
      StocktakingLineModel(
        id: _asInt(map['id']),
        sessionId: _asInt(map['session_id']),
        batchId: _asInt(map['batch_id']),
        systemUnits: _asInt(map['system_units']),
        countedPacks: _asInt(map['counted_packs']),
        countedLooseUnits: _asInt(map['counted_loose_units']),
        countedUnits: _asInt(map['counted_units']),
        diffUnits: _asInt(map['diff_units']),
        unitCost: _asDouble(map['unit_cost']),
        diffValue: _asDouble(map['diff_value']),
        reasonCode: _asString(map['reason_code']),
        batchNo: _asString(map['batch_no']),
        drugName: _asString(map['trade_name_ar']),
        unitsPerPack: _asInt(map['units_per_pack'], 1),
      );
}

@immutable
class DisposalModel {
  const DisposalModel({
    required this.id,
    required this.disposalNo,
    required this.disposalDate,
    required this.reason,
    required this.status,
    this.method = '',
    this.witnessName = '',
    this.authorityRef = '',
    this.totalCostValue = 0,
    this.journalEntryId,
    this.itemsCount = 0,
  });

  final int id;
  final String disposalNo;
  final String disposalDate;
  final String reason;
  final String status;
  final String method;
  final String witnessName;
  final String authorityRef;
  final double totalCostValue;
  final int? journalEntryId;
  final int itemsCount;

  factory DisposalModel.fromMap(Map<String, Object?> map) => DisposalModel(
        id: _asInt(map['id']),
        disposalNo: _asString(map['disposal_no']),
        disposalDate: _asString(map['disposal_date']),
        reason: _asString(map['reason']),
        status: _asString(map['status']),
        method: _asString(map['method']),
        witnessName: _asString(map['witness_name']),
        authorityRef: _asString(map['authority_ref']),
        totalCostValue: _asDouble(map['total_cost_value']),
        journalEntryId: _asNullableInt(map['journal_entry_id']),
        itemsCount: _asInt(map['items_count']),
      );
}

@immutable
class StockTransferModel {
  const StockTransferModel({
    required this.id,
    required this.transferNo,
    required this.transferType,
    required this.fromWarehouseId,
    required this.toWarehouseId,
    required this.status,
    this.createdAt = '',
    this.receivedAt,
    this.itemsCount = 0,
  });

  final int id;
  final String transferNo;
  final String transferType;
  final int fromWarehouseId;
  final int toWarehouseId;
  final String status;
  final String createdAt;
  final String? receivedAt;
  final int itemsCount;

  factory StockTransferModel.fromMap(Map<String, Object?> map) =>
      StockTransferModel(
        id: _asInt(map['id']),
        transferNo: _asString(map['transfer_no']),
        transferType: _asString(map['transfer_type']),
        fromWarehouseId: _asInt(map['from_warehouse_id']),
        toWarehouseId: _asInt(map['to_warehouse_id']),
        status: _asString(map['status']),
        createdAt: _asString(map['created_at']),
        receivedAt: _asNullableString(map['received_at']),
        itemsCount: _asInt(map['items_count']),
      );
}

@immutable
class PurchaseInvoiceModel {
  const PurchaseInvoiceModel({
    required this.id,
    required this.invoiceNo,
    required this.supplierPartyId,
    required this.warehouseId,
    required this.invoiceDate,
    required this.paymentType,
    this.supplierInvoiceNo = '',
    this.poId,
    this.dueDate,
    this.subtotal = 0,
    this.discountPct = 0,
    this.discountAmount = 0,
    this.taxAmount = 0,
    this.netTotal = 0,
    this.paidTotal = 0,
    this.remainingLah = 0,
    this.status = 'DRAFT',
    this.journalEntryId,
  });

  final int id;
  final String invoiceNo;
  final String supplierInvoiceNo;
  final int supplierPartyId;
  final int warehouseId;
  final int? poId;
  final String invoiceDate;
  final String? dueDate;
  final String paymentType;
  final double subtotal;
  final double discountPct;
  final double discountAmount;
  final double taxAmount;
  final double netTotal;
  final double paidTotal;
  final double remainingLah;
  final String status;
  final int? journalEntryId;

  factory PurchaseInvoiceModel.fromMap(Map<String, Object?> map) =>
      PurchaseInvoiceModel(
        id: _asInt(map['id']),
        invoiceNo: _asString(map['invoice_no']),
        supplierInvoiceNo: _asString(map['supplier_invoice_no']),
        supplierPartyId: _asInt(map['supplier_party_id']),
        warehouseId: _asInt(map['warehouse_id']),
        poId: _asNullableInt(map['po_id']),
        invoiceDate: _asString(map['invoice_date']),
        dueDate: _asNullableString(map['due_date']),
        paymentType: _asString(map['payment_type']),
        subtotal: _asDouble(map['subtotal']),
        discountPct: _asDouble(map['discount_pct']),
        discountAmount: _asDouble(map['discount_amount']),
        taxAmount: _asDouble(map['tax_amount']),
        netTotal: _asDouble(map['net_total']),
        paidTotal: _asDouble(map['paid_total']),
        remainingLah: _asDouble(map['remaining_lah']),
        status: _asString(map['status']),
        journalEntryId: _asNullableInt(map['journal_entry_id']),
      );
}

@immutable
class PurchaseItemModel {
  const PurchaseItemModel({
    required this.id,
    required this.invoiceId,
    required this.drugId,
    required this.batchNo,
    required this.expiryDate,
    required this.qtyPacksPaid,
    required this.bonusPacks,
    required this.packPrice,
    this.locationId,
    this.lineDiscountPct = 0,
    this.lineTotal = 0,
    this.effectivePackCost = 0,
    this.newSellPricePack = 0,
    this.unitsPerPack = 1,
  });

  final int id;
  final int invoiceId;
  final int drugId;
  final int? locationId;
  final String batchNo;
  final String expiryDate;
  final int qtyPacksPaid;
  final int bonusPacks;
  final double packPrice;
  final double lineDiscountPct;
  final double lineTotal;
  final double effectivePackCost;
  final double newSellPricePack;
  final int unitsPerPack;

  int get qtyPacksTotal => qtyPacksPaid + bonusPacks;
  int get totalUnits => qtyPacksTotal * unitsPerPack;
  double get bonusValue => bonusPacks * packPrice;

  factory PurchaseItemModel.fromMap(Map<String, Object?> map) =>
      PurchaseItemModel(
        id: _asInt(map['id']),
        invoiceId: _asInt(map['invoice_id']),
        drugId: _asInt(map['drug_id']),
        locationId: _asNullableInt(map['location_id']),
        batchNo: _asString(map['batch_no']),
        expiryDate: _asString(map['expiry_date']),
        qtyPacksPaid: _asInt(map['qty_packs_paid']),
        bonusPacks: _asInt(map['bonus_packs']),
        packPrice: _asDouble(map['pack_price']),
        lineDiscountPct: _asDouble(map['line_discount_pct']),
        lineTotal: _asDouble(map['line_total']),
        effectivePackCost: _asDouble(map['effective_pack_cost']),
        newSellPricePack: _asDouble(map['new_sell_price_pack']),
        unitsPerPack: _asInt(map['units_per_pack'], 1),
      );
}

@immutable
class PurchaseReturnModel {
  const PurchaseReturnModel({
    required this.id,
    required this.returnNo,
    required this.supplierPartyId,
    required this.returnDate,
    required this.reason,
    required this.settlementType,
    this.totalValue = 0,
    this.costValue = 0,
    this.settlementDifference = 0,
    this.status = 'DRAFT',
    this.journalEntryId,
  });

  final int id;
  final String returnNo;
  final int supplierPartyId;
  final String returnDate;
  final String reason;
  final String settlementType;
  final double totalValue;
  final double costValue;
  final double settlementDifference;
  final String status;
  final int? journalEntryId;

  factory PurchaseReturnModel.fromMap(Map<String, Object?> map) =>
      PurchaseReturnModel(
        id: _asInt(map['id']),
        returnNo: _asString(map['return_no']),
        supplierPartyId: _asInt(map['supplier_party_id']),
        returnDate: _asString(map['return_date']),
        reason: _asString(map['reason']),
        settlementType: _asString(map['settlement_type']),
        totalValue: _asDouble(map['total_value']),
        costValue: _asDouble(map['cost_value']),
        settlementDifference: _asDouble(map['settlement_difference']),
        status: _asString(map['status']),
        journalEntryId: _asNullableInt(map['journal_entry_id']),
      );
}

@immutable
class ShortageItemModel {
  const ShortageItemModel({
    required this.drugId,
    required this.drugName,
    required this.currentUnits,
    required this.minimumUnits,
    required this.suggestedPacks,
    this.averageDailySales = 0,
    this.bestSupplierName = '',
    this.bestSupplierId,
    this.effectivePackCost = 0,
    this.unitsPerPack = 1,
    this.reorderDays = 0,
  });

  final int drugId;
  final String drugName;
  final int currentUnits;
  final int minimumUnits;
  final int suggestedPacks;
  final double averageDailySales;
  final String bestSupplierName;
  final int? bestSupplierId;
  final double effectivePackCost;
  final int unitsPerPack;
  final int reorderDays;

  int get suggestedUnits => suggestedPacks * unitsPerPack;

  factory ShortageItemModel.fromMap(Map<String, Object?> map) =>
      ShortageItemModel(
        drugId: _asInt(map['drug_id']),
        drugName: _asString(map['drug_name']),
        currentUnits: _asInt(map['current_units']),
        minimumUnits: _asInt(map['minimum_units']),
        suggestedPacks: _asInt(map['suggested_packs']),
        averageDailySales: _asDouble(map['average_daily_sales']),
        bestSupplierName: _asString(map['best_supplier_name']),
        bestSupplierId: _asNullableInt(map['best_supplier_id']),
        effectivePackCost: _asDouble(map['effective_pack_cost']),
        unitsPerPack: _asInt(map['units_per_pack'], 1),
        reorderDays: _asInt(map['reorder_days']),
      );
}
