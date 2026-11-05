import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/pos_and_drugs_provider.dart';
import '../../providers/session_and_erp_provider.dart';
import '../../core/theme/enterprise_dark_theme.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/erp_models.dart';

class S03SmartPosScreen extends StatefulWidget{const S03SmartPosScreen({super.key});@override State<S03SmartPosScreen> createState()=>_S03SmartPosScreenState();}
class _S03SmartPosScreenState extends State<S03SmartPosScreen>{
 final search=TextEditingController();final walletRef=TextEditingController();final paidAmount=TextEditingController();String method='CASH';String mixedChannel='CASH';int? customerId;int? cashId;double discount=0;
 @override void dispose(){search.dispose();walletRef.dispose();paidAmount.dispose();super.dispose();}
 @override Widget build(BuildContext context){final p=context.watch<PosAndDrugsProvider>();final s=context.watch<SessionAndErpProvider>();final wide=MediaQuery.sizeOf(context).width>850;
  return Padding(padding:const EdgeInsets.all(12),child:Column(children:[
   SizedBox(height:48,child:Row(children:[Expanded(child:ListView(scrollDirection:Axis.horizontal,children:[for(var i=0;i<p.tabs.length;i++)Padding(padding:const EdgeInsetsDirectional.only(end:6),child:ChoiceChip(label:Text(p.tabs[i].label+(p.tabs[i].held?' • معلقة':'')),selected:i==p.activeTab,onSelected:(_)=>p.selectTab(i)))])),IconButton(tooltip:'تبويب جديد',onPressed:p.createTab,icon:const Icon(Icons.add_circle_outline)),IconButton(tooltip:'تعليق الفاتورة',onPressed:p.holdCurrent,icon:const Icon(Icons.pause_circle_outline)),IconButton(tooltip:'استرجاع المعلقة',onPressed:p.restoreCurrent,icon:const Icon(Icons.restore))])),
   Expanded(child:wide?Row(children:[Expanded(flex:3,child:_catalog(p)),const SizedBox(width:12),Expanded(flex:2,child:_checkout(p,s))]):Column(children:[Expanded(child:_catalog(p)),SizedBox(height:MediaQuery.sizeOf(context).height*.48,child:_checkout(p,s))])),
  ]));
 }
 Widget _catalog(PosAndDrugsProvider p)=>Column(children:[TextField(controller:search,decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'اسم تجاري أو علمي أو باركود'),onChanged:p.searchDrugs),const SizedBox(height:8),Expanded(child:ListView.builder(itemCount:p.drugs.length,itemBuilder:(c,i){final d=p.drugs[i];return Card(child:ListTile(title:Text(d.tradeNameAr),subtitle:Text(d.scientificName+' • مخزون '+d.stockTotalUnits.toString()),trailing:Text(MoneyFormatter.format(d.sellPricePack)),onTap:p.currentTab.held?null:()=>p.addDrug(d)));}))]);
 Widget _checkout(PosAndDrugsProvider p,SessionAndErpProvider s)=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
  Wrap(spacing:5,children:[_flag(p,'PREGNANT','حامل'),_flag(p,'BREASTFEEDING','مرضع'),_flag(p,'KIDNEY','مريض كلى'),_flag(p,'LIVER','مريض كبد'),_flag(p,'CHILD','طفل'),_flag(p,'ELDERLY','مسن')]),
  if(p.clinicalBlock!=null)ClinicalAlertBanner(message:p.clinicalBlock!,level:ClinicalAlertLevel.block),
  Expanded(child:p.cart.isEmpty?const Center(child:Text('السلة فارغة')):ListView(children:p.cart.map((item)=>_cartLine(p,item)).toList())),
  Text('الإجمالي: '+MoneyFormatter.format(p.total),textAlign:TextAlign.center,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
  Row(children:[Expanded(child:DropdownButtonFormField<String>(value:method,decoration:const InputDecoration(labelText:'طريقة الدفع'),items:const [DropdownMenuItem(value:'CASH',child:Text('نقداً')),DropdownMenuItem(value:'WALLET',child:Text('محفظة إلكترونية')),DropdownMenuItem(value:'CREDIT',child:Text('آجل')),DropdownMenuItem(value:'MIXED',child:Text('مختلط'))],onChanged:(v)=>setState(()=>method=v??'CASH'))),const SizedBox(width:8),Expanded(child:DropdownButtonFormField<int>(value:cashId,decoration:const InputDecoration(labelText:'الصندوق / المحفظة'),items:s.cashAccounts.map((a)=>DropdownMenuItem(value:a.id,child:Text(a.nameAr))).toList(),onChanged:(v)=>setState(()=>cashId=v))) ]),
  if(method=='MIXED')TextField(controller:paidAmount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'المبلغ المدفوع الآن (والباقي على حساب العميل)'),onChanged:(_)=>setState((){})),
  if(method=='MIXED')DropdownButtonFormField<String>(value:mixedChannel,decoration:const InputDecoration(labelText:'وسيلة الجزء المدفوع'),items:const [DropdownMenuItem(value:'CASH',child:Text('نقداً')),DropdownMenuItem(value:'WALLET',child:Text('محفظة إلكترونية'))],onChanged:(v)=>setState(()=>mixedChannel=v??'CASH')),
  if(method=='WALLET'||(method=='MIXED'&&mixedChannel=='WALLET'))WalletRefField(controller:walletRef),
  if(method=='CREDIT'||method=='MIXED')DropdownButtonFormField<int>(value:customerId,decoration:const InputDecoration(labelText:'العميل'),items:s.parties.where((a)=>a.partyType=='CUSTOMER').map((a)=>DropdownMenuItem(value:a.id,child:Text(a.nameAr))).toList(),onChanged:(v)=>setState(()=>customerId=v)),
  if(method=='CREDIT'||method=='MIXED')_creditPreview(p,s),
  const SizedBox(height:8),FilledButton.icon(onPressed:p.cart.isEmpty?null:()=>_finish(p,s),icon:const Icon(Icons.check_circle),label:const Text('إتمام الفاتورة')),
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
 Widget _flag(PosAndDrugsProvider p,String code,String label)=>FilterChip(label:Text(label),selected:p.patientFlags.contains(code),onSelected:(v)=>p.setPatientFlag(code,v));
 Widget _cartLine(PosAndDrugsProvider p,CartItemModel item)=>ListTile(dense:true,title:Text(item.drug.tradeNameAr),subtitle:Row(children:[DropdownButton<String>(value:item.sellUnit,items:const [DropdownMenuItem(value:'PACK',child:Text('باكت')),DropdownMenuItem(value:'STRIP',child:Text('شريط')),DropdownMenuItem(value:'UNIT',child:Text('حبة'))],onChanged:(v)=>p.changeUnit(item,v??'UNIT')),const SizedBox(width:10),SizedBox(width:65,child:TextFormField(initialValue:item.quantity.toString(),keyboardType:TextInputType.number,onChanged:(v)=>p.changeQuantity(item,double.tryParse(v)??item.quantity))) ]),trailing:IconButton(icon:const Icon(Icons.delete_outline,color:AppColors.danger),onPressed:()=>p.removeItem(item)));
 Future<void> _finish(PosAndDrugsProvider p,SessionAndErpProvider s)async{
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
  try{final id=await p.checkout(cashierId:(s.currentUser?['id'] as int?) ?? 1,saleType:method=='CREDIT'?'CREDIT':method=='MIXED'?'MIXED':'CASH',payments:payments,customerId:customerId,discount:discount,managerApproved:p.clinicalBlock!=null,branchId:s.branchId);if(mounted){_message('تم حفظ الفاتورة رقم '+id.toString());await s.refresh();}}catch(e){_message(e.toString());}
 }
 void _message(String text)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));
}
