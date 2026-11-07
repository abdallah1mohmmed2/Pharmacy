// lib/screens/hr_partners/s26_owner_partners_profit_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/database/database_helper.dart';
import '../../providers/treasury_hr_partner_provider.dart';
import '../../providers/session_and_erp_provider.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../core/theme/enterprise_dark_theme.dart';
import '../../reports_pdf/registry/report_registry_and_provider.dart';

class S26OwnerPartnersProfitScreen extends StatefulWidget {
  const S26OwnerPartnersProfitScreen({super.key});
  @override
  State<S26OwnerPartnersProfitScreen> createState() =>
      _S26OwnerPartnersProfitScreenState();
}

class _S26OwnerPartnersProfitScreenState
    extends State<S26OwnerPartnersProfitScreen>
    with SingleTickerProviderStateMixin {
  late final tabs = TabController(length: 2, vsync: this);
  final period = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 7));
  final reserve = TextEditingController(text: '10');
  int? draftId;
  bool calculating = false;
  @override
  void dispose() {
    tabs.dispose();
    period.dispose();
    reserve.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TreasuryHrPartnerProvider>();
    final mode = p.partnerPolicy.mode;
    return Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                const Align(
                    alignment: Alignment.centerRight,
                    child: Text('المالك والشركاء وتوزيع الأرباح',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold))),
                Row(children: [
                  const Text('نمط التوزيع: '),
                  Expanded(
                      child: SegmentedButton<String>(
                          segments: const [
                        ButtonSegment(
                            value: 'shares',
                            label: Text('نظام الحصص (الأسهم)')),
                        ButtonSegment(
                            value: 'percentage',
                            label: Text('نظام النسب المئوية (%)'))
                      ],
                          selected: {
                        mode
                      },
                          onSelectionChanged: (v) =>
                              _switchMode(context, p, v.first)))
                ])
              ])),
          TabBar(controller: tabs, tabs: const [
            Tab(text: 'الشركاء ورأس المال'),
            Tab(text: 'صافي الربح وتوزيعه')
          ]),
          Expanded(
              child: TabBarView(
                  controller: tabs, children: [_partners(p), _profit(p)]))
        ]));
  }

  Widget _partners(TreasuryHrPartnerProvider p) {
    final total = p.partners.fold<double>(
      0,
      (sum, entry) => sum + ((entry['shares_count'] as num?)?.toDouble() ?? 0),
    );
    return ListView(
      padding: const EdgeInsets.all(12),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.group, color: AppColors.primary),
            title: const Text('إدارة الشركاء'),
            subtitle: Text(
                'النظام الحالي: ${p.partnerPolicy.mode == 'shares' ? 'الحصص' : 'النسب المئوية'}'),
            trailing: IconButton(
              onPressed: () => _addPartner(context, p),
              icon: const Icon(Icons.person_add_alt_1),
            ),
          ),
        ),
        ...p.partners.map((partner) {
          final shares = (partner['shares_count'] as num?)?.toDouble();
          final percentage = (partner['percentage'] as num?)?.toDouble();
          final ratio = total <= 0 ? 0 : (shares ?? 0) / total * 100;
          final mode = p.partnerPolicy.mode;
          return SmartExpandableCard(
            title: partner['name_ar'].toString(),
            primary:
                'رأس المال: ${((partner['capital_amount'] as num?) ?? 0).toStringAsFixed(2)}',
            secondary: mode == 'shares'
                ? 'الحصص: ${shares?.toStringAsFixed(0) ?? '—'} • الحصة المشتقة: ${ratio.toStringAsFixed(2)}%'
                : 'النسبة: ${percentage?.toStringAsFixed(2) ?? 'غير محددة'}%',
            leading: const CircleAvatar(
              backgroundColor: Color(0x224DB6AC),
              child: Icon(Icons.groups_outlined, color: AppColors.primary),
            ),
            trailing: PartyBalanceChip(
              totalAlayh: ((partner['total_alayh'] as num?) ?? 0).toDouble(),
              totalLah: ((partner['total_lah'] as num?) ?? 0).toDouble(),
              compact: true,
            ),
            details: [
              if (partner['needs_input'] == 1)
                const ClinicalAlertBanner(
                  message: 'يلزم استكمال بيانات التوزيع',
                  level: ClinicalAlertLevel.warning,
                ),
              Text(mode == 'shares'
                  ? 'نظام الحصص فعال؛ النسبة المعروضة مشتقة للقراءة فقط.'
                  : 'نظام النسب المئوية فعال؛ حقول الحصص مقفلة.'),
            ],
            actions: [
              OutlinedButton.icon(
                onPressed: () => _editPartner(context, p, partner),
                icon: const Icon(Icons.edit),
                label: const Text('تعديل بيانات'),
              ),
              OutlinedButton.icon(
                onPressed: () => _withdraw(context, p, partner),
                icon: const Icon(Icons.outbox),
                label: const Text('سحب شخصي'),
              ),
              OutlinedButton.icon(
                onPressed: () => _statement(context, partner),
                icon: const Icon(Icons.receipt_long),
                label: const Text('كشف حساب'),
              ),
            ],
          );
        }),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _addPartner(context, p),
          icon: const Icon(Icons.add),
          label: const Text('إضافة شريك'),
        ),
      ],
    );
  }

  Widget _profit(TreasuryHrPartnerProvider p) {
    final summary = p.profitSummary;
    final net = summary['net_profit'] ?? 0;
    return ListView(
        padding: const EdgeInsets.all(12),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          TextField(
              controller: period,
              decoration: const InputDecoration(labelText: 'الفترة (YYYY-MM)')),
          TextField(
              controller: reserve,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'نسبة الاحتياطي المحتجز %')),
          FilledButton.icon(
              onPressed: calculating
                  ? null
                  : () async {
                      setState(() => calculating = true);
                      try {
                        await p.calculateProfit(period.text.trim());
                      } catch (e) {
                        if (mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString())));
                      }
                      if (mounted) setState(() => calculating = false);
                    },
              icon: const Icon(Icons.calculate),
              label: const Text('حساب قائمة الدخل وصافي الربح')),
          if (summary.isNotEmpty)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _metric(
                              'إجمالي المبيعات', summary['gross_sales'] ?? 0),
                          _metric(
                              'المرتجعات والخصومات',
                              (summary['returns'] ?? 0) +
                                  (summary['discounts'] ?? 0)),
                          _metric('صافي المبيعات', summary['net_sales'] ?? 0),
                          _metric('تكلفة البضاعة المباعة COGS',
                              summary['cogs'] ?? 0),
                          _metric('المصروفات التشغيلية',
                              summary['operating_expenses'] ?? 0),
                          _metric('الرواتب واليوميات', summary['wages'] ?? 0),
                          _metric(
                              'خسائر أخرى', summary['additional_losses'] ?? 0),
                          const Divider(),
                          _metric('صافي الربح', net,
                              color: net >= 0
                                  ? const Color(0xFF66BB6A)
                                  : const Color(0xFFEF5350)),
                          _metric(
                              'الربح القابل للتوزيع بعد الاحتياطي',
                              net *
                                  (1 -
                                      (double.tryParse(reserve.text) ?? 0) /
                                          100),
                              color: const Color(0xFF4DB6AC))
                        ]))),
          FilledButton.icon(
              onPressed: summary.isEmpty || net < 0
                  ? null
                  : () async {
                      try {
                        final id = await p.createDistribution(
                            period: period.text.trim(),
                            reservePct: double.parse(reserve.text));
                        setState(() => draftId = id);
                        if (mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('تم إنشاء معاينة توزيع الأرباح')));
                      } catch (e) {
                        if (mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString())));
                      }
                    },
              icon: const Icon(Icons.account_balance),
              label: const Text('إنشاء مسودة توزيع الأرباح')),
          if (draftId != null)
            FutureBuilder<List<Map<String, Object?>>>(
                future: DatabaseHelper.instance.rawQuery(
                    'SELECT l.*,p.name_ar FROM partner_distribution_lines l JOIN partners x ON x.id=l.partner_id JOIN parties p ON p.id=x.party_id WHERE l.distribution_id=? ORDER BY l.id',
                    [draftId]),
                builder: (context, snapshot) {
                  final rows = snapshot.data ?? [];
                  final table = SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('الشريك')),
                        DataColumn(label: Text('الأساس')),
                        DataColumn(label: Text('نصيبه (له)')),
                        DataColumn(label: Text('مسحوباته (عليه)')),
                        DataColumn(label: Text('الصافي')),
                      ],
                      rows: rows
                          .map((row) => DataRow(cells: [
                                DataCell(Text(row['name_ar'].toString())),
                                DataCell(Text((row['basis_value'] as num)
                                    .toStringAsFixed(2))),
                                DataCell(Text((row['share_amount_lah'] as num)
                                    .toStringAsFixed(2))),
                                DataCell(Text((row['withdrawals_alayh'] as num)
                                    .toStringAsFixed(2))),
                                DataCell(Text((row['net_payable'] as num)
                                    .toStringAsFixed(2))),
                              ]))
                          .toList(),
                    ),
                  );
                  final mobileCards = Column(
                    children: rows
                        .map((row) => SmartExpandableCard(
                              title: row['name_ar'].toString(),
                              primary:
                                  'الصافي: ${(row['net_payable'] as num).toStringAsFixed(2)}',
                              secondary:
                                  'نصيبه: ${(row['share_amount_lah'] as num).toStringAsFixed(2)}',
                              details: [
                                Text(
                                    'أساس التوزيع: ${(row['basis_value'] as num).toStringAsFixed(2)}'),
                                Text(
                                    'مسحوباته: ${(row['withdrawals_alayh'] as num).toStringAsFixed(2)}'),
                              ],
                            ))
                        .toList(),
                  );
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('معاينة التوزيع',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          ResponsiveLayout(mobile: mobileCards, desktop: table),
                          FilledButton(
                            onPressed: () => _postDraftDistribution(p),
                            child: const Text('اعتماد وترحيل توزيع الأرباح'),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
          const SizedBox(height: 16),
          const Text('التوزيعات السابقة',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ...p.distributions.map((d) => ListTile(
              title: Text('${d['distribution_no']} • ${d['period_code']}'),
              subtitle: Text(
                  'النمط: ${d['distribution_mode']} • الحالة: ${d['status']}'),
              trailing:
                  Text((d['distributable_profit'] as num).toStringAsFixed(2))))
        ]);
  }

  Future<void> _postDraftDistribution(TreasuryHrPartnerProvider p) async {
    final id = draftId;
    if (id == null) return;
    try {
      await p.postDistribution(id);
      if (mounted) {
        setState(() => draftId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم اعتماد وترحيل توزيع الأرباح')),
        );
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
    }
  }

  Widget _metric(String label, double value, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label)),
        Text(value.toStringAsFixed(2),
            style: TextStyle(fontWeight: FontWeight.bold, color: color))
      ]));
  Future<void> _switchMode(
      BuildContext context, TreasuryHrPartnerProvider p, String mode) async {
    if (mode == p.partnerPolicy.mode) return;
    final session = context.read<SessionAndErpProvider>();
    final pin = TextEditingController();
    final approved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('تغيير نظام توزيع الأرباح'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(mode == 'shares'
                      ? 'سيتم مسح النسب المئوية لجميع الشركاء وإلزامهم بإدخال الحصص.'
                      : 'سيتم مسح عدد الحصص لجميع الشركاء وإلزامهم بإدخال النسب.'),
                  TextField(
                      controller: pin,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'رمز اعتماد المالك / المدير'))
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('إلغاء')),
                  FilledButton(
                      onPressed: () async {
                        final ok = await session.verifyManagerPin(pin.text);
                        if (ctx.mounted) Navigator.pop(ctx, ok);
                      },
                      child: const Text('اعتماد التغيير'))
                ]));
    pin.dispose();
    if (approved == true) {
      try {
        final managerId = session.consumeVerifiedManagerUserId();
        if (managerId == null)
          throw StateError('تعذر تحديد هوية المدير المعتمد');
        await p.switchDistributionMode(mode, managerUserId: managerId);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('تم تغيير نمط التوزيع وقفل الحقول المقابلة')));
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _addPartner(
      BuildContext context, TreasuryHrPartnerProvider p) async {
    final mode = p.partnerPolicy.mode;
    final name = TextEditingController();
    final code = TextEditingController(
      text: 'PART-${DateTime.now().millisecondsSinceEpoch}',
    );
    final capital = TextEditingController(text: '0');
    final shares = TextEditingController(text: mode == 'percentage' ? '—' : '');
    final percentage = TextEditingController(text: mode == 'shares' ? '—' : '');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة شريك'),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'اسم الشريك')),
                TextField(
                    controller: code,
                    decoration: const InputDecoration(labelText: 'كود الشريك')),
                TextField(
                    controller: capital,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'رأس المال')),
                TextField(
                    controller: shares,
                    enabled: mode == 'shares',
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: 'عدد الحصص',
                        suffixIcon:
                            mode == 'shares' ? null : const Icon(Icons.lock))),
                TextField(
                    controller: percentage,
                    enabled: mode == 'percentage',
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: 'النسبة المئوية (%)',
                        suffixIcon: mode == 'percentage'
                            ? null
                            : const Icon(Icons.lock))),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              try {
                final partnerName = name.text.trim();
                final partnerCode = code.text.trim();
                final capitalValue = double.tryParse(capital.text);
                if (partnerName.isEmpty || partnerCode.isEmpty) {
                  throw ArgumentError('اسم الشريك والكود مطلوبان');
                }
                if (capitalValue == null || capitalValue < 0) {
                  throw ArgumentError('رأس المال يجب أن يكون صفراً أو أكبر');
                }
                final sh = mode == 'shares' ? int.parse(shares.text) : null;
                final pc =
                    mode == 'percentage' ? double.parse(percentage.text) : null;
                await p.validatePartnerFields(shares: sh, percentage: pc);
                final db = await DatabaseHelper.instance.database;
                final now = DateTime.now().toIso8601String();
                await db.transaction((txn) async {
                  final partyId = await txn.insert('parties', {
                    'uuid': 'partner-${DateTime.now().microsecondsSinceEpoch}',
                    'branch_id': p.branchId,
                    'created_at': now,
                    'updated_at': now,
                    'party_type': 'PARTNER',
                    'code': partnerCode,
                    'name_ar': partnerName,
                    'opening_alayh': 0,
                    'opening_lah': 0,
                  });
                  await txn.insert('partners', {
                    'party_id': partyId,
                    'capital_amount': capitalValue,
                    'shares_count': sh,
                    'percentage': pc,
                    'needs_input': 0,
                    'join_date': now.substring(0, 10),
                    'is_active': 1,
                    'branch_id': p.branchId,
                  });
                });
                if (ctx.mounted) Navigator.pop(ctx);
                await p.refresh();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text(e.toString())));
                }
              }
            },
            child: const Text('حفظ الشريك'),
          ),
        ],
      ),
    );
    name.dispose();
    code.dispose();
    capital.dispose();
    shares.dispose();
    percentage.dispose();
  }

  Future<void> _editPartner(BuildContext context, TreasuryHrPartnerProvider p,
      Map<String, Object?> partner) async {
    final mode = p.partnerPolicy.mode;
    final name =
        TextEditingController(text: partner['name_ar']?.toString() ?? '');
    final capital = TextEditingController(
        text: ((partner['capital_amount'] as num?) ?? 0).toString());
    final shares = TextEditingController(
        text: mode == 'shares'
            ? (partner['shares_count']?.toString() ?? '0')
            : '—');
    final percentage = TextEditingController(
        text: mode == 'percentage'
            ? (partner['percentage']?.toString() ?? '0')
            : '—');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل بيانات الشريك'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'اسم الشريك')),
              TextField(
                  controller: capital,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'رأس المال')),
              TextField(
                  controller: shares,
                  enabled: mode == 'shares',
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: 'عدد الحصص',
                      suffixIcon:
                          mode == 'shares' ? null : const Icon(Icons.lock))),
              TextField(
                  controller: percentage,
                  enabled: mode == 'percentage',
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: 'النسبة المئوية (%)',
                      suffixIcon: mode == 'percentage'
                          ? null
                          : const Icon(Icons.lock))),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              try {
                final partnerName = name.text.trim();
                final capitalValue = double.parse(capital.text);
                if (partnerName.isEmpty || capitalValue < 0) {
                  throw ArgumentError('تحقق من اسم الشريك ورأس المال');
                }
                final sh = mode == 'shares' ? int.parse(shares.text) : null;
                final pc =
                    mode == 'percentage' ? double.parse(percentage.text) : null;
                await p.validatePartnerFields(shares: sh, percentage: pc);
                final db = await DatabaseHelper.instance.database;
                final now = DateTime.now().toIso8601String();
                await db.transaction((txn) async {
                  final partyChanged = await txn.update(
                    'parties',
                    {'name_ar': partnerName, 'updated_at': now},
                    where: 'id=? AND branch_id=?',
                    whereArgs: [partner['party_id'], p.branchId],
                  );
                  final partnerChanged = await txn.update(
                    'partners',
                    {
                      'capital_amount': capitalValue,
                      'shares_count': sh,
                      'percentage': pc,
                      'needs_input': 0,
                    },
                    where: 'id=? AND branch_id=?',
                    whereArgs: [partner['id'], p.branchId],
                  );
                  if (partyChanged != 1 || partnerChanged != 1) {
                    throw StateError('الشريك غير موجود في الفرع الحالي');
                  }
                });
                if (ctx.mounted) Navigator.pop(ctx);
                await p.refresh();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text(e.toString())));
                }
              }
            },
            child: const Text('حفظ التعديلات'),
          ),
        ],
      ),
    );
    name.dispose();
    capital.dispose();
    shares.dispose();
    percentage.dispose();
  }

  Future<void> _withdraw(BuildContext context, TreasuryHrPartnerProvider p,
      Map<String, Object?> partner) async {
    if (p.cashAccounts.isEmpty) return;
    int account = p.cashAccounts.first['id'] as int;
    final amount = TextEditingController();
    final note = TextEditingController(text: 'سحب شخصي للشريك');
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('سحب شخصي • ${partner['name_ar']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: account,
                  items: p.cashAccounts
                      .map((a) => DropdownMenuItem(
                          value: a['id'] as int,
                          child: Text(a['name_ar'].toString())))
                      .toList(),
                  onChanged: (v) => set(() => account = v ?? account),
                ),
                TextField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'المبلغ')),
                TextField(
                    controller: note,
                    decoration: const InputDecoration(labelText: 'البيان')),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                try {
                  final value = double.parse(amount.text);
                  if (value <= 0)
                    throw ArgumentError('المبلغ يجب أن يكون أكبر من صفر');
                  final db = await DatabaseHelper.instance.database;
                  final now = DateTime.now().toIso8601String();
                  final partyId = partner['party_id'] as int;
                  await db.transaction((txn) async {
                    final partnerRows = await txn.query(
                      'partners',
                      columns: ['id'],
                      where:
                          'id=? AND party_id=? AND branch_id=? AND is_active=1',
                      whereArgs: [partner['id'], partyId, p.branchId],
                      limit: 1,
                    );
                    if (partnerRows.isEmpty)
                      throw StateError('الشريك غير موجود في الفرع الحالي');
                    final cashRows = await txn.query(
                      'cash_accounts',
                      where: 'id=? AND branch_id=? AND is_deleted=0',
                      whereArgs: [account, p.branchId],
                      limit: 1,
                    );
                    if (cashRows.isEmpty)
                      throw StateError('حساب النقد غير موجود في الفرع الحالي');
                    final cash = cashRows.first;
                    final currentBalance =
                        (cash['current_balance'] as num).toDouble();
                    if (currentBalance < value)
                      throw StateError('رصيد الحساب لا يكفي');
                    final glRows = await txn.query(
                      'chart_of_accounts',
                      columns: ['id'],
                      where: "code='2301'",
                      limit: 1,
                    );
                    if (glRows.isEmpty)
                      throw StateError(
                          'حساب سحوبات الشركاء غير موجود في دليل الحسابات');
                    final cashGl = cash['gl_account_id'] as int?;
                    if (cashGl == null)
                      throw StateError('اربط حساب النقد بدليل الحسابات');
                    final token = DateTime.now().microsecondsSinceEpoch;
                    final je = await txn.insert('journal_entries', {
                      'uuid': 'partner-withdraw-je-$token',
                      'branch_id': p.branchId,
                      'created_at': now,
                      'updated_at': now,
                      'entry_no': 'PW-$token',
                      'entry_date': now,
                      'description': note.text.trim(),
                      'source_type': 'PARTNER_WITHDRAWAL',
                      'source_id': partner['id'],
                      'is_posted': 1,
                    });
                    await txn.insert('journal_lines', {
                      'uuid': 'pwl1-$token',
                      'branch_id': p.branchId,
                      'created_at': now,
                      'updated_at': now,
                      'journal_entry_id': je,
                      'account_id': glRows.first['id'],
                      'party_id': partyId,
                      'dr_amount': value,
                      'cr_amount': 0,
                      'memo': note.text.trim(),
                    });
                    await txn.insert('journal_lines', {
                      'uuid': 'pwl2-$token',
                      'branch_id': p.branchId,
                      'created_at': now,
                      'updated_at': now,
                      'journal_entry_id': je,
                      'account_id': cashGl,
                      'party_id': null,
                      'dr_amount': 0,
                      'cr_amount': value,
                      'memo': note.text.trim(),
                    });
                    final balanceAfter = currentBalance - value;
                    await txn.update(
                      'cash_accounts',
                      {'current_balance': balanceAfter, 'updated_at': now},
                      where: 'id=? AND branch_id=?',
                      whereArgs: [account, p.branchId],
                    );
                    final shiftRows = await txn.query(
                      'cashier_shifts',
                      columns: ['id'],
                      where:
                          "branch_id=? AND drawer_account_id=? AND status='OPEN'",
                      whereArgs: [p.branchId, account],
                      orderBy: 'id DESC',
                      limit: 1,
                    );
                    final txId = await txn.insert('cash_transactions', {
                      'cash_account_id': account,
                      'tx_date': now,
                      'direction': 'OUT',
                      'amount': value,
                      'tx_type': 'PARTNER_WITHDRAWAL',
                      'doc_type': 'JOURNAL',
                      'doc_id': je,
                      'cashier_shift_id':
                          shiftRows.isEmpty ? null : shiftRows.first['id'],
                      'balance_after': balanceAfter,
                      'note': note.text.trim(),
                      'branch_id': p.branchId,
                    });
                    await txn.insert('lah_alayh_ledger', {
                      'uuid': 'partner-withdraw-ledger-$token',
                      'branch_id': p.branchId,
                      'created_at': now,
                      'updated_at': now,
                      'party_id': partyId,
                      'entry_date': now,
                      'entry_type': 'PARTNER_WITHDRAWAL',
                      'alayh_amount': value,
                      'lah_amount': 0,
                      'doc_type': 'CASH_TRANSACTION',
                      'doc_id': txId,
                      'journal_entry_id': je,
                      'statement_ar': note.text.trim(),
                    });
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  await p.refresh();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                }
              },
              child: const Text('تسجيل السحب'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    note.dispose();
  }

  Future<void> _statement(
      BuildContext context, Map<String, Object?> partner) async {
    final rows = await DatabaseHelper.instance.rawQuery(
      'SELECT * FROM lah_alayh_ledger WHERE party_id=? ORDER BY entry_date,id',
      [partner['party_id']],
    );
    if (!mounted) return;
    final ledgerRows = rows
        .map((row) => LahAlayhRow(
              date: row['entry_date'].toString().split('T').first,
              statement: row['statement_ar']?.toString() ?? '',
              document: row['doc_type']?.toString() ?? '',
              alayh: (row['alayh_amount'] as num?) ?? 0,
              lah: (row['lah_amount'] as num?) ?? 0,
            ))
        .toList();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('كشف حساب • ${partner['name_ar']}'),
        content: SizedBox(
          width: 850,
          height: 500,
          child: Column(
            children: [
              PartyBalanceChip(
                totalAlayh: (partner['total_alayh'] as num?) ?? 0,
                totalLah: (partner['total_lah'] as num?) ?? 0,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ResponsiveLayout(
                  mobile: LahAlayhTable(rows: ledgerRows),
                  desktop: LahAlayhTable(rows: ledgerRows, forceTable: true),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
          OutlinedButton.icon(
            onPressed: () => _printPartnerStatement(partner),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('طباعة PDF'),
          ),
        ],
      ),
    );
  }

  Future<void> _printPartnerStatement(Map<String, Object?> partner) async {
    final session = context.read<SessionAndErpProvider>();
    final user = session.currentUser;
    if (user == null) return;
    final reports = context.read<ReportsCenterProvider>();
    try {
      await reports.initialize(
          userId: user['id'] as int,
          userName: user['full_name'] as String? ?? '',
          branchId: session.branchId);
      reports.selectReport(45);
      reports.updateParams({'partner_id': partner['id']});
      final data = await reports.runSelected();
      final definition = reports.selected;
      if (data != null && definition != null)
        await reports.engine.preview(
            definition: definition, data: data, params: reports.params);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('تعذر طباعة كشف الشريك: $e')));
    }
  }
}
