import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/pos_and_drugs_provider.dart';
import '../../providers/session_and_erp_provider.dart';
import '../../core/theme/enterprise_dark_theme.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/erp_models.dart';
import '../../data/models/drug_model.dart';
import '../../data/models/pos_cash_tender.dart';
import '../../data/models/sale_unit_labels.dart';
import '../../providers/inventory_and_purchase_provider.dart';
import '../../providers/clinical_and_rx_provider.dart';
import 's04_clinical_guard_dialog.dart';
import 's05_drug_alternatives_sheet.dart';
import 's06_prescription_insurance_screen.dart';
import 's07_sales_returns_screen.dart';
import '../../data/database/database_helper.dart';
import '../../reports_pdf/engine/receipt_and_label_builder.dart';

class S03SmartPosScreen extends StatefulWidget {
  const S03SmartPosScreen({super.key});

  @override
  State<S03SmartPosScreen> createState() => _S03SmartPosScreenState();
}

class _S03SmartPosScreenState extends State<S03SmartPosScreen> {
  final search = TextEditingController();
  final walletRef = TextEditingController();
  final paidAmount = TextEditingController();
  final discountField = TextEditingController(text: '0');
  final tenderField = TextEditingController();
  Timer? _searchDebounce;
  bool _checkoutBusy = false;
  String method = 'CASH';
  String mixedChannel = 'CASH';
  int? customerId;
  int? cashId;
  double discount = 0;
  ReceiptData? _lastReceipt;
  final _receiptBuilder = const ReceiptAndLabelBuilder();

  double _net(PosAndDrugsProvider pos) =>
      (pos.total - discount).clamp(0, double.infinity).toDouble();

