import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/inventory_and_purchase_provider.dart';
import '../../providers/session_and_erp_provider.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/database/database_helper.dart';

class S13StocktakingScreen extends StatefulWidget {
  const S13StocktakingScreen({super.key});
  @override
  State<S13StocktakingScreen> createState() => _S13StocktakingScreenState();
}

class _S13StocktakingScreenState extends State<S13StocktakingScreen> {
  int? warehouseId;
  bool blind = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<InventoryAndPurchaseProvider>().loadAll());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<InventoryAndPurchaseProvider>();
    return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            const Expanded(
                child: Text('الجرد المخزني ومطابقة الرصيد',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            FilledButton.icon(
                onPressed: p.warehouses.isEmpty ? null : () => _newSession(p),
                icon: const Icon(Icons.add),
                label: const Text('جلسة جرد'))
          ]),
          Expanded(
              child: p.stocktaking.isEmpty
                  ? const Center(child: Text('لا توجد جلسات جرد'))
                  : ListView(
                      children: p.stocktaking
                          .map((s) => Card(
                              child: ListTile(
                                  title: Text(s.sessionNo),
                                  subtitle: Text(s.scopeType +
                                      ' • ' +
                                      s.status +
                                      ' • ' +
                                      s.createdAt),
                                  trailing: Wrap(children: [
                                    IconButton(
                                        onPressed: () =>
                                            _lines(s.id, s.blindCount),
                                        icon: const Icon(
                                            Icons.fact_check_outlined)),
                                    if (s.status != 'APPROVED')
                                      IconButton(
                                          onPressed: () => _approve(p, s.id),
                                          icon: const Icon(Icons.verified_user,
                                              color: Colors.green))
                                  ]))))
                          .toList()))
        ]));
  }

  Future<void> _newSession(InventoryAndPurchaseProvider p) async {
    warehouseId ??= p.warehouses.first.id;
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, set) => AlertDialog(
                    title: const Text('إنشاء جلسة جرد'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButton<int>(
                          value: warehouseId,
                          items: p.warehouses
                              .map((w) => DropdownMenuItem(
                                  value: w.id, child: Text(w.nameAr)))
                              .toList(),
                          onChanged: (v) => set(() => warehouseId = v)),
                      SwitchListTile(
                          value: blind,
                          onChanged: (v) => set(() => blind = v),
                          title:
                              const Text('الجرد الأعمى (إخفاء الرصيد الدفتري)'))
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('إلغاء')),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('إنشاء'))
                    ])));
    if (ok == true) {
      await p.createStocktaking(warehouseId!, blind: blind);
      _message('تم إنشاء جلسة الجرد');
    }
  }

  Future<void> _lines(int sessionId, bool isBlind) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
        'SELECT l.*,b.batch_no,d.trade_name_ar,d.units_per_pack FROM stocktaking_lines l JOIN batches_fefo b ON b.id=l.batch_id JOIN drugs d ON d.id=b.drug_id WHERE l.session_id=? ORDER BY d.trade_name_ar,b.expiry_date',
        [sessionId]);
    if (!mounted) return;
    await showDialog<void>(
        context: context,
        builder: (c) {
          return AlertDialog(
              title: const Text('عد التشغيلات'),
              content: SizedBox(
                  width: 600,
                  child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: rows.length,
                      itemBuilder: (c, i) {
                        final row = rows[i];
                        return ListTile(
                            title: Text(row['trade_name_ar'].toString() +
                                ' • ' +
                                row['batch_no'].toString()),
                            subtitle: Text(isBlind
                                ? 'الرصيد الدفتري مخفي'
                                : 'الدفتري: ' +
                                    row['system_units'].toString() +
                                    ' حبة • الفرق: ' +
                                    row['diff_units'].toString()),
                            trailing: IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _count(sessionId, row)));
                      })),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('إغلاق'))
              ]);
        });
  }

  Future<void> _count(int sessionId, Map<String, Object?> row) async {
    final packs = TextEditingController(text: row['counted_packs'].toString());
    final loose =
        TextEditingController(text: row['counted_loose_units'].toString());
    final reason =
        TextEditingController(text: row['reason_code']?.toString() ?? '');
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text('عد ' + row['trade_name_ar'].toString()),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: packs,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'الباكتات المغلقة')),
                  TextField(
                      controller: loose,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'الحبات السائبة')),
                  TextField(
                      controller: reason,
                      decoration: const InputDecoration(labelText: 'سبب الفرق'))
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('إلغاء')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('حفظ العد'))
                ]));
    if (ok == true) {
      await context.read<InventoryAndPurchaseProvider>().countBatch(
          sessionId: sessionId,
          batchId: row['batch_id'] as int,
          packs: int.tryParse(packs.text) ?? 0,
          loose: int.tryParse(loose.text) ?? 0,
          unitsPerPack: (row['units_per_pack'] as int?) ?? 1,
          reason: reason.text);
      if (mounted) setState(() {});
    }
  }

  Future<void> _approve(InventoryAndPurchaseProvider p, int id) async {
    final session = context.read<SessionAndErpProvider>();
    final ok = await ManagerPinDialog.show(context,
        verifier: session.verifyManagerPin);
    if (ok) {
      await p.approveStocktaking(id, (session.currentUser?['id'] as int?) ?? 1);
      _message('تم اعتماد الجرد وترحيل فروق المخزون');
    }
  }

  void _message(String v) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(v)));
}
