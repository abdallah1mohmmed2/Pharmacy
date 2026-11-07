import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../providers/session_and_erp_provider.dart';
import '../providers/pos_and_drugs_provider.dart';
import '../providers/inventory_and_purchase_provider.dart';
import '../providers/clinical_and_rx_provider.dart';
import '../providers/treasury_hr_partner_provider.dart';
import '../providers/settings_and_system_provider.dart';
import '../core/constants/setting_keys.dart';
import '../core/theme/enterprise_dark_theme.dart';
import '../core/widgets/shared_widgets.dart';
import 'dashboard/s02_executive_dashboard_screen.dart';
import 'pos/s03_smart_pos_screen.dart';
import 'drugs/s08_s09_drug_encyclopedia_screen.dart';
import 'accounts/s19_s20_s21_parties_and_vouchers_screen.dart';
import 'inventory/s11_inventory_batches_shelves_screen.dart';
import 'inventory/s12_fefo_expiry_radar_screen.dart';
import 'inventory/s13_stocktaking_screen.dart';
import 'inventory/s14_disposals_screen.dart';
import 'inventory/s15_stock_transfers_screen.dart';
import 'purchases/s16_purchase_invoice_bonus_screen.dart';
import 'purchases/s17_s18_returns_and_shortages_screen.dart';
import 'pos/s06_prescription_insurance_screen.dart';
import 'pos/s07_sales_returns_screen.dart';
import 'clinical/s08_clinical_audit_screen.dart';
import 'finance/s22_treasury_wallets_screen.dart';
import 'finance/s23_shift_close_handover_screen.dart';
import 'finance/s24_operating_expenses_screen.dart';
import 'hr_partners/s25_employees_shifts_payroll_screen.dart';
import 'hr_partners/s26_owner_partners_profit_screen.dart';
import 'reports/s27_reports_center_pdf_screen.dart';
import 'drugs/s10_drug_import_export_screen.dart';
import 'settings/s28_system_settings_backup_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int index = 0;
  bool _closingBackupStarted = false;

  static const _pageIcons = <IconData>[
    Icons.dashboard_outlined,
    Icons.point_of_sale,
    Icons.medication_outlined,
    Icons.account_balance_wallet_outlined,
    Icons.inventory_2_outlined,
    Icons.radar,
    Icons.fact_check_outlined,
    Icons.delete_outline,
    Icons.swap_horiz,
    Icons.shopping_cart_outlined,
    Icons.assignment_return_outlined,
    Icons.receipt_long_outlined,
    Icons.assignment_returned_outlined,
    Icons.health_and_safety_outlined,
    Icons.account_balance_outlined,
    Icons.lock_clock_outlined,
    Icons.receipt_outlined,
    Icons.groups_outlined,
    Icons.pie_chart_outline,
    Icons.assessment_outlined,
    Icons.import_export,
    Icons.settings_outlined,
  ];

  final pages = const <Widget>[
    S02ExecutiveDashboardScreen(),
    S03SmartPosScreen(),
    S08S09DrugEncyclopediaScreen(),
    S19S20S21PartiesAndVouchersScreen(),
    S11InventoryBatchesShelvesScreen(),
    S12FefoExpiryRadarScreen(),
    S13StocktakingScreen(),
    S14DisposalsScreen(),
    S15StockTransfersScreen(),
    S16PurchaseInvoiceBonusScreen(),
    S17S18ReturnsAndShortagesScreen(),
    S06PrescriptionInsuranceScreen(),
    S07SalesReturnsScreen(),
    S08ClinicalAuditScreen(),
    S22TreasuryWalletsScreen(),
    S23ShiftCloseHandoverScreen(),
    S24OperatingExpensesScreen(),
    S25EmployeesShiftsPayrollScreen(),
    S26OwnerPartnersProfitScreen(),
    S27ReportsCenterPdfScreen(),
    S10DrugImportExportScreen(),
    S28SystemSettingsBackupScreen(),
  ];

  final titles = const <String>[
    'لوحة التحكم التنفيذية',
    'الكاشير الذكي',
    'الموسوعة الدوائية',
    'حسابات الأطراف والسندات',
    'المخزون والتشغيلات',
    'رادار الصلاحية',
    'الجرد المخزني',
    'الإعدام والإتلاف',
    'التحويلات المخزنية',
    'فواتير المشتريات والبونص',
    'المرتجعات والنواقص',
    'الوصفات والتأمين',
    'مرتجع المبيعات',
    'سجل الرقابة السريرية',
    'الخزينة والمحافظ',
    'إغلاق وتسليم الوردية',
    'المصروفات التشغيلية',
    'الموظفون والرواتب',
    'المالك والشركاء',
    'مركز التقارير (55 تقريراً)',
    'استيراد وتصدير الأدوية',
    'إعدادات النظام والنسخ الاحتياطي',
  ];

  static const _permissions = <String>[
    'dashboard.view',
    'pos.sell',
    'drugs.view',
    'finance.view',
    'inventory.view',
    'inventory.view',
    'inventory.stocktake',
    'inventory.adjust',
    'inventory.adjust',
    'purchases.manage',
    'sales.returns',
    'pos.sell',
    'sales.returns',
    'clinical.override',
    'finance.view',
    'finance.manage',
    'finance.manage',
    'users.manage',
    'partners.manage',
    'reports.view',
    'drugs.import',
    'settings.view',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) &&
        !_closingBackupStarted) {
      _closingBackupStarted = true;
      final provider = context.read<SettingsAndSystemProvider>();
      if (!provider.loading) {
        try {
          final config =
              provider.settings.getJson(SettingKey.autoLocalOnClose);
          if (config['enabled'] == true) {
            provider.createBackup(
              triggerType: 'ON_APP_CLOSE',
              userId: context.read<SessionAndErpProvider>().currentUser?['id']
                  as int?,
            );
          }
        } catch (_) {
          // Backup errors are exposed by the backup service when opened.
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 700;
    final session = context.watch<SessionAndErpProvider>();
    final system = context.watch<SettingsAndSystemProvider>();

    if (session.currentUser == null) return const _LoginScreen();

    final role = session.currentUser?['role_code'] as String? ?? '';
    final visibleIndexes = List<int>.generate(pages.length, (i) => i)
        .where(
          (i) =>
              role == 'OWNER' ||
              system.roleRows.any(
                (row) =>
                    row['role_code'] == role &&
                    row['permission_code'] == _permissions[i] &&
                    (row['is_allowed'] as num) == 1,
              ),
        )
        .toList();

    if (visibleIndexes.isEmpty) visibleIndexes.add(0);
    if (!visibleIndexes.contains(index)) index = visibleIndexes.first;

    final primaryIndexes = <int>[
      for (final i in const [0, 1, 2, 3])
        if (visibleIndexes.contains(i)) i,
    ];
    if (primaryIndexes.isEmpty) primaryIndexes.add(visibleIndexes.first);

    final selectedMobileIndex = primaryIndexes.indexOf(index);
    final moreSelected = selectedMobileIndex < 0;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (HardwareKeyboard.instance.isControlPressed &&
            key == LogicalKeyboardKey.keyK) {
          _showQuickSearch(visibleIndexes);
          return KeyEventResult.handled;
        }
        const functionKeys = <LogicalKeyboardKey>[
          LogicalKeyboardKey.f1,
          LogicalKeyboardKey.f2,
          LogicalKeyboardKey.f3,
          LogicalKeyboardKey.f4,
          LogicalKeyboardKey.f5,
          LogicalKeyboardKey.f6,
          LogicalKeyboardKey.f7,
          LogicalKeyboardKey.f8,
          LogicalKeyboardKey.f9,
          LogicalKeyboardKey.f10,
          LogicalKeyboardKey.f11,
          LogicalKeyboardKey.f12,
        ];
        final target = functionKeys.indexOf(key);
        if (target >= 0) {
          if (target < visibleIndexes.length) {
            setState(() => index = visibleIndexes[target]);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(titles[index], maxLines: 1,
              overflow: TextOverflow.ellipsis),
          actions: [
            if (!wide)
              IconButton(
                tooltip: 'بقية الشاشات',
                onPressed: () => _showMoreScreens(visibleIndexes),
                icon: const Icon(Icons.apps_outlined),
              ),
            if (wide)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Text(
                    'الصيدلية • الفرع الرئيسي • '
                    '${session.currentUser?['full_name'] as String? ?? ''}',
                  ),
                ),
              ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: session.refresh,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'تسجيل الخروج',
              onPressed: session.logout,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: Row(
          children: [
            if (wide)
              SingleChildScrollView(
                child: NavigationRail(
                  selectedIndex: visibleIndexes.indexOf(index),
                  onDestinationSelected: (value) =>
                      setState(() => index = visibleIndexes[value]),
                  labelType: NavigationRailLabelType.all,
                  destinations: visibleIndexes
                      .map(
                        (i) => NavigationRailDestination(
                          icon: Icon(_pageIcons[i]),
                          selectedIcon: Icon(_pageIcons[i]),
                          label: Text(titles[i]),
                        ),
                      )
                      .toList(),
                ),
              ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusScope.of(context).unfocus(),
                child: IndexedStack(index: index, children: pages),
              ),
            ),
          ],
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex:
                    moreSelected ? primaryIndexes.length : selectedMobileIndex,
                onDestinationSelected: (value) {
                  if (value == primaryIndexes.length) {
                    _showMoreScreens(visibleIndexes);
                  } else {
                    FocusScope.of(context).unfocus();
                    setState(() => index = primaryIndexes[value]);
                  }
                },
                destinations: [
                  for (final i in primaryIndexes)
                    NavigationDestination(
                      icon: Icon(_pageIcons[i]),
                      selectedIcon: Icon(_pageIcons[i]),
                      label: titles[i],
                    ),
                  const NavigationDestination(
                    icon: Icon(Icons.apps_outlined),
                    selectedIcon: Icon(Icons.apps),
                    label: 'المزيد',
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _showMoreScreens(List<int> visibleIndexes) async {
    final extra = visibleIndexes.where((i) => i >= 4).toList();
    await KeyboardSafeModalSheet.show<void>(
      context: context,
      heightFactor: .88,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('جميع أقسام النظام',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: extra.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:
                  MediaQuery.sizeOf(sheetContext).width >= 700 ? 4 : 2,
              childAspectRatio: 2.5,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (context, position) {
              final pageIndex = extra[position];
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    FocusScope.of(context).unfocus();
                    if (mounted) setState(() => index = pageIndex);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Icon(_pageIcons[pageIndex],
                            color: AppColors.primary),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(titles[pageIndex],
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showQuickSearch(List<int> visibleIndexes) async {
    final controller = TextEditingController();
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('البحث السريع'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 360,
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration:
                  const InputDecoration(hintText: 'اكتب اسم الشاشة'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final query = controller.text.trim();
              final matches = visibleIndexes
                  .where((i) => titles[i].contains(query))
                  .toList();
              Navigator.pop(
                dialogContext,
                matches.isEmpty ? null : matches.first,
              );
            },
            child: const Text('فتح'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (selected != null && mounted) {
      FocusScope.of(context).unfocus();
      setState(() => index = selected);
    }
  }
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen();

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final user = TextEditingController(text: 'admin');
  final pass = TextEditingController(text: '123456');
  bool busy = false;
  String? error;

  @override
  void dispose() {
    user.dispose();
    pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.local_pharmacy,
                          size: 58, color: AppColors.primary),
                      const SizedBox(height: 14),
                      const Text(
                        'Global Pharmacy ERP',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: user,
                        decoration:
                            const InputDecoration(labelText: 'اسم المستخدم'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: pass,
                        obscureText: true,
                        decoration:
                            const InputDecoration(labelText: 'كلمة المرور'),
                        onSubmitted: (_) => _login(),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(error!,
                              style:
                                  const TextStyle(color: Colors.redAccent)),
                        ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: busy ? null : _login,
                          child: Text(
                              busy ? 'جارٍ الدخول' : 'تسجيل الدخول'),
                        ),
                      ),
                      const Text(
                        'حساب التأسيس: admin / 123456',
                        style:
                            TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> _login() async {
    final session = context.read<SessionAndErpProvider>();
    final pos = context.read<PosAndDrugsProvider>();
    final inventory = context.read<InventoryAndPurchaseProvider>();
    final clinical = context.read<ClinicalAndRxProvider>();
    final finance = context.read<TreasuryHrPartnerProvider>();
    setState(() => busy = true);
    final ok = await session.login(user.text, pass.text);
    if (!mounted) return;
    setState(() {
      busy = false;
      error = ok ? null : 'بيانات الدخول غير صحيحة';
    });
    if (ok) {
      final activeBranch = session.branchId;
      await pos.setBranchId(activeBranch);
      if (!mounted) return;
      await inventory.setBranch(activeBranch);
      if (!mounted) return;
      await clinical.setBranch(activeBranch);
      if (!mounted) return;
      await finance.loadAll(
        branchId: activeBranch,
        userId: session.currentUser!['id'] as int,
      );
    }
  }
}
