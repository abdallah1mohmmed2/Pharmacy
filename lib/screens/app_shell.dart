import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../providers/session_and_erp_provider.dart';
import '../providers/pos_and_drugs_provider.dart';
import '../providers/inventory_and_purchase_provider.dart';
import '../providers/treasury_hr_partner_provider.dart';
import '../providers/settings_and_system_provider.dart';
import '../core/constants/setting_keys.dart';
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
  @override State<AppShell> createState()=>_AppShellState();
}
class _AppShellState extends State<AppShell> with WidgetsBindingObserver{
  int index=0; bool _closingBackupStarted=false;
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);}
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if((state==AppLifecycleState.paused||state==AppLifecycleState.detached)&&!_closingBackupStarted){
      _closingBackupStarted=true;
      final provider=context.read<SettingsAndSystemProvider>();
      if(!provider.loading){try{final config=provider.settings.getJson(SettingKey.autoLocalOnClose);if(config['enabled']==true){provider.createBackup(triggerType:'ON_APP_CLOSE',userId:context.read<SessionAndErpProvider>().currentUser?['id'] as int?);}}catch(_){}}
    }
  }
  static const _pageIcons=[Icons.dashboard,Icons.point_of_sale,Icons.medication,Icons.account_balance_wallet,Icons.inventory_2,Icons.radar,Icons.fact_check,Icons.delete,Icons.swap_horiz,Icons.shopping_cart,Icons.assignment_return,Icons.receipt_long,Icons.assignment_returned,Icons.health_and_safety,Icons.account_balance,Icons.lock_clock,Icons.receipt,Icons.groups,Icons.pie_chart,Icons.assessment,Icons.import_export,Icons.settings];
  final pages=const [S02ExecutiveDashboardScreen(),S03SmartPosScreen(),S08S09DrugEncyclopediaScreen(),S19S20S21PartiesAndVouchersScreen(),S11InventoryBatchesShelvesScreen(),S12FefoExpiryRadarScreen(),S13StocktakingScreen(),S14DisposalsScreen(),S15StockTransfersScreen(),S16PurchaseInvoiceBonusScreen(),S17S18ReturnsAndShortagesScreen(),S06PrescriptionInsuranceScreen(),S07SalesReturnsScreen(),S08ClinicalAuditScreen(),S22TreasuryWalletsScreen(),S23ShiftCloseHandoverScreen(),S24OperatingExpensesScreen(),S25EmployeesShiftsPayrollScreen(),S26OwnerPartnersProfitScreen(),S27ReportsCenterPdfScreen(),S10DrugImportExportScreen(),S28SystemSettingsBackupScreen()];
  final titles=const ['لوحة التحكم التنفيذية','الكاشير الذكي','الموسوعة الدوائية','حسابات الأطراف والسندات','المخزون والتشغيلات','رادار الصلاحية','الجرد المخزني','الإعدام والإتلاف','التحويلات المخزنية','فواتير المشتريات والبونص','المرتجعات والنواقص','الوصفات والتأمين','مرتجع المبيعات','سجل الرقابة السريرية','الخزينة والمحافظ','إغلاق وتسليم الوردية','المصروفات التشغيلية','الموظفون والرواتب','المالك والشركاء','مركز التقارير (55 تقريراً)','استيراد وتصدير الأدوية','إعدادات النظام والنسخ الاحتياطي'];
  @override Widget build(BuildContext context){
    final wide=MediaQuery.sizeOf(context).width>=900;
    final session=context.watch<SessionAndErpProvider>();
    final system=context.watch<SettingsAndSystemProvider>();
    const permissions=['dashboard.view','pos.sell','drugs.view','finance.view','inventory.view','inventory.view','inventory.stocktake','inventory.adjust','inventory.adjust','purchases.manage','sales.returns','pos.sell','sales.returns','clinical.override','finance.view','finance.manage','finance.manage','users.manage','partners.manage','reports.view','drugs.import','settings.view'];
    final role=session.currentUser?['role_code'] as String? ?? '';
    final visibleIndexes=List.generate(pages.length,(i)=>i).where((i)=>role=='OWNER'||system.roleRows.any((r)=>r['role_code']==role&&r['permission_code']==permissions[i]&&(r['is_allowed'] as num)==1)).toList();
    if(visibleIndexes.isEmpty)visibleIndexes.add(0);
    final mobileIndexes=visibleIndexes.where((i)=>i<4).toList();
    if(mobileIndexes.isEmpty)mobileIndexes.add(visibleIndexes.first);
    if(session.currentUser==null)return const _LoginScreen();
    return Focus(autofocus:true,onKeyEvent:(node,event){
      if(event is! KeyDownEvent)return KeyEventResult.ignored;
      final key=event.logicalKey;
      if(HardwareKeyboard.instance.isControlPressed&&key==LogicalKeyboardKey.keyK){_showQuickSearch();return KeyEventResult.handled;}
      final functionKeys=[LogicalKeyboardKey.f1,LogicalKeyboardKey.f2,LogicalKeyboardKey.f3,LogicalKeyboardKey.f4,LogicalKeyboardKey.f5,LogicalKeyboardKey.f6,LogicalKeyboardKey.f7,LogicalKeyboardKey.f8,LogicalKeyboardKey.f9,LogicalKeyboardKey.f10,LogicalKeyboardKey.f11,LogicalKeyboardKey.f12];
      final target=functionKeys.indexOf(key);if(target>=0){if(target<visibleIndexes.length)setState(()=>index=visibleIndexes[target]);return KeyEventResult.handled;}
      return KeyEventResult.ignored;
    },child:Scaffold(
      drawer:wide?null:Drawer(child:ListView(children:[const DrawerHeader(child:Text('Global Pharmacy ERP',style:TextStyle(fontSize:20))),for(final i in visibleIndexes)ListTile(selected:index==i,title:Text(titles[i]),onTap:(){setState(()=>index=i);Navigator.pop(context);})])),
      appBar:AppBar(title:Text(titles[index]),actions:[
        Padding(padding:const EdgeInsets.symmetric(horizontal:8),child:Center(child:Text('الصيدلية • الفرع الرئيسي • '+(session.currentUser?['full_name'] as String? ?? '')))),
        IconButton(tooltip:'تحديث',onPressed:session.refresh,icon:const Icon(Icons.refresh)),
        IconButton(tooltip:'تسجيل الخروج',onPressed:session.logout,icon:const Icon(Icons.logout)),
      ]),
      body:Row(children:[
        if(wide)SingleChildScrollView(child:NavigationRail(selectedIndex:visibleIndexes.indexOf(index).clamp(0,visibleIndexes.length-1).toInt(),onDestinationSelected:(v)=>setState(()=>index=visibleIndexes[v]),labelType:NavigationRailLabelType.all,
          destinations:visibleIndexes.map((i)=>NavigationRailDestination(icon:Icon(_pageIcons[i]),selectedIcon:Icon(_pageIcons[i]),label:Text(titles[i]))).toList())),
        Expanded(child:IndexedStack(index:index,children:pages)),
      ]),
      bottomNavigationBar:wide?null:NavigationBar(selectedIndex:mobileIndexes.indexOf(index).clamp(0,mobileIndexes.length-1).toInt(),onDestinationSelected:(v)=>setState(()=>index=mobileIndexes[v]),destinations:mobileIndexes.map((i)=>NavigationDestination(icon:Icon(_pageIcons[i]),label:titles[i])).toList()),
    ));
  }
  Future<void> _showQuickSearch(List<int> visibleIndexes,List<String> titles) async {
    final controller=TextEditingController();
    final selected=await showDialog<int>(context:context,builder:(ctx)=>AlertDialog(title:const Text('البحث السريع'),content:SizedBox(width:360,child:TextField(controller:controller,autofocus:true,decoration:const InputDecoration(hintText:'اكتب اسم الشاشة'))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),FilledButton(onPressed:(){final q=controller.text.trim();final matches=visibleIndexes.where((index)=>titles[index].contains(q)).toList();Navigator.pop(ctx,matches.isEmpty?null:matches.first);},child:const Text('فتح'))]));
    if(selected!=null&&mounted)setState(()=>index=selected);
  }
}

