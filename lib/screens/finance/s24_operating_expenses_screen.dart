// lib/screens/finance/s24_operating_expenses_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/treasury_hr_partner_provider.dart';

class S24OperatingExpensesScreen extends StatefulWidget {
  const S24OperatingExpensesScreen({super.key});
  @override
  State<S24OperatingExpensesScreen> createState() =>
      _S24OperatingExpensesScreenState();
}

class _S24OperatingExpensesScreenState
    extends State<S24OperatingExpensesScreen> {
  int? categoryId, cashAccountId;
  final amount = TextEditingController(),
      paidTo = TextEditingController(),
      description = TextEditingController();
  @override
  void dispose() {
    amount.dispose();
    paidTo.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TreasuryHrPartnerProvider>();
    final period = DateTime.now().toIso8601String().substring(0, 7);
    final monthExpenses = p.expenses
        .where((e) => e['expense_date'].toString().startsWith(period))
        .toList();
    final total = monthExpenses.fold<double>(
        0, (s, e) => s + (e['amount'] as num).toDouble());
    return Scaffold(
        backgroundColor: Colors.transparent,
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('المصروفات التشغيلية',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Row(children: [
                      const Expanded(
                          child: Text('تسجيل مصروف سريع',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 17))),
                      Text('مصروفات الشهر: ${total.toStringAsFixed(2)}',
                          style: const TextStyle(color: Color(0xFFFFB74D)))
                    ]),
                    DropdownButtonFormField<int>(
                        value: categoryId,
                        decoration:
                            const InputDecoration(labelText: 'بند المصروف'),
                        items: p.categories
                            .map((c) => DropdownMenuItem(
                                value: c['id'] as int,
                                child: Text(c['name_ar'].toString())))
                            .toList(),
                        onChanged: (v) => setState(() => categoryId = v)),
                    TextField(
                        controller: amount,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(labelText: 'المبلغ')),
                    DropdownButtonFormField<int>(
                        value: cashAccountId,
                        decoration: const InputDecoration(
                            labelText: 'حساب الدفع: الدرج / الخزينة / المحفظة'),
                        items: p.cashAccounts
                            .map((a) => DropdownMenuItem(
                                value: a['id'] as int,
                                child: Text(a['name_ar'].toString())))
                            .toList(),
                        onChanged: (v) => setState(() => cashAccountId = v)),
                    TextField(
                        controller: paidTo,
                        decoration: const InputDecoration(
                            labelText: 'المستفيد / جهة الصرف')),
                    TextField(
                        controller: description,
                        decoration: const InputDecoration(labelText: 'البيان')),
                    const SizedBox(height: 10),
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                            onPressed: categoryId == null ||
                                    cashAccountId == null
                                ? null
                                : () async {
                                    try {
                                      await p.recordExpense(
                                          categoryId: categoryId!,
                                          cashAccountId: cashAccountId!,
                                          amount: double.parse(amount.text),
                                          description: description.text.trim(),
                                          paidTo: paidTo.text.trim());
                                      amount.clear();
                                      paidTo.clear();
                                      description.clear();
                                      if (mounted)
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text(
                                                    'تم تسجيل المصروف وترحيل الحركة')));
                                    } catch (e) {
                                      if (mounted)
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content: Text(e.toString())));
                                    }
                                  },
                            icon: const Icon(Icons.save),
                            label: const Text('حفظ المصروف')))
                  ]))),
          const SizedBox(height: 16),
          const Text('استهلاك الميزانية الشهرية',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ...p.categories.map((c) {
            final used = monthExpenses
                .where((e) => e['category_id'] == c['id'])
                .fold<double>(0, (s, e) => s + (e['amount'] as num).toDouble());
            final limit = (c['monthly_budget_limit'] as num).toDouble();
            final ratio = limit <= 0 ? 0 : used / limit;
            final color = ratio > 1
                ? const Color(0xFFEF5350)
                : ratio >= .8
                    ? const Color(0xFFFFB74D)
                    : const Color(0xFF66BB6A);
            return Card(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(c['name_ar'].toString(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold))),
                            Text(
                                '${used.toStringAsFixed(2)} / ${limit.toStringAsFixed(2)}',
                                style: TextStyle(color: color))
                          ]),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                              value: ratio.clamp(0, 1).toDouble(),
                              color: color,
                              backgroundColor: const Color(0xFF333333),
                              minHeight: 8),
                          if (ratio > 1)
                            const Text('تم تجاوز الميزانية الشهرية',
                                style: TextStyle(
                                    color: Color(0xFFEF5350), fontSize: 12))
                        ])));
          }),
          const SizedBox(height: 16),
          const Text('سجل المصروفات',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                  columns: const [
                    DataColumn(label: Text('رقم المصروف')),
                    DataColumn(label: Text('التاريخ')),
                    DataColumn(label: Text('البند')),
                    DataColumn(label: Text('المبلغ')),
                    DataColumn(label: Text('حساب الدفع')),
                    DataColumn(label: Text('المستفيد')),
                    DataColumn(label: Text('البيان'))
                  ],
                  rows: p.expenses
                      .map((e) => DataRow(cells: [
                            DataCell(Text(e['expense_no'].toString())),
                            DataCell(Text(
                                e['expense_date'].toString().split('T').first)),
                            DataCell(Text(e['category_name'].toString())),
                            DataCell(
                                Text((e['amount'] as num).toStringAsFixed(2))),
                            DataCell(Text(e['cash_account_name'].toString())),
                            DataCell(Text(e['paid_to']?.toString() ?? '')),
                            DataCell(Text(e['description']?.toString() ?? ''))
                          ]))
                      .toList()))
        ]));
  }
}
