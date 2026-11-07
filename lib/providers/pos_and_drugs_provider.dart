import 'package:flutter/foundation.dart';
import '../data/database/database_helper.dart';
import '../data/models/drug_model.dart';
import '../data/models/erp_models.dart';
import '../data/models/clinical_and_rx_models.dart';
import '../data/services/posting_and_sales_service.dart';

class PosAndDrugsProvider extends ChangeNotifier {
  PosAndDrugsProvider(
      {DatabaseHelper? database, PostingAndSalesService? posting})
      : _db = database ?? DatabaseHelper.instance,
        _posting = posting ?? PostingAndSalesService(helper: database);
  final DatabaseHelper _db;
  final PostingAndSalesService _posting;
  List<DrugModel> drugs = [];
  final List<PosTabSession> tabs = [
    PosTabSession(id: 'tab-1', label: 'فاتورة 1', createdAt: DateTime.now())
  ];
  int activeTab = 0;
  int branchId = 1;
  String search = '';
  bool loading = false;
  String? clinicalBlock;
  PosTabSession get currentTab => tabs[activeTab];
  List<CartItemModel> get cart => currentTab.items;
  Set<String> get patientFlags => currentTab.patientFlags;
  double get total => currentTab.total;

  Future<void> setBranchId(int value) async {
    branchId = value;
    await loadDrugs();
  }

  Future<void> loadDrugs() async {
    loading = true;
    notifyListeners();
    final rows = await _db.query('drugs',
        where: 'branch_id=? AND is_deleted=0 AND is_active=1',
        whereArgs: [branchId],
        orderBy: 'trade_name_ar');
    drugs = rows.map(DrugModel.fromMap).toList();
    loading = false;
    notifyListeners();
  }

  Future<void> searchDrugs(String value) async {
    search = value;
    final rows = await _db.rawQuery(
        "SELECT * FROM drugs WHERE branch_id=? AND is_deleted=0 AND is_active=1 AND (trade_name_ar LIKE ? OR trade_name_en LIKE ? OR scientific_name LIKE ? OR barcode_local LIKE ? OR barcode_international LIKE ?) ORDER BY trade_name_ar LIMIT 100",
        [
          branchId,
          '%' + value + '%',
          '%' + value + '%',
          '%' + value + '%',
          '%' + value + '%',
          '%' + value + '%'
        ]);
    drugs = rows.map(DrugModel.fromMap).toList();
    notifyListeners();
  }

  bool createTab() {
    if (tabs.length >= 8) return false;
    tabs.add(PosTabSession(
        id: 'tab-' + DateTime.now().microsecondsSinceEpoch.toString(),
        label: 'فاتورة ' + (tabs.length + 1).toString(),
        createdAt: DateTime.now()));
    activeTab = tabs.length - 1;
    clinicalBlock = null;
    notifyListeners();
    return true;
  }

  void selectTab(int index) {
    if (index < 0 || index >= tabs.length) return;
    activeTab = index;
    clinicalBlock = null;
    for (final item in cart) {
      _checkDrug(item.drug);
    }
    notifyListeners();
  }

  void holdCurrent() {
    currentTab.held = true;
    notifyListeners();
  }

  bool restoreCurrent() {
    if (!currentTab.held) return false;
    currentTab.held = false;
    notifyListeners();
    return true;
  }

  void closeCurrent() {
    if (tabs.length == 1) {
      currentTab.items.clear();
      currentTab.patientFlags.clear();
      currentTab.held = false;
    } else {
      tabs.removeAt(activeTab);
      activeTab = activeTab.clamp(0, tabs.length - 1).toInt();
    }
    clinicalBlock = null;
    for (final item in cart) {
      _checkDrug(item.drug);
    }
    notifyListeners();
  }

  void setPatientFlag(String flag, bool enabled) {
    if (currentTab.held) return;
    if (enabled) {
      patientFlags.add(flag);
    } else {
      patientFlags.remove(flag);
    }
    clinicalBlock = null;
    for (final item in cart) {
      _checkDrug(item.drug);
    }
    notifyListeners();
  }

  void addDrug(DrugModel drug, {String unit = 'UNIT'}) {
    if (currentTab.held) throw StateError('استرجع الفاتورة قبل تعديلها');
    _checkDrug(drug);
    cart.add(CartItemModel(drug: drug, sellUnit: unit));
    notifyListeners();
  }

  void removeItem(CartItemModel item) {
    if (currentTab.held) return;
    cart.remove(item);
    clinicalBlock = null;
    for (final i in cart) {
      _checkDrug(i.drug);
    }
    notifyListeners();
  }

  void replaceCartItem(CartItemModel item, DrugModel replacement) {
    if (currentTab.held) return;
    final index = cart.indexOf(item);
    if (index < 0) return;
    cart[index] = CartItemModel(
        drug: replacement,
        sellUnit: item.sellUnit,
        quantity: item.quantity,
        discount: item.discount,
        isSubstitute: true,
        substitutedForDrugId: item.drug.id);
    clinicalBlock = null;
    for (final line in cart) {
      _checkDrug(line.drug);
    }
    notifyListeners();
  }