class _LoginScreen extends StatefulWidget{const _LoginScreen();@override State<_LoginScreen> createState()=>_LoginScreenState();}
class _LoginScreenState extends State<_LoginScreen>{
  final user=TextEditingController(text:'admin');final pass=TextEditingController(text:'123456');bool busy=false;String? error;
  @override void dispose(){user.dispose();pass.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:380),child:Card(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
    const Icon(Icons.local_pharmacy,size:58,color:Color(0xFF4DB6AC)),const SizedBox(height:14),const Text('Global Pharmacy ERP',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
    const SizedBox(height:20),TextField(controller:user,decoration:const InputDecoration(labelText:'اسم المستخدم')),
    const SizedBox(height:10),TextField(controller:pass,obscureText:true,decoration:const InputDecoration(labelText:'كلمة المرور'),onSubmitted:(_)=>_login()),
    if(error!=null)Padding(padding:const EdgeInsets.all(8),child:Text(error!,style:const TextStyle(color:Colors.redAccent))),
    const SizedBox(height:14),SizedBox(width:double.infinity,child:FilledButton(onPressed:busy?null:_login,child:Text(busy?'جارٍ الدخول':'تسجيل الدخول'))),
    const Text('حساب التأسيس: admin / 123456',style:TextStyle(color:Colors.white54,fontSize:11)),
  ]))))));
  Future<void> _login()async{
    final session=context.read<SessionAndErpProvider>();
    final pos=context.read<PosAndDrugsProvider>();
    final inventory=context.read<InventoryAndPurchaseProvider>();
    final finance=context.read<TreasuryHrPartnerProvider>();
    setState(()=>busy=true);
    final ok=await session.login(user.text,pass.text);
    if(!mounted)return;
    setState((){busy=false;error=ok?null:'بيانات الدخول غير صحيحة';});
    if(ok){
      final activeBranch=session.branchId;
      await pos.setBranchId(activeBranch);
      if(!mounted)return;
      await inventory.setBranch(activeBranch);
      if(!mounted)return;
      await finance.loadAll(branchId:activeBranch,userId:session.currentUser!['id'] as int);
    }
  }
}
