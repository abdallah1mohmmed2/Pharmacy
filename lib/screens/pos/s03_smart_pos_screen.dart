import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/pos_and_drugs_provider.dart';
import '../../providers/session_and_erp_provider.dart';
import '../../core/theme/enterprise_dark_theme.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/erp_models.dart';
import '../../providers/inventory_and_purchase_provider.dart';
import '../../providers/clinical_and_rx_provider.dart';
import 's04_clinical_guard_dialog.dart';
import 's05_drug_alternatives_sheet.dart';
import 's06_prescription_insurance_screen.dart';
import 's07_sales_returns_screen.dart';
import '../../data/database/database_helper.dart';
import '../../reports_pdf/engine/receipt_and_label_builder.dart';

class S03SmartPosScreen extends StatefulWidget{const S03SmartPosScreen({super.key});@override State<S03SmartPosScreen> createState()=>_S03SmartPosScreenState();}
class _S03SmartPosScreenState extends State<S03SmartPosScreen>{
 final search=TextEditingController();final walletRef=TextEditingController();final paidAmount=TextEditingController();String method='CASH';String mixedChannel='CASH';int? customerId;int? cashId;double discount=0;
 ReceiptData? _lastReceipt;
 final _receiptBuilder=const ReceiptAndLabelBuilder();
 @override void dispose(){search.dispose();walletRef.dispose();paidAmount.dispose();super.dispose();}
 @override Widget build(BuildContext context){final p=context.watch<PosAndDrugsProvider>();final s=context.watch<SessionAndErpProvider>();final inventory=context.watch<InventoryAndPurchaseProvider>();final clinical=context.watch<ClinicalAndRxProvider>();final wide=MediaQuery.sizeOf(context).width>850;
  return Focus(onKeyEvent:(node,event){
    if(event is KeyDownEvent&&event.logicalKey==LogicalKeyboardKey.f9){if(_lastReceipt!=null){_receiptBuilder.printReceiptNow(context,_lastReceipt!);}else{_message('لا توجد فاتورة محفوظة للطباعة بعد.');}return KeyEventResult.handled;}
    if(event is KeyDownEvent&&event.logicalKey==LogicalKeyboardKey.f8&&p.cart.isNotEmpty){_finish(p,s,inventory,clinical);return KeyEventResult.handled;}
    if(event is KeyDownEvent&&event.logicalKey==LogicalKeyboardKey.f12&&p.cart.isNotEmpty){
      final item=p.cart.last;
      S05DrugAlternativesSheet.show(context,item.drug,(replacement)=>p.replaceCartItem(item,replacement));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  },child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
   SizedBox(height:48,child:Row(children:[Expanded(child:ListView(scrollDirection:Axis.horizontal,children:[for(var i=0;i<p.tabs.length;i++)Padding(padding:const EdgeInsetsDirectional.only(end:6),child:ChoiceChip(label:Text(p.tabs[i].label+(p.tabs[i].held?' • معلقة':'')),selected:i==p.activeTab,onSelected:(_)=>p.selectTab(i)))])),IconButton(tooltip:'تبويب جديد',onPressed:p.createTab,icon:const Icon(Icons.add_circle_outline)),IconButton(tooltip:'تعليق الفاتورة',onPressed:p.holdCurrent,icon:const Icon(Icons.pause_circle_outline)),IconButton(tooltip:'استرجاع المعلقة',onPressed:p.restoreCurrent,icon:const Icon(Icons.restore))])),
   Expanded(child:wide?Row(children:[Expanded(flex:3,child:_catalog(p)),const SizedBox(width:12),Expanded(flex:2,child:_checkout(p,s,inventory,clinical))]):Column(children:[Expanded(child:_catalog(p)),SizedBox(height:MediaQuery.sizeOf(context).height*.48,child:_checkout(p,s,inventory,clinical))])),
  ])));
 }
 Widget _catalog(PosAndDrugsProvider p)=>Column(children:[TextField(controller:search,decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'اسم تجاري أو علمي أو باركود'),onChanged:p.searchDrugs),const SizedBox(height:8),Expanded(child:ListView.builder(itemCount:p.drugs.length,itemBuilder:(c,i){final d=p.drugs[i];return Card(child:ListTile(title:Text(d.tradeNameAr),subtitle:Text(d.scientificName+' • مخزون '+d.stockTotalUnits.toString()),trailing:Text(MoneyFormatter.format(d.sellPricePack)),onTap:p.currentTab.held?null:()=>p.addDrug(d)));}))]);
 Widget _checkout(PosAndDrugsProvider p,SessionAndErpProvider s,InventoryAndPurchaseProvider inventory,ClinicalAndRxProvider clinical)=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
  Row(children:[Expanded(child:DropdownButtonFormField<int?>(value:clinical.currentPatient?.id,decoration:const InputDecoration(labelText:'المريض / الملف السريري'),items:[const DropdownMenuItem<int?>(value:null,child:Text('بدون ملف مريض')), ...clinical.patients.map((x)=>DropdownMenuItem<int?>(value:x.id,child:Text(x.fullName)))],onChanged:(id)=>clinical.selectPatient(id==null?null:clinical.patients.firstWhere((x)=>x.id==id)))),IconButton(tooltip:'فحص سريري شامل',onPressed:()=>S04ClinicalGuardDialog.show(context),icon:const Icon(Icons.health_and_safety,color:Color(0xffEF5350))),IconButton(tooltip:'الوصفات والتأمين',onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const S06PrescriptionInsuranceScreen())),icon:const Icon(Icons.receipt_long)),IconButton(tooltip:'مرتجع المبيعات',onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const S07SalesReturnsScreen())),icon:const Icon(Icons.assignment_return))]),
  Wrap(spacing:5,children:[_flag(p,clinical,'PREGNANT','حامل'),_flag(p,clinical,'BREASTFEEDING','مرضع'),_flag(p,clinical,'KIDNEY','مريض كلى'),_flag(p,clinical,'LIVER','مريض كبد'),_flag(p,clinical,'CHILD','طفل'),_flag(p,clinical,'ELDERLY','مسن')]),
  if(p.clinicalBlock!=null)ClinicalAlertBanner(message:p.clinicalBlock!,level:ClinicalAlertLevel.block),
  Expanded(child:p.cart.isEmpty?const Center(child:Text('السلة فارغة')):ListView(children:p.cart.map((item)=>_cartLine(context,p,item,inventory,clinical)).toList())),
  Text('الإجمالي: '+MoneyFormatter.format(p.total),textAlign:TextAlign.center,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
  Row(children:[Expanded(child:DropdownButtonFormField<String>(value:method,decoration:const InputDecoration(labelText:'طريقة الدفع'),items:const [DropdownMenuItem(value:'CASH',child:Text('نقداً')),DropdownMenuItem(value:'WALLET',child:Text('محفظة إلكترونية')),DropdownMenuItem(value:'CREDIT',child:Text('آجل')),DropdownMenuItem(value:'MIXED',child:Text('مختلط'))],onChanged:(v)=>setState(()=>method=v??'CASH'))),const SizedBox(width:8),Expanded(child:DropdownButtonFormField<int>(value:cashId,decoration:const InputDecoration(labelText:'الصندوق / المحفظة'),items:s.cashAccounts.map((a)=>DropdownMenuItem(value:a.id,child:Text(a.nameAr))).toList(),onChanged:(v)=>setState(()=>cashId=v))) ]),
  if(method=='MIXED')TextField(controller:paidAmount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'المبلغ المدفوع الآن (والباقي على حساب العميل)'),onChanged:(_)=>setState((){})),
  if(method=='MIXED')DropdownButtonFormField<String>(value:mixedChannel,decoration:const InputDecoration(labelText:'وسيلة الجزء المدفوع'),items:const [DropdownMenuItem(value:'CASH',child:Text('نقداً')),DropdownMenuItem(value:'WALLET',child:Text('محفظة إلكترونية'))],onChanged:(v)=>setState(()=>mixedChannel=v??'CASH')),
  if(method=='WALLET'||(method=='MIXED'&&mixedChannel=='WALLET'))WalletRefField(controller:walletRef),
  if(method=='CREDIT'||method=='MIXED')DropdownButtonFormField<int>(value:customerId,decoration:const InputDecoration(labelText:'العميل'),items:s.parties.where((a)=>a.partyType=='CUSTOMER').map((a)=>DropdownMenuItem(value:a.id,child:Text(a.nameAr))).toList(),onChanged:(v)=>setState(()=>customerId=v)),
  if(method=='CREDIT'||method=='MIXED')_creditPreview(p,s),
  const SizedBox(height:8),FilledButton.icon(onPressed:p.cart.isEmpty?null:()=>_finish(p,s,inventory,clinical),icon:const Icon(Icons.check_circle),label:const Text('إتمام الفاتورة')),
 ])));
 Widget _creditPreview(PosAndDrugsProvider p,SessionAndErpProvider s){
  final matches=s.parties.where((party)=>party.id==customerId).toList();
  if(matches.isEmpty)return const SizedBox.shrink();
  final party=matches.first;
  final paid=method=='CREDIT'?0.0:double.tryParse(paidAmount.text)??0.0;
  final remaining=(p.total-paid).clamp(0,double.infinity).toDouble();
  return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
   const Text('المتبقي عليه بعد الفاتورة',style:TextStyle(color:Colors.white70,fontSize:12)),
   PartyBalanceChip(totalAlayh:party.totalAlayh+remaining,totalLah:party.totalLah),
  ]);
 }
 Widget _flag(PosAndDrugsProvider p,ClinicalAndRxProvider clinical,String code,String label)=>FilterChip(label:Text(label),selected:p.patientFlags.contains(code),onSelected:(v){p.setPatientFlag(code,v);clinical.setQuickFlag(code,v);});
 Widget _cartLine(BuildContext context,PosAndDrugsProvider p,CartItemModel item,InventoryAndPurchaseProvider inventory,ClinicalAndRxProvider clinical){final lots=inventory.batches.where((b)=>b.drugId==item.drug.id&&b.status=='ACTIVE'&&b.daysUntilExpiry>=0&&b.totalUnits>0&&inventory.warehouses.any((w)=>w.id==b.warehouseId&&w.isSellable)).toList()..sort((a,b)=>a.expiryDate.compareTo(b.expiryDate));var remaining=item.baseUnits;final plan=<String>[];for(final lot in lots){if(remaining<=0)break;final take=lot.totalUnits<remaining?lot.totalUnits:remaining;plan.add(lot.batchNo+' • '+lot.expiryDate+' ('+take.toString()+' حبة)');remaining-=take;}final label=plan.isEmpty?'لا توجد تشغيلة صالحة للبيع':'سحب FEFO المتوقع: '+plan.join(' ← ')+(remaining>0?' • نقص '+remaining.toString()+' حبة':'');return ListTile(dense:true,title:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(item.drug.tradeNameAr),Text(label,style:TextStyle(fontSize:11,color:remaining>0?AppColors.danger:AppColors.success))]),subtitle:Row(children:[DropdownButton<String>(value:item.sellUnit,items:const [DropdownMenuItem(value:'PACK',child:Text('باكت')),DropdownMenuItem(value:'STRIP',child:Text('شريط')),DropdownMenuItem(value:'UNIT',child:Text('حبة'))],onChanged:(v)=>p.changeUnit(item,v??'UNIT')),const SizedBox(width:10),SizedBox(width:65,child:TextFormField(initialValue:item.quantity.toString(),keyboardType:TextInputType.number,onChanged:(v)=>p.changeQuantity(item,double.tryParse(v)??item.quantity)))]),trailing:Row(mainAxisSize:MainAxisSize.min,children:[IconButton(tooltip:'طباعة ملصق الجرعة',icon:const Icon(Icons.label_outline),onPressed:(){final expiry=lots.isEmpty?'غير محدد':lots.first.expiryDate;final meal=switch(item.drug.takeWithFood){'BEFORE'=>'قبل الأكل','WITH'=>'مع الأكل','AFTER'=>'بعد الأكل',_=>'حسب تعليمات الصيدلي'};_receiptBuilder.printDoseLabelNow(context,DoseLabelData(pharmacyName:'الصيدلية',patientName:clinical.currentPatient?.fullName??'غير محدد',drugName:item.drug.tradeNameAr,strength:item.drug.strengthText,doseTextAr:item.drug.labelDoseTextAr.isEmpty?item.drug.dosageAdministration:item.drug.labelDoseTextAr,mealInstruction:meal,expiryDate:expiry,keepRefrigerated:item.drug.requiresRefrigeration));}),IconButton(tooltip:'بدائل الدواء (F12)',icon:const Icon(Icons.swap_horiz),onPressed:()=>S05DrugAlternativesSheet.show(context,item.drug,(replacement)=>p.replaceCartItem(item,replacement))),IconButton(icon:const Icon(Icons.delete_outline,color:AppColors.danger),onPressed:()=>p.removeItem(item))]));}
 Future<void> _finish(PosAndDrugsProvider p,SessionAndErpProvider s,InventoryAndPurchaseProvider inventory,ClinicalAndRxProvider clinical)async{
  final verdict=await clinical.evaluateCart(p.cart.map((item)=>item.drug).toList());
  if(verdict.hasUnresolvedCritical){final approved=await S04ClinicalGuardDialog.show(context);if(!approved||context.read<ClinicalAndRxProvider>().verdict.hasUnresolvedCritical)return;}
  if(p.clinicalBlock!=null){final approved=await ManagerPinDialog.show(context,verifier:s.verifyManagerPin);if(!approved)return;}
  if(cashId==null){_message('اختر الصندوق أو المحفظة');return;}
  final tender=method=='MIXED'?mixedChannel:method;
  final isWallet=tender=='WALLET';if(isWallet&&walletRef.text.trim().length<6){_message('أدخل رقم إشعار صحيحاً');return;}
  final credit=method=='CREDIT'||method=='MIXED';if(credit&&customerId==null){_message('اختر العميل');return;}
  final paid=method=='CREDIT'?0.0:method=='MIXED'?(double.tryParse(paidAmount.text)??-1):p.total;
  if(paid<0||paid>p.total){_message('أدخل مبلغاً مدفوعاً صحيحاً لا يتجاوز إجمالي الفاتورة');return;}
  final List<({int cashAccountId, double amount, String method, String? walletRef})> payments =
      paid > 0
          ? [
              (
                cashAccountId: cashId!,
                amount: paid,
                method: tender == 'WALLET' ? 'WALLET' : 'CASH',
                walletRef: isWallet ? walletRef.text.trim() : null,
              ),
            ]
          : <({int cashAccountId, double amount, String method, String? walletRef})>[];
  try{final id=await p.checkout(cashierId:(s.currentUser?['id'] as int?) ?? 1,saleType:method=='CREDIT'?'CREDIT':method=='MIXED'?'MIXED':'CASH',payments:payments,customerId:customerId,discount:discount,managerApproved:p.clinicalBlock!=null,branchId:s.branchId,clinicalVerdict:clinical.verdict);if(mounted){await _loadReceipt(id);_message('تم حفظ الفاتورة رقم '+id.toString()+' • اضغط F9 لطباعة الإيصال');await s.refresh();await inventory.loadAll();}}catch(e){_message(e.toString());}
 }
 void _message(String text)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));

  Future<void> _loadReceipt(int invoiceId) async {
    final db=DatabaseHelper.instance;
    final invoiceRows=await db.rawQuery('''
      SELECT i.*,COALESCE(p.name_ar,'عميل نقدي') AS customer_name
      FROM sales_invoices i LEFT JOIN parties p ON p.id=i.customer_party_id
      WHERE i.id=? LIMIT 1
    ''',[invoiceId]);
    if(invoiceRows.isEmpty)return;
    final row=invoiceRows.first;
    final items=await db.rawQuery('''
      SELECT d.trade_name_ar,si.sell_unit,si.qty_in_sell_unit,si.unit_price_sell_unit,si.line_total
      FROM sales_invoice_items si JOIN drugs d ON d.id=si.drug_id
      WHERE si.invoice_id=? ORDER BY si.id
    ''',[invoiceId]);
    final payments=await db.rawQuery('SELECT method,wallet_ref_no FROM sales_payments WHERE invoice_id=? ORDER BY id',[invoiceId]);
    final paymentLabel=payments.map((e)=>e['method']?.toString()??'').where((e)=>e.isNotEmpty).toSet().join(' + ');
    final wallet=payments.map((e)=>e['wallet_ref_no']?.toString()??'').firstWhere((e)=>e.isNotEmpty,orElse:()=> '');
    final date=DateTime.tryParse(row['invoice_date']?.toString()??'')??DateTime.now();
    _lastReceipt=ReceiptData(
      invoiceNumber:row['invoice_no']?.toString()??invoiceId.toString(),
      dateTime:date,
      customerName:row['customer_name']?.toString()??'عميل نقدي',
      lines:items.map((e)=>ReceiptLine(
        name:e['trade_name_ar']?.toString()??'',
        unit:switch(e['sell_unit']){'PACK'=>'باكت','STRIP'=>'شريط','UNIT'=>'حبة',_=>e['sell_unit']?.toString()??''},
        quantity:(e['qty_in_sell_unit'] as num?)??0,
        unitPrice:(e['unit_price_sell_unit'] as num?)??0,
        total:(e['line_total'] as num?)??0,
      )).toList(),
      subtotal:(row['subtotal'] as num?)??0,
      discount:(row['discount_amount'] as num?)??0,
      rounding:(row['rounding_diff'] as num?)??0,
      netTotal:(row['net_total'] as num?)??0,
      paid:(row['paid_total'] as num?)??0,
      paymentMethod:paymentLabel.isEmpty?'غير محدد':paymentLabel,
      walletNotificationNumber:wallet.isEmpty?null:wallet,
      remainingAfterInvoice:(row['remaining_alayh'] as num?)??0,
    );
  }
}
