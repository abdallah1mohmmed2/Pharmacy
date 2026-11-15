import 'package:flutter/material.dart';
import '../theme/enterprise_dark_theme.dart';

/// Chooses a single-column phone layout or a wider desktop/tablet layout.
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.mobile,
    required this.desktop,
    this.breakpoint = 700,
  });

  final Widget mobile;
  final Widget desktop;
  final double breakpoint;

  bool staticIsMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < breakpoint;

  @override
  Widget build(BuildContext context) =>
      staticIsMobile(context) ? mobile : desktop;
}

/// A compact summary that progressively reveals secondary information/actions.
class SmartExpandableCard extends StatelessWidget {
  const SmartExpandableCard({
    super.key,
    required this.title,
    required this.primary,
    this.secondary,
    this.leading,
    this.trailing,
    this.details = const [],
    this.actions = const [],
    this.initiallyExpanded = false,
    this.dense = false,
  });

  final String title;
  final String primary;
  final String? secondary;
  final Widget? leading;
  final Widget? trailing;
  final List<Widget> details;
  final List<Widget> actions;
  final bool initiallyExpanded;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        leading: leading,
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(primary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              if (secondary != null && secondary!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(secondary!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 12)),
                ),
            ],
          ),
        ),
        trailing: trailing == null
            ? const Icon(Icons.expand_more)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  trailing!,
                  const SizedBox(width: 3),
                  const Icon(Icons.expand_more),
                ],
              ),
        children: [
          if (details.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, dense ? 4 : 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: details,
              ),
            ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Wrap(spacing: 8, runSpacing: 4, children: actions),
            ),
        ],
      ),
    );
  }
}

/// Search remains visible; secondary filters are moved into a keyboard-safe sheet.
class CompactSearchAndFilterBar extends StatelessWidget {
  const CompactSearchAndFilterBar({
    super.key,
    required this.controller,
    this.hintText = 'بحث...',
    this.onChanged,
    this.onFilter,
    this.filterBuilder,
    this.activeFilterCount = 0,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFilter;
  final WidgetBuilder? filterBuilder;
  final int activeFilterCount;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 50,
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: hintText,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح البحث',
                        onPressed: () {
                          controller.clear();
                          onChanged?.call('');
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Badge(
          isLabelVisible: activeFilterCount > 0,
          label: Text(activeFilterCount > 99 ? '99+' : '$activeFilterCount'),
          child: IconButton.filledTonal(
            tooltip: 'الفلاتر المتقدمة',
            onPressed: () {
              if (onFilter != null) {
                onFilter!();
              } else if (filterBuilder != null) {
                KeyboardSafeModalSheet.show<void>(
                  context: context,
                  builder: filterBuilder!,
                );
              }
            },
            icon: const Icon(Icons.tune),
          ),
        ),
      ],
    );
  }
}

/// Standard modal sheet that lifts above the keyboard and remains scrollable.
abstract final class KeyboardSafeModalSheet {
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isDismissible = true,
    bool enableDrag = true,
    double heightFactor = .92,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 8, 16, 20),
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: media.size.height * heightFactor,
              ),
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: padding,
                child: builder(sheetContext),
              ),
            ),
          ),
        );
      },
    );
  }
}

class PartyBalanceChip extends StatelessWidget {
  const PartyBalanceChip({
    super.key,
    required this.totalAlayh,
    required this.totalLah,
    this.compact = false,
  });

  final num totalAlayh;
  final num totalLah;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final net = totalAlayh - totalLah;
    final settled = net.abs() < .005;
    final color = settled
        ? Colors.white60
        : net > 0
            ? AppColors.danger
            : AppColors.success;
    final label = settled
        ? 'مسدَّد'
        : net > 0
            ? 'المتبقي عليه'
            : 'المتبقي له';
    final amount = net.abs().toStringAsFixed(2);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 12,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Text(
        settled ? label : '$label $amount',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: compact ? 11 : 13,
        ),
      ),
    );
  }
}

class LahAlayhRow {
  const LahAlayhRow({
    required this.date,
    required this.statement,
    required this.document,
    required this.alayh,
    required this.lah,
  });

  final String date;
  final String statement;
  final String document;
  final num alayh;
  final num lah;
}

class LahAlayhTable extends StatefulWidget {
  const LahAlayhTable({
    super.key,
    required this.rows,
    this.openingBalance = 0,
    this.forceTable = false,
  });

  final List<LahAlayhRow> rows;
  final double openingBalance;
  final bool forceTable;

  @override
  State<LahAlayhTable> createState() => _LahAlayhTableState();
}

