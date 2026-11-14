import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:global_enterprise_pharmacy_erp/core/theme/enterprise_dark_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/database_helper.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/shift_and_treasury_service.dart';
import 'package:global_enterprise_pharmacy_erp/providers/session_and_erp_provider.dart';
import 'treasury_integrity_integration_test.dart' show openSaleDatabase;
import 'package:global_enterprise_pharmacy_erp/providers/treasury_hr_partner_provider.dart';
import 'package:global_enterprise_pharmacy_erp/screens/finance/s22_treasury_wallets_screen.dart';

class _FailMovementsOnce extends ShiftAndTreasuryService {
  _FailMovementsOnce(DatabaseHelper helper) : super(helper: helper);
  bool fail = true;
  @override
  Future<List<Map<String, Object?>>> transactions(int branchId,
      {int? accountId, String? from, String? to}) {
    if (fail) return Future.error(StateError('test movement read failure'));
    return super.transactions(branchId, accountId: accountId, from: from, to: to);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final arabic = FontLoader('TreasuryArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf'));
    await arabic.load();
  });

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
      MultiProvider(providers: [
        ChangeNotifierProvider<TreasuryHrPartnerProvider>.value(value: provider),
        ChangeNotifierProvider(create: (_) => SessionAndErpProvider()),
      ], child: const MaterialApp(home: S22TreasuryWalletsScreen())),
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
  Future<void> captureLayout(WidgetTester tester, String filename) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('treasury-test-render')));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('test_artifacts').create(recursive: true);
        await File('test_artifacts/$filename').writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  Future<void> waitForTreasury(WidgetTester tester,
      TreasuryHrPartnerProvider provider) async {
    // SQLite replies arrive on the real event loop, while provider futures
    // started by a widget finish in the test's fake zone. Advance both.
    for (var attempt = 0; attempt < 500 && provider.treasuryLoading; attempt++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(provider.treasuryLoading, isFalse, reason: 'treasury load must finish');
  }

  Future<void> mountFromEmptyProvider(WidgetTester tester,
      TreasuryHrPartnerProvider provider, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = SessionAndErpProvider()..currentUser = {'id': 1};
    expect(provider.cashAccounts, isEmpty);
    await tester.pumpWidget(MultiProvider(providers: [
        ChangeNotifierProvider<TreasuryHrPartnerProvider>.value(value: provider),
        ChangeNotifierProvider<SessionAndErpProvider>.value(value: session),
      ], child: RepaintBoundary(key: const ValueKey('treasury-test-render'),
          child: MaterialApp(theme: EnterpriseDarkTheme.data.copyWith(
              platform: size.width >= 700 ? TargetPlatform.windows : TargetPlatform.android,
              textTheme: EnterpriseDarkTheme.data.textTheme.apply(fontFamily: 'TreasuryArabic')),
              builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
              home: const S22TreasuryWalletsScreen()))));
    await waitForTreasury(tester, provider);
    expect(provider.userId, 1);
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
      session.dispose();
    });
  }

  for (final size in [const Size(360, 640), const Size(390, 844), const Size(1280, 900), const Size(1366, 768)]) {
    testWidgets('seeded SQLite accounts load on entry and every card is visible at $size', (tester) async {
      final db = await tester.runAsync(() => openSaleDatabase(inMemoryDatabasePath));
      addTearDown(() => db!.close());
      final provider = TreasuryHrPartnerProvider(database: DatabaseHelper.forTesting(db!));
      await mountFromEmptyProvider(tester, provider, size);
      expect(provider.treasuryError, isNull);
      expect(provider.cashAccounts.length, greaterThanOrEqualTo(6));
      expect(provider.cashAccounts.any((a) => a['name_ar'] == 'محفظة جيب'), isTrue);
      await captureLayout(tester, 'treasury_${size.width.toInt()}_top.png');
      for (final account in provider.cashAccounts) {
        final card = find.byKey(ValueKey('treasury-account-${account['id']}'));
        expect(card, findsOneWidget);
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        final rect = tester.getRect(card);
        expect(rect.width, greaterThan(0));
        expect(rect.height, greaterThan(0));
        expect(rect.overlaps(Offset.zero & size), isTrue);
        if (account['code'] == 'W-JAIB') {
          await captureLayout(tester, 'treasury_${size.width.toInt()}_wallets.png');
        }
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed movements do not hide seeded wallet cards and retry recovers', (tester) async {
    final db = await tester.runAsync(() => openSaleDatabase(inMemoryDatabasePath));
    addTearDown(() => db!.close());
    final helper = DatabaseHelper.forTesting(db!);
    final service = _FailMovementsOnce(helper);
    final provider = TreasuryHrPartnerProvider(database: helper, treasury: service);
    await mountFromEmptyProvider(tester, provider, const Size(1280, 900));
    expect(find.textContaining('تعذر تحميل بيانات الخزينة'), findsOneWidget);
    expect(provider.cashAccounts, isNotEmpty);
    expect(find.byKey(ValueKey('treasury-account-${provider.cashAccounts.first['id']}')), findsOneWidget);
    service.fail = false;
    await tester.tap(find.text('إعادة المحاولة'));
    await waitForTreasury(tester, provider);
    await tester.pumpAndSettle();
    expect(provider.treasuryError, isNull);
    expect(find.textContaining('تعذر تحميل بيانات الخزينة'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty branch explains missing accounts instead of showing only table headings', (tester) async {
    final db = await tester.runAsync(() => openSaleDatabase(inMemoryDatabasePath));
    addTearDown(() => db!.close());
    await tester.runAsync(() => db!.update('cash_accounts', {'is_deleted': 1}));
    final provider = TreasuryHrPartnerProvider(database: DatabaseHelper.forTesting(db!));
    await mountFromEmptyProvider(tester, provider, const Size(390, 844));
    expect(find.text('لا توجد حسابات خزينة أو محافظ في الفرع الحالي'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
