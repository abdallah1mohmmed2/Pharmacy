import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/session_and_erp_provider.dart';
import '../../core/theme/enterprise_dark_theme.dart';
import '../../core/widgets/shared_widgets.dart';

class S02ExecutiveDashboardScreen extends StatelessWidget{
 const S02ExecutiveDashboardScreen({super.key});
 @override Widget build(BuildContext context){
  final p=context.watch<SessionAndErpProvider>();final d=p.dashboard;
  final metrics=<({String title,String key,IconData icon,Color color})>[
   (title:'مبيعات اليوم',key:'sales',icon:Icons.point_of_sale,color:AppColors.primary),
   (title:'أرباح اليوم التقديرية',key:'profit',icon:Icons.trending_up,color:AppColors.success),
   (title:'فواتير اليوم',key:'invoiceCount',icon:Icons.receipt_long,color:AppColors.info),
   (title:'الأصناف المسجلة',key:'drugCount',icon:Icons.medication,color:AppColors.primary),
   (title:'أصناف وصلت حد النقص',key:'lowStock',icon:Icons.warning_amber,color:AppColors.warning),
   (title:'إجمالي المتبقي عليهم',key:'totalAlayh',icon:Icons.call_received,color:AppColors.danger),
   (title:'إجمالي المتبقي لنا',key:'totalLah',icon:Icons.call_made,color:AppColors.success),
   (title:'أرصدة الصناديق والمحافظ',key:'cashTotal',icon:Icons.account_balance_wallet,color:AppColors.info),
  ];
  return RefreshIndicator(onRefresh:p.refresh,child:ListView(padding:const EdgeInsets.all(16),children:[
   Row(children:[const Expanded(child:Text('المؤشرات التنفيذية',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold))),IconButton(onPressed:p.refresh,icon:const Icon(Icons.refresh))]),
   if(p.lastError!=null)ClinicalAlertBanner(message:p.lastError!,level:ClinicalAlertLevel.block),
   GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),itemCount:metrics.length,gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:MediaQuery.sizeOf(context).width>1000?4:MediaQuery.sizeOf(context).width>600?2:2,childAspectRatio:1.65,crossAxisSpacing:10,mainAxisSpacing:10),itemBuilder:(context,i){final m=metrics[i];final value=d[m.key]??0;return Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Icon(m.icon,color:m.color),Text(value.toStringAsFixed(m.key=='invoiceCount'||m.key=='drugCount'||m.key=='lowStock'?0:2),style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),Text(m.title,style:const TextStyle(color:Colors.white70))])));}),
   const SizedBox(height:18),const Text('الصناديق والمحافظ',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
   ...p.cashAccounts.map((a)=>Card(child:ListTile(leading:const Icon(Icons.account_balance_wallet_outlined,color:AppColors.info),title:Text(a.nameAr),subtitle:Text(a.accountKind),trailing:Text(MoneyFormatter.format(a.currentBalance))))),
   const SizedBox(height:12),const Text('تنبيهات المخزون',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
   if(p.lowStockDrugs.isEmpty)const Text('لا توجد أصناف وصلت حد النقص.') else ...p.lowStockDrugs.map((drug)=>Card(child:ListTile(leading:const Icon(Icons.warning_amber,color:AppColors.warning),title:Text(drug['trade_name_ar'] as String),subtitle:Text('المخزون: '+drug['stock_total_units'].toString()+' • حد الطلب: '+drug['min_stock_units'].toString())))),
   const SizedBox(height:16),const Text('آخر الفواتير',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
   ...p.recentInvoices.map((invoice)=>Card(child:ListTile(leading:const Icon(Icons.receipt_long),title:Text(invoice['invoice_no'] as String),subtitle:Text(invoice['invoice_date'] as String),trailing:Text(MoneyFormatter.format((invoice['net_total'] as num).toDouble()))))),
   const SizedBox(height:12),const Text('آخر السندات',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
   ...p.recentVouchers.map((voucher)=>Card(child:ListTile(leading:const Icon(Icons.request_quote_outlined),title:Text(voucher['voucher_no'] as String),subtitle:Text(voucher['voucher_type'] as String),trailing:Text(MoneyFormatter.format((voucher['amount'] as num).toDouble()))))),
  ]));
 }
}
