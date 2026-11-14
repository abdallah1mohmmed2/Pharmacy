import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/session_and_erp_provider.dart';
import '../../core/theme/enterprise_dark_theme.dart';
import '../../core/widgets/shared_widgets.dart';

class S02ExecutiveDashboardScreen extends StatelessWidget {
  const S02ExecutiveDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SessionAndErpProvider>();
    final data = provider.dashboard;
    final metrics = <({
      String title,
      String key,
      IconData icon,
      Color color,
      bool integer,
    })>[
      (
        title: 'مبيعات اليوم',
        key: 'sales',
        icon: Icons.point_of_sale,
        color: AppColors.primary,
        integer: false
      ),
      (
        title: 'أرباح اليوم التقديرية',
        key: 'profit',
        icon: Icons.trending_up,
        color: AppColors.success,
        integer: false
      ),
      (
        title: 'فواتير اليوم',
        key: 'invoiceCount',
        icon: Icons.receipt_long,
        color: AppColors.info,
        integer: true
      ),
      (
        title: 'الأصناف المسجلة',
        key: 'drugCount',
        icon: Icons.medication,
        color: AppColors.primary,
        integer: true
      ),
      (
        title: 'أصناف وصلت حد النقص',
        key: 'lowStock',
        icon: Icons.warning_amber,
        color: AppColors.warning,
        integer: true
      ),
      (
        title: 'إجمالي المتبقي عليهم',
        key: 'totalAlayh',
        icon: Icons.call_received,
        color: AppColors.danger,
        integer: false
      ),
      (
        title: 'إجمالي المتبقي لنا',
        key: 'totalLah',
        icon: Icons.call_made,
        color: AppColors.success,
        integer: false
      ),
      (
        title: 'أرصدة الصناديق والمحافظ',
        key: 'cashTotal',
        icon: Icons.account_balance_wallet,
        color: AppColors.info,
        integer: false
      ),
    ];

    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  const Expanded(
                    child: Text('المؤشرات التنفيذية',
                        style: TextStyle(
                            fontSize: 21, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    tooltip: 'تحديث البيانات',
                    onPressed: provider.refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          ),
          if (provider.lastError != null)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverToBoxAdapter(
                child: ClinicalAlertBanner(
                  message: provider.lastError!,
                  level: ClinicalAlertLevel.block,
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.sizeOf(context).width >= 1100
                    ? 4
                    : MediaQuery.sizeOf(context).width >= 700
                        ? 3
                        : 2,
                childAspectRatio:
                    MediaQuery.sizeOf(context).width < 380 ? 1.18 : 1.38,
                crossAxisSpacing: 9,
                mainAxisSpacing: 9,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final metric = metrics[index];
                  final value = (data[metric.key] as num?)?.toDouble() ?? 0;
                  return _KpiCard(
                    title: metric.title,
                    value: metric.integer
                        ? value.toStringAsFixed(0)
                        : MoneyFormatter.format(value),
                    icon: metric.icon,
                    color: metric.color,
                  );
                },
                childCount: metrics.length,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _SectionExpansion(
                  title: 'أرصدة الصناديق والمحافظ',
                  icon: Icons.account_balance_wallet_outlined,
                  count: provider.cashAccounts.length,
                  child: provider.cashAccounts.isEmpty
                      ? const _EmptyHint('لا توجد حسابات نقدية مسجلة.')
                      : Column(
                          children: provider.cashAccounts.map((account) {
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(
                                backgroundColor: Color(0x2264B5F6),
                                child:
                                    Icon(Icons.wallet, color: AppColors.info),
                              ),
                              title: Text(account.nameAr),
                              subtitle: Text(account.accountKind),
                              trailing: Text(
                                MoneyFormatter.format(account.currentBalance),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            );
                          }).toList(),
                        ),
                ),
                _SectionExpansion(
                  title: 'تنبيهات المخزون',
                  icon: Icons.inventory_2_outlined,
                  count: provider.lowStockDrugs.length,
                  child: provider.lowStockDrugs.isEmpty
                      ? const _EmptyHint('لا توجد أصناف وصلت حد النقص.')
                      : Column(
                          children: provider.lowStockDrugs.map((drug) {
                            return SmartExpandableCard(
                              title: drug['trade_name_ar'] as String,
                              primary:
                                  'المخزون: ${drug['stock_total_units']} حبة',
                              secondary:
                                  'حد الطلب: ${drug['min_stock_units']} حبة',
                              leading: const Icon(Icons.warning_amber,
                                  color: AppColors.warning),
                            );
                          }).toList(),
                        ),
                ),
                _SectionExpansion(
                  title: 'الأدوية ذات التنبيهات السريرية والرقابية',
                  icon: Icons.health_and_safety_outlined,
                  count: provider.criticalDrugs.length,
                  child: provider.criticalDrugs.isEmpty
                      ? const _EmptyHint('لا توجد أصناف حرجة مسجلة.')
                      : Column(
                          children: provider.criticalDrugs.map((drug) {
                            return SmartExpandableCard(
                              title: drug['trade_name_ar'] as String,
                              primary: 'الحمل: ${drug['pregnancy_category']}',
                              secondary:
                                  'مراقب: ${drug['is_controlled']} • سمية كلوية: ${drug['is_nephrotoxic']}',
                              leading: const Icon(
                                Icons.health_and_safety,
                                color: AppColors.danger,
                              ),
                            );
                          }).toList(),
                        ),
                ),
                _SectionExpansion(
                  title: 'آخر الفواتير',
                  icon: Icons.receipt_long_outlined,
                  count: provider.recentInvoices.length,
                  child: provider.recentInvoices.isEmpty
                      ? const _EmptyHint('لا توجد فواتير حديثة.')
                      : Column(
                          children: provider.recentInvoices.map((invoice) {
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.receipt_long,
                                  color: AppColors.info),
                              title: Text(invoice['invoice_no'] as String),
                              subtitle: Text(invoice['invoice_date'] as String),
                              trailing: Text(MoneyFormatter.format(
                                (invoice['net_total'] as num).toDouble(),
                              )),
                            );
                          }).toList(),
                        ),
                ),
                _SectionExpansion(
                  title: 'آخر السندات',
                  icon: Icons.request_quote_outlined,
                  count: provider.recentVouchers.length,
                  child: provider.recentVouchers.isEmpty
                      ? const _EmptyHint('لا توجد سندات حديثة.')
                      : Column(
                          children: provider.recentVouchers.map((voucher) {
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.request_quote_outlined),
                              title: Text(voucher['voucher_no'] as String),
                              subtitle: Text(voucher['voucher_type'] as String),
                              trailing: Text(MoneyFormatter.format(
                                (voucher['amount'] as num).toDouble(),
                              )),
                            );
                          }).toList(),
                        ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 21),
                const Spacer(),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionExpansion extends StatelessWidget {
  const _SectionExpansion({
    required this.title,
    required this.icon,
    required this.count,
    required this.child,
  });

  final String title;
  final IconData icon;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$count', style: const TextStyle(color: Colors.white60)),
            const SizedBox(width: 8),
            const Icon(Icons.expand_more),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(text, style: const TextStyle(color: Colors.white54)),
      );
}
