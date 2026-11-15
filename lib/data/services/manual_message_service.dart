import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';

/// A manual external-app handoff: never automatically sends or marks messages sent.
class ManualMessageKind {
  const ManualMessageKind(
      this.id, this.title, this.defaultText, this.partyTypes);
  final String id, title, defaultText;
  final List<String> partyTypes;

  static const all = <ManualMessageKind>[
    ManualMessageKind(
        'customer_balance',
        'تذكير العميل بالمبلغ المتبقي',
        'مرحباً {name}، نذكّركم بأن المبلغ المتبقي على حسابكم هو {amount}. نرجو مراجعة الصيدلية عند التمكن، وشكراً لتعاونكم.',
        ['CUSTOMER']),
    ManualMessageKind(
        'customer_receipt',
        'تأكيد استلام دفعة من العميل',
        'مرحباً {name}، نؤكد استلام دفعتكم بمبلغ {amount} بموجب المستند رقم {document}. شكراً لتعاملكم معنا.',
        ['CUSTOMER']),
    ManualMessageKind(
        'supplier_balance',
        'إشعار المورد بالمبلغ المستحق',
        'مرحباً {name}، نود إفادتكم بأن المبلغ المستحق لكم في حساب الصيدلية هو {amount}. شاكرين تعاونكم.',
        ['SUPPLIER']),
    ManualMessageKind(
        'supplier_payment',
        'إشعار بسداد مستحقات المورد',
        'مرحباً {name}، نحيطكم علماً بإجراء دفعة بمبلغ {amount} بموجب المستند رقم {document}. يرجى مطابقة العملية مع حسابكم.',
        ['SUPPLIER']),
    ManualMessageKind(
        'employee_payment',
        'إشعار مالي للموظف',
        'مرحباً {name}، نود إشعاركم بعملية مالية بمبلغ {amount}. يرجى مراجعة تفاصيل الحساب لدى الإدارة.',
        ['EMPLOYEE']),
    ManualMessageKind(
        'partner_notice',
        'إشعار مالي للشريك',
        'مرحباً {name}، نود إشعاركم بتحديث حسابكم المالي بمبلغ {amount}. يرجى مراجعة التفاصيل لدى الإدارة.',
        ['PARTNER']),
    ManualMessageKind(
        'representative_notice',
        'إشعار للمندوب',
        'مرحباً {name}، يرجى التواصل مع الصيدلية بشأن متابعة المعاملة الخاصة بكم.',
        ['REPRESENTATIVE']),
    ManualMessageKind(
        'general_notice',
        'رسالة عامة',
        'مرحباً {name}، تحية طيبة من الصيدلية.',
        ['CUSTOMER', 'SUPPLIER', 'EMPLOYEE', 'PARTNER', 'REPRESENTATIVE']),
  ];

  static List<ManualMessageKind> forParty(String partyType) =>
      all.where((kind) => kind.partyTypes.contains(partyType)).toList();
  static ManualMessageKind byId(String id) =>
      all.firstWhere((kind) => kind.id == id);
}

abstract class ManualMessageTemplateRepository {
  Future<String> load(String kindId);
  Future<void> save(String kindId, String template);
}

/// app_settings is already part of the SQLite backup. No schema or financial edits.
class SqliteManualMessageTemplates implements ManualMessageTemplateRepository {
  SqliteManualMessageTemplates({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;
  final DatabaseHelper _helper;
  static const _prefix = 'messaging.manual.template.';

  @override
  Future<String> load(String kindId) async {
    final kind = ManualMessageKind.byId(kindId);
    final rows = await _helper.query('app_settings',
        where: 'setting_key=?', whereArgs: ['$_prefix$kindId'], limit: 1);
    return rows.isEmpty
        ? kind.defaultText
        : (rows.first['value_text'] as String? ?? kind.defaultText);
  }

  @override
  Future<void> save(String kindId, String template) async {
    ManualMessageKind.byId(kindId);
    if (template.trim().isEmpty) throw ArgumentError('لا يمكن حفظ قالب فارغ');
    final db = await _helper.database;
    await db.insert(
        'app_settings',
        {
          'setting_key': '$_prefix$kindId',
          'value_text': template,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

class ManualMessageFormatter {
  static String render(
    String template, {
    required String name,
    String? amount,
    String? document,
  }) =>
      template
          .replaceAll('{name}', name)
          .replaceAll('{amount}',
              amount?.trim().isNotEmpty == true ? amount! : '{amount}')
          .replaceAll('{document}',
              document?.trim().isNotEmpty == true ? document! : '{document}');

  static bool hasUnresolvedVariables(String text) =>
      RegExp(r'\{(?:name|amount|document)\}').hasMatch(text);

  static String normalizedPhone(String input) {
    var number = input.trim().replaceAll(RegExp(r'[\s().-]'), '');
    number = number.replaceAllMapped(RegExp(r'[٠-٩۰-۹]'), (match) {
      final code = match.group(0)!.runes.first;
      return (code >= 0x06F0 ? code - 0x06F0 : code - 0x0660).toString();
    });
    if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(number)) {
      throw const FormatException(
          'رقم الهاتف غير صالح. أدخل رقماً من 7 إلى 15 خانة.');
    }
    return number;
  }

  static Uri smsUri({required String phone, required String text}) {
    final number = normalizedPhone(phone);
    if (text.trim().isEmpty) throw ArgumentError('نص الرسالة فارغ');
    return Uri.parse('sms:$number?body=${Uri.encodeComponent(text)}');
  }

  static Uri whatsappUri({required String phone, required String text}) {
    final number = normalizedPhone(phone);
    if (text.trim().isEmpty) throw ArgumentError('نص الرسالة فارغ');
    final digits = number.startsWith('+')
        ? number.substring(1)
        : number.startsWith('00')
            ? number.substring(2)
            : number;
    if (digits.startsWith('0') || digits.length < 9) {
      throw const FormatException(
          'واتساب يحتاج رقم الهاتف مع رمز الدولة، مثل +967xxxxxxxxx.');
    }
    return Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(text)}');
  }
}
