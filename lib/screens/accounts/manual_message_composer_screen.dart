import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/manual_message_service.dart';

typedef ExternalMessageOpener = Future<bool> Function(Uri uri);

/// Previews a local message and hands off to WhatsApp/SMS; user sends it.
class ManualMessageComposerScreen extends StatefulWidget {
  const ManualMessageComposerScreen({
    super.key,
    required this.partyType,
    required this.name,
    required this.phone,
    this.balanceAmount,
    this.transactionAmount,
    this.documentNumber,
    this.initialKind,
    this.preferredChannel = 'whatsapp',
    this.templates,
    this.openExternal,
  });

  final String partyType, name, phone, preferredChannel;
  final String? balanceAmount, transactionAmount, documentNumber, initialKind;
  final ManualMessageTemplateRepository? templates;
  final ExternalMessageOpener? openExternal;

  @override
  State<ManualMessageComposerScreen> createState() =>
      _ManualMessageComposerScreenState();
}

class _ManualMessageComposerScreenState
    extends State<ManualMessageComposerScreen> {
  late final ManualMessageTemplateRepository _templates;
  late final List<ManualMessageKind> _kinds;
  late String _kindId;
  late final TextEditingController _phone;
  late final TextEditingController _amount;
  late final TextEditingController _document;
  final _template = TextEditingController();
  final _message = TextEditingController();
  bool _loading = true, _busy = false;
  String? _error;

  bool _isBalanceKind(String id) =>
      id == 'customer_balance' || id == 'supplier_balance';

  String _initialAmount(String id) =>
      (_isBalanceKind(id) ? widget.balanceAmount : widget.transactionAmount) ??
      '';

  @override
  void initState() {
    super.initState();
    _templates = widget.templates ?? SqliteManualMessageTemplates();
    _kinds = ManualMessageKind.forParty(widget.partyType);
    _kindId = _kinds.any((kind) => kind.id == widget.initialKind)
        ? widget.initialKind!
        : _kinds.first.id;
    _phone = TextEditingController(text: widget.phone);
    _amount = TextEditingController(text: _initialAmount(_kindId));
    _document = TextEditingController(text: widget.documentNumber ?? '');
    _load();
  }

  Future<void> _load() async {
    final id = _kindId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final saved = await _templates.load(id);
      if (!mounted || _kindId != id) return;
      _template.text = saved;
      _fill();
    } catch (_) {
      if (!mounted || _kindId != id) return;
      _template.text = ManualMessageKind.byId(id).defaultText;
      _fill();
      setState(
          () => _error = 'تعذر تحميل القالب المحفوظ؛ تم عرض القالب الافتراضي.');
    } finally {
      if (mounted && _kindId == id) setState(() => _loading = false);
    }
  }

  void _selectKind(String? value) {
    if (value == null || value == _kindId) return;
    setState(() {
      _kindId = value;
      _amount.text = _initialAmount(value);
      _document.text = widget.documentNumber ?? '';
      _message.clear();
    });
    _load();
  }

  void _fill() {
    _message.text = ManualMessageFormatter.render(
      _template.text,
      name: widget.name,
      amount: _amount.text,
      document: _document.text,
    );
  }

  Future<void> _saveTemplate() async {
    if (_template.text.trim().isEmpty) {
      setState(() => _error = 'لا يمكن حفظ قالب فارغ.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _templates.save(_kindId, _template.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ القالب للاستخدام لاحقاً.')),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر حفظ القالب. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String channel) async {
    final text = _message.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'اكتب نص الرسالة أولاً.');
      return;
    }
    if (ManualMessageFormatter.hasUnresolvedVariables(text)) {
      setState(() => _error =
          'أكمل المبلغ ورقم المستند المطلوبين ثم اضغط «تعبئة النص»، أو عدّل النص لإزالة المتغيرات الناقصة.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final uri = channel == 'sms'
          ? ManualMessageFormatter.smsUri(phone: _phone.text, text: text)
          : ManualMessageFormatter.whatsappUri(phone: _phone.text, text: text);
      final opened = await (widget.openExternal?.call(uri) ??
          launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!mounted) return;
      if (!opened) {
        setState(() =>
            _error = 'لم يتمكن الجهاز من فتح التطبيق المطلوب. تحقق من تثبيته.');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(seconds: 5),
          content: Text(
              'تم فتح التطبيق فقط. اضغط إرسال بنفسك؛ لا يمكن تأكيد تسليم الرسالة.'),
        ));
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted)
        setState(
            () => _error = 'تعذر فتح التطبيق. تحقق من الرقم والتطبيق المثبت.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _channelButton(String channel) {
    final preferred = widget.preferredChannel == channel;
    final icon = channel == 'sms' ? Icons.sms_outlined : Icons.chat_outlined;
    final label = channel == 'sms' ? 'فتح SMS' : 'فتح واتساب';
    final action = _loading || _busy ? null : () => _open(channel);
    if (preferred) {
      return FilledButton.icon(
        onPressed: action,
        icon: Icon(icon),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: action,
      icon: Icon(icon),
      label: Text(label),
    );
  }

  @override
  void dispose() {
    _phone.dispose();
    _amount.dispose();
    _document.dispose();
    _template.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('رسالة يدوية • واتساب أو SMS')),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('إلى: ${widget.name}',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'رقم الهاتف',
                        helperText:
                            'لواتساب استخدم رمز الدولة، مثل +967xxxxxxxxx',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _kindId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'نوع الرسالة / الحالة',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final kind in _kinds)
                          DropdownMenuItem(
                              value: kind.id, child: Text(kind.title)),
                      ],
                      onChanged: _busy ? null : _selectKind,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amount,
                      decoration: const InputDecoration(
                        labelText: 'المبلغ (عند توفره)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _document,
                      decoration: const InputDecoration(
                        labelText: 'رقم المستند (اختياري ما لم يطلبه القالب)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('القالب المحفوظ',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text(
                        'المتغيرات: {name} اسم الطرف، {amount} المبلغ، {document} رقم المستند.'),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('manual-template-editor'),
                      controller: _template,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'تعديل قالب هذه الحالة',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _loading || _busy ? null : _saveTemplate,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('حفظ القالب'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _loading || _busy
                              ? null
                              : () {
                                  setState(() => _error = null);
                                  _fill();
                                },
                          icon: const Icon(Icons.auto_fix_high),
                          label: const Text('تعبئة النص من القالب'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('معاينة الرسالة قبل الإرسال',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _message,
                      key: const ValueKey('manual-message-body'),
                      minLines: 4,
                      maxLines: 9,
                      decoration: const InputDecoration(
                        labelText: 'نص قابل للتعديل قبل فتح التطبيق',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (widget.preferredChannel == 'sms') ...[
                        _channelButton('sms'),
                        _channelButton('whatsapp'),
                      ] else ...[
                        _channelButton('whatsapp'),
                        _channelButton('sms'),
                      ],
                    ]),
                    const SizedBox(height: 8),
                    const Text(
                        'الإرسال يدوي من التطبيق الخارجي. فتحه لا يعني أن الرسالة أُرسلت.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
