import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/enterprise_dark_theme.dart';
import 'data/database/database_helper.dart';
import 'providers/session_and_erp_provider.dart';
import 'providers/pos_and_drugs_provider.dart';
import 'providers/inventory_and_purchase_provider.dart';
import 'providers/clinical_and_rx_provider.dart';
import 'providers/treasury_hr_partner_provider.dart';
import 'providers/settings_and_system_provider.dart';
import 'reports_pdf/registry/report_registry_and_provider.dart';
import 'screens/app_shell.dart';

Future<void> main() async {
 WidgetsFlutterBinding.ensureInitialized();
 await DatabaseHelper.instance.database;
 runApp(const PharmacyErpApplication());
}
class PharmacyErpApplication extends StatelessWidget {
 const PharmacyErpApplication({super.key});
 @override Widget build(BuildContext context)=>MultiProvider(
  providers:[
   ChangeNotifierProvider(create:(_)=>SessionAndErpProvider()..refresh()),
   ChangeNotifierProvider(create:(_)=>PosAndDrugsProvider()..loadDrugs()),
   ChangeNotifierProvider(create:(_)=>InventoryAndPurchaseProvider()..loadAll()),
   ChangeNotifierProvider(create:(_)=>ClinicalAndRxProvider()..loadAll()),
   ChangeNotifierProvider(create:(_)=>TreasuryHrPartnerProvider()),
   ChangeNotifierProvider(create:(_)=>ReportsCenterProvider()),
   ChangeNotifierProvider(create:(context)=>SettingsAndSystemProvider(verifyManagerPin:(pin)=>context.read<SessionAndErpProvider>().verifyManagerPin(pin))..initialize()),
  ],
  child:MaterialApp(
   title:'Global Enterprise Pharmacy ERP',
   debugShowCheckedModeBanner:false,
   theme:EnterpriseDarkTheme.data,
   builder:(context,child)=>Directionality(textDirection:TextDirection.rtl,child:child??const SizedBox.shrink()),
   home:const AppShell(),
  ),
 );
}
