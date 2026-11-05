import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/inventory_and_purchase_provider.dart';
import '../../providers/session_and_erp_provider.dart';

class S17S18ReturnsAndShortagesScreen extends StatefulWidget {
 const S17S18ReturnsAndShortagesScreen({super.key});
 @override State<S17S18ReturnsAndShortagesScreen> createState()=>_S17S18ReturnsAndShortagesScreenState();
}
class _S17S18ReturnsAndShortagesScreenState extends State<S17S18ReturnsAndShortagesScreen> {
 int? supplier,batch,cashAccount; String settlement='CREDIT_NOTE';
 final qty=TextEditingController(),value=TextEditingController(),reason=TextEditingController(text:'مرتجع للمورد');
 @override void dispose(){qty.dispose();value.dispose();reason.dispose();super.dispose();}
 @override Widget build(BuildContext context){
  final p=context.watch<InventoryAndPurchaseProvider>();final s=context.watch<SessionAndErpProvider>();
  final suppliers=s.parties.where((x)=>x.partyType=='SUPPLIER').toList();final batches=p.batches.where((x)=>x.totalUnits>0).toList();final selected=p.batches.where((x)=>x.id==batch).toList();final cost=selected.isEmpty?0.0:selected.first.unitCost*(int.tryParse(qty.text)??0);final difference=cost-(double.tryParse(value.text)??0);
  return DefaultTabController(length:2,child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
   const Text('مرتجعات المشتريات والنواقص الذكية',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
   const TabBar(tabs:[Tab(text:'مرتجع المشتريات'),Tab(text:'النواقص وأوامر الشراء')]),
   Expanded(child:TabBarView(children:[
    ListView(children:[
     DropdownButtonFormField<int>(value:supplier,decoration:const InputDecoration(labelText:'المورد'),items:suppliers.map((x)=>DropdownMenuItem(value:x.id,child:Text(x.nameAr))).toList(),onChanged:(v)=>setState(()=>supplier=v)),
     DropdownButtonFormField<int>(value:batch,decoration:const InputDecoration(labelText:'التشغيلة'),items:batches.map((x)=>DropdownMenuItem(value:x.id,child:Text(x.drugName+' • '+x.batchNo))).toList(),onChanged:(v)=>setState(()=>batch=v)),
     TextField(controller:qty,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'الكمية بالحبة'),onChanged:(_)=>setState((){})),
     DropdownButtonFormField<String>(value:settlement,decoration:const InputDecoration(labelText:'طريقة التسوية'),items:const [DropdownMenuItem(value:'CREDIT_NOTE',child:Text('إشعار خصم يخفض ما له')),DropdownMenuItem(value:'CASH_REFUND',child:Text('استرداد نقدي')),DropdownMenuItem(value:'EXCHANGE_GOODS',child:Text('استبدال'))],onChanged:(v)=>setState(()=>settlement=v??settlement)),
     if(settlement=='CASH_REFUND')DropdownButtonFormField<int>(value:cashAccount,decoration:const InputDecoration(labelText:'الصندوق المستلم للاسترداد'),items:s.cashAccounts.map((x)=>DropdownMenuItem(value:x.id,child:Text(x.nameAr))).toList(),onChanged:(v)=>setState(()=>cashAccount=v)),
     TextField(controller:value,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'قيمة الاسترداد المتفق عليها'),onChanged:(_)=>setState((){})),Text('تكلفة البضاعة المرتجعة: '+cost.toStringAsFixed(2)+' • فرق التسوية (التكلفة − قيمة الاسترداد): '+difference.toStringAsFixed(2),style:TextStyle(color:difference>0?Colors.orange:Colors.green)),
     TextField(controller:reason,decoration:const InputDecoration(labelText:'سبب المرتجع')),
     FilledButton(onPressed:()=>_return(p),child:const Text('تسجيل المرتجع'))
    ]),
    ListView(children:[
     const Text('الأصناف التي وصلت للحد الأدنى'),
     ...p.shortages.map((x)=>ListTile(title:Text(x.drugName),subtitle:Text('الرصيد '+x.currentUnits.toString()+' • الحد '+x.minimumUnits.toString()+' • متوسط البيع اليومي '+x.averageDailySales.toStringAsFixed(1)+' • أفضل مورد '+(x.bestSupplierName.isEmpty?'غير متاح':x.bestSupplierName)+' • تكلفة فعلية '+x.effectivePackCost.toStringAsFixed(2)),trailing:Text('طلب '+x.suggestedPacks.toString()+' باكت'))),
     DropdownButtonFormField<int>(value:supplier,decoration:const InputDecoration(labelText:'المورد'),items:suppliers.map((x)=>DropdownMenuItem(value:x.id,child:Text(x.nameAr))).toList(),onChanged:(v)=>setState(()=>supplier=v)),
     FilledButton(onPressed:()=>_order(p),child:const Text('توليد أوامر شراء تلقائياً'))
    ])
   ]))
  ])));
 }
 Future<void> _return(InventoryAndPurchaseProvider p)async{
  final q=int.tryParse(qty.text)??0;final amount=double.tryParse(value.text)??0;
  if(supplier==null||batch==null||q<=0||amount<0||(settlement=='CASH_REFUND'&&cashAccount==null)){_msg('أكمل بيانات المورد والتشغيلة والكمية والقيمة');return;}
  try{await p.postPurchaseReturn(supplierId:supplier!,batchId:batch!,units:q,reason:reason.text,settlement:settlement,agreedValue:amount,cashAccountId:cashAccount);_msg(settlement=='EXCHANGE_GOODS'?'تم تسجيل المرتجع بانتظار استلام البضاعة البديلة':'تم تسجيل المرتجع وترحيل التسوية');}catch(e){_msg(e.toString());}
 }
 Future<void> _order(InventoryAndPurchaseProvider p)async{
  if(p.shortages.isEmpty){_msg('لا توجد أصناف ناقصة لإنشاء أمر شراء');return;}
  final grouped=<int,List<({int drugId,int packs,double cost,int bonus})>>{};
  for(final item in p.shortages.where((x)=>x.suggestedPacks>0)){
   final supplierId=item.bestSupplierId??supplier;
   if(supplierId==null)continue;
   grouped.putIfAbsent(supplierId,()=>[]).add((drugId:item.drugId,packs:item.suggestedPacks,cost:item.effectivePackCost,bonus:0));
  }
  if(grouped.isEmpty){_msg('لا يوجد مورد مرتبط بتكلفة شراء سابقة؛ اختر مورداً أولاً');return;}
  try{
   final created=<int>[];
   for(final entry in grouped.entries){
    created.add(await p.createShortageOrder(supplierId:entry.key,items:entry.value));
   }
   _msg('تم إنشاء '+created.length.toString()+' أمر شراء تلقائياً: '+created.join('، '));
  }catch(e){_msg(e.toString());}
 }
 void _msg(String v)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(v)));
}