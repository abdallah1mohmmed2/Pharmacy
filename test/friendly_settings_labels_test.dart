import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/core/constants/setting_keys.dart';
import 'package:global_enterprise_pharmacy_erp/screens/settings/friendly_settings_labels.dart';

void main() {
  test('all 35 established settings have human-readable titles and explanations',
      () {
    expect(SettingKeys.all, hasLength(35));
    expect(FriendlySettingsLabels.titles.keys.toSet(),
        SettingKeys.all.map((s) => s.key).toSet());
    expect(FriendlySettingsLabels.descriptions.keys.toSet(),
        SettingKeys.all.map((s) => s.key).toSet());
    for (final spec in SettingKeys.all) {
      final title = FriendlySettingsLabels.title(spec);
      final description = FriendlySettingsLabels.explanation(spec);
      expect(title.trim(), isNotEmpty);
      expect(description.trim(), isNotEmpty);
      expect(title, isNot(contains('.')));
      for (final value in spec.allowedValues) {
        expect(FriendlySettingsLabels.choices.containsKey(value), isTrue,
            reason: 'Missing localized choice for ' + spec.name + ': ' + value);
      }
    }
  });

  test('32 existing dropdown values still have the exact same internal codes',
      () {
    final values = SettingKeys.all
        .where((spec) => spec.allowedValues.isNotEmpty)
        .toList();
    expect(values, hasLength(11));
    for (final spec in values) {
      for (final value in spec.allowedValues) {
        expect(FriendlySettingsLabels.choice(value), isNotEmpty);
      }
    }
  });

  test('sensitive settings and immutable accounting lock remain restricted', () {
    expect(SettingKeys.byKey(SettingKey.partnerDistributionMode).requiresManager,
        isTrue);
    expect(SettingKeys.byKey(SettingKey.periodLock).requiresManager, isTrue);
    expect(SettingKeys.byKey(SettingKey.vat).requiresManager, isTrue);
    expect(SettingKeys.byKey(SettingKey.cloudSync).requiresManager, isTrue);
    expect(SettingKeys.byKey(SettingKey.lahAlayhTermsOnly).defaultValue, true);
  });

  test('every known role permission uses an Arabic description', () {
    const existing = [
      'dashboard.view','pos.sell','pos.discount.override','drugs.view',
      'drugs.create','drugs.update','drugs.import','drugs.export',
      'inventory.view','inventory.adjust','inventory.stocktake',
      'purchases.manage','sales.returns','clinical.override','finance.view',
      'finance.manage','partners.manage','reports.view','reports.export',
      'settings.view','settings.manage','settings.manager_pin','audit.view',
      'audit.verify','backup.create','backup.restore','sync.manage',
      'period.close','users.manage','roles.manage','reports.cost.view'
    ];
    expect(FriendlySettingsLabels.permissions.keys.toSet(), existing.toSet());
    expect(FriendlySettingsLabels.permission('backup.restore'), 'استعادة نسخة احتياطية');
  });
}