class _LahAlayhTableState extends State<LahAlayhTable> {
  bool _showTable = false;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 700;
    if (!mobile || widget.forceTable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: _table(),
        ),
      );
    }
    return Column(
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: () => setState(() => _showTable = !_showTable),
            icon: Icon(
                _showTable ? Icons.view_agenda_outlined : Icons.table_chart),
            label: Text(_showTable ? 'عرض البطاقات' : 'عرض الجدول'),
          ),
        ),
        Expanded(
          child: _showTable
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _table(),
                )
              : _cards(),
        ),
      ],
    );
  }

  Widget _cards() {
    var running = widget.openingBalance;
    final balances = <double>[];
    for (final row in widget.rows) {
      running += row.alayh.toDouble() - row.lah.toDouble();
      balances.add(running);
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: widget.rows.length,
      itemBuilder: (context, index) {
        final row = widget.rows[index];
        final balance = balances[index];
        final color = balance > .005
            ? AppColors.danger
            : balance < -.005
                ? AppColors.success
                : Colors.white60;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(row.statement,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Text(row.date,
                        style: const TextStyle(color: Colors.white60)),
                  ],
                ),
                if (row.document.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(row.document,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ),
                const Divider(height: 18),
                Wrap(
                  spacing: 18,
                  runSpacing: 8,
                  children: [
                    _amountLabel('عليه', row.alayh, AppColors.danger),
                    _amountLabel('له', row.lah, AppColors.success),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Expanded(
                        child: Text('المتبقي التراكمي',
                            style: TextStyle(color: Colors.white60))),
                    Text(balance.abs().toStringAsFixed(2),
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _amountLabel(String label, num value, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(color: Colors.white60)),
          Text(value.toStringAsFixed(2),
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      );

  Widget _table() {
    var running = widget.openingBalance;
    final values = <DataRow>[];
    for (final row in widget.rows) {
      running += row.alayh.toDouble() - row.lah.toDouble();
      final color = running > .005
          ? AppColors.danger
          : running < -.005
              ? AppColors.success
              : Colors.white70;
      values.add(DataRow(cells: [
        DataCell(Text(row.date)),
        DataCell(Text(row.statement)),
        DataCell(Text(row.document)),
        DataCell(Text(row.alayh.toStringAsFixed(2))),
        DataCell(Text(row.lah.toStringAsFixed(2))),
        DataCell(Text(running.abs().toStringAsFixed(2),
            style: TextStyle(color: color))),
      ]));
    }
    return DataTable(
      headingRowColor: WidgetStateProperty.all(AppColors.surfaceHigh),
      columns: const [
        DataColumn(label: Text('التاريخ')),
        DataColumn(label: Text('البيان')),
        DataColumn(label: Text('المستند')),
        DataColumn(label: Text('عليه')),
        DataColumn(label: Text('له')),
        DataColumn(label: Text('المتبقي التراكمي')),
      ],
      rows: values,
    );
  }
}

enum ClinicalAlertLevel { info, caution, warning, block }

class ClinicalAlertBanner extends StatelessWidget {
  const ClinicalAlertBanner({
    super.key,
    required this.message,
    required this.level,
  });

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
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        border: Border.all(color: color.withValues(alpha: .55)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.health_and_safety_outlined, color: color),
          const SizedBox(width: 9),
          Expanded(child: Text(message, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}

class ManagerPinDialog extends StatefulWidget {
  const ManagerPinDialog({
    super.key,
    this.expectedPin,
    this.verifier,
    this.title = 'تأكيد المدير',
  });

  final String? expectedPin;
  final Future<bool> Function(String)? verifier;
  final String title;

  static Future<bool> show(
    BuildContext context, {
    String? expectedPin,
    Future<bool> Function(String)? verifier,
  }) async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ManagerPinDialog(
          expectedPin: expectedPin,
          verifier: verifier,
        ),
      ) ??
      false;

  @override
  State<ManagerPinDialog> createState() => _ManagerPinDialogState();
}

class _ManagerPinDialogState extends State<ManagerPinDialog> {
  final controller = TextEditingController();
  String? error;
  bool verifying = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            decoration:
                InputDecoration(labelText: 'رمز المدير', errorText: error),
            onSubmitted: (_) => _verify(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: verifying ? null : () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: verifying ? null : _verify,
            child: verifying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('تحقق'),
          ),
        ],
      );

  Future<void> _verify() async {
    setState(() => verifying = true);
    final valid = widget.verifier != null
        ? await widget.verifier!(controller.text)
        : controller.text == widget.expectedPin;
    if (!mounted) return;
    if (valid) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        verifying = false;
        error = 'رمز التحقق غير صحيح';
      });
    }
  }
}

class WalletRefField extends StatelessWidget {
  const WalletRefField({
    super.key,
    required this.controller,
    this.label = 'رقم إشعار المحفظة',
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        textDirection: TextDirection.ltr,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.receipt_long),
        ),
        validator: (value) => value == null || value.trim().length < 6
            ? 'رقم الإشعار مطلوب ولا يقل عن 6 خانات'
            : null,
      );
}