  void changeQuantity(CartItemModel item, double qty) {
    if (currentTab.held) return;
    if (qty <= 0) {
      removeItem(item);
    } else {
      item.quantity = qty;
      notifyListeners();
    }
  }

  void changeUnit(CartItemModel item, String unit) {
    if (currentTab.held) return;
    item.sellUnit = unit;
    notifyListeners();
  }

  void _checkDrug(DrugModel d) {
    if (patientFlags.contains('PREGNANT') && d.pregnancyCategory == 'X')
      clinicalBlock = 'تحذير حمل حرج: ' + d.tradeNameAr + ' مصنف ضمن الفئة X.';
    if (patientFlags.contains('KIDNEY') &&
        ['ADJUST', 'AVOID', 'CONTRAINDICATED'].contains(d.renalStatus))
      clinicalBlock = 'تحذير كلوي: ' + d.tradeNameAr + ' — ' + d.renalNotes;
    if (patientFlags.contains('LIVER') &&
        ['ADJUST', 'AVOID', 'CONTRAINDICATED'].contains(d.hepaticStatus))
      clinicalBlock = 'تحذير كبدي: ' + d.tradeNameAr + ' — ' + d.hepaticNotes;
    if (patientFlags.contains('CHILD') &&
        ['ADJUST', 'AVOID', 'CONTRAINDICATED'].contains(d.pediatricStatus))
      clinicalBlock =
          'تحذير للأطفال: ' + d.tradeNameAr + ' — ' + d.pediatricNotes;
    if (patientFlags.contains('ELDERLY') &&
        ['ADJUST', 'AVOID'].contains(d.geriatricStatus))
      clinicalBlock =
          'تحذير لكبار السن: ' + d.tradeNameAr + ' — ' + d.geriatricNotes;
    if (patientFlags.contains('BREASTFEEDING') &&
        ['L3', 'L4', 'L5'].contains(d.lactationRisk))
      clinicalBlock =
          'تحذير رضاعة: ' + d.tradeNameAr + ' — ' + d.lactationNotes;
  }

  Future<void> saveDrug(DrugModel drug) async {
    final now = DateTime.now().toIso8601String();
    final map = drug.toMap();
    map.remove('id');
    map['uuid'] =
        drug.uuid ?? 'drug-' + DateTime.now().microsecondsSinceEpoch.toString();
    map['branch_id'] = branchId;
    map['created_at'] = drug.createdAt ?? now;
    map['updated_at'] = now;
    map['internal_code'] = drug.internalCode.isEmpty
        ? 'DR-' + DateTime.now().microsecondsSinceEpoch.toString()
        : drug.internalCode;
    final stripsPerPack = drug.stripsPerPack ?? 1;
    final unitsPerStrip = drug.unitsPerStrip ?? 1;
    if (stripsPerPack < 1 || unitsPerStrip < 1) {
      throw ArgumentError('يجب أن يكون عدد الأشرطة والحبات أكبر من صفر');
    }
    map['sell_price_strip'] = drug.stripPriceMode == 'MANUAL'
        ? drug.sellPriceStrip
        : drug.sellPricePack / stripsPerPack;
    map['sell_price_unit'] =
        drug.sellPricePack / (stripsPerPack * unitsPerStrip);
    final db = await _db.database;
    if (drug.id == null) {
      // Stock is derived from FEFO batches and stock movements. A catalogue
      // form must never create stock without a traceable inventory batch.
      map['stock_total_units'] = 0;
      await db.insert('drugs', map);
    } else {
      final existing = await db.query(
        'drugs',
        columns: ['stock_total_units'],
        where: 'id=? AND branch_id=? AND is_deleted=0',
        whereArgs: [drug.id, branchId],
        limit: 1,
      );
      if (existing.isEmpty)
        throw StateError('الدواء غير موجود في الفرع الحالي');
      map['stock_total_units'] = existing.first['stock_total_units'];
      await db.update('drugs', map,
          where: 'id=? AND branch_id=?', whereArgs: [drug.id, branchId]);
    }
    await loadDrugs();
  }

  Future<int> checkout(
      {required int cashierId,
      required String saleType,
      required List<
              ({
                int cashAccountId,
                double amount,
                String method,
                String? walletRef
              })>
          payments,
      int? customerId,
      double discount = 0,
      bool managerApproved = false,
      int branchId = 1,
      required ClinicalVerdict clinicalVerdict}) async {
    if (currentTab.held) throw StateError('استرجع الفاتورة قبل إتمامها');
    if (clinicalBlock != null && !managerApproved)
      throw StateError('يلزم حذف الدواء المتعارض أو اعتماد المدير');
    final id = await _posting.postSale(
        branchId: branchId,
        cashierUserId: cashierId,
        items: List<CartItemModel>.from(cart),
        saleType: saleType,
        payments: payments,
        customerPartyId: customerId ?? 0,
        discountAmount: discount,
        clinicalVerdict: clinicalVerdict);
    currentTab.items.clear();
    currentTab.held = false;
    await loadDrugs();
    notifyListeners();
    return id;
  }
}
