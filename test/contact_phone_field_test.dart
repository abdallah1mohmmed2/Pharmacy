import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/core/widgets/contact_phone_field.dart';

void main() {
  testWidgets(
      'fills phone and blank party name from a selected Android contact',
      (tester) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    addTearDown(name.dispose);
    addTearDown(phone.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ContactPhoneField(
          nameController: name,
          phoneController: phone,
          selector: () async => const SelectedPhoneContact(
            name: 'أحمد المورد',
            phone: '+967777123456',
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('pick-party-contact')));
    await tester.pumpAndSettle();
    expect(name.text, 'أحمد المورد');
    expect(phone.text, '+967777123456');
  });

  testWidgets('preserves edited client name and only replaces selected phone',
      (tester) async {
    final name = TextEditingController(text: 'اسم العميل المحفوظ');
    final phone = TextEditingController(text: '111222333');
    addTearDown(name.dispose);
    addTearDown(phone.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ContactPhoneField(
          nameController: name,
          phoneController: phone,
          selector: () async => const SelectedPhoneContact(
            name: 'اسم آخر من دفتر الهاتف',
            phone: '+967733222111',
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('pick-party-contact')));
    await tester.pumpAndSettle();
    expect(name.text, 'اسم العميل المحفوظ');
    expect(phone.text, '+967733222111');
  });

  testWidgets('cancelling picker leaves existing values unchanged',
      (tester) async {
    final name = TextEditingController(text: 'المورد الحالي');
    final phone = TextEditingController(text: '123456789');
    addTearDown(name.dispose);
    addTearDown(phone.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ContactPhoneField(
          nameController: name,
          phoneController: phone,
          selector: () async => null,
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('pick-party-contact')));
    await tester.pumpAndSettle();
    expect(name.text, 'المورد الحالي');
    expect(phone.text, '123456789');
  });

  testWidgets('failed picker keeps manual editing available', (tester) async {
    final name = TextEditingController();
    final phone = TextEditingController(text: '123456789');
    addTearDown(name.dispose);
    addTearDown(phone.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ContactPhoneField(
          nameController: name,
          phoneController: phone,
          selector: () async => throw StateError('Contact app missing'),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('pick-party-contact')));
    await tester.pumpAndSettle();
    expect(phone.text, '123456789');
    await tester.enterText(
        find.byKey(const ValueKey('party-contact-phone')), '+967777888999');
    expect(phone.text, '+967777888999');
  });
}
