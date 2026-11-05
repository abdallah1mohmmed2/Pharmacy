import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/session_and_erp_provider.dart';
import '../providers/pos_and_drugs_provider.dart';
import '../providers/inventory_and_purchase_provider.dart';
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

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override State<AppShell> createState()=>_AppShellState();
}
class _AppShellState extends State<AppShell>{
  int index=0;
  final pages=const [S02ExecutiveDashboardScreen(),S03SmartPosScreen(),S08S09DrugEncyclopediaScreen(),S19S20S21PartiesAndVouchersScreen(),S11InventoryBatchesShelvesScreen(),S12FefoExpiryRadarScreen(),S13StocktakingScreen(),S14DisposalsScreen(),S15StockTransfersScreen(),S16PurchaseInvoiceBonusScreen(),S17S18ReturnsAndShortagesScreen(),S06PrescriptionInsuranceScreen(),S07SalesReturnsScreen(),S08ClinicalAuditScreen()];
  final titles=const ['لوحة التحكم التنفيذية','الكاشير الذكي','الموسوعة الدوائية','حسابات الأطراف والسندات','المخزون والتشغيلات','رادار الصلاحية','الجرد المخزني','الإعدام والإتلاف','التحويلات المخزنية','فواتير المشتريات والبونص','المرتجعات والنواقص','الوصفات والتأمين','مرتجع المبيعات','سجل الرقابة السريرية'];
  @override Widget build(BuildContext context){
    final wide=MediaQuery.sizeOf(context).width>=900;
    final session=context.watch<SessionAndErpProvider>();
    if(session.currentUser==null)return const _LoginScreen();
    return Scaffold(
      drawer:wide?null:Drawer(child:ListView(children:[const DrawerHeader(child:Text('Global Pharmacy ERP',style:TextStyle(fontSize:20))),for(var i=0;i<titles.length;i++)ListTile(selected:index==i,title:Text(titles[i]),onTap:(){setState(()=>index=i);Navigator.pop(context);})])),
      appBar:AppBar(title:Text(titles[index]),actions:[
        Padding(padding:const EdgeInsets.symmetric(horizontal:8),child:Center(child:Text('الصيدلية • الفرع الرئيسي • '+(session.currentUser?['full_name'] as String? ?? '')))),
        IconButton(tooltip:'تحديث',onPressed:session.refresh,icon:const Icon(Icons.refresh)),
        IconButton(tooltip:'تسجيل الخروج',onPressed:session.logout,icon:const Icon(Icons.logout)),
      ]),
      body:Row(children:[
        if(wide)SingleChildScrollView(child:NavigationRail(selectedIndex:index,onDestinationSelected:(v)=>setState(()=>index=v),labelType:NavigationRailLabelType.all,
          destinations:const [
            NavigationRailDestination(icon:Icon(Icons.dashboard_outlined),selectedIcon:Icon(Icons.dashboard),label:Text('الرئيسية')),
            NavigationRailDestination(icon:Icon(Icons.point_of_sale_outlined),selectedIcon:Icon(Icons.point_of_sale),label:Text('الكاشير')),
            NavigationRailDestination(icon:Icon(Icons.medication_outlined),selectedIcon:Icon(Icons.medication),label:Text('الأدوية')),
            NavigationRailDestination(icon:Icon(Icons.account_balance_wallet_outlined),selectedIcon:Icon(Icons.account_balance_wallet),label:Text('الحسابات')),
            NavigationRailDestination(icon:Icon(Icons.inventory_2_outlined),label:Text('التشغيلات')),
            NavigationRailDestination(icon:Icon(Icons.radar),label:Text('رادار الصلاحية')),
            NavigationRailDestination(icon:Icon(Icons.fact_check_outlined),label:Text('الجرد')),
            NavigationRailDestination(icon:Icon(Icons.delete_outline),label:Text('الإعدام')),
            NavigationRailDestination(icon:Icon(Icons.swap_horiz),label:Text('التحويلات')),
            NavigationRailDestination(icon:Icon(Icons.shopping_cart_outlined),label:Text('المشتريات')),
            NavigationRailDestination(icon:Icon(Icons.assignment_return_outlined),label:Text('المرتجعات والنواقص')),
            NavigationRailDestination(icon:Icon(Icons.receipt_long_outlined),label:Text('الوصفات والتأمين')),
            NavigationRailDestination(icon:Icon(Icons.assignment_return),label:Text('مرتجع المبيعات')),
            NavigationRailDestination(icon:Icon(Icons.health_and_safety_outlined),label:Text('الرقابة السريرية')),
          ])),
        Expanded(child:IndexedStack(index:index,children:pages)),
      ]),
      bottomNavigationBar:wide?null:NavigationBar(selectedIndex:index.clamp(0,3).toInt(),onDestinationSelected:(v)=>setState(()=>index=v),destinations:const [
        NavigationDestination(icon:Icon(Icons.dashboard_outlined),label:'الرئيسية'),NavigationDestination(icon:Icon(Icons.point_of_sale_outlined),label:'الكاشير'),
        NavigationDestination(icon:Icon(Icons.medication_outlined),label:'الأدوية'),NavigationDestination(icon:Icon(Icons.account_balance_wallet_outlined),label:'الحسابات'),
      ]),
    );
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
    setState(()=>busy=true);
    final ok=await session.login(user.text,pass.text);
    if(!mounted)return;
    setState((){busy=false;error=ok?null:'بيانات الدخول غير صحيحة';});
    if(ok){
      final activeBranch=session.branchId;
      await pos.setBranchId(activeBranch);
      if(!mounted)return;
      await inventory.setBranch(activeBranch);
    }
  }
}
