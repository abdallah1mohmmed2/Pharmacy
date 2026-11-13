import 'dart:async';

import 'package:flutter/material.dart';
import '../../data/models/drug_model.dart';

/// Search one pharmacy's medicines without building a dropdown for the entire
/// catalog. The caller supplies a bounded, branch-scoped SQLite lookup.
class PurchaseMedicineSearchSheet extends StatefulWidget {
  const PurchaseMedicineSearchSheet({super.key, required this.search});
  final Future<List<DrugModel>> Function(String query) search;

  @override
  State<PurchaseMedicineSearchSheet> createState() =>
      _PurchaseMedicineSearchSheetState();
}

class _PurchaseMedicineSearchSheetState
    extends State<PurchaseMedicineSearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<DrugModel> _results = const [];
  String? _error;
  bool _searching = false;
  int _request = 0;

  @override
  void dispose() {
    _request++;
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _debounce?.cancel();
    final current = ++_request;
    final query = text.trim();
    setState(() {
      _results = const [];
      _error = null;
      _searching = query.isNotEmpty;
    });
    if (query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final matches = await widget.search(query);
        if (!mounted || current != _request) return;
        setState(() {
          _results = matches;
          _searching = false;
        });
      } catch (e) {
        if (!mounted || current != _request) return;
        setState(() {
          _error = 'تعذر البحث عن الأدوية: $e';
          _searching = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('ابحث عن الدواء',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _changed,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            labelText: 'الاسم أو المادة الفعالة أو الباركود',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        if (query.isEmpty)
          const Text('اكتب جزءًا من الاسم؛ لن تُحمَّل قائمة الأدوية كاملة.'),
        if (_searching)
          const LinearProgressIndicator(),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        if (query.isNotEmpty && !_searching && _error == null)
          Text(
            _results.isEmpty
                ? 'لا توجد نتائج مطابقة'
                : 'النتائج المعروضة: ${_results.length} كحد أقصى 40 دواء',
          ),
        const SizedBox(height: 6),
        SizedBox(
          height: 300,
          child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final medicine = _results[index];
              return ListTile(
                dense: true,
                title: Text(medicine.tradeNameAr),
                subtitle: Text(
                  [
                    if (medicine.tradeNameEn.isNotEmpty) medicine.tradeNameEn,
                    if (medicine.strengthText.isNotEmpty) medicine.strengthText,
                    if (medicine.internalCode.isNotEmpty)
                      medicine.internalCode,
                  ].join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.of(context).pop(medicine),
              );
            },
          ),
        ),
      ],
    );
  }
}
