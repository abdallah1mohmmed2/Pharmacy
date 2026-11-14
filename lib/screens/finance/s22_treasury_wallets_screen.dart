// lib/screens/finance/s22_treasury_wallets_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/database/database_helper.dart';
import '../../providers/treasury_hr_partner_provider.dart';
import '../../providers/session_and_erp_provider.dart';

class S22TreasuryWalletsScreen extends StatefulWidget {
  const S22TreasuryWalletsScreen({super.key});
  @override
  State<S22TreasuryWalletsScreen> createState() =>
      _S22TreasuryWalletsScreenState();
}

class _S22TreasuryWalletsScreenState extends State<S22TreasuryWalletsScreen> {
  String? _loadedSession;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<SessionAndErpProvider>();
    final userId = session.currentUser?['id'] as int?;
    if (userId == null) return;
    final branchId = session.branchId;
    final key = '$branchId:$userId';
    if (_loadedSession == key) return;
    _loadedSession = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<TreasuryHrPartnerProvider>()
          .loadTreasury(branchId: branchId, userId: userId);
    });
  }

  Future<void> _reload() {
    final session = context.read<SessionAndErpProvider>();
    return context.read<TreasuryHrPartnerProvider>().loadTreasury(
        branchId: session.branchId, userId: session.currentUser?['id'] as int?);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TreasuryHrPartnerProvider>();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return Scaffold(
        backgroundColor: Colors.transparent,
        body: RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  LayoutBuilder(builder: (context, constraints) {
                    final actions = Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        IconButton(
                            onPressed: () => _addAccount(context),
                            icon: const Icon(Icons.add_card),
                            tooltip: 'إضافة حساب'),
                        FilledButton.icon(
                            onPressed: p.operationPending
                                ? null
                                : () => _transfer(context, p),
                            icon: const Icon(Icons.swap_horiz),
                            label: const Text('تحويل'))
                      ],
                    );
                    if (constraints.maxWidth < 520) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('الخزينة والصناديق والمحافظ',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          actions,
                        ],
                      );
                    }
                    return Row(children: [
                      const Expanded(
                          child: Text('الخزينة والصناديق والمحافظ',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold))),
                      actions,
                    ]);
                  }),
                  const SizedBox(height: 12),
                  if (p.treasuryLoading) const LinearProgressIndicator(),
                  if (p.treasuryError != null) ...[
                    Text('تعذر تحميل بيانات الخزينة: ${p.treasuryError}',
                        style: const TextStyle(color: Color(0xFFEF5350))),
                    TextButton(
                        onPressed: _reload,
                        child: const Text('إعادة المحاولة')),
                  ],
                  if (!p.treasuryLoading &&
                      p.treasuryError == null &&
                      p.cashAccounts.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                            'لا توجد حسابات خزينة أو محافظ في الفرع الحالي')),
                  LayoutBuilder(builder: (context, constraints) {
                    final cardWidth = constraints.maxWidth < 600
                        ? constraints.maxWidth
                        : 280.0;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: p.cashAccounts.map((a) {
                        final id = a['id'];
                        final movements = p.transactions.where((t) =>
                            t['cash_account_id'] == id &&
                            t['tx_date'].toString().startsWith(today));
                        final incoming = movements
                            .where((t) => t['direction'] == 'IN')
                            .fold<double>(0,
                                (s, t) => s + (t['amount'] as num).toDouble());
                        final outgoing = movements
                            .where((t) => t['direction'] == 'OUT')
                            .fold<double>(0,
                                (s, t) => s + (t['amount'] as num).toDouble());
                        return SizedBox(
                            width: cardWidth,
                            child: Card(
                                key: ValueKey('treasury-account-$id'),
                                child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            const Icon(
                                                Icons.account_balance_wallet,
                                                color: Color(0xFF4DB6AC)),
                                            const SizedBox(width: 8),
                                            Expanded(
                                                child: Text(
                                                    a['name_ar'].toString(),
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold))),
                                            if (a['account_kind'] == 'WALLET')
                                              const Icon(Icons.phonelink_lock,
                                                  size: 16,
                                                  color: Colors.white54)
                                          ]),
                                          const SizedBox(height: 8),
                                          Text(
                                              '${((a['current_balance'] as num?) ?? 0).toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                  fontSize: 23,
                                                  fontWeight: FontWeight.bold)),
                                          if (a['wallet_phone'] != null)
                                            Text(
                                                'الهاتف: ${a['wallet_phone']}'),
                                          const Divider(),
                                          Wrap(
                                            spacing: 12,
                                            runSpacing: 6,
                                            children: [
                                              Text(
                                                'وارد اليوم: ${incoming.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                    color: Color(0xFF66BB6A)),
                                              ),
                                              Text(
                                                'صادر: ${outgoing.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                    color: Color(0xFFEF5350)),
                                              ),
                                            ],
                                          ),
                                          if (a['account_kind'] == 'WALLET')
                                            Align(
                                                alignment: Alignment.centerLeft,
                                                child: TextButton.icon(
                                                    onPressed:
                                                        p.operationPending
                                                            ? null
                                                            : () => _reconcile(
                                                                context, p, a),
                                                    icon: const Icon(
                                                        Icons.fact_check),
                                                    label: const Text(
                                                        'مطابقة الرصيد الفعلي')))
                                        ]))));
                      }).toList(),
                    );
                  }),
                  const SizedBox(height: 20),
                  const Text('دفتر حركة الصندوق والخزينة',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                          columns: const [
                            DataColumn(label: Text('التاريخ')),
                            DataColumn(label: Text('الحساب')),
                            DataColumn(label: Text('الحركة')),
                            DataColumn(label: Text('وارد')),
                            DataColumn(label: Text('صادر')),
                            DataColumn(label: Text('الرصيد بعد الحركة')),
                            DataColumn(label: Text('رقم الإشعار'))
                          ],
                          rows: p.transactions
                              .map((t) => DataRow(cells: [
                                    DataCell(Text(t['tx_date']
                                        .toString()
                                        .replaceFirst('T', ' '))),
                                    DataCell(Text(
                                        t['account_name']?.toString() ?? '')),
                                    DataCell(Text(t['tx_type'].toString())),
                                    DataCell(Text(t['direction'] == 'IN'
                                        ? (t['amount'] as num)
                                            .toStringAsFixed(2)
                                        : '—')),
                                    DataCell(Text(t['direction'] == 'OUT'
                                        ? (t['amount'] as num)
                                            .toStringAsFixed(2)
                                        : '—')),
                                    DataCell(Text((t['balance_after'] as num)
                                        .toStringAsFixed(2))),
                                    DataCell(Text(
                                        t['wallet_ref_no']?.toString() ?? '—'))
                                  ]))
                              .toList()))
                ])));
  }

  Future<void> _transfer(
      BuildContext context, TreasuryHrPartnerProvider p) async {
    if (p.cashAccounts.length < 2) return;
    int from = p.cashAccounts.first['id'] as int;
    int to = p.cashAccounts[1]['id'] as int;
    final amount = TextEditingController();
    final fee = TextEditingController(text: '0');
    final ref = TextEditingController();
    final note = TextEditingController();
    await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, set) => AlertDialog(
                    title: const Text('تحويل بين الحسابات'),
                    content: SizedBox(
                        width: 420,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          DropdownButtonFormField<int>(
                              value: from,
                              decoration:
                                  const InputDecoration(labelText: 'من حساب'),
                              items: p.cashAccounts
                                  .map((a) => DropdownMenuItem(
                                      value: a['id'] as int,
                                      child: Text(a['name_ar'].toString())))
                                  .toList(),
                              onChanged: (v) => set(() => from = v ?? from)),
                          DropdownButtonFormField<int>(
                              value: to,
                              decoration:
                                  const InputDecoration(labelText: 'إلى حساب'),
                              items: p.cashAccounts
                                  .map((a) => DropdownMenuItem(
                                      value: a['id'] as int,
                                      child: Text(a['name_ar'].toString())))
                                  .toList(),
                              onChanged: (v) => set(() => to = v ?? to)),
                          TextField(
                              controller: amount,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'مبلغ التحويل')),
                          TextField(
                              controller: fee,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'رسوم التحويل')),
                          TextField(
                              controller: ref,
                              decoration: const InputDecoration(
                                  labelText: 'رقم الإشعار / المرجع')),
                          TextField(
                              controller: note,
                              decoration:
                                  const InputDecoration(labelText: 'البيان'))
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('إلغاء')),
                      FilledButton(
                          onPressed: () async {
                            try {
                              await p.transfer(
                                  fromAccountId: from,
                                  toAccountId: to,
                                  amount: double.parse(amount.text),
                                  fee: double.parse(fee.text),
                                  reference: ref.text,
                                  note: note.text);
                              if (ctx.mounted) Navigator.pop(ctx);
                            } catch (e) {
                              if (ctx.mounted)
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text(e.toString())));
                            }
                          },
                          child: const Text('تنفيذ التحويل'))
                    ])));
    amount.dispose();
    fee.dispose();
    ref.dispose();
    note.dispose();
  }

  Future<void> _reconcile(BuildContext context, TreasuryHrPartnerProvider p,
      Map<String, Object?> account) async {
    final actual = TextEditingController();
    final ref = TextEditingController();
    await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text('مطابقة ${account['name_ar']}'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                      'الرصيد الدفتري: ${((account['current_balance'] as num?) ?? 0).toStringAsFixed(2)}'),
                  TextField(
                      controller: actual,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'الرصيد الفعلي')),
                  TextField(
                      controller: ref,
                      decoration:
                          const InputDecoration(labelText: 'رقم الإشعار'))
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('إلغاء')),
                  FilledButton(
                      onPressed: () async {
                        try {
                          final d = await p.reconcileWallet(
                              accountId: account['id'] as int,
                              actual: double.parse(actual.text),
                              reference: ref.text);
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(
                                    'فرق المطابقة: ${d.toStringAsFixed(2)}')));
                          }
                        } catch (e) {
                          if (ctx.mounted)
                            ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text(e.toString())));
                        }
                      },
                      child: const Text('اعتماد المطابقة'))
                ]));
    actual.dispose();
    ref.dispose();
  }

  Future<void> _addAccount(BuildContext context) async {
    bool saving = false;
    final name = TextEditingController();
    final phone = TextEditingController();
    String kind = 'WALLET';
    String provider = 'JAWALI';
    final p = context.read<TreasuryHrPartnerProvider>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('إضافة محفظة أو حساب'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'اسم الحساب'),
              ),
              DropdownButtonFormField<String>(
                value: kind,
                items: const [
                  DropdownMenuItem(
                      value: 'WALLET', child: Text('محفظة إلكترونية')),
                  DropdownMenuItem(value: 'BANK', child: Text('حساب بنكي')),
                  DropdownMenuItem(value: 'MAIN_SAFE', child: Text('خزينة')),
                  DropdownMenuItem(
                      value: 'CASHIER_DRAWER', child: Text('درج كاشير')),
                ],
                onChanged: (v) => set(() => kind = v ?? kind),
              ),
              if (kind == 'WALLET')
                DropdownButtonFormField<String>(
                  value: provider,
                  items: const [
                    DropdownMenuItem(value: 'JAWALI', child: Text('جوالي')),
                    DropdownMenuItem(value: 'JAIB', child: Text('جيب')),
                    DropdownMenuItem(value: 'FLOUSK', child: Text('فلوسك')),
                    DropdownMenuItem(value: 'KURAIMI', child: Text('كريمي')),
                    DropdownMenuItem(value: 'OTHER', child: Text('أخرى')),
                  ],
                  onChanged: (v) => set(() => provider = v ?? provider),
                ),
              TextField(
                controller: phone,
                decoration:
                    const InputDecoration(labelText: 'رقم الهاتف / الحساب'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                if (saving || name.text.trim().isEmpty) return;
                saving = true;
                try {
                  final db = await DatabaseHelper.instance.database;
                  final now = DateTime.now().toIso8601String();
                  final glCode = switch (kind) {
                    'BANK' => '1107',
                    'MAIN_SAFE' => '1101',
                    'CASHIER_DRAWER' => '1102',
                    _ => switch (provider) {
                        'JAWALI' => '1103',
                        'JAIB' => '1104',
                        'FLOUSK' => '1105',
                        'KURAIMI' => '1106',
                        _ => '1108',
                      },
                  };
                  await db.transaction((txn) async {
                    var glRows = await txn.query(
                      'chart_of_accounts',
                      columns: ['id'],
                      where: 'code=?',
                      whereArgs: [glCode],
                      limit: 1,
                    );
                    if (glRows.isEmpty && glCode == '1108') {
                      await txn.insert('chart_of_accounts', {
                        'uuid': 'acc-1108',
                        'branch_id': p.branchId,
                        'created_at': now,
                        'updated_at': now,
                        'is_deleted': 0,
                        'sync_status': 'LOCAL',
                        'sync_version': 1,
                        'code': '1108',
                        'name_ar': 'محافظ إلكترونية أخرى',
                        'acc_type': 'ASSET',
                      });
                      glRows = await txn.query(
                        'chart_of_accounts',
                        columns: ['id'],
                        where: 'code=?',
                        whereArgs: [glCode],
                        limit: 1,
                      );
                    }
                    if (glRows.isEmpty) {
                      throw StateError('الحساب المحاسبي $glCode غير موجود');
                    }
                    await txn.insert('cash_accounts', {
                      'uuid': 'cash-${DateTime.now().microsecondsSinceEpoch}',
                      'branch_id': p.branchId,
                      'created_at': now,
                      'updated_at': now,
                      'code': 'CASH-${DateTime.now().millisecondsSinceEpoch}',
                      'name_ar': name.text.trim(),
                      'account_kind': kind,
                      'wallet_provider': kind == 'WALLET' ? provider : null,
                      'wallet_phone': phone.text.trim(),
                      'gl_account_id': glRows.first['id'],
                      'current_balance': 0,
                    });
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  await p.refresh();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                } finally {
                  saving = false;
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    phone.dispose();
  }
}
