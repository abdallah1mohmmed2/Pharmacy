import 'package:flutter/material.dart';
import '../theme/enterprise_dark_theme.dart';

class PartyBalanceChip extends StatelessWidget {
  const PartyBalanceChip({super.key, required this.totalAlayh, required this.totalLah, this.compact = false});
  final num totalAlayh;
  final num totalLah;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final net = totalAlayh - totalLah;
    final zero = net.abs() < 0.005;
    final color = zero ? Colors.white60 : net > 0 ? AppColors.danger : AppColors.success;
    final label = zero ? 'مسدَّد' : net > 0 ? 'المتبقي عليه ' : 'المتبقي له ';
    final amount = net.abs().toStringAsFixed(2);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 12, vertical: compact ? 5 : 8),
      decoration: BoxDecoration(color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(30)),
      child: Text(zero ? '$label (0.00)' : label + amount,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: compact ? 11 : 13)),
    );
  }
}

class LahAlayhRow {
  const LahAlayhRow({required this.date, required this.statement, required this.document, required this.alayh, required this.lah});
  final String date, statement, document;
  final num alayh, lah;
}

class LahAlayhTable extends StatelessWidget {
  const LahAlayhTable({super.key, required this.rows, this.openingBalance = 0});
  final List<LahAlayhRow> rows;
  final double openingBalance;

  @override
  Widget build(BuildContext context) {
    var running = openingBalance;
    final values = <DataRow>[];
    for (final row in rows) {
      running += row.alayh.toDouble() - row.lah.toDouble();
      values.add(DataRow(cells: [
        DataCell(Text(row.date)),
        DataCell(Text(row.statement)),
        DataCell(Text(row.document)),
        DataCell(Text(row.alayh.toStringAsFixed(2))),
        DataCell(Text(row.lah.toStringAsFixed(2))),
        DataCell(Text(running.abs().toStringAsFixed(2), style: TextStyle(color: running > 0 ? AppColors.danger : running < 0 ? AppColors.success : Colors.white70))),
      ]));
    }
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
      headingRowColor: WidgetStateProperty.all(AppColors.surfaceHigh),
      columns: const [
        DataColumn(label: Text('التاريخ')), DataColumn(label: Text('البيان')),
        DataColumn(label: Text('المستند')), DataColumn(label: Text('عليه')),
        DataColumn(label: Text('له')), DataColumn(label: Text('المتبقي التراكمي')),
      ],
      rows: values,
    ));
  }
}

enum ClinicalAlertLevel { info, caution, warning, block }

class ClinicalAlertBanner extends StatelessWidget {
  const ClinicalAlertBanner({super.key, required this.message, required this.level});
  final String message;
  final ClinicalAlertLevel level;

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      ClinicalAlertLevel.info => AppColors.info,
      ClinicalAlertLevel.caution => AppColors.success,
      ClinicalAlertLevel.warning => AppColors.warning,
      ClinicalAlertLevel.block => AppColors.danger,
    };
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: .12), border: Border.all(color: color), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [Icon(Icons.health_and_safety_outlined, color: color), const SizedBox(width: 9), Expanded(child: Text(message, style: TextStyle(color: color)))]),
    );
  }
}

class ManagerPinDialog extends StatefulWidget {
  const ManagerPinDialog({super.key, this.expectedPin, this.verifier, this.title = 'تأكيد المدير'});
  final String? expectedPin;
  final Future<bool> Function(String)? verifier;
  final String title;
  static Future<bool> show(BuildContext context, {String? expectedPin, Future<bool> Function(String)? verifier}) async =>
      await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => ManagerPinDialog(expectedPin: expectedPin, verifier: verifier)) ?? false;

  @override State<ManagerPinDialog> createState() => _ManagerPinDialogState();
}
class _ManagerPinDialogState extends State<ManagerPinDialog> {
  final controller = TextEditingController();
  String? error;
  @override void dispose() { controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(controller: controller, autofocus: true, obscureText: true, keyboardType: TextInputType.number, maxLength: 8,
      decoration: InputDecoration(labelText: 'رمز المدير', errorText: error),
      onSubmitted: (_) => _verify()),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
      FilledButton(onPressed: _verify, child: const Text('تحقق')),
    ],
  );
  Future<void> _verify() async {
    final valid = widget.verifier != null ? await widget.verifier!(controller.text) : controller.text == widget.expectedPin;
    if (!mounted) return;
    if (valid) { Navigator.pop(context, true); }
    else { setState(() => error = 'رمز التحقق غير صحيح'); }
  }
}

class WalletRefField extends StatelessWidget {
  const WalletRefField({super.key, required this.controller, this.label = 'رقم إشعار المحفظة'});
  final TextEditingController controller;
  final String label;
  @override Widget build(BuildContext context) => TextFormField(
    controller: controller,
    textDirection: TextDirection.ltr,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.receipt_long)),
    validator: (value) => value == null || value.trim().length < 6 ? 'رقم الإشعار مطلوب ولا يقل عن 6 خانات' : null,
  );
}
