// lib/screens/inventory/s14_disposals_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/inventory_and_purchase_provider.dart';
import '../../providers/session_and_erp_provider.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/inventory_and_purchase_models.dart';

class S14DisposalsScreen extends StatefulWidget {
  const S14DisposalsScreen({super.key});

  @override
  State<S14DisposalsScreen> createState() => _S14DisposalsScreenState();
}

class _S14DisposalsScreenState extends State<S14DisposalsScreen> {
  String reason = 'EXPIRED';
  final method = TextEditingController(text: 'إتلاف وفق تعليمات الجهة الصحية');
  final witness = TextEditingController();
  final authority = TextEditingController();
  final Set<int> selectedBatchIds = {};
  final Map<int, TextEditingController> quantities = {};
  bool saving = false;

  @override
  void dispose() {
    method.dispose();
    witness.dispose();
    authority.dispose();
    for (final controller in quantities.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryAndPurchaseProvider>();
    final eligible = provider.batches.where((batch) {
      if (batch.totalUnits <= 0) return false;
      return reason != 'EXPIRED' || batch.isExpired;
    }).toList();
    final totalCost = selectedBatchIds.fold<double>(0, (sum, id) {
      final matches = provider.batches.where((batch) => batch.id == id);
      if (matches.isEmpty) return sum;
      final batch = matches.first;
      final quantity = int.tryParse(quantities[id]?.text ?? '') ?? 0;
      return sum + quantity * batch.unitCost;
    });

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'محاضر الإعدام والإتلاف',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: reason,
            decoration: const InputDecoration(labelText: 'سبب الإعدام'),
            items: const [
              DropdownMenuItem(value: 'EXPIRED', child: Text('منتهي الصلاحية')),
              DropdownMenuItem(value: 'BROKEN', child: Text('مكسور')),
              DropdownMenuItem(
                  value: 'DAMAGED_STORAGE', child: Text('تلف التخزين')),
              DropdownMenuItem(value: 'RECALL', child: Text('سحب تشغيلة')),
              DropdownMenuItem(value: 'CONTAMINATED', child: Text('تلوث')),
            ],
            onChanged: saving
                ? null
                : (value) => setState(() {
                      reason = value ?? reason;
                      if (reason == 'EXPIRED') {
                        final provider =
                            context.read<InventoryAndPurchaseProvider>();
                        selectedBatchIds.removeWhere((id) => provider.batches
                            .where((batch) => batch.id == id)
                            .every((batch) => !batch.isExpired));
                      }
                    }),
          ),
          TextField(
            controller: method,
            decoration: const InputDecoration(labelText: 'طريقة الإتلاف'),
          ),
          TextField(
            controller: witness,
            decoration: const InputDecoration(labelText: 'اسم الشاهد'),
          ),
          TextField(
            controller: authority,
            decoration: const InputDecoration(
              labelText: 'رقم محضر الجهة الصحية',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'اختر التشغيلات والكميات المطلوب إتلافها',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: eligible.isEmpty
                ? const Center(child: Text('لا توجد تشغيلات مؤهلة لهذا السبب'))
                : ListView.builder(
                    itemCount: eligible.length,
                    itemBuilder: (context, index) =>
                        _batchCard(eligible[index]),
                  ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('عدد التشغيلات المختارة: ${selectedBatchIds.length}'),
                  Text(
                    'إجمالي قيمة الخسارة بالتكلفة: ${totalCost.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: saving || selectedBatchIds.isEmpty
                        ? null
                        : () => _submit(provider),
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_forever),
                    label: const Text('اعتماد محضر الإعدام'),
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          SizedBox(
            height: 130,
            child: ListView(
              children: provider.disposals
                  .map(
                    (disposal) => ListTile(
                      dense: true,
                      title: Text(disposal.disposalNo),
                      subtitle: Text(
                        '${disposal.reason} • ${disposal.disposalDate} • ${disposal.status}',
                      ),
                      trailing:
                          Text(disposal.totalCostValue.toStringAsFixed(2)),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _batchCard(BatchFefoModel batch) {
    final selected = selectedBatchIds.contains(batch.id);
    final controller = quantities.putIfAbsent(
      batch.id,
      () => TextEditingController(text: batch.totalUnits.toString()),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          children: [
            CheckboxListTile(
              value: selected,
              onChanged: (value) => setState(() {
                if (value == true) {
                  selectedBatchIds.add(batch.id);
                } else {
                  selectedBatchIds.remove(batch.id);
                }
              }),
              title: Text('${batch.drugName} • ${batch.batchNo}'),
              subtitle: Text(
                'الصلاحية ${batch.expiryDate} • المتاح ${batch.totalUnits} حبة • تكلفة الحبة ${batch.unitCost.toStringAsFixed(2)}',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (selected)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 48,
                  end: 12,
                  bottom: 8,
                ),
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'كمية الإتلاف بالحبة (الحد ${batch.totalUnits})',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(InventoryAndPurchaseProvider provider) async {
    if (witness.text.trim().isEmpty || method.text.trim().isEmpty) {
      _message('أدخل طريقة الإتلاف واسم الشاهد');
      return;
    }
    final items = <({int batchId, int qtyUnits})>[];
    for (final batchId in selectedBatchIds) {
      final batch = provider.batches.firstWhere((item) => item.id == batchId);
      final amount = int.tryParse(quantities[batchId]?.text ?? '') ?? 0;
      if (amount <= 0 || amount > batch.totalUnits) {
        _message('كمية الإتلاف غير صحيحة للتشغيلة ${batch.batchNo}');
        return;
      }
      items.add((batchId: batchId, qtyUnits: amount));
    }
    final session = context.read<SessionAndErpProvider>();
    final approved = await ManagerPinDialog.show(
      context,
      verifier: session.verifyManagerPin,
    );
    if (!approved || !mounted) return;
    setState(() => saving = true);
    try {
      provider.branchId = session.branchId;
      await provider.createDisposal(
        reason: reason,
        method: method.text.trim(),
        witness: witness.text.trim(),
        authority: authority.text.trim(),
        items: items,
      );
      if (!mounted) return;
      setState(() {
        selectedBatchIds.clear();
        for (final controller in quantities.values) {
          controller.dispose();
        }
        quantities.clear();
        saving = false;
      });
      _message('تم اعتماد محضر الإعدام وترحيل تكلفة الخسارة');
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
