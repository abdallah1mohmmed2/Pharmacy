import 'drug_model.dart';

class PartyModel {
  const PartyModel(
      {this.id,
      this.uuid,
      this.branchId = 1,
      this.createdAt,
      this.updatedAt,
      this.isDeleted = false,
      this.syncStatus = 'LOCAL',
      this.syncVersion = 1,
      required this.partyType,
      this.code = '',
      required this.nameAr,
      this.phone = '',
      this.address = '',
      this.nationalId = '',
      this.creditLimit = 0,
      this.paymentTermsDays = 0,
      this.isChronicPatient = false,
      this.isPatient = false,
      this.isBlocked = false,
      this.openingAlayh = 0,
      this.openingLah = 0,
      this.totalAlayh = 0,
      this.totalLah = 0,
      this.net = 0,
      this.balanceSide = 'ZERO',
      this.balanceAbs = 0});
  final int? id, branchId, paymentTermsDays, syncVersion;
  final String? uuid, createdAt, updatedAt;
  final bool isDeleted, isChronicPatient, isPatient, isBlocked;
  final String syncStatus,
      partyType,
      code,
      nameAr,
      phone,
      address,
      nationalId,
      balanceSide;
  final double creditLimit,
      openingAlayh,
      openingLah,
      totalAlayh,
      totalLah,
      net,
      balanceAbs;
  factory PartyModel.fromMap(Map<String, Object?> m) => PartyModel(
      id: m['id'] as int?,
      uuid: m['uuid'] as String?,
      branchId: m['branch_id'] as int? ?? 1,
      createdAt: m['created_at'] as String?,
      updatedAt: m['updated_at'] as String?,
      isDeleted: (m['is_deleted'] as int? ?? 0) == 1,
      syncStatus: m['sync_status'] as String? ?? 'LOCAL',
      syncVersion: m['sync_version'] as int? ?? 1,
      partyType: m['party_type'] as String,
      nameAr: m['name_ar'] as String,
      code: m['code'] as String? ?? '',
      phone: m['phone'] as String? ?? '',
      address: m['address'] as String? ?? '',
      nationalId: m['national_id'] as String? ?? '',
      creditLimit: (m['credit_limit'] as num? ?? 0).toDouble(),
      paymentTermsDays: m['payment_terms_days'] as int? ?? 0,
      isChronicPatient: (m['is_chronic_patient'] as int? ?? 0) == 1,
      isPatient: (m['is_patient'] as int? ?? 0) == 1,
      isBlocked: (m['is_blocked'] as int? ?? 0) == 1,
      openingAlayh: (m['opening_alayh'] as num? ?? 0).toDouble(),
      openingLah: (m['opening_lah'] as num? ?? 0).toDouble(),
      totalAlayh: (m['total_alayh'] as num? ?? 0).toDouble(),
      totalLah: (m['total_lah'] as num? ?? 0).toDouble(),
      net: (m['net'] as num? ?? 0).toDouble(),
      balanceSide: m['balance_side'] as String? ?? 'ZERO',
      balanceAbs: (m['balance_abs'] as num? ?? 0).toDouble());
}

class LedgerEntryModel {
  const LedgerEntryModel(
      {this.id,
      this.uuid,
      this.branchId = 1,
      required this.partyId,
      required this.entryDate,
      required this.entryType,
      this.alayhAmount = 0,
      this.lahAmount = 0,
      required this.docType,
      this.docId,
      this.statementAr = '',
      this.journalEntryId});
  final int? id, branchId, partyId, docId, journalEntryId;
  final String? uuid;
  final String entryDate, entryType, docType, statementAr;
  final double alayhAmount, lahAmount;
  Map<String, Object?> toMap() => {
        'id': id,
        'uuid': uuid,
        'branch_id': branchId,
        'party_id': partyId,
        'entry_date': entryDate,
        'entry_type': entryType,
        'alayh_amount': alayhAmount,
        'lah_amount': lahAmount,
        'doc_type': docType,
        'doc_id': docId,
        'statement_ar': statementAr,
        'journal_entry_id': journalEntryId
      };
}

class CashAccountModel {
  const CashAccountModel(
      {this.id,
      this.uuid,
      this.branchId = 1,
      required this.code,
      required this.nameAr,
      required this.accountKind,
      this.walletProvider,
      this.walletPhone,
      this.glAccountId,
      this.currentBalance = 0});
  final int? id, branchId, glAccountId;
  final String? uuid, walletProvider, walletPhone;
  final String code, nameAr, accountKind;
  final double currentBalance;
}

class VoucherModel {
  const VoucherModel(
      {this.id,
      this.uuid,
      this.branchId = 1,
      required this.voucherNo,
      required this.voucherType,
      required this.voucherDate,
      this.partyId,
      this.cashAccountId,
      required this.amount,
      required this.method,
      this.walletRefNo,
      this.description = '',
      this.journalEntryId});
  final int? id, branchId, partyId, cashAccountId, journalEntryId;
  final String? uuid, walletRefNo;
  final String voucherNo, voucherType, voucherDate, method, description;
  final double amount;
}

class CartItemModel {
  CartItemModel(
      {required this.drug,
      required this.sellUnit,
      this.quantity = 1,
      this.discount = 0,
      this.isSubstitute = false,
      this.substitutedForDrugId});
  final DrugModel drug;
  final bool isSubstitute;
  final int? substitutedForDrugId;
  String sellUnit;
  double quantity, discount;
  int get baseUnits => drug.toBaseUnits(sellUnit, quantity);
  double get unitPrice => switch (sellUnit) {
        'PACK' => drug.sellPricePack,
        'STRIP' => drug.sellPriceStrip,
        'UNIT' => drug.sellPriceUnit,
        _ => 0
      };
  double get lineTotal =>
      (unitPrice * quantity - discount).clamp(0, double.infinity).toDouble();
}

class PosTabSession {
  PosTabSession(
      {required this.id,
      this.label = '',
      List<CartItemModel>? items,
      this.held = false,
      this.customerPartyId,
      this.createdAt,
      Set<String>? patientFlags})
      : items = items ?? [],
        patientFlags = patientFlags ?? {};
  final String id;
  String label;
  final List<CartItemModel> items;
  final Set<String> patientFlags;
  bool held;
  int? customerPartyId;
  final DateTime? createdAt;
  double get total => items.fold(0, (sum, item) => sum + item.lineTotal);
}

class SaleInvoiceModel {
  const SaleInvoiceModel(
      {this.id,
      this.uuid,
      this.branchId = 1,
      required this.invoiceNo,
      required this.invoiceDate,
      required this.cashierUserId,
      this.customerPartyId,
      required this.saleType,
      required this.status,
      this.holdLabel = '',
      this.subtotal = 0,
      this.discountPct = 0,
      this.discountAmount = 0,
      this.roundingDiff = 0,
      this.netTotal = 0,
      this.paidTotal = 0,
      this.remainingAlayh = 0,
      this.totalCost = 0,
      this.journalEntryId});
  final int? id, branchId, cashierUserId, customerPartyId, journalEntryId;
  final String? uuid;
  final String invoiceNo, invoiceDate, saleType, status, holdLabel;
  final double subtotal,
      discountPct,
      discountAmount,
      roundingDiff,
      netTotal,
      paidTotal,
      remainingAlayh,
      totalCost;
}
