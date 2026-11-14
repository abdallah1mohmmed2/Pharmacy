import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/manual_message_service.dart';
import 'package:global_enterprise_pharmacy_erp/screens/accounts/manual_message_composer_screen.dart';

class _FakeTemplates implements ManualMessageTemplateRepository {
  final saved = <String, String>{};

  @override
  Future<String> load(String kindId) async =>
      saved[kindId] ?? ManualMessageKind.byId(kindId).defaultText;

  @override
  Future<void> save(String kindId, String template) async {
    saved[kindId] = template;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => sqfliteFfiInit());

  test('SQLite templates are preserved after database restart', () async {
    final dir = await Directory.systemTemp.createTemp('pharmacy-templates-');
    final path = '${dir.path}/messages.db';
    try {
      final firstDb = await databaseFactoryFfi.openDatabase(path);
      await firstDb.execute('''CREATE TABLE app_settings (
        setting_key TEXT PRIMARY KEY,
        value_text TEXT NOT NULL,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )''');
      final first = SqliteManualMessageTemplates(
          helper: DatabaseHelper.forTesting(firstDb));
      await first.save('customer_balance', 'تذكير خاص {name}: {amount}');
      await firstDb.close();
      final reopened = await databaseFactoryFfi.openDatabase(path);
      try {
        final second = SqliteManualMessageTemplates(
            helper: DatabaseHelper.forTesting(reopened));
        expect(await second.load('customer_balance'),
            'تذكير خاص {name}: {amount}');
        expect(await second.load('supplier_balance'),
            ManualMessageKind.byId('supplier_balance').defaultText);
      } finally {
        await reopened.close();
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('only relevant templates are exposed to each account type', () {
    expect(
      ManualMessageKind.forParty('CUSTOMER').map((kind) => kind.id),
      containsAll(['customer_balance', 'customer_receipt', 'general_notice']),
    );
    expect(
      ManualMessageKind.forParty('SUPPLIER').map((kind) => kind.id),
      containsAll(['supplier_balance', 'supplier_payment', 'general_notice']),
    );
    expect(
      ManualMessageKind.forParty('REPRESENTATIVE').map((kind) => kind.id),
      containsAll(['representative_notice', 'general_notice']),
    );
    expect(
      ManualMessageKind.forParty('CUSTOMER').map((kind) => kind.id),
      isNot(contains('supplier_payment')),
    );
  });

  test('template fills only available data and flags missing values', () {
    const template = 'إلى {name}: {amount} سند {document}';
    final text = ManualMessageFormatter.render(
      template,
      name: 'أحمد',
      amount: '175.00',
    );
    expect(text, 'إلى أحمد: 175.00 سند {document}');
    expect(ManualMessageFormatter.hasUnresolvedVariables(text), isTrue);
    expect(
      ManualMessageFormatter.render(
        template,
        name: 'أحمد',
        amount: '175.00',
        document: 'VCH-123',
      ),
      'إلى أحمد: 175.00 سند VCH-123',
    );
  });

  test('SMS URI prepopulates phone and Arabic text, never sends', () {
    final uri = ManualMessageFormatter.smsUri(
      phone: '+٩٦٧ ٧٧٧ ١٢٣ ٤٥٦',
      text: 'مرحباً، المبلغ 100',
    );
    expect(uri.scheme, 'sms');
    expect(uri.path, '+967777123456');
    expect(uri.queryParameters['body'], 'مرحباً، المبلغ 100');
  });

  test('WhatsApp URL uses international number and encoded body', () {
    final uri = ManualMessageFormatter.whatsappUri(
      phone: '00967-777123456',
      text: 'فاتورة رقم ١٠ / مبلغ 200',
    );
    expect(uri.scheme, 'https');
    expect(uri.host, 'wa.me');
    expect(uri.path, '/967777123456');
    expect(uri.queryParameters['text'], 'فاتورة رقم ١٠ / مبلغ 200');
    expect(
      () => ManualMessageFormatter.whatsappUri(
          phone: '0777123456', text: 'رسالة'),
      throwsFormatException,
    );
  });

  test('invalid phone and empty message are rejected before handoff', () {
    expect(
      () => ManualMessageFormatter.smsUri(phone: '12', text: 'نص'),
      throwsFormatException,
    );
    expect(
      () => ManualMessageFormatter.smsUri(phone: '+967777123456', text: '  '),
      throwsArgumentError,
    );
  });

  testWidgets('edited SMS opens external app but never records a send',
      (tester) async {
    final templates = _FakeTemplates();
    final opened = <Uri>[];
    await tester.pumpWidget(MaterialApp(
      home: ManualMessageComposerScreen(
        partyType: 'CUSTOMER',
        name: 'عميل تجريبي',
        phone: '+967777123456',
        balanceAmount: '120.00',
        preferredChannel: 'sms',
        templates: templates,
        openExternal: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('تذكير العميل بالمبلغ المتبقي'), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const ValueKey('manual-message-body')));
    await tester.enterText(
      find.byKey(const ValueKey('manual-message-body')),
      'تم تعديل الرسالة يدوياً',
    );
    await tester.ensureVisible(find.text('فتح SMS'));
    await tester.tap(find.text('فتح SMS'));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
    expect(opened.single.scheme, 'sms');
    expect(opened.single.queryParameters['body'], 'تم تعديل الرسالة يدوياً');
    expect(templates.saved, isEmpty);
    expect(find.textContaining('لا يمكن تأكيد تسليم الرسالة'), findsOneWidget);
  });

  testWidgets('custom template is persisted only when save is pressed',
      (tester) async {
    final templates = _FakeTemplates();
    await tester.pumpWidget(MaterialApp(
      home: ManualMessageComposerScreen(
        partyType: 'SUPPLIER',
        name: 'مورد تجريبي',
        phone: '+967777123456',
        templates: templates,
        openExternal: (_) async => true,
      ),
    ));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('manual-template-editor')));
    await tester.enterText(
      find.byKey(const ValueKey('manual-template-editor')),
      'مرحباً {name}، القالب المعدّل',
    );
    expect(templates.saved, isEmpty);
    await tester.ensureVisible(find.text('حفظ القالب'));
    await tester.tap(find.text('حفظ القالب'));
    await tester.pumpAndSettle();
    expect(
      templates.saved['supplier_balance'],
      'مرحباً {name}، القالب المعدّل',
    );
  });
}
