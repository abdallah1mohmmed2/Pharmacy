// lib/screens/finance/s22_treasury_wallets_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/database/database_helper.dart';
import '../../providers/treasury_hr_partner_provider.dart';

class S22TreasuryWalletsScreen extends StatelessWidget {
  const S22TreasuryWalletsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<TreasuryHrPartnerProvider>();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return Scaffold(
        backgroundColor: Colors.transparent,
        body: RefreshIndicator(
            onRefresh: p.refresh,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                const Expanded(
                    child: Text('الخزينة والصناديق والمحافظ',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold))),
                IconButton(
                    onPressed: () => _addAccount(context),
                    icon: const Icon(Icons.add_card),
                    tooltip: 'إضافة حساب'),
                FilledButton.icon(
                    onPressed: () => _transfer(context, p),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('تحويل'))
              ]),
              const SizedBox(height: 12),
              if (p.error != null)
                Text(p.error!,
                    style: const TextStyle(color: Color(0xFFEF5350))),
              Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: p.cashAccounts.map((a) {
                    final id = a['id'];
                    final movements = p.transactions.where((t) =>
                        t['cash_account_id'] == id &&
                        t['tx_date'].toString().startsWith(today));
                    final incoming = movements
                        .where((t) => t['direction'] == 'IN')
                        .fold<double>(
                            0, (s, t) => s + (t['amount'] as num).toDouble());
                    final outgoing = movements
                        .where((t) => t['direction'] == 'OUT')
                        .fold<double>(
                            0, (s, t) => s + (t['amount'] as num).toDouble());
                    return SizedBox(
                        width: 280,
                        child: Card(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        const Icon(Icons.account_balance_wallet,
                                            color: Color(0xFF4DB6AC)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                            child: Text(a['name_ar'].toString(),
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold))),
                                        if (a['account_kind'] == 'WALLET')
                                          const Icon(Icons.phonelink_lock,
                                              size: 16, color: Colors.white54)
                                      ]),
                                      const SizedBox(height: 8),
                                      Text(
                                          '${((a['current_balance'] as num?) ?? 0).toStringAsFixed(2)}',
                                          style: const TextStyle(
                                              fontSize: 23,
                                              fontWeight: FontWeight.bold)),
                                      if (a['wallet_phone'] != null)
                                        Text('الهاتف: ${a['wallet_phone']}'),
                                      const Divider(),
                                      Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                                'وارد اليوم: ${incoming.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                    color: Color(0xFF66BB6A))),
                                            Text(
                                                'صادر: ${outgoing.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                    color: Color(0xFFEF5350)))
                                          ]),
                                      if (a['account_kind'] == 'WALLET')
                                        Align(
                                            alignment: Alignment.centerLeft,
                                            child: TextButton.icon(
                                                onPressed: () =>
                                                    _reconcile(context, p, a),
                                                icon: const Icon(
                                                    Icons.fact_check),
                                                label: const Text(
                                                    'مطابقة الرصيد الفعلي')))
                                    ]))));
                  }).toList()),
              const SizedBox(height: 20),
              const Text('دفتر حركة الصندوق والخزينة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                                DataCell(
                                    Text(t['account_name']?.toString() ?? '')),
                                DataCell(Text(t['tx_type'].toString())),
                                DataCell(Text(t['direction'] == 'IN'
                                    ? (t['amount'] as num).toStringAsFixed(2)
                                    : '—')),
                                DataCell(Text(t['direction'] == 'OUT'
                                    ? (t['amount'] as num).toStringAsFixed(2)
                                    : '—')),
                                DataCell(Text((t['balance_after'] as num)
                                    .toStringAsFixed(2))),
                                DataCell(
                                    Text(t['wallet_ref_no']?.toString() ?? '—'))
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
                                  fee: double.tryParse(fee.text) ?? 0,
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
                if (name.text.trim().isEmpty) return;
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
