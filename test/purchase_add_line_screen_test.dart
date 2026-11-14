import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/database_helper.dart';
import 'package:global_enterprise_pharmacy_erp/providers/pos_and_drugs_provider.dart';
import 'package:global_enterprise_pharmacy_erp/providers/session_and_erp_provider.dart';
import 'package:global_enterprise_pharmacy_erp/providers/inventory_and_purchase_provider.dart';
import 'package:global_enterprise_pharmacy_erp/screens/purchases/s16_purchase_invoice_bonus_screen.dart';
import 'package:global_enterprise_pharmacy_erp/core/theme/enterprise_dark_theme.dart';
import 'treasury_integrity_integration_test.dart' show openSaleDatabase;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  late Database db;
  late InventoryAndPurchaseProvider inventory;
  late SessionAndErpProvider session;
  late PosAndDrugsProvider pos;
  final year = DateTime.now().year + 2;
  String arabic(String value) => value
      .split('')
      .map((c) => '0123456789'.contains(c) ? '٠١٢٣٤٥٦٧٨٩'[int.parse(c)] : c)
      .join();

  Future<void> drain(WidgetTester tester, bool Function() done) async {
    for (var n = 0; n < 500 && !done(); n++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(done(), isTrue);
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      final scroll = find.byType(Scrollable).last;
      await tester.drag(scroll, const Offset(0, 1200));
      await tester.pumpAndSettle();
      for (var n = 0; n < 20 && finder.evaluate().isEmpty; n++) {
        await tester.drag(scroll, const Offset(0, -200));
        await tester.pumpAndSettle();
      }
    }
    await tester.ensureVisible(finder);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> text(WidgetTester tester, String label, String value) async {
    final field = find.widgetWithText(TextField, label);
    await reveal(tester, field);
    await tester.enterText(field, value);
    await tester.pump();
  }

  Future<void> mount(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      db = await openSaleDatabase(inMemoryDatabasePath);
      await db.insert('parties', {
        'uuid': 'add-line-supplier',
        'branch_id': 1,
        'created_at': '2026-11-14',
        'updated_at': '2026-11-14',
        'party_type': 'SUPPLIER',
        'code': 'ADD-SUP',
        'name_ar': 'مورد اختبار البند'
      });
      await db.insert('drugs', {
        'uuid': 'add-line-drug',
        'branch_id': 1,
        'created_at': '2026-11-14',
        'updated_at': '2026-11-14',
        'internal_code': 'ADD-DRUG',
        'trade_name_ar': 'دواء اختبار البند',
        'units_per_pack': 20,
        'strips_per_pack': 2,
        'units_per_strip': 10,
        'stock_total_units': 0
      });
      final helper = DatabaseHelper.forTesting(db);
      session = SessionAndErpProvider(database: helper)
        ..currentUser = {'id': 1, 'role_code': 'OWNER'};
      inventory = InventoryAndPurchaseProvider(database: helper);
      pos = PosAndDrugsProvider(database: helper);
      await session.refresh();
      await inventory.loadAll();
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      pos.dispose();
      inventory.dispose();
      session.dispose();
      await db.close();
    });
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionAndErpProvider>.value(value: session),
          ChangeNotifierProvider<InventoryAndPurchaseProvider>.value(
              value: inventory),
          ChangeNotifierProvider<PosAndDrugsProvider>.value(value: pos),
        ],
        child: MaterialApp(
            theme: EnterpriseDarkTheme.data,
            builder: (context, child) =>
                Directionality(textDirection: TextDirection.rtl, child: child!),
            home: const Scaffold(body: S16PurchaseInvoiceBonusScreen()))));
    await tester.pumpAndSettle();
    await tap(tester, find.text('إضافة بند شراء'));
    await tap(tester, find.text('ابحث واختر الدواء *'));
    await tester.enterText(
        find.widgetWithText(TextField, 'الاسم أو المادة الفعالة أو الباركود'),
        'اختبار');
    await tester.pump(const Duration(milliseconds: 300));
    await drain(
        tester, () => find.text('دواء اختبار البند').evaluate().isNotEmpty);
    await tap(tester, find.text('دواء اختبار البند'));
    await text(tester, 'رقم التشغيلة *', 'BATCH-AR');
    await text(tester, 'تاريخ الصلاحية *', '٣١/١٢/${arabic('$year')}');
    await text(tester, 'باكتات مدفوعة *', '٢');
    await text(tester, 'باكتات بونص', '١');
    await text(tester, 'سعر الباكت *', '١٬٢٥٠٫٥٠');
    await text(tester, 'خصم البند %', '٥');
    await text(tester, 'سعر البيع المقترح للباكت', '١٥٠٠');
    await tester.testTextInput.hide();
    await tester.pumpAndSettle();
  }

  Future<void> chooseWarehouse(WidgetTester tester) async {
    await tap(
        tester, find.byKey(const ValueKey('purchase-line-warehouse-null')));
    await tap(tester, find.text('صالة الصيدلية').last);
  }

  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets(
        'add purchase item with Arabic inputs and visible missing-warehouse error at $size',
        (tester) async {
      await mount(tester, size);
      await tap(tester, find.text('إضافة البند إلى الفاتورة'));
      expect(find.text('اختر مستودع البند أولاً.'), findsOneWidget);
      expect(find.byType(AddPurchaseItemSheet), findsOneWidget);
      await chooseWarehouse(tester);
      await tap(tester, find.text('إضافة البند إلى الفاتورة'));
      expect(find.byType(AddPurchaseItemSheet), findsNothing);
      await reveal(tester, find.text('دواء اختبار البند • BATCH-AR'));
      expect(find.text('دواء اختبار البند • BATCH-AR'), findsOneWidget);
      await text(tester, 'رقم فاتورة النظام', 'AR-ADD-LINE');
      await tap(tester,
          find.widgetWithText(DropdownButtonFormField<int>, 'المورد *'));
      await tap(tester, find.text('مورد اختبار البند').last);
      await reveal(tester, find.text('ترحيل فاتورة المشتريات'));
      await tester.tap(find.text('ترحيل فاتورة المشتريات'));
      await tester.pump();
      await drain(
          tester,
          () =>
              !inventory.loading &&
              !session.loading &&
              find
                  .text('تم ترحيل فاتورة المشتريات رقم 1')
                  .evaluate()
                  .isNotEmpty);
      final rows =
          await tester.runAsync(() => db.query('purchase_invoice_items'));
      expect(rows, hasLength(1));
      expect(rows!.single['expiry_date'], '$year-12-31');
      expect(rows.single['qty_packs_paid'], 2);
      expect(rows.single['bonus_packs'], 1);
      expect(rows.single['pack_price'], 1250.5);
      expect(rows.single['line_discount_pct'], 5);
      final batches = await tester.runAsync(() => db.query('batches_fefo'));
      expect(batches!.single['total_units'], 60);
      await tester.runAsync(() => pos.loadSaleWarehouses());
      expect(pos.saleError, isNull);
      expect(pos.saleDrugs.single.tradeNameAr, 'دواء اختبار البند');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'invalid expiry and fractional pack counts explain exact fields without losing input',
      (tester) async {
    await mount(tester, const Size(390, 844));
    await chooseWarehouse(tester);
    await text(tester, 'تاريخ الصلاحية *', '٣١/٠٢/${arabic('$year')}');
    await tap(tester, find.text('إضافة البند إلى الفاتورة'));
    expect(find.textContaining('تاريخ الصلاحية غير صحيح'), findsOneWidget);
    await text(tester, 'تاريخ الصلاحية *', '١٢/${arabic('$year')}');
    await text(tester, 'باكتات مدفوعة *', '٢٫٥');
    await tap(tester, find.text('إضافة البند إلى الفاتورة'));
    expect(find.textContaining('أدخل عدد الباكتات المدفوعة'), findsOneWidget);
    await text(tester, 'باكتات مدفوعة *', '٢');
    await tap(tester, find.text('إضافة البند إلى الفاتورة'));
    expect(find.byType(AddPurchaseItemSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
