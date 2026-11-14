import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/enterprise_dark_theme.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/erp_models.dart';
import '../../data/database/database_helper.dart';
import '../../providers/session_and_erp_provider.dart';
import 'manual_message_composer_screen.dart';

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

  Future<void> _openMessage(PartyModel party, String channel, {
    String? transactionAmount,
    String? documentNumber,
    String? initialKind,
  }) async {
    final outstanding = party.partyType == 'SUPPLIER'
        ? party.totalLah - party.totalAlayh
        : party.totalAlayh - party.totalLah;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => ManualMessageComposerScreen(
        partyType: party.partyType,
        name: party.nameAr,
        phone: party.phone,
        preferredChannel: channel,
        initialKind: initialKind,
        balanceAmount: outstanding > 0 ? MoneyFormatter.format(outstanding) : null,
        transactionAmount: transactionAmount,
        documentNumber: documentNumber,
      ),
    ));
  }

  Future<void> _messageForEntry(
    PartyModel party,
    Map<String, Object?> entry,
  ) async {
    String? documentNumber;
    String kind = 'general_notice';
    final docId = entry['doc_id'] as int?;
    try {
      if (docId != null && entry['doc_type'] == 'VOUCHER') {
        final vouchers = await DatabaseHelper.instance.query(
          'vouchers',
          where: 'id=? AND party_id=? AND branch_id=?',
          whereArgs: [docId, party.id, party.branchId],
          limit: 1,
        );
        if (vouchers.isNotEmpty) {
          final voucher = vouchers.first;
          documentNumber = voucher['voucher_no']?.toString();
          if (party.partyType == 'CUSTOMER' &&
              voucher['voucher_type'] == 'RECEIPT') kind = 'customer_receipt';
          if (party.partyType == 'SUPPLIER' &&
              voucher['voucher_type'] == 'PAYMENT') kind = 'supplier_payment';
        }
      } else if (docId != null && entry['doc_type'] == 'INVOICE') {
        final invoices = await DatabaseHelper.instance.query(
          'sales_invoices',
          where: 'id=? AND branch_id=? AND customer_party_id=?',
          whereArgs: [docId, party.branchId, party.id],
          limit: 1,
        );
        if (invoices.isNotEmpty) {
          documentNumber = invoices.first['invoice_no']?.toString();
        }
      }
    } catch (_) {
      // A failed lookup must not invent a document number or block composing.
    }
    if (!mounted) return;
    final debit = (entry['alayh_amount'] as num?) ?? 0;
    final credit = (entry['lah_amount'] as num?) ?? 0;
    final amount = debit > 0 ? debit : credit;
    await _openMessage(party, 'whatsapp',
      initialKind: kind,
      transactionAmount: amount > 0 ? MoneyFormatter.format(amount) : null,
      documentNumber: documentNumber,
    );
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('party-message-whatsapp'),
                      onPressed: () => _openMessage(party, 'whatsapp'),
                      icon: const Icon(Icons.chat_outlined),
                      label: const Text('واتساب'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('party-message-sms'),
                      onPressed: () => _openMessage(party, 'sms'),
                      icon: const Icon(Icons.sms_outlined),
                      label: const Text('SMS'),
                    ),
                  ],
                ),
              ),
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
                  onPressed:
                      _busy ? null : () => _run(() => widget.onPrint(party)),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('طباعة كشف PDF'),
                ),
                FilledButton.tonalIcon(
                  onPressed:
                      _busy ? null : () => _run(() => widget.onVoucher(party)),
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
                        actions: [
                          OutlinedButton.icon(
                            onPressed: () => _messageForEntry(party, entry),
                            icon: const Icon(Icons.chat_outlined),
                            label: const Text('رسالة عن هذه الحركة'),
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
