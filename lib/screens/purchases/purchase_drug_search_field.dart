import 'package:flutter/material.dart';
import '../../data/models/drug_model.dart';

/// Bounded, on-demand medicine lookup for purchase/bonus invoice lines.
///
/// This intentionally never builds a dropdown from the whole local catalog.
/// The database-backed search must filter by the active branch and limit rows.
class PurchaseDrugSearchField extends StatefulWidget {
  const PurchaseDrugSearchField({
    super.key,
    required this.search,
    required this.onSelected,
    required this.onCleared,
    this.initialDrug,
    this.enabled = true,
  });

  final Future<List<DrugModel>> Function(String query) search;
  final ValueChanged<DrugModel> onSelected;
  final VoidCallback onCleared;
  final DrugModel? initialDrug;
  final bool enabled;

  @override
  State<PurchaseDrugSearchField> createState() =>
      _PurchaseDrugSearchFieldState();
}

class _PurchaseDrugSearchFieldState extends State<PurchaseDrugSearchField> {
  String? _selectionLabel;

  static String _label(DrugModel drug) {
    final name = drug.tradeNameAr.trim().isNotEmpty
        ? drug.tradeNameAr
        : drug.tradeNameEn;
    final strength =
        drug.strengthText.trim().isEmpty ? '' : ' • ${drug.strengthText.trim()}';
    final code = drug.internalCode.trim().isEmpty
        ? ''
        : ' [${drug.internalCode.trim()}]';
    return '$name$strength$code';
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialDrug != null) {
      _selectionLabel = _label(widget.initialDrug!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<DrugModel>(
      initialValue: widget.initialDrug == null
          ? null
          : TextEditingValue(text: _label(widget.initialDrug!)),
      displayStringForOption: _label,
      optionsBuilder: (value) async {
        final query = value.text.trim();
        // Avoid full-catalog searches for an empty or one-character query.
        if (!widget.enabled || query.length < 2) {
          return const <DrugModel>[];
        }
        // Debounce rapid typing; RawAutocomplete discards stale async replies.
        await Future<void>.delayed(const Duration(milliseconds: 180));
        if (!mounted) return const <DrugModel>[];
        final results = await widget.search(query);
        return results.take(40).toList(growable: false);
      },
      onSelected: (selected) {
        _selectionLabel = _label(selected);
        widget.onSelected(selected);
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
          TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: widget.enabled,
        onChanged: (value) {
          if (_selectionLabel != null && value != _selectionLabel) {
            _selectionLabel = null;
            widget.onCleared();
          }
        },
        onSubmitted: (_) => onSubmitted(),
        decoration: const InputDecoration(
          labelText: 'ابحث عن الدواء بالاسم أو الباركود أو الرمز *',
          hintText: 'اكتب حرفين على الأقل ثم اختر الدواء',
          prefixIcon: Icon(Icons.search),
          border: OutlineInputBorder(),
        ),
      ),
    );
  }
}