  void _scheduleSearch(PosAndDrugsProvider pos, String query) {
    _searchDebounce?.cancel();
    pos.invalidateSearch(query);
    final term = query.trim();
    if (term.isEmpty) {
      pos.loadDrugs();
      return;
    }
    if (term.length < 2) {
      pos.searchDrugs(term);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      if (mounted) pos.searchDrugs(term);
    });
  }

  @override
  void dispose() {
    search.dispose();
    walletRef.dispose();
    paidAmount.dispose();
    discountField.dispose();
    tenderField.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosAndDrugsProvider>();
    final session = context.watch<SessionAndErpProvider>();
    final inventory = context.watch<InventoryAndPurchaseProvider>();
    final clinical = context.watch<ClinicalAndRxProvider>();
    final wide = MediaQuery.sizeOf(context).width >= 700;

    return Focus(
      onKeyEvent: (node, event) {
        if (_checkoutBusy || pos.checkoutPending) return KeyEventResult.handled;
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.f9) {
          if (_lastReceipt != null) {
            _receiptBuilder.printReceiptNow(context, _lastReceipt!);
          } else {
            _message('لا توجد فاتورة محفوظة للطباعة بعد.');
          }
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.f8 &&
            pos.cart.isNotEmpty) {
          _finish(pos, session, inventory, clinical);
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.f12 &&
            pos.cart.isNotEmpty) {
          final item = pos.cart.last;
          S05DrugAlternativesSheet.show(
            context,
            item.drug,
            (replacement) => pos.replaceCartItem(item, replacement),
          );
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AbsorbPointer(
        absorbing: _checkoutBusy || pos.checkoutPending,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: true,
          body: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: wide
                ? Row(
                    children: [
                      Expanded(flex: 3, child: _catalog(pos)),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: _checkout(pos, session, inventory, clinical),
                      ),
                    ],
                  )
                : _mobileWorkspace(pos, session, inventory, clinical),
          ),
          bottomNavigationBar: wide
              ? null
              : _StickyCheckoutBar(
                  itemCount: pos.cart.length,
                  total: _net(pos),
                  onCheckout: pos.cart.isEmpty ||
                          _checkoutBusy ||
                          pos.checkoutPending
                      ? null
                      : () => _openCheckout(pos, session, inventory, clinical),
                ),
        ),
      ),
    );
  }

  Widget _mobileWorkspace(
    PosAndDrugsProvider pos,
    SessionAndErpProvider session,
    InventoryAndPurchaseProvider inventory,
    ClinicalAndRxProvider clinical,
  ) {
    return Column(
      children: [
        _tabStrip(pos),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: search,
                textInputAction: TextInputAction.search,
                onChanged: (value) => _scheduleSearch(pos, value),
                onSubmitted: (_) => _showDrugPicker(pos),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'اسم الدواء أو الباركود',
                ),
              ),
            ),
            const SizedBox(width: 7),
            IconButton.filledTonal(
              tooltip: 'اختيار دواء وإضافته',
              onPressed: () => _showDrugPicker(pos),
              icon: const Icon(Icons.add_shopping_cart),
            ),
            if (_lastReceipt != null) ...[
              const SizedBox(width: 5),
              IconButton(
                tooltip: 'طباعة آخر فاتورة',
                onPressed: () =>
                    _receiptBuilder.printReceiptNow(context, _lastReceipt!),
                icon: const Icon(Icons.print_outlined),
              ),
            ],
          ],
        ),
        const SizedBox(height: 7),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ActionChip(
            avatar: const Icon(
              Icons.health_and_safety_outlined,
              color: AppColors.primary,
            ),
            label: Text(
              clinical.currentPatient == null
                  ? 'حالة المريض والمحرك السريري'
                  : 'المريض: ${clinical.currentPatient!.fullName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: () => _showClinicalSheet(pos, clinical),
          ),
        ),
        if (pos.clinicalBlock != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ClinicalAlertBanner(
              message: pos.clinicalBlock!,
              level: ClinicalAlertLevel.block,
            ),
          ),
        Expanded(
          child: pos.cart.isEmpty
              ? _EmptyCart(onBrowse: () => _showDrugPicker(pos))
              : _cartList(pos, inventory, clinical),
        ),
      ],
    );
  }

  Widget _tabStrip(PosAndDrugsProvider pos) {
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < pos.tabs.length; i++)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ChoiceChip(
                      label: Text(
                        pos.tabs[i].label +
                            (pos.tabs[i].held ? ' • معلقة' : ''),
                      ),
                      selected: i == pos.activeTab,
                      onSelected: (_) => pos.selectTab(i),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'تبويب جديد',
            onPressed: pos.createTab,
            icon: const Icon(Icons.add_circle_outline),
          ),
          IconButton(
            tooltip: 'تعليق الفاتورة',
            onPressed: pos.holdCurrent,
            icon: const Icon(Icons.pause_circle_outline),
          ),
          IconButton(
            tooltip: 'استرجاع المعلقة',
            onPressed: pos.restoreCurrent,
            icon: const Icon(Icons.restore),
          ),
        ],
      ),
    );
  }

  Widget _catalog(PosAndDrugsProvider pos) => Column(
        children: [
          _tabStrip(pos),
          TextField(
            controller: search,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'اسم تجاري أو علمي أو باركود',
            ),
            onChanged: (value) => _scheduleSearch(pos, value),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: pos.drugs.length,
              itemBuilder: (context, i) {
                final drug = pos.drugs[i];
                return Card(
                  child: ListTile(
                    title: Text(drug.tradeNameAr),
                    subtitle: Text(
                      '${drug.scientificName} • مخزون ${drug.stockTotalUnits}',
                    ),
                    trailing: Text(MoneyFormatter.format(drug.sellPricePack)),
                    onTap: pos.currentTab.held ? null : () => pos.addDrug(drug),
                  ),
                );
              },
            ),
          ),
        ],
      );

  Future<void> _showDrugPicker(PosAndDrugsProvider pos) async {
    await KeyboardSafeModalSheet.show<void>(
      context: context,
      heightFactor: .9,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'اختيار دواء للسلة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          TextField(
            autofocus: true,
            onChanged: (value) => _scheduleSearch(pos, value),
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'الاسم التجاري أو العلمي أو الباركود',
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .58,
            child: Consumer<PosAndDrugsProvider>(
              builder: (context, current, _) => ListView.builder(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: current.drugs.length,
                itemBuilder: (context, index) {
                  final drug = current.drugs[index];
                  return Card(
                    child: ListTile(
                      title: Text(drug.tradeNameAr),
                      subtitle: Text(
                        '${drug.scientificName} • المتاح ${drug.stockTotalUnits} حبة',
                      ),
                      trailing: Text(MoneyFormatter.format(drug.sellPricePack)),
                      onTap: pos.currentTab.held
                          ? null
                          : () {
                              pos.addDrug(drug);
                              Navigator.pop(sheetContext);
                            },
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showClinicalSheet(
    PosAndDrugsProvider pos,
    ClinicalAndRxProvider clinical,
  ) async {
    await KeyboardSafeModalSheet.show<void>(
      context: context,
      heightFactor: .9,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ملف المريض والحماية السريرية',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            value: clinical.currentPatient?.id,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'المريض / الملف السريري',
            ),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('بدون ملف مريض'),
              ),
              ...clinical.patients.map(
                (patient) => DropdownMenuItem<int?>(
                  value: patient.id,
                  child: Text(patient.fullName),
                ),
              ),
            ],
            onChanged: (id) {
              final patient = id == null
                  ? null
                  : clinical.patients.firstWhere((item) => item.id == id);
              clinical.selectPatient(patient);
              setState(() => customerId = patient?.partyId);
            },
          ),
          const SizedBox(height: 12),
          const Text(
            'الحالات السريعة',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _flag(pos, clinical, 'PREGNANT', 'حامل'),
              _flag(pos, clinical, 'BREASTFEEDING', 'مرضع'),
              _flag(pos, clinical, 'KIDNEY', 'مريض كلى'),
              _flag(pos, clinical, 'LIVER', 'مريض كبد'),
              _flag(pos, clinical, 'CHILD', 'طفل'),
              _flag(pos, clinical, 'ELDERLY', 'مسن'),
            ],
          ),
          if (pos.clinicalBlock != null)
            ClinicalAlertBanner(
              message: pos.clinicalBlock!,
              level: ClinicalAlertLevel.block,
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => S04ClinicalGuardDialog.show(context),
            icon: const Icon(Icons.health_and_safety),
            label: const Text('فتح فحص الحماية السريرية الكامل'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const S06PrescriptionInsuranceScreen(),
              ),
            ),
            icon: const Icon(Icons.receipt_long),
            label: const Text('الوصفات والتأمين'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const S07SalesReturnsScreen()),
            ),
            icon: const Icon(Icons.assignment_return),
            label: const Text('مرتجع المبيعات'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(sheetContext),
            child: const Text('تم'),
          ),
        ],
      ),
    );
  }

  Widget _checkout(
    PosAndDrugsProvider pos,
    SessionAndErpProvider session,
    InventoryAndPurchaseProvider inventory,
    ClinicalAndRxProvider clinical,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: const Color(0x2239A9A0),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'تنبيه قبل إتمام البيع: أضف دواءً واحداً على الأقل وتأكد من الكمية، واختر الصندوق/المحفظة. '
                        'للبيع الآجل أو المختلط اختر العميل. عند الدفع بالمحفظة أدخل رقم إشعار صحيحاً (6 خانات على الأقل). '
                        'في البيع المختلط أدخل المبلغ المدفوع الآن وحدد وسيلة دفعه، ثم راجع الإجمالي قبل التأكيد.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _patientSelector(clinical),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: [
                _flag(pos, clinical, 'PREGNANT', 'حامل'),
                _flag(pos, clinical, 'BREASTFEEDING', 'مرضع'),
                _flag(pos, clinical, 'KIDNEY', 'مريض كلى'),
                _flag(pos, clinical, 'LIVER', 'مريض كبد'),
                _flag(pos, clinical, 'CHILD', 'طفل'),
                _flag(pos, clinical, 'ELDERLY', 'مسن'),
              ],
            ),
            if (pos.clinicalBlock != null)
              ClinicalAlertBanner(
                message: pos.clinicalBlock!,
                level: ClinicalAlertLevel.block,
              ),
            Expanded(child: _cartList(pos, inventory, clinical)),
            Text(
              'الصافي بعد الخصم: ${MoneyFormatter.format(_net(pos))}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _paymentFields(pos, session),
            if (_lastReceipt != null)
              OutlinedButton.icon(
                onPressed: () =>
                    _receiptBuilder.printReceiptNow(context, _lastReceipt!),
                icon: const Icon(Icons.print_outlined),
                label: const Text('طباعة آخر فاتورة'),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed:
                  pos.cart.isEmpty || _checkoutBusy || pos.checkoutPending
                      ? null
                      : () => _finish(pos, session, inventory, clinical),
              icon: const Icon(Icons.check_circle),
              label: Text(
                _checkoutBusy ? 'جارٍ حفظ الفاتورة...' : 'إتمام الفاتورة',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _patientSelector(ClinicalAndRxProvider clinical) {
    return DropdownButtonFormField<int?>(
      value: clinical.currentPatient?.id,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'المريض / الملف السريري'),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('بدون ملف مريض')),
        ...clinical.patients.map(
          (patient) => DropdownMenuItem<int?>(
            value: patient.id,
            child: Text(patient.fullName),
          ),
        ),
      ],
      onChanged: (id) {
        final patient = id == null
            ? null
            : clinical.patients.firstWhere((item) => item.id == id);
        clinical.selectPatient(patient);
        setState(() => customerId = patient?.partyId);
      },
    );
  }

  Widget _paymentFields(
    PosAndDrugsProvider pos,
    SessionAndErpProvider session, {
    StateSetter? sheetRefresh,
  }) {
    void update(VoidCallback action) {
      setState(action);
      sheetRefresh?.call(() {});
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: discountField,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'خصم إجمالي الفاتورة',
            helperText: 'لا يمكن أن يتجاوز الخصم قيمة الأصناف',
          ),
          onChanged: (value) =>
              update(() => discount = double.tryParse(value.trim()) ?? -1),
        ),
        const SizedBox(height: 8),
        if (method == 'CASH') ...[
          TextField(
            controller: tenderField,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'المبلغ المستلم من العميل (اختياري)',
            ),
            onChanged: (_) => update(() {}),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: tenderField,
            builder: (_, value, __) {
              if (value.text.trim().isEmpty) {
                return const Text(
                    'عدم إدخال المبلغ يعني الدفع بقيمة الفاتورة تمامًا');
              }
              try {
                final change = posCashChange(
                    netTotal: _net(pos), receivedText: value.text);
                return Text('الباقي للعميل: ${MoneyFormatter.format(change)}');
              } on StateError catch (error) {
                return Text(error.message);
              }
            },
          ),
          const SizedBox(height: 8),
        ],
        DropdownButtonFormField<String>(
          value: method,
          decoration: const InputDecoration(labelText: 'طريقة الدفع *'),
          items: const [
            DropdownMenuItem(value: 'CASH', child: Text('نقداً')),
            DropdownMenuItem(value: 'WALLET', child: Text('محفظة إلكترونية')),
            DropdownMenuItem(value: 'CREDIT', child: Text('آجل')),
            DropdownMenuItem(value: 'MIXED', child: Text('مختلط')),
          ],
          onChanged: (value) => update(() => method = value ?? 'CASH'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          value: cashId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'الصندوق / المحفظة *'),
          items: session.cashAccounts
              .map(
                (account) => DropdownMenuItem(
                  value: account.id,
                  child: Text(account.nameAr),
                ),
              )
              .toList(),
          onChanged: (value) => update(() => cashId = value),
        ),
        if (method == 'MIXED')
          TextField(
            controller: paidAmount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'المبلغ المدفوع الآن والباقي على حساب العميل',
            ),
            onChanged: (_) => update(() {}),
          ),
        if (method == 'MIXED')
          DropdownButtonFormField<String>(
            value: mixedChannel,
            decoration: const InputDecoration(labelText: 'وسيلة الجزء المدفوع'),
            items: const [
              DropdownMenuItem(value: 'CASH', child: Text('نقداً')),
              DropdownMenuItem(value: 'WALLET', child: Text('محفظة إلكترونية')),
            ],
            onChanged: (value) => update(() => mixedChannel = value ?? 'CASH'),
          ),
        if (method == 'WALLET' ||
            (method == 'MIXED' && mixedChannel == 'WALLET'))
          WalletRefField(controller: walletRef),
        if (method == 'CREDIT' || method == 'MIXED')
          DropdownButtonFormField<int>(
            value: customerId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'العميل *'),
            items: session.parties
                .where((party) => party.partyType == 'CUSTOMER')
                .map(
                  (party) => DropdownMenuItem(
                    value: party.id,
                    child: Text(party.nameAr),
                  ),
                )
                .toList(),
            onChanged: (value) => update(() => customerId = value),
          ),
        if (method == 'CREDIT' || method == 'MIXED')
          _creditPreview(pos, session),
      ],
    );
  }

  Widget _cartList(
    PosAndDrugsProvider pos,
    InventoryAndPurchaseProvider inventory,
    ClinicalAndRxProvider clinical,
  ) {
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: pos.cart.length,
      itemBuilder: (context, index) =>
          _cartLine(context, pos, pos.cart[index], inventory, clinical),
    );
  }

  Widget _flag(
    PosAndDrugsProvider pos,
    ClinicalAndRxProvider clinical,
    String code,
    String label,
  ) =>
      FilterChip(
        label: Text(label),
        selected: pos.patientFlags.contains(code),
        onSelected: (selected) {
          pos.setPatientFlag(code, selected);
          clinical.setQuickFlag(code, selected);
        },
      );

  Widget _cartLine(
    BuildContext context,
    PosAndDrugsProvider pos,
    CartItemModel item,
    InventoryAndPurchaseProvider inventory,
    ClinicalAndRxProvider clinical,
  ) {
    final lots = inventory.batches
        .where(
          (batch) =>
              batch.drugId == item.drug.id &&
              batch.status == 'ACTIVE' &&
              batch.daysUntilExpiry >= 0 &&
              batch.totalUnits > 0 &&
              inventory.warehouses.any(
                (warehouse) =>
                    warehouse.id == batch.warehouseId && warehouse.isSellable,
              ),
        )
        .toList()
      ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));

    var remaining = item.baseUnits;
    final plan = <String>[];
    for (final lot in lots) {
      if (remaining <= 0) break;
      final take = lot.totalUnits < remaining ? lot.totalUnits : remaining;
      plan.add('${lot.batchNo} • ${lot.expiryDate} ($take حبة)');
      remaining -= take;
    }
    final fefoText = plan.isEmpty
        ? 'لا توجد تشغيلة صالحة للبيع'
        : 'سحب FEFO المتوقع: ${plan.join(' ← ')}'
            '${remaining > 0 ? ' • نقص $remaining حبة' : ''}';

    return SmartExpandableCard(
      title: item.drug.tradeNameAr,
      primary: MoneyFormatter.format(item.lineTotal),
      secondary:
          '${item.quantity} ${drugSaleUnitLabel(item.drug, item.sellUnit)}',
      leading: const CircleAvatar(
        backgroundColor: Color(0x224DB6AC),
        child: Icon(Icons.medication, color: AppColors.primary),
      ),
      details: [
        Text(
          fefoText,
          style: TextStyle(
            color: remaining > 0 ? AppColors.danger : AppColors.success,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text('وحدة البيع'),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: item.sellUnit,
              items: drugAvailableSaleUnits(item.drug, selected: item.sellUnit)
                  .map(
                    (unit) => DropdownMenuItem(
                      value: unit,
                      child: Text(drugSaleUnitLabel(item.drug, unit)),
                    ),
                  )
                  .toList(),
              onChanged: (value) => pos.changeUnit(item, value ?? 'UNIT'),
            ),
            const Spacer(),
            IconButton.filledTonal(
              tooltip: 'تقليل الكمية',
              onPressed: item.quantity > 1
                  ? () => pos.changeQuantity(item, item.quantity - 1)
                  : null,
              icon: const Icon(Icons.remove),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                item.quantity.toStringAsFixed(
                  item.quantity.truncateToDouble() == item.quantity ? 0 : 2,
                ),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'زيادة الكمية',
              onPressed: () => pos.changeQuantity(item, item.quantity + 1),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            final expiry = lots.isEmpty ? 'غير محدد' : lots.first.expiryDate;
            final meal = switch (item.drug.takeWithFood) {
              'BEFORE' => 'قبل الأكل',
              'WITH' => 'مع الأكل',
              'AFTER' => 'بعد الأكل',
              _ => 'حسب تعليمات الصيدلي',
            };
            _receiptBuilder.printDoseLabelNow(
              context,
              DoseLabelData(
                pharmacyName: 'الصيدلية',
                patientName: clinical.currentPatient?.fullName ?? 'غير محدد',
                drugName: item.drug.tradeNameAr,
                strength: item.drug.strengthText,
                doseTextAr: item.drug.labelDoseTextAr.isEmpty
                    ? item.drug.dosageAdministration
                    : item.drug.labelDoseTextAr,
                mealInstruction: meal,
                expiryDate: expiry,
                keepRefrigerated: item.drug.requiresRefrigeration,
              ),
            );
          },
          icon: const Icon(Icons.label_outline),
          label: const Text('ملصق الجرعة'),
        ),
        OutlinedButton.icon(
          onPressed: () => S05DrugAlternativesSheet.show(
            context,
            item.drug,
            (replacement) => pos.replaceCartItem(item, replacement),
          ),
          icon: const Icon(Icons.swap_horiz),
          label: const Text('البدائل'),
        ),
        IconButton(
          tooltip: 'حذف من السلة',
          onPressed: () => pos.removeItem(item),
          icon: const Icon(Icons.delete_outline, color: AppColors.danger),
        ),
      ],
    );
  }

  Widget _creditPreview(
    PosAndDrugsProvider pos,
    SessionAndErpProvider session,
  ) {
    final matches =
        session.parties.where((party) => party.id == customerId).toList();
    if (matches.isEmpty) return const SizedBox.shrink();
    final party = matches.first;
    final paid =
        method == 'CREDIT' ? 0.0 : double.tryParse(paidAmount.text) ?? 0.0;
    final remaining = (_net(pos) - paid).clamp(0, double.infinity).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'المتبقي عليه بعد الفاتورة',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        PartyBalanceChip(
          totalAlayh: party.totalAlayh + remaining,
          totalLah: party.totalLah,
        ),
      ],
    );
  }

  Future<void> _openCheckout(
    PosAndDrugsProvider pos,
    SessionAndErpProvider session,
    InventoryAndPurchaseProvider inventory,
    ClinicalAndRxProvider clinical,
  ) async {
    await KeyboardSafeModalSheet.show<void>(
      context: context,
      heightFactor: .94,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refreshSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'الدفع وإتمام الفاتورة',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('عدد الأصناف: ${pos.cart.length}')),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: discountField,
                  builder: (_, __, ___) => Text(
                    MoneyFormatter.format(_net(pos)),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 22),
            _patientSelector(clinical),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                _flag(pos, clinical, 'PREGNANT', 'حامل'),
                _flag(pos, clinical, 'BREASTFEEDING', 'مرضع'),
                _flag(pos, clinical, 'KIDNEY', 'مريض كلى'),
                _flag(pos, clinical, 'LIVER', 'مريض كبد'),
                _flag(pos, clinical, 'CHILD', 'طفل'),
                _flag(pos, clinical, 'ELDERLY', 'مسن'),
              ],
            ),
            if (pos.clinicalBlock != null)
              ClinicalAlertBanner(
                message: pos.clinicalBlock!,
                level: ClinicalAlertLevel.block,
              ),
            OutlinedButton.icon(
              onPressed: () => S04ClinicalGuardDialog.show(context),
              icon: const Icon(Icons.health_and_safety),
              label: const Text('مراجعة التنبيهات السريرية'),
            ),
            const SizedBox(height: 8),
            _paymentFields(pos, session, sheetRefresh: refreshSheet),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed:
                  pos.cart.isEmpty || _checkoutBusy || pos.checkoutPending
                      ? null
                      : () async {
                          Navigator.pop(sheetContext);
                          await _finish(pos, session, inventory, clinical);
                        },
              icon: const Icon(Icons.check_circle),
              label: const Text('تأكيد الدفع وحفظ الفاتورة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finish(
    PosAndDrugsProvider pos,
    SessionAndErpProvider session,
    InventoryAndPurchaseProvider inventory,
    ClinicalAndRxProvider clinical,
  ) async {
    if (_checkoutBusy || pos.checkoutPending) return;
    setState(() => _checkoutBusy = true);
    try {
      final checkoutTab = pos.currentTab;
      final verdict = await clinical.evaluateCart(
        pos.cart.map((item) => item.drug).toList(),
      );
      if (verdict.hasUnresolvedCritical) {
        final approved = await S04ClinicalGuardDialog.show(context);
        if (!approved ||
            context
                .read<ClinicalAndRxProvider>()
                .verdict
                .hasUnresolvedCritical) {
          return;
        }
      }
      if (pos.clinicalBlock != null) {
        final approved = await ManagerPinDialog.show(
          context,
          verifier: session.verifyManagerPin,
        );
        if (!approved) return;
      }
      if (!mounted || pos.currentTab != checkoutTab) return;
      if (method != 'CREDIT' && cashId == null) {
        _message('اختر الصندوق أو المحفظة');
        return;
      }
      final tender = method == 'MIXED' ? mixedChannel : method;
      final isWallet = tender == 'WALLET';
      if (isWallet && walletRef.text.trim().length < 6) {
        _message('أدخل رقم إشعار صحيحاً');
        return;
      }
      final credit = method == 'CREDIT' || method == 'MIXED';
      if (credit && customerId == null) {
        _message('اختر العميل');
        return;
      }
      if (!discount.isFinite || discount < 0 || discount > pos.total) {
        _message('الخصم غير صحيح أو أكبر من إجمالي الفاتورة');
        return;
      }
      final net = _net(pos);
      final paid = method == 'CREDIT'
          ? 0.0
          : method == 'MIXED'
              ? (double.tryParse(paidAmount.text) ?? -1)
              : net;
      if (!paid.isFinite || paid < 0 || paid > net) {
        _message('أدخل مبلغاً مدفوعاً صحيحاً لا يتجاوز الصافي');
        return;
      }
      if (method == 'CASH') {
        try {
          posCashChange(netTotal: net, receivedText: tenderField.text);
        } on StateError catch (error) {
          _message(error.message);
          return;
        }
      }
      final List<
              ({int cashAccountId, double amount, String method, String? walletRef})>
          payments = paid > 0
              ? [
                  (
                    cashAccountId: cashId!,
                    amount: paid,
                    method: tender == 'WALLET' ? 'WALLET' : 'CASH',
                    walletRef: isWallet ? walletRef.text.trim() : null,
                  ),
                ]
              : <({
                  int cashAccountId,
                  double amount,
                  String method,
                  String? walletRef,
                })>[];
      int savedId;
      try {
        savedId = await pos.checkout(
          cashierId: (session.currentUser?['id'] as int?) ?? 1,
          saleType: method == 'CREDIT'
              ? 'CREDIT'
              : method == 'MIXED'
                  ? 'MIXED'
                  : 'CASH',
          payments: payments,
          customerId: customerId,
          discount: discount,
          managerApproved: pos.clinicalBlock != null,
          branchId: session.branchId,
          clinicalVerdict: clinical.verdict,
        );
      } catch (error) {
        _message('لم تُحفظ الفاتورة: $error');
        return;
      }
      // Committed sale must never be described as a failed transaction if a
      // subsequent receipt query or dashboard refresh fails.
      _lastReceipt = null;
      paidAmount.clear();
      walletRef.clear();
      discount = 0;
      discountField.text = '0';
      tenderField.clear();
      if (mounted) _message('تم حفظ الفاتورة رقم $savedId');
      try {
        if (mounted) await _loadReceipt(savedId);
        if (mounted) await session.refresh();
        if (mounted) await inventory.loadAll();
      } catch (error) {
        if (mounted) {
          _message('الفاتورة $savedId محفوظة، لكن تعذر تحديث الشاشة: $error');
        }
      }
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _checkoutBusy = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _loadReceipt(int invoiceId) async {
    final db = DatabaseHelper.instance;
    final invoiceRows = await db.rawQuery(
      '''
      SELECT i.*,COALESCE(p.name_ar,'عميل نقدي') AS customer_name,
        b.name_ar AS branch_name,b.phone AS branch_phone
      FROM sales_invoices i LEFT JOIN parties p ON p.id=i.customer_party_id
      LEFT JOIN branches b ON b.id=i.branch_id
      WHERE i.id=? LIMIT 1
    ''',
      [invoiceId],
    );
    if (invoiceRows.isEmpty) return;
    final row = invoiceRows.first;
    final items = await db.rawQuery(
      '''
      SELECT d.trade_name_ar,d.dosage_form,d.is_strip_based,si.sell_unit,si.qty_in_sell_unit,si.unit_price_sell_unit,si.line_total
      FROM sales_invoice_items si JOIN drugs d ON d.id=si.drug_id
      WHERE si.invoice_id=? ORDER BY si.id
    ''',
      [invoiceId],
    );
    final payments = await db.rawQuery(
      'SELECT method,wallet_ref_no FROM sales_payments WHERE invoice_id=? ORDER BY id',
      [invoiceId],
    );
    var paymentLabel = payments
        .map((entry) => entry['method']?.toString() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet()
        .join(' + ');
    if (row['sale_type'] == 'CREDIT' && paymentLabel.isEmpty) {
      paymentLabel = 'آجل';
    } else if (row['sale_type'] == 'MIXED') {
      paymentLabel = paymentLabel.isEmpty ? 'آجل' : '$paymentLabel + آجل';
    }
    final wallet = payments
        .map((entry) => entry['wallet_ref_no']?.toString() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final date = DateTime.tryParse(row['invoice_date']?.toString() ?? '') ??
        DateTime.now();
    _lastReceipt = ReceiptData(
      invoiceNumber: row['invoice_no']?.toString() ?? invoiceId.toString(),
      dateTime: date,
      customerName: row['customer_name']?.toString() ?? 'عميل نقدي',
      lines: items
          .map(
            (entry) => ReceiptLine(
              name: entry['trade_name_ar']?.toString() ?? '',
              unit: drugSaleUnitLabel(
                DrugModel.fromMap(entry),
                entry['sell_unit']?.toString() ?? '',
              ),
              quantity: (entry['qty_in_sell_unit'] as num?) ?? 0,
              unitPrice: (entry['unit_price_sell_unit'] as num?) ?? 0,
              total: (entry['line_total'] as num?) ?? 0,
            ),
          )
          .toList(),
      subtotal: (row['subtotal'] as num?) ?? 0,
      discount: (row['discount_amount'] as num?) ?? 0,
      rounding: (row['rounding_diff'] as num?) ?? 0,
      netTotal: (row['net_total'] as num?) ?? 0,
      paid: (row['paid_total'] as num?) ?? 0,
      paymentMethod: paymentLabel.isEmpty ? 'غير محدد' : paymentLabel,
      walletNotificationNumber: wallet.isEmpty ? null : wallet,
      remainingAfterInvoice: (row['remaining_alayh'] as num?) ?? 0,
      branchName: row['branch_name']?.toString() ?? 'الفرع الرئيسي',
      phone: row['branch_phone']?.toString() ?? '',
    );
  }
}

class _StickyCheckoutBar extends StatelessWidget {
  const _StickyCheckoutBar({
    required this.itemCount,
    required this.total,
    required this.onCheckout,
  });

  final int itemCount;
  final double total;
  final VoidCallback? onCheckout;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Material(
        color: AppColors.surface,
        elevation: 12,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
          child: Row(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$itemCount أصناف',
                    style: const TextStyle(color: Colors.white60),
                  ),
                  Text(
                    MoneyFormatter.format(total),
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onCheckout,
                  icon: const Icon(Icons.payment),
                  label: const Text('الدفع وإتمام الفاتورة'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.shopping_basket_outlined,
              size: 48,
              color: Colors.white38,
            ),
            const SizedBox(height: 10),
            const Text('السلة فارغة', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onBrowse,
              icon: const Icon(Icons.search),
              label: const Text('ابحث عن دواء'),
            ),
          ],
        ),
      );
}
