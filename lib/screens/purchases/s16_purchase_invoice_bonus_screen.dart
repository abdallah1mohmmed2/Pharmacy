// lib/screens/purchases/s16_purchase_invoice_bonus_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/inventory_and_purchase_provider.dart';
import '../../providers/session_and_erp_provider.dart';
import '../../providers/pos_and_drugs_provider.dart';
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
  int? drug;
  int? location;
  int? cash;
  String payment = 'CREDIT';
  bool bonusCost = true;
  bool saving = false;

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
    final pos = context.watch<PosAndDrugsProvider>();
    final suppliers =
        session.parties.where((party) => party.partyType == 'SUPPLIER').toList();
    final selectedSupplier =
        suppliers.where((party) => party.id == supplier).toList();
    final subtotal = lines.fold<double>(
      0,
      (sum, item) =>
          sum +
          item.qtyPacksPaid *
              item.packPrice *
              (1 - item.lineDiscountPct / 100),
    );
    final headerDiscount = double.tryParse(invoiceDiscount.text) ?? 0;
    final taxAmount = double.tryParse(tax.text) ?? 0;
    final netTotal =
        (subtotal - headerDiscount + taxAmount).clamp(0, double.infinity);
    final paidNow = payment == 'CREDIT' ? 0.0 : double.tryParse(paid.text) ?? 0;
    final remaining = (netTotal - paidNow).clamp(0, double.infinity);
    final bonusValue = lines.fold<double>(
      0,
      (sum, item) => sum + item.bonusPacks * item.packPrice,
    );
    final shelves = inventory.shelves
        .where((shelf) => shelf.warehouseId == warehouse)
        .where((shelf) {
      final selectedDrugs = pos.drugs.where((item) => item.id == drug);
      if (selectedDrugs.isEmpty || !selectedDrugs.first.requiresRefrigeration) {
        return true;
      }
      return shelf.isFridge;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
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
            decoration: const InputDecoration(labelText: 'المورد'),
            items: suppliers
                .map((party) => DropdownMenuItem(
                      value: party.id,
                      child: Text(party.nameAr),
                    ))
                .toList(),
            onChanged: saving ? null : (value) => setState(() => supplier = value),
          ),
          if (selectedSupplier.isNotEmpty)
            PartyBalanceChip(
              totalAlayh: selectedSupplier.first.totalAlayh,
              totalLah: selectedSupplier.first.totalLah,
            ),
          DropdownButtonFormField<int>(
            value: warehouse,
            decoration: const InputDecoration(labelText: 'المستودع'),
            items: inventory.warehouses
                .map((item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(item.nameAr),
                    ))
                .toList(),
            onChanged: saving
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
              onChanged: saving ? null : (value) => setState(() => cash = value),
            ),
          const Divider(),
          const Text(
            'إضافة بند شراء',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          DropdownButtonFormField<int>(
            value: drug,
            decoration: const InputDecoration(labelText: 'الدواء'),
            items: pos.drugs
                .map((item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(item.tradeNameAr),
                    ))
                .toList(),
            onChanged: saving
                ? null
                : (value) => setState(() {
                      drug = value;
                      location = null;
                    }),
          ),
          TextField(
            controller: batchNo,
            decoration: const InputDecoration(labelText: 'رقم التشغيلة'),
          ),
          TextField(
            controller: expiry,
            decoration: const InputDecoration(
              labelText: 'الصلاحية YYYY-MM-DD',
              hintText: '2027-12-31',
            ),
          ),
          DropdownButtonFormField<int>(
            value: location,
            decoration: const InputDecoration(labelText: 'موقع الرف'),
            items: shelves
                .map((item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(item.code + (item.isFridge ? ' • مبرد' : '')),
                    ))
                .toList(),
            onChanged: saving
                ? null
                : (value) => setState(() => location = value),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: paidPacks,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'باكتات مدفوعة'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: bonus,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'باكتات بونص'),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'سعر الباكت'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: lineDiscount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'خصم البند %'),
                ),
              ),
            ],
          ),
          TextField(
            controller: sellPrice,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:
                const InputDecoration(labelText: 'سعر البيع المقترح للباكت'),
          ),
          SwitchListTile(
            value: bonusCost,
            onChanged: saving ? null : (value) => setState(() => bonusCost = value),
            title: const Text('احتساب البونص ضمن تخفيض التكلفة'),
          ),
          FilledButton(
            onPressed: saving ? null : () => _addLine(pos, inventory),
            child: const Text('إضافة البند إلى الفاتورة'),
          ),
          if (lines.isNotEmpty) ...[
            const Divider(),
            ...lines.map((item) {
              final matches = pos.drugs.where((drug) => drug.id == item.drugId);
              final name = matches.isEmpty
                  ? 'دواء رقم ${item.drugId}'
                  : matches.first.tradeNameAr;
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
            onPressed: saving ? null : () => _post(inventory, session, netTotal),
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

  Widget _summaryLine(String label, num amount) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(amount.toStringAsFixed(2)),
          ],
        ),
      );

  Future<void> _addLine(
    PosAndDrugsProvider pos,
    InventoryAndPurchaseProvider inventory,
  ) async {
    final selected = pos.drugs.where((item) => item.id == drug).toList();
    final packs = int.tryParse(paidPacks.text) ?? 0;
    final free = int.tryParse(bonus.text) ?? 0;
    final cost = double.tryParse(price.text) ?? -1;
    final discountPct = double.tryParse(lineDiscount.text) ?? 0;
    final expiryDate = DateTime.tryParse(expiry.text.trim());
    if (selected.isEmpty ||
        warehouse == null ||
        batchNo.text.trim().isEmpty ||
        expiryDate == null ||
        DateTime(expiryDate.year, expiryDate.month, expiryDate.day)
            .isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)) ||
        packs <= 0 ||
        free < 0 ||
        cost < 0 ||
        discountPct < 0 ||
        discountPct > 100) {
      _message('تحقق من الدواء والتشغيلة والصلاحية والكميات والسعر والخصم');
      return;
    }
    if (selected.first.requiresRefrigeration) {
      final shelf = inventory.shelves.where((item) => item.id == location);
      if (shelf.isEmpty || !shelf.first.isFridge) {
        _message('الدواء المبرد يجب وضعه على رف مبرد');
        return;
      }
      final selectedWarehouse =
          inventory.warehouses.where((item) => item.id == warehouse);
      if (selectedWarehouse.isEmpty || !selectedWarehouse.first.isFridge) {
        _message('الدواء المبرد يجب توريده إلى مستودع الثلاجة');
        return;
      }
    }
    if (location != null &&
        !inventory.shelves.any((item) =>
            item.id == location && item.warehouseId == warehouse)) {
      _message('موقع الرف لا يتبع المستودع المحدد');
      return;
    }
    setState(() {
      lines.add(
        PurchaseLineInput(
          drugId: drug!,
          batchNo: batchNo.text.trim(),
          expiryDate: expiry.text.trim(),
          warehouseId: warehouse!,
          qtyPacksPaid: packs,
          bonusPacks: free,
          packPrice: cost,
          locationId: location,
          lineDiscountPct: discountPct,
          newSellPricePack: double.tryParse(sellPrice.text) ?? 0,
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
    final paidNow = payment == 'CREDIT' ? 0.0 : double.tryParse(paid.text) ?? 0;
    final discountAmount = double.tryParse(invoiceDiscount.text) ?? 0;
    final taxAmount = double.tryParse(tax.text) ?? 0;
    if (supplier == null ||
        warehouse == null ||
        lines.isEmpty ||
        discountAmount < 0 ||
        taxAmount < 0 ||
        paidNow < 0 ||
        paidNow > netTotal ||
        (payment == 'CASH' && (paidNow - netTotal).abs() > 0.005) ||
        (payment != 'CREDIT' && paidNow > 0 && cash == null)) {
      _message('تحقق من المورد والمستودع والبنود والخصم والضريبة وبيانات السداد');
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
