import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/inventory_and_purchase_provider.dart';
import '../../providers/session_and_erp_provider.dart';

class S17S18ReturnsAndShortagesScreen extends StatefulWidget {
 const S17S18ReturnsAndShortagesScreen({super.key});
 @override State<S17S18ReturnsAndShortagesScreen> createState()=>_S17S18ReturnsAndShortagesScreenState();
}
class _S17S18ReturnsAndShortagesScreenState extends State<S17S18ReturnsAndShortagesScreen> {
 int? supplier,batch; String settlement='CREDIT_NOTE';
 final qty=TextEditingController(),value=TextEditingController(),reason=TextEditingController(text:'مرتجع للمورد');
 @override void dispose(){qty.dispose();value.dispose();reason.dispose();super.dispose();}
 @override Widget build(BuildContext context){
  final p=context.watch<InventoryAndPurchaseProvider>();final s=context.watch<SessionAndErpProvider>();
  final suppliers=s.parties.where((x)=>x.partyType=='SUPPLIER').toList();final batches=p.batches.where((x)=>x.totalUnits>0).toList();
  return DefaultTabController(length:2,child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
   const Text('مرتجعات المشتريات والنواقص الذكية',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
   const TabBar(tabs:[Tab(text:'مرتجع المشتريات'),Tab(text:'النواقص وأوامر الشراء')]),
   Expanded(child:TabBarView(children:[
    ListView(children:[
     DropdownButtonFormField<int>(value:supplier,decoration:const InputDecoration(labelText:'المورد'),items:suppliers.map((x)=>DropdownMenuItem(value:x.id,child:Text(x.nameAr))).toList(),onChanged:(v)=>setState(()=>supplier=v)),
     DropdownButtonFormField<int>(value:batch,decoration:const InputDecoration(labelText:'التشغيلة'),items:batches.map((x)=>DropdownMenuItem(value:x.id,child:Text(x.drugName+' • '+x.batchNo))).toList(),onChanged:(v)=>setState(()=>batch=v)),
     TextField(controller:qty,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'الكمية بالحبة')),
     DropdownButtonFormField<String>(value:settlement,decoration:const InputDecoration(labelText:'طريقة التسوية'),items:const [DropdownMenuItem(value:'CREDIT_NOTE',child:Text('إشعار خصم يخفض ما له')),DropdownMenuItem(value:'CASH_REFUND',child:Text('استرداد نقدي')),DropdownMenuItem(value:'EXCHANGE_GOODS',child:Text('استبدال'))],onChanged:(v)=>setState(()=>settlement=v??settlement)),
     TextField(controller:value,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'قيمة الاسترداد المتفق عليها')),
     TextField(controller:reason,decoration:const InputDecoration(labelText:'سبب المرتجع')),
     FilledButton(onPressed:()=>_return(p),child:const Text('تسجيل المرتجع'))
    ]),
    ListView(children:[
     const Text('الأصناف التي وصلت للحد الأدنى'),
     ...p.shortages.map((x)=>ListTile(title:Text(x.drugName),subtitle:Text('الرصيد '+x.currentUnits.toString()+' • الحد '+x.minimumUnits.toString()+' • متوسط البيع اليومي '+x.averageDailySales.toStringAsFixed(1)),trailing:Text('طلب '+x.suggestedPacks.toString()+' باكت'))),
     DropdownButtonFormField<int>(value:supplier,decoration:const InputDecoration(labelText:'المورد'),items:suppliers.map((x)=>DropdownMenuItem(value:x.id,child:Text(x.nameAr))).toList(),onChanged:(v)=>setState(()=>supplier=v)),
     FilledButton(onPressed:()=>_order(p),child:const Text('توليد أوامر شراء تلقائياً'))
    ])
   ]))
  ])));
 }
 Future<void> _return(InventoryAndPurchaseProvider p)async{
  final q=int.tryParse(qty.text)??0;final amount=double.tryParse(value.text)??0;
  if(supplier==null||batch==null||q<=0||amount<0){_msg('أكمل بيانات المورد والتشغيلة والكمية والقيمة');return;}
  try{await p.postPurchaseReturn(supplierId:supplier!,batchId:batch!,units:q,reason:reason.text,settlement:settlement,agreedValue:amount);_msg('تم تسجيل مرتجع المشتريات');}catch(e){_msg(e.toString());}
 }
 Future<void> _order(InventoryAndPurchaseProvider p)async{
  if(supplier==null||p.shortages.isEmpty){_msg('اختر المورد وتأكد من وجود نواقص');return;}
  final items=p.shortages.where((x)=>x.suggestedPacks>0).map((x)=>(drugId:x.drugId,packs:x.suggestedPacks,cost:0.0,bonus:0)).toList();
  try{final id=await p.createShortageOrder(supplierId:supplier!,items:items);_msg('تم إنشاء أمر الشراء رقم '+id.toString());}catch(e){_msg(e.toString());}
 }
 void _msg(String v)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(v)));
}