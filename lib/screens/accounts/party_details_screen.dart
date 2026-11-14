import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/enterprise_dark_theme.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/erp_models.dart';
import '../../providers/session_and_erp_provider.dart';

/// Uses the application's existing theme, account vocabulary and card widgets.
class PartyDetailsScreen extends StatefulWidget {
  const PartyDetailsScreen({
    super.key,
    required this.party,
    required this.onPrint,
    required this.onVoucher,
  });

  final PartyModel party;
  final Future<void> Function(PartyModel) onPrint;
  final Future<void> Function(PartyModel) onVoucher;

  @override
  State<PartyDetailsScreen> createState() => _PartyDetailsScreenState();
}

class _PartyDetailsScreenState extends State<PartyDetailsScreen> {
  late Future<List<Map<String, Object?>>> _entries;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _entries = _loadEntries();
  }

  Future<List<Map<String, Object?>>> _loadEntries() =>
      context.read<SessionAndErpProvider>().ledger(widget.party.id!);

  Future<void> _reload() async {
    final entries = _loadEntries();
    setState(() => _entries = entries);
    await entries;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) await _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر إكمال العملية. حاول مرة أخرى.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionAndErpProvider>();
    final party =
        session.parties.where((p) => p.id == widget.party.id).firstOrNull ??
        widget.party;
    final customer = party.partyType == 'CUSTOMER';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(customer ? 'تفاصيل العميل' : 'تفاصيل المورد'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            SmartExpandableCard(
              title: party.nameAr,
              primary: party.phone.isEmpty ? 'لا يوجد رقم هاتف' : party.phone,
              secondary: party.code,
              initiallyExpanded: true,
              leading: CircleAvatar(
                backgroundColor: const Color(0x224DB6AC),
                child: Icon(
                  customer
                      ? Icons.person_outline
                      : Icons.local_shipping_outlined,
                  color: AppColors.primary,
                ),
              ),
              details: [
                Text(
                  'العنوان: ${party.address.isEmpty ? 'غير مسجل' : party.address}',
                ),
                Text('حالة الحساب: ${party.isBlocked ? 'محظور' : 'نشط'}'),
                Text(
                  'حد الائتمان: ${MoneyFormatter.format(party.creditLimit)}',
                ),
                Text('مهلة السداد: ${party.paymentTermsDays ?? 0} يوم'),
                if (customer)
                  Text('الملف الطبي: ${party.isPatient ? 'نشط' : 'غير مفعّل'}'),
              ],
            ),
            SmartExpandableCard(
              title: 'ملخص الحساب',
              primary: 'الرصيد الحالي',
              initiallyExpanded: true,
              details: [
                PartyBalanceChip(
                  totalAlayh: party.totalAlayh,
                  totalLah: party.totalLah,
                ),
                const SizedBox(height: 8),
                Text('إجمالي عليه: ${MoneyFormatter.format(party.totalAlayh)}'),
                Text('إجمالي له: ${MoneyFormatter.format(party.totalLah)}'),
                Text(
                  'الافتتاحي عليه: ${MoneyFormatter.format(party.openingAlayh)}',
                ),
                Text(
                  'الافتتاحي له: ${MoneyFormatter.format(party.openingLah)}',
                ),
              ],
              actions: [
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() => widget.onPrint(party)),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('طباعة كشف PDF'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy
                      ? null
                      : () => _run(() => widget.onVoucher(party)),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('سند قبض / صرف'),
                ),
              ],
            ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'حركات الحساب',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'تحديث حركات الحساب',
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await session.refresh();
                          if (session.lastError != null)
                            throw StateError('refresh failed');
                        }),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            FutureBuilder<List<Map<String, Object?>>>(
              future: _entries,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text('تعذر تحميل حركات الحساب.'),
                          TextButton(
                            onPressed: _busy ? null : () => _run(() async {}),
                            child: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final entries = snapshot.data ?? [];
                if (entries.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('لا توجد حركات مسجلة لهذا الحساب.'),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final entry in entries.reversed)
                      SmartExpandableCard(
                        title: entry['statement_ar']?.toString() ?? 'حركة حساب',
                        primary: (entry['entry_date']?.toString() ?? '')
                            .split('T')
                            .first,
                        secondary:
                            '${entry['doc_type'] ?? ''} #${entry['doc_id'] ?? ''}',
                        details: [
                          Text(
                            'عليه: ${MoneyFormatter.format((entry['alayh_amount'] as num?) ?? 0)}',
                          ),
                          Text(
                            'له: ${MoneyFormatter.format((entry['lah_amount'] as num?) ?? 0)}',
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
