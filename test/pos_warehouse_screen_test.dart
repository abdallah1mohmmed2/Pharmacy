import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/database_helper.dart';
import 'package:global_enterprise_pharmacy_erp/providers/pos_and_drugs_provider.dart';
import 'package:global_enterprise_pharmacy_erp/providers/session_and_erp_provider.dart';
import 'package:global_enterprise_pharmacy_erp/providers/inventory_and_purchase_provider.dart';
import 'package:global_enterprise_pharmacy_erp/providers/clinical_and_rx_provider.dart';
import 'package:global_enterprise_pharmacy_erp/screens/pos/s03_smart_pos_screen.dart';
import 'package:global_enterprise_pharmacy_erp/core/theme/enterprise_dark_theme.dart';
import 'treasury_integrity_integration_test.dart' show openSaleDatabase;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });
  for (final size in [const Size(390,844), const Size(1280,900)]) {
    testWidgets('cashier warehouse and scoped medicine list at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = await tester.runAsync(() => openSaleDatabase(inMemoryDatabasePath));
      addTearDown(() => db!.close());
      await tester.runAsync(() async {
        final floor = (await db!.query('warehouses', where: 'code=?', whereArgs: ['PHARM'])).single['id'];
        final id = await db.insert('drugs', {'uuid':'ui-stock-drug','branch_id':1,
          'created_at':'2026-11-14','updated_at':'2026-11-14','internal_code':'UI-STOCK',
          'trade_name_ar':'دواء الصيدلية المتاح','units_per_pack':1,'strips_per_pack':1,
          'units_per_strip':1,'stock_total_units':2,'sell_price_unit':100.0,'sell_price_pack':100.0});
        await db.insert('batches_fefo', {'uuid':'ui-stock-batch','drug_id':id,'warehouse_id':floor,
          'batch_no':'UI-B','expiry_date':'2030-12-31','sealed_packs':2,'loose_units':0,
          'total_units':2,'unit_cost':10.0,'pack_cost':10.0});
        await db.insert('drugs', {'uuid':'ui-directory-only','branch_id':1,
          'created_at':'2026-11-14','updated_at':'2026-11-14','internal_code':'UI-DIR',
          'trade_name_ar':'دواء الدليل غير المضاف'});
      });
      final helper = DatabaseHelper.forTesting(db!);
      final pos = PosAndDrugsProvider(database: helper);
      await tester.pumpWidget(MultiProvider(providers: [
        ChangeNotifierProvider<PosAndDrugsProvider>.value(value: pos),
        ChangeNotifierProvider(create: (_) => SessionAndErpProvider(database: helper)..currentUser = {'id':1,'role_code':'OWNER'}),
        ChangeNotifierProvider(create: (_) => InventoryAndPurchaseProvider(database: helper)),
        ChangeNotifierProvider(create: (_) => ClinicalAndRxProvider(helper: helper)),
      ], child: MaterialApp(theme: EnterpriseDarkTheme.data,
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const S03SmartPosScreen())));
      for (var n=0;n<500 && pos.saleLoading;n++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds:20)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(pos.saleLoading, isFalse);
      expect(pos.saleError, isNull);
      expect(find.text('مخزن البيع'), findsOneWidget);
      expect(find.text('صالة الصيدلية'), findsOneWidget);
      if (size.width < 700) {
        await tester.tap(find.byTooltip('اختيار دواء وإضافته'));
        await tester.pumpAndSettle();
      }
      expect(find.text('دواء الصيدلية المتاح'), findsOneWidget);
      expect(find.text('دواء الدليل غير المضاف'), findsNothing);
      if (size.width >= 700) {
        // Keep the cash-account selector empty and finish a real SQLite sale.
        await tester.tap(find.text('دواء الصيدلية المتاح'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('إتمام الفاتورة'));
        await tester.pump();
        for (var n=0;n<500;n++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds:20)));
          await tester.pump();
          if (pos.cart.isEmpty && !pos.checkoutPending && find.text('جارٍ حفظ الفاتورة...').evaluate().isEmpty) break;
        }
        final invoices = await tester.runAsync(() => db.query('sales_invoices'));
        final payments = await tester.runAsync(() => db.query('sales_payments'));
        final drawer = await tester.runAsync(() => db.query('cash_accounts', where: 'code=?', whereArgs: ['CASH-DRAWER']));
        expect(invoices, hasLength(1));
        expect(payments, hasLength(1));
        expect(payments!.single['cash_account_id'], drawer!.single['id']);
        expect(payments.single['amount'], 100);
        expect(pos.cart, isEmpty);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      pos.dispose();
    });
  }
}
