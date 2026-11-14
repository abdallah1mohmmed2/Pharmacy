import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:global_enterprise_pharmacy_erp/core/theme/enterprise_dark_theme.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/erp_models.dart';
import 'package:global_enterprise_pharmacy_erp/providers/session_and_erp_provider.dart';
import 'package:global_enterprise_pharmacy_erp/screens/accounts/party_details_screen.dart';
import 'package:global_enterprise_pharmacy_erp/screens/accounts/s19_s20_s21_parties_and_vouchers_screen.dart';

class _Session extends SessionAndErpProvider {
  bool fail = false;
  final requested = <int>[];
  @override
  Future<List<Map<String, Object?>>> ledger(int partyId) async {
    requested.add(partyId);
    if (fail) throw StateError('offline');
    return [
      {
        'entry_date': '2026-11-14',
        'statement_ar': 'حركة خاصة $partyId',
        'doc_type': 'TEST',
        'doc_id': partyId,
        'alayh_amount': 20,
        'lah_amount': 0,
      },
    ];
  }
}

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    for (final type in ['CUSTOMER', 'SUPPLIER']) {
      testWidgets('opens $type details from collapsed card at $size', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final session = _Session()
          ..parties = [
            const PartyModel(
              id: 1,
              partyType: 'CUSTOMER',
              nameAr: 'عميل الاختبار',
            ),
            const PartyModel(
              id: 2,
              partyType: 'SUPPLIER',
              nameAr: 'مورد الاختبار',
            ),
          ];
        addTearDown(session.dispose);
        await tester.pumpWidget(
          ChangeNotifierProvider<SessionAndErpProvider>.value(
            value: session,
            child: MaterialApp(
              theme: EnterpriseDarkTheme.data,
              home: const Directionality(
                textDirection: TextDirection.rtl,
                child: S19S20S21PartiesAndVouchersScreen(),
              ),
            ),
          ),
        );
        if (type == 'SUPPLIER') {
          await tester.tap(find.text('الموردون / المذاخر'));
          await tester.pumpAndSettle();
        }
        final id = type == 'CUSTOMER' ? 1 : 2;
        await tester.tap(find.byKey(ValueKey('party-details-$id')));
        await tester.pumpAndSettle();
        expect(find.byType(PartyDetailsScreen), findsOneWidget);
        expect(session.requested, [id]);
        await tester.scrollUntilVisible(
          find.text('حركة خاصة $id'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('حركة خاصة $id'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(PartyDetailsScreen), findsNothing);
        expect(find.byKey(ValueKey('party-details-$id')), findsOneWidget);
      });
    }
  }

  testWidgets('failed ledger can be retried without losing party details', (
    tester,
  ) async {
    final session = _Session()..fail = true;
    addTearDown(session.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<SessionAndErpProvider>.value(
        value: session,
        child: MaterialApp(
          theme: EnterpriseDarkTheme.data,
          home: PartyDetailsScreen(
            party: const PartyModel(
              id: 7,
              partyType: 'SUPPLIER',
              nameAr: 'مورد',
            ),
            onPrint: (_) async {},
            onVoucher: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('إعادة المحاولة'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    session.fail = false;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('حركة خاصة 7'), findsOneWidget);
    expect(session.requested, [7, 7]);
    expect(tester.takeException(), isNull);
  });
}
