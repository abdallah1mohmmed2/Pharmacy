import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:global_enterprise_pharmacy_erp/providers/treasury_hr_partner_provider.dart';
import 'package:global_enterprise_pharmacy_erp/screens/finance/s22_treasury_wallets_screen.dart';

void main() {
  Future<void> expectTreasuryCardsAtSize(
    WidgetTester tester, {
    required Size size,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = TreasuryHrPartnerProvider()
      ..cashAccounts = [
        {
          'id': 1,
          'name_ar': 'صندوق الاختبار',
          'account_kind': 'MAIN_SAFE',
          'current_balance': 1250.0,
          'wallet_phone': null,
        },
      ]
      ..transactions = [];

    await tester.pumpWidget(
      ChangeNotifierProvider<TreasuryHrPartnerProvider>.value(
        value: provider,
        child: const MaterialApp(home: S22TreasuryWalletsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('صندوق الاختبار'), findsOneWidget);
    expect(find.text('1250.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  testWidgets('treasury account cards are visible on phone width',
      (tester) async {
    await expectTreasuryCardsAtSize(
      tester,
      size: const Size(390, 844),
    );
  });

  testWidgets('treasury account cards remain visible on desktop width',
      (tester) async {
    await expectTreasuryCardsAtSize(
      tester,
      size: const Size(1280, 900),
    );
  });
}
