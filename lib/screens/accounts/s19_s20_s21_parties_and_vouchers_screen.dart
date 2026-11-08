import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/session_and_erp_provider.dart';
import '../../data/models/erp_models.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../core/theme/enterprise_dark_theme.dart';
import 'party_extensions_screen.dart';
import '../../reports_pdf/registry/report_registry_and_provider.dart';

class S19S20S21PartiesAndVouchersScreen extends StatefulWidget {
  const S19S20S21PartiesAndVouchersScreen({super.key});
  @override
  State<S19S20S21PartiesAndVouchersScreen> createState() =>
      _S19S20S21PartiesAndVouchersScreenState();
}

class _S19S20S21PartiesAndVouchersScreenState
    extends State<S19S20S21PartiesAndVouchersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController tabs = TabController(length: 3, vsync: this);
  final searchController = TextEditingController();
  String query = '';
  String balanceFilter = 'ALL';
  @override
  void dispose() {
    tabs.dispose();
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SessionAndErpProvider>();
    return Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addParty(context),
            icon: const Icon(Icons.person_add),
            label: const Text('إضافة طرف')),
        body: Column(children: [
          TabBar(controller: tabs, tabs: const [
            Tab(text: 'العملاء'),
            Tab(text: 'الموردون / المذاخر'),
            Tab(text: 'خدمات الأطراف')
          ]),
          Expanded(
              child: TabBarView(controller: tabs, children: [
            _partyList(p, 'CUSTOMER'),
            _partyList(p, 'SUPPLIER'),
            const PartyExtensionsScreen()
          ])),
        ]));
  }

  Widget _partyList(SessionAndErpProvider p, String type) {
    final list = p.parties
        .where((party) =>
            party.partyType == type &&
            (query.isEmpty ||
                party.nameAr.toLowerCase().contains(query) ||
                party.phone.toLowerCase().contains(query) ||
                party.code.toLowerCase().contains(query)) &&
            (balanceFilter == 'ALL' ||
                (balanceFilter == 'ALAYH' &&
                    party.totalAlayh > party.totalLah) ||
                (balanceFilter == 'LAH' && party.totalLah > party.totalAlayh) ||
                (balanceFilter == 'SETTLED' &&
                    (party.totalAlayh - party.totalLah).abs() < .005)))
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: CompactSearchAndFilterBar(
            controller: searchController,
            hintText: type == 'CUSTOMER'
                ? 'ابحث عن عميل بالاسم أو الهاتف'
                : 'ابحث عن مورد بالاسم أو الهاتف',
            onChanged: (value) =>
                setState(() => query = value.trim().toLowerCase()),
            activeFilterCount: balanceFilter == 'ALL' ? 0 : 1,
            onFilter: _showPartyFilters,
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('لا توجد أطراف مطابقة للبحث.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final party = list[index];
                    return SmartExpandableCard(
                      title: party.nameAr,
                      primary: party.phone.isEmpty
                          ? 'لا يوجد رقم هاتف'
                          : party.phone,
                      secondary: party.code,
                      leading: CircleAvatar(
                        backgroundColor: const Color(0x224DB6AC),
                        child: Icon(
                            type == 'CUSTOMER'
                                ? Icons.person_outline
                                : Icons.local_shipping_outlined,
                            color: AppColors.primary),
                      ),
                      trailing: PartyBalanceChip(
                        totalAlayh: party.totalAlayh,
                        totalLah: party.totalLah,
                        compact: true,
                      ),
                      details: [
                        Text(type == 'CUSTOMER'
                            ? (party.isPatient ? 'عميل • ملف طبي نشط' : 'حساب عميل')
                            : 'حساب مورد / مذخر'),
                        if (party.address.isNotEmpty)
                          Text('العنوان: ${party.address}'),
                        if (party.creditLimit > 0)
                          Text(
                              'حد الائتمان: ${party.creditLimit.toStringAsFixed(2)}'),
                      ],
                      actions: [
                        OutlinedButton.icon(
                          onPressed: () => _statement(p, party),
                          icon: const Icon(Icons.receipt_long),
                          label: const Text('كشف الحساب'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => _voucher(p, party),
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('سند قبض / صرف'),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _showPartyFilters() async {
    await KeyboardSafeModalSheet.show<void>(
      context: context,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('تصفية الحسابات',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          for (final option in const [
            ('ALL', 'جميع الحسابات'),
            ('ALAYH', 'لديه مبلغ متبقٍ عليه'),
            ('LAH', 'لديه مبلغ متبقٍ له'),
            ('SETTLED', 'حسابات مسددة'),
          ])
            RadioListTile<String>(
              value: option.$1,
              groupValue: balanceFilter,
              title: Text(option.$2),
              onChanged: (value) {
                setState(() => balanceFilter = value ?? 'ALL');
                Navigator.pop(sheetContext);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _statement(SessionAndErpProvider p, PartyModel party) async {
    final entries = await p.ledger(party.id!);
    if (!mounted) return;
    final rows = <LahAlayhRow>[];
    if (party.openingAlayh > 0 || party.openingLah > 0) {
      rows.add(LahAlayhRow(
          date: '—',
          statement: 'رصيد افتتاحي',
          document: 'OPENING',
          alayh: party.openingAlayh,
          lah: party.openingLah));
    }
    for (final e in entries) {
      final a = (e['alayh_amount'] as num).toDouble();
      final l = (e['lah_amount'] as num).toDouble();
      rows.add(LahAlayhRow(
          date: (e['entry_date'] as String).split('T').first,
          statement: e['statement_ar'] as String,
          document: (e['doc_type'] as String) +
              ' #' +
              (e['doc_id']?.toString() ?? ''),
          alayh: a,
          lah: l));
    }
    await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text('كشف حساب • ' + party.nameAr),
                content: SizedBox(
                    width: 850,
                    height: 500,
                    child: Column(children: [
                      PartyBalanceChip(
                          totalAlayh: party.totalAlayh,
                          totalLah: party.totalLah),
                      const SizedBox(height: 12),
                      Expanded(child: LahAlayhTable(rows: rows))
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('إغلاق')),
                  OutlinedButton.icon(
                      onPressed: () => _printPartyStatement(p, party),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('طباعة كشف PDF')),
                  FilledButton.icon(
                      onPressed: () => _voucher(p, party),
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('سند قبض / صرف'))
                ]));
  }

  Future<void> _printPartyStatement(
      SessionAndErpProvider session, PartyModel party) async {
    final user = session.currentUser;
    if (user == null || party.id == null) return;
    final reports = context.read<ReportsCenterProvider>();
    final reportNumber = party.partyType == 'CUSTOMER' ? 33 : 36;
    try {
      await reports.initialize(
          userId: user['id'] as int,
          userName: user['full_name'] as String? ?? '',
          branchId: session.branchId);
      reports.selectReport(reportNumber);
      reports.updateParams({'party_id': party.id});
      final data = await reports.runSelected();
      final definition = reports.selected;
      if (data != null && definition != null)
        await reports.engine.preview(
            definition: definition, data: data, params: reports.params);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('تعذر إنشاء كشف الحساب: $e')));
    }
  }

  Future<void> _voucher(SessionAndErpProvider p, PartyModel party) async {
    final amount = TextEditingController();
    final note = TextEditingController();
    final ref = TextEditingController();
    String type = party.partyType == 'CUSTOMER' ? 'RECEIPT' : 'PAYMENT';
    String method = 'CASH';
    int? cashId = p.cashAccounts.isEmpty ? null : p.cashAccounts.first.id;
    await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, set) => AlertDialog(
                    title: const Text('إصدار سند'),
                    content: SizedBox(
                        width: 430,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              DropdownButtonFormField<String>(
                                  value: type,
                                  decoration: const InputDecoration(
                                      labelText: 'نوع السند'),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'RECEIPT',
                                        child: Text('سند قبض من عميل')),
                                    DropdownMenuItem(
                                        value: 'PAYMENT',
                                        child: Text('سند صرف لمورد')),
                                    DropdownMenuItem(
                                        value: 'SETTLEMENT',
                                        child: Text('تسوية مالية'))
                                  ],
                                  onChanged: (v) => set(() {
                                        type = v ?? type;
                                        if (type != 'SETTLEMENT' &&
                                            method == 'OFFSET') method = 'CASH';
                                      })),
                              TextField(
                                  controller: amount,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'المبلغ')),
                              if (method != 'OFFSET')
                                DropdownButtonFormField<int>(
                                    value: cashId,
                                    decoration: const InputDecoration(
                                        labelText: 'الصندوق / المحفظة'),
                                    items: p.cashAccounts
                                        .map((a) => DropdownMenuItem(
                                            value: a.id, child: Text(a.nameAr)))
                                        .toList(),
                                    onChanged: (v) => set(() => cashId = v)),
                              DropdownButtonFormField<String>(
                                  value: method,
                                  decoration: const InputDecoration(
                                      labelText: 'وسيلة الدفع'),
                                  items: [
                                    const DropdownMenuItem(
                                        value: 'CASH', child: Text('نقداً')),
                                    const DropdownMenuItem(
                                        value: 'WALLET', child: Text('محفظة')),
                                    const DropdownMenuItem(
                                        value: 'BANK', child: Text('بنك')),
                                    if (type == 'SETTLEMENT')
                                      const DropdownMenuItem(
                                          value: 'OFFSET',
                                          child: Text('تسوية بدون نقدية'))
                                  ],
                                  onChanged: (v) => set(() {
                                        method = v ?? 'CASH';
                                        if (method == 'OFFSET') {
                                          cashId = null;
                                        } else {
                                          cashId ??= p.cashAccounts.isEmpty
                                              ? null
                                              : p.cashAccounts.first.id;
                                        }
                                      })),
                              if (method == 'WALLET')
                                TextField(
                                    controller: ref,
                                    textDirection: TextDirection.ltr,
                                    decoration: const InputDecoration(
                                        labelText: 'رقم إشعار المحفظة')),
                              TextField(
                                  controller: note,
                                  decoration: const InputDecoration(
                                      labelText: 'البيان')),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('إلغاء')),
                      FilledButton(
                          onPressed: () async {
                            final value = double.tryParse(amount.text);
                            if (value == null ||
                                value <= 0 ||
                                (method != 'OFFSET' && cashId == null) ||
                                (method == 'WALLET' &&
                                    ref.text.trim().length < 6)) return;
                            final no = 'VCH-' +
                                DateTime.now()
                                    .microsecondsSinceEpoch
                                    .toString();
                            try {
                              await p.issueVoucher(
                                  voucherNo: no,
                                  type: type,
                                  partyId: party.id!,
                                  cashAccountId: cashId,
                                  amount: value,
                                  method: method,
                                  walletRef: method == 'WALLET'
                                      ? ref.text.trim()
                                      : null,
                                  description: note.text);
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('تم حفظ السند')));
                            } catch (e) {
                              if (mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())));
                            }
                          },
                          child: const Text('حفظ السند'))
                    ])));
    amount.dispose();
    note.dispose();
    ref.dispose();
    await p.refresh();
  }

  Future<void> _addParty(BuildContext context) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final code = TextEditingController(
        text: 'PTY-' + DateTime.now().millisecondsSinceEpoch.toString());
    final opening = TextEditingController();
    String type = 'CUSTOMER';
    bool createPatient = false;
    String side = 'ALAYH';
    await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, set) => AlertDialog(
                    title: const Text('إضافة عميل أو مورد'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<String>(
                          value: type,
                          items: const [
                            DropdownMenuItem(
                                value: 'CUSTOMER', child: Text('عميل')),
                            DropdownMenuItem(
                                value: 'SUPPLIER', child: Text('مورد / مذخر'))
                          ],
                          onChanged: (v) => set(() {
                            type = v ?? type;
                            if (type != 'CUSTOMER') createPatient = false;
                          })),
                      if (type == 'CUSTOMER')
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: createPatient,
                          title: const Text('تفعيل الملف الطبي لهذا العميل'),
                          subtitle: const Text('سيظهر في اختيار المرضى للوصفات والرقابة السريرية والتأمين.'),
                          onChanged: (value) => set(() => createPatient = value ?? false),
                        ),
                      TextField(
                          controller: code,
                          decoration:
                              const InputDecoration(labelText: 'الكود')),
                      TextField(
                          controller: name,
                          decoration:
                              const InputDecoration(labelText: 'الاسم')),
                      TextField(
                          controller: phone,
                          decoration:
                              const InputDecoration(labelText: 'الهاتف')),
                      TextField(
                          controller: opening,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'الرصيد الافتتاحي (اختياري)')),
                      DropdownButtonFormField<String>(
                          value: side,
                          items: const [
                            DropdownMenuItem(
                                value: 'ALAYH', child: Text('عليه')),
                            DropdownMenuItem(value: 'LAH', child: Text('له'))
                          ],
                          onChanged: (v) => set(() => side = v ?? side)),
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('إلغاء')),
                      FilledButton(
                          onPressed: () async {
                            if (name.text.trim().isEmpty) return;
                            final v = double.tryParse(opening.text) ?? 0;
                            await context
                                .read<SessionAndErpProvider>()
                                .createParty(
                                    PartyModel(
                                        partyType: type,
                                        code: code.text,
                                        nameAr: name.text,
                                        phone: phone.text),
                                    openingAlayh: side == 'ALAYH' ? v : 0,
                                    openingLah: side == 'LAH' ? v : 0,
                                    createPatient: createPatient);
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          child: const Text('حفظ'))
                    ])));
    name.dispose();
    phone.dispose();
    code.dispose();
    opening.dispose();
    await context.read<SessionAndErpProvider>().refresh();
  }
}
