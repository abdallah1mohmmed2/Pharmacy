import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/core/constants/setting_keys.dart';
import 'package:global_enterprise_pharmacy_erp/screens/settings/friendly_json_setting_editor.dart';

Future<Map<String, Object?>?> _edit(
  WidgetTester tester,
  SettingKey key,
  Map<String, Object?> initial,
  Future<void> Function(WidgetTester tester) applyChanges,
) async {
  Map<String, Object?>? saved;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
          builder: (context) => FilledButton(
                key: const ValueKey('show-friendly-dialog'),
                onPressed: () async {
                  saved = await showDialog<Map<String, Object?>>(
                    context: context,
                    builder: (_) => FriendlyJsonSettingEditor(
                      spec: SettingKeys.byKey(key),
                      initialValue: initial,
                    ),
                  );
                },
                child: const Text('تحرير الإعداد'),
              )),
    ),
  ));
  await tester.tap(find.byKey(const ValueKey('show-friendly-dialog')));
  await tester.pumpAndSettle();
  await applyChanges(tester);
  await tester.tap(find.byKey(const ValueKey('friendly-settings-save')));
  await tester.pumpAndSettle();
  return saved;
}

void main() {
  testWidgets('tax switch and percentage preserve unknown JSON members',
      (tester) async {
    final output = await _edit(tester, SettingKey.vat, {
      'enabled': false,
      'rate_pct': 0,
      'custom_future_value': 'unchanged'
    }, (tester) async {
      await tester
          .tap(find.byKey(const ValueKey('setting-json-switch-enabled')));
      await tester.enterText(
          find.byKey(const ValueKey('setting-json-number-rate_pct')), '15.5');
      await tester.pumpAndSettle();
    });
    expect(output?['enabled'], isTrue);
    expect(output?['rate_pct'], 15.5);
    expect(output?['custom_future_value'], 'unchanged');
  });

  testWidgets('currency choice changes code and symbol but keeps stored types',
      (tester) async {
    final output = await _edit(tester, SettingKey.currency, {
      'code': 'YER',
      'symbol': 'ر.ي',
      'decimals': 0,
      'future': 17
    }, (tester) async {
      await tester.tap(find.byKey(const ValueKey('setting-json-choice-code')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ريال سعودي').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('setting-json-text-symbolSAR')),
            )
            .initialValue,
        'ر.س',
      );
    });
    expect(output?['code'], 'SAR');
    expect(output?['symbol'], 'ر.س');
    expect(output?['decimals'], isA<int>());
    expect(output?['decimals'], 2);
    expect(output?['future'], 17);
  });

  testWidgets('cloud credentials survive when advanced settings stay collapsed',
      (tester) async {
    const original = <String, Object?>{
      'enabled': false,
      'provider': 'firestore',
      'project_id': 'existing-project',
      'api_key': 'existing-key',
      'database_id': '(default)',
      'batch_size': 100,
      'future_key': 'keep',
    };
    final output =
        await _edit(tester, SettingKey.cloudSync, original, (tester) async {
      await tester
          .tap(find.byKey(const ValueKey('setting-json-switch-enabled')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('setting-json-text-api_key')),
          findsNothing);
    });
    expect(output?['enabled'], isTrue);
    expect(output?['api_key'], 'existing-key');
    expect(output?['project_id'], 'existing-project');
    expect(output?['batch_size'], 100);
    expect(output?['future_key'], 'keep');
    expect(original['enabled'], false, reason: 'Initial map must be immutable');
  });

  testWidgets('backup toggle and retention count do not replace other keys',
      (tester) async {
    final output = await _edit(tester, SettingKey.autoLocalOnClose, {
      'enabled': true,
      'keep_last': 10,
      'compress': true,
      'extra': 'preserve'
    }, (tester) async {
      await tester.enterText(
          find.byKey(const ValueKey('setting-json-number-keep_last')), '25');
      await tester
          .tap(find.byKey(const ValueKey('setting-json-switch-compress')));
      await tester.pumpAndSettle();
    });
    expect(output, {
      'enabled': true,
      'keep_last': 25,
      'compress': false,
      'extra': 'preserve',
    });
  });

  testWidgets('setting can clear period lock date without editing JSON',
      (tester) async {
    final output = await _edit(tester, SettingKey.periodLock,
        {'locked_through': '2026-10-31', 'future': true}, (tester) async {
      await tester.tap(find.byKey(const ValueKey('setting-period-clear-date')));
      await tester.pumpAndSettle();
    });
    expect(output?['locked_through'], isNull);
    expect(output?['future'], isTrue);
  });

  testWidgets('report heading editor retains all other JSON entries',
      (tester) async {
    final output = await _edit(tester, SettingKey.reportHeaderFooter,
        {'header': 'قديم', 'footer': 'ثابت', 'extra': 42}, (tester) async {
      await tester.enterText(
          find.byKey(const ValueKey('setting-json-text-header')),
          'مرحبًا بكم في الصيدلية');
    });
    expect(output?['header'], 'مرحبًا بكم في الصيدلية');
    expect(output?['footer'], 'ثابت');
    expect(output?['extra'], 42);
  });
}
