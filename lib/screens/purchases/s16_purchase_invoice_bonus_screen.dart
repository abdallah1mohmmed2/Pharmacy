// lib/screens/purchases/s16_purchase_invoice_bonus_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/inventory_and_purchase_provider.dart';
import '../../providers/session_and_erp_provider.dart';
import '../../providers/pos_and_drugs_provider.dart';
import '../../data/models/drug_model.dart';
import '../../data/models/purchase_input_parser.dart';
import 'purchase_medicine_search_sheet.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/services/purchase_and_bonus_service.dart';

class S16PurchaseInvoiceBonusScreen extends StatefulWidget {
  const S16PurchaseInvoiceBonusScreen({super.key});

  @override
  State<S16PurchaseInvoiceBonusScreen> createState() =>
      _S16PurchaseInvoiceBonusScreenState();
}

class _S16PurchaseInvoiceBonusScreenState
    extends State<S16PurchaseInvoiceBonusScreen> {
  int? supplier;
  int? warehouse;
  DrugModel? selectedPurchaseDrug;
  final Map<int, String> itemDrugNames = {};
  int? location;
  int? cash;
  String payment = 'CREDIT';
  bool bonusCost = true;
  bool saving = false;
  String? lineError;

  final invoice = TextEditingController();
  final supplierInvoice = TextEditingController();
  final batchNo = TextEditingController();
  final expiry = TextEditingController();
  final paidPacks = TextEditingController(text: '1');
  final bonus = TextEditingController(text: '0');
  final price = TextEditingController();
  final lineDiscount = TextEditingController(text: '0');
  final sellPrice = TextEditingController();
  final paid = TextEditingController(text: '0');
  final invoiceDiscount = TextEditingController(text: '0');
  final tax = TextEditingController(text: '0');

  final List<PurchaseLineInput> lines = [];

  @override
  void dispose() {
    for (final controller in [
      invoice,
      supplierInvoice,
      batchNo,
      expiry,
      paidPacks,
      bonus,
      price,
      lineDiscount,
      sellPrice,
      paid,
      invoiceDiscount,
      tax,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryAndPurchaseProvider>();
    final session = context.watch<SessionAndErpProvider>();
    final suppliers = session.parties
        .where((party) => party.partyType == 'SUPPLIER')
        .toList();
    final selectedSupplier =
        suppliers.where((party) => party.id == supplier).toList();
    final subtotal = lines.fold<double>(
      0,
      (sum, item) =>
          sum +
          item.qtyPacksPaid * item.packPrice * (1 - item.lineDiscountPct / 100),
    );
    final headerDiscount = parsePurchaseNumber(invoiceDiscount.text) ?? 0;
    final taxAmount = parsePurchaseNumber(tax.text) ?? 0;
    final netTotal = (subtotal - headerDiscount + taxAmount)
        .clamp(0, double.infinity)
        .toDouble();
    final paidNow =
        payment == 'CREDIT' ? 0.0 : parsePurchaseNumber(paid.text) ?? 0;
    final remaining = (netTotal - paidNow).clamp(0, double.infinity);
    final bonusValue = lines.fold<double>(
      0,
      (sum, item) => sum + item.bonusPacks * item.packPrice,
    );

    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const Card(
            color: Color(0x2239A9A0),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تنبيه: قبل ترحيل الشراء اختر المورد والمستودع وأضف بنداً واحداً على الأقل. '
                      'ولكل بند أدخل الدواء ورقم التشغيلة وتاريخ صلاحية مستقبلي والكمية المدفوعة وسعر التكلفة. '
                      'الرف مطلوب للأدوية المبردة، أما رقم فاتورة المورد وسعر البيع المقترح فاختياريان.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Text(
            'فواتير المشتريات والبونص',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          TextField(
            controller: invoice,
            decoration: const InputDecoration(labelText: 'رقم فاتورة النظام'),
          ),
          TextField(
            controller: supplierInvoice,
            decoration: const InputDecoration(labelText: 'رقم فاتورة المورد'),
          ),
          DropdownButtonFormField<int>(
            value: supplier,
            decoration: const InputDecoration(labelText: 'المورد *'),
            items: suppliers
                .map((party) => DropdownMenuItem(
                      value: party.id,
                      child: Text(party.nameAr),
                    ))
                .toList(),
            onChanged:
                saving ? null : (value) => setState(() => supplier = value),
          ),
          if (selectedSupplier.isNotEmpty)
            PartyBalanceChip(
              totalAlayh: selectedSupplier.first.totalAlayh,
              totalLah: selectedSupplier.first.totalLah,
            ),
          DropdownButtonFormField<int>(
            value: warehouse,
            decoration: const InputDecoration(
                labelText: 'المستودع *',
                helperText: 'يمكن اختياره أيضاً داخل نافذة إضافة البند'),
            items: inventory.warehouses
                .map((item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(item.nameAr),
                    ))
                .toList(),
            onChanged: saving || lines.isNotEmpty
                ? null
                : (value) => setState(() {
                      warehouse = value;
                      location = null;
                    }),
          ),
          DropdownButtonFormField<String>(
            value: payment,
            decoration: const InputDecoration(labelText: 'نوع الدفع'),
            items: const [
              DropdownMenuItem(value: 'CASH', child: Text('نقدي')),
              DropdownMenuItem(value: 'CREDIT', child: Text('آجل')),
              DropdownMenuItem(value: 'PARTIAL', child: Text('جزئي')),
            ],
            onChanged: saving
                ? null
                : (value) => setState(() => payment = value ?? payment),
          ),
          if (payment != 'CREDIT')
            DropdownButtonFormField<int>(
              value: cash,
              decoration: const InputDecoration(labelText: 'الصندوق / المحفظة'),
              items: session.cashAccounts
                  .map((account) => DropdownMenuItem(
                        value: account.id,
                        child: Text(account.nameAr),
                      ))
                  .toList(),
              onChanged:
                  saving ? null : (value) => setState(() => cash = value),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('بنود فاتورة المشتريات',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Text('عدد البنود: ${lines.length}',
                      style: const TextStyle(color: Colors.white60)),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: saving
                        ? null
                        : () => _showAddPurchaseItemSheet(inventory),
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('إضافة بند شراء'),
                  ),
                ],
              ),
            ),
          ),
          if (lines.isNotEmpty) ...[
            const Divider(),
            ...lines.map((item) {
              final name =
                  itemDrugNames[item.drugId] ?? 'دواء رقم ${item.drugId}';
              final lineTotal = item.qtyPacksPaid *
                  item.packPrice *
                  (1 - item.lineDiscountPct / 100);
              final effective = lineTotal /
                  (bonusCost
                      ? item.qtyPacksPaid + item.bonusPacks
                      : item.qtyPacksPaid);
              return Card(
                child: ListTile(
                  title: Text('$name • ${item.batchNo}'),
                  subtitle: Text(
                    'مدفوع ${item.qtyPacksPaid} + بونص ${item.bonusPacks} باكت'
                    '\nالتكلفة الفعلية للباكت بعد البونص: ${effective.toStringAsFixed(2)}'
                    '\nسعر البيع المقترح: ${item.newSellPricePack.toStringAsFixed(2)}',
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    onPressed: saving
                        ? null
                        : () => setState(() => lines.remove(item)),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              );
            }),
          ],
          const Divider(),
          TextField(
            controller: invoiceDiscount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'خصم إجمالي الفاتورة'),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: tax,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'الضريبة'),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: paid,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'المدفوع الآن'),
            enabled: payment != 'CREDIT' && !saving,
            onChanged: (_) => setState(() {}),
          ),
          _summaryLine('المجموع', subtotal),
          _summaryLine('الصافي بعد الخصم والضريبة', netTotal),
          _summaryLine('المدفوع الآن', paidNow),
          _summaryLine('المتبقي له للمورد', remaining),
          _summaryLine('قيمة البونص المكتسب', bonusValue),
          FilledButton.icon(
            onPressed:
                saving ? null : () => _post(inventory, session, netTotal),
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('ترحيل فاتورة المشتريات'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddPurchaseItemSheet(
    InventoryAndPurchaseProvider inventory,
  ) async {
    lineError = null;
    final branchId = context.read<SessionAndErpProvider>().branchId;
    if (selectedPurchaseDrug?.branchId != branchId) {
      selectedPurchaseDrug = null;
    }
    await KeyboardSafeModalSheet.show<void>(
      context: context,
      heightFactor: .94,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refreshSheet) {
          final coldRequired =
              selectedPurchaseDrug?.requiresRefrigeration ?? false;
          final shelves = inventory.shelves
              .where((shelf) => shelf.warehouseId == warehouse)
              .where((shelf) => !coldRequired || shelf.isFridge)
              .toList();
          final paidQuantity = parsePurchaseCount(paidPacks.text) ?? 0;
          final bonusQuantity = parsePurchaseCount(bonus.text) ?? 0;
          final unitCost = parsePurchaseNumber(price.text) ?? 0;
          final discountPct = parsePurchaseNumber(lineDiscount.text) ?? 0;
          final gross = paidQuantity * unitCost * (1 - discountPct / 100);
          final effectiveUnits =
              bonusCost ? paidQuantity + bonusQuantity : paidQuantity;
          final effectiveCost =
              effectiveUnits > 0 ? gross / effectiveUnits : 0.0;

          return AddPurchaseItemSheet(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('إضافة بند إلى فاتورة الشراء',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey('purchase-line-warehouse-$warehouse'),
                  value: inventory.warehouses.any((w) => w.id == warehouse)
                      ? warehouse
                      : null,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'مستودع البند *'),
                  items: inventory.warehouses
                      .map((w) => DropdownMenuItem<int>(
                          value: w.id, child: Text(w.nameAr)))
                      .toList(),
                  onChanged: saving || lines.isNotEmpty
                      ? null
                      : (value) {
                          setState(() {
                            warehouse = value;
                            location = null;
                            lineError = null;
                          });
                          refreshSheet(() {});
                        },
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.search),
                  label: Text(
                    selectedPurchaseDrug == null
                        ? 'ابحث واختر الدواء *'
                        : '${selectedPurchaseDrug!.tradeNameAr} • ${selectedPurchaseDrug!.internalCode}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: saving
                      ? null
                      : () async {
                          final picked =
                              await KeyboardSafeModalSheet.show<DrugModel>(
                            context: sheetContext,
                            heightFactor: .85,
                            builder: (_) => PurchaseMedicineSearchSheet(
                              search: (query) => context
                                  .read<PosAndDrugsProvider>()
                                  .searchPurchaseDrugs(
                                    query,
                                    branchId: branchId,
                                  ),
                            ),
                          );
                          if (picked == null ||
                              !mounted ||
                              !sheetContext.mounted) {
                            return;
                          }
                          setState(() {
                            selectedPurchaseDrug = picked;
                            location = null;
                            lineError = null;
                          });
                          refreshSheet(() {});
                        },
                ),
                const SizedBox(height: 8),
                TextField(
                    controller: batchNo,
                    decoration:
                        const InputDecoration(labelText: 'رقم التشغيلة *')),
                const SizedBox(height: 8),
                TextField(
                  controller: expiry,
                  keyboardType: TextInputType.datetime,
                  decoration: InputDecoration(
                    labelText: 'تاريخ الصلاحية *',
                    hintText: '2027-12-31 أو 31/12/2027 أو 12/2027',
                    helperText: 'عند إدخال شهر وسنة تُستخدم نهاية الشهر',
                    suffixIcon: IconButton(
                        tooltip: 'اختيار تاريخ الصلاحية',
                        icon: const Icon(Icons.calendar_month),
                        onPressed: () async {
                          final now = DateTime.now();
                          final today = DateTime(now.year, now.month, now.day);
                          final last = DateTime(now.year + 30, 12, 31);
                          final parsed = parsePurchaseExpiry(expiry.text);
                          final initial =
                              parsed == null || parsed.isBefore(today)
                                  ? today
                                  : parsed.isAfter(last)
                                      ? last
                                      : parsed;
                          final picked = await showDatePicker(
                              context: sheetContext,
                              initialDate: initial,
                              firstDate: today,
                              lastDate: last);
                          if (picked != null && sheetContext.mounted) {
                            expiry.text = purchaseExpiryIso(picked);
                            setState(() => lineError = null);
                            refreshSheet(() {});
                          }
                        }),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: location,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'موقع الرف'),
                  items: shelves
                      .map((item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(
                                item.code + (item.isFridge ? ' • مبرد' : '')),
                          ))
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) {
                          setState(() => location = value);
                          refreshSheet(() {});
                        },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: TextField(
                      controller: paidPacks,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'باكتات مدفوعة *'),
                      onChanged: (_) => refreshSheet(() {}),
                    )),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                      controller: bonus,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'باكتات بونص'),
                      onChanged: (_) => refreshSheet(() {}),
                    )),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: TextField(
                      controller: price,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'سعر الباكت *'),
                      onChanged: (_) => refreshSheet(() {}),
                    )),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                      controller: lineDiscount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'خصم البند %'),
                      onChanged: (_) => refreshSheet(() {}),
                    )),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: sellPrice,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'سعر البيع المقترح للباكت'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: bonusCost,
                  onChanged: saving
                      ? null
                      : (value) {
                          setState(() => bonusCost = value);
                          refreshSheet(() {});
                        },
                  title: const Text('احتساب البونص ضمن تخفيض التكلفة'),
                ),
                Card(
                  color: const Color(0x224DB6AC),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('التكلفة الفعلية بعد البونص',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        Text(effectiveCost.toStringAsFixed(2),
                            style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF4DB6AC))),
                        Text(
                            'الكمية المدفوعة: $paidQuantity • البونص: $bonusQuantity باكت'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (lineError != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(lineError!,
                          key: const ValueKey('purchase-line-error'),
                          style: const TextStyle(color: Colors.redAccent))),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final previousCount = lines.length;
                          await _addLine(inventory);
                          if (sheetContext.mounted) refreshSheet(() {});
                          if (lines.length > previousCount &&
                              sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة البند إلى الفاتورة'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _summaryLine(String label, num amount) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(amount.toStringAsFixed(2)),
          ],
        ),
      );

  void _rejectLine(String message) {
    setState(() => lineError = message);
  }

  Future<void> _addLine(
    InventoryAndPurchaseProvider inventory,
  ) async {
    final selected = selectedPurchaseDrug;
    final packs = parsePurchaseCount(paidPacks.text);
    final free = bonus.text.trim().isEmpty ? 0 : parsePurchaseCount(bonus.text);
    final cost = parsePurchaseNumber(price.text);
    final discountPct = lineDiscount.text.trim().isEmpty
        ? 0.0
        : parsePurchaseNumber(lineDiscount.text);
    final suggested = sellPrice.text.trim().isEmpty
        ? 0.0
        : parsePurchaseNumber(sellPrice.text);
    final expiryDate = parsePurchaseExpiry(expiry.text);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (selected == null || selected.id == null) {
      _rejectLine('اختر الدواء من نتائج البحث؛ كتابة الاسم وحدها لا تكفي.');
      return;
    }
    if (selected.branchId != context.read<SessionAndErpProvider>().branchId) {
      _rejectLine('الدواء لا يتبع الفرع الحالي؛ أعد اختياره من البحث.');
      return;
    }
    if (warehouse == null ||
        !inventory.warehouses.any((w) => w.id == warehouse)) {
      _rejectLine('اختر مستودع البند أولاً.');
      return;
    }
    if (batchNo.text.trim().isEmpty) {
      _rejectLine('أدخل رقم التشغيلة.');
      return;
    }
    if (expiryDate == null) {
      _rejectLine(
          'تاريخ الصلاحية غير صحيح؛ استخدم 2027-12-31 أو 31/12/2027 أو 12/2027.');
      return;
    }
    if (expiryDate.isBefore(today)) {
      _rejectLine('تاريخ الصلاحية منتهٍ؛ أدخل تاريخ اليوم أو بعده.');
      return;
    }
    if (packs == null || packs <= 0) {
      _rejectLine('أدخل عدد الباكتات المدفوعة كعدد صحيح أكبر من صفر.');
      return;
    }
    if (free == null || free < 0) {
      _rejectLine('البونص يجب أن يكون عدداً صحيحاً يساوي صفراً أو أكثر.');
      return;
    }
    if (cost == null || cost < 0) {
      _rejectLine('أدخل سعر الباكت كرقم صالح يساوي صفراً أو أكثر.');
      return;
    }
    if (discountPct == null || discountPct < 0 || discountPct > 100) {
      _rejectLine('خصم البند يجب أن يكون رقماً من 0 إلى 100.');
      return;
    }
    if (suggested == null || suggested < 0) {
      _rejectLine(
          'سعر البيع المقترح غير صحيح؛ أدخل رقماً موجباً أو اتركه فارغاً.');
      return;
    }
    if (selected.requiresRefrigeration) {
      final shelf = inventory.shelves.where((item) => item.id == location);
      if (shelf.isEmpty || !shelf.first.isFridge) {
        _rejectLine('الدواء المبرد يجب وضعه على رف مبرد');
        return;
      }
      final selectedWarehouse =
          inventory.warehouses.where((item) => item.id == warehouse);
      if (selectedWarehouse.isEmpty || !selectedWarehouse.first.isFridge) {
        _rejectLine('الدواء المبرد يجب توريده إلى مستودع الثلاجة');
        return;
      }
    }
    if (location != null &&
        !inventory.shelves.any(
            (item) => item.id == location && item.warehouseId == warehouse)) {
      _rejectLine('موقع الرف لا يتبع المستودع المحدد');
      return;
    }
    setState(() {
      lineError = null;
      itemDrugNames[selected.id!] = selected.tradeNameAr;
      lines.add(
        PurchaseLineInput(
          drugId: selected.id!,
          batchNo: batchNo.text.trim(),
          expiryDate: purchaseExpiryIso(expiryDate),
          warehouseId: warehouse!,
          qtyPacksPaid: packs,
          bonusPacks: free,
          packPrice: cost,
          locationId: location,
          lineDiscountPct: discountPct,
          newSellPricePack: suggested,
        ),
      );
      batchNo.clear();
      expiry.clear();
      paidPacks.text = '1';
      bonus.text = '0';
      price.clear();
      lineDiscount.text = '0';
      sellPrice.clear();
    });
  }

  Future<void> _post(
    InventoryAndPurchaseProvider inventory,
    SessionAndErpProvider session,
    double netTotal,
  ) async {
    final paidNow =
        payment == 'CREDIT' ? 0.0 : parsePurchaseNumber(paid.text) ?? 0;
    final discountAmount = parsePurchaseNumber(invoiceDiscount.text) ?? 0;
    final taxAmount = parsePurchaseNumber(tax.text) ?? 0;
    if (supplier == null ||
        warehouse == null ||
        lines.isEmpty ||
        discountAmount < 0 ||
        taxAmount < 0 ||
        paidNow < 0 ||
        paidNow > netTotal ||
        (payment == 'CASH' && (paidNow - netTotal).abs() > 0.005) ||
        (payment == 'PARTIAL' && (paidNow <= 0 || paidNow >= netTotal)) ||
        (payment != 'CREDIT' && paidNow > 0 && cash == null)) {
      _message(
          'تحقق من المورد والمستودع والبنود والخصم والضريبة وبيانات السداد');
      return;
    }
    setState(() => saving = true);
    try {
      inventory.branchId = session.branchId;
      final id = await inventory.postPurchase(
        supplierId: supplier!,
        warehouseId: warehouse!,
        invoiceNo: invoice.text,
        paymentType: payment,
        paid: paidNow,
        items: lines,
        cashAccountId: cash,
        bonusIncluded: bonusCost,
        discount: discountAmount,
        tax: taxAmount,
        supplierInvoiceNo: supplierInvoice.text,
      );
      await session.refresh();
      if (!mounted) return;
      setState(() {
        lines.clear();
        itemDrugNames.clear();
        paid.text = '0';
        invoiceDiscount.text = '0';
        tax.text = '0';
        saving = false;
      });
      _message('تم ترحيل فاتورة المشتريات رقم $id');
    } catch (error) {
      if (mounted) setState(() => saving = false);
      _message(error.toString());
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }
}

class AddPurchaseItemSheet extends StatelessWidget {
  const AddPurchaseItemSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
