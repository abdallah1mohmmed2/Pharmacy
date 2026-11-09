import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/inventory_and_purchase_provider.dart';
import '../../providers/session_and_erp_provider.dart';
import '../../data/database/database_helper.dart';
import '../../data/services/purchase_and_bonus_service.dart';

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
     FilledButton(onPressed:()=>_order(p),child:const Text('توليد أوامر شراء تلقائياً')),
     const Divider(),
     const Text('أوامر الشراء المفتوحة — تحويل عند الاستلام',style:TextStyle(fontWeight:FontWeight.bold)),
     ...p.purchaseOrders.map((order)=>Card(child:ListTile(
      title:Text(order['po_no'].toString()+' • '+order['supplier_name'].toString()),
      subtitle:Text(order['status'].toString()+' • '+order['item_count'].toString()+' أصناف • '+order['estimated_total'].toString()),
      trailing:IconButton(icon:const Icon(Icons.receipt_long),tooltip:'تحويل الأمر لفاتورة مشتريات عند الاستلام',onPressed:()=>_convertOrder(p,order)),
     )))
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
  var skipped=0;
  for(final item in p.shortages.where((x)=>x.suggestedPacks>0)){
   final supplierId=item.bestSupplierId??supplier;
   if(supplierId==null||item.effectivePackCost<=0){skipped++;continue;}
   grouped.putIfAbsent(supplierId,()=>[]).add((drugId:item.drugId,packs:item.suggestedPacks,cost:item.effectivePackCost,bonus:0));
  }
  if(grouped.isEmpty){_msg('لا توجد توصيات لها مورد وتكلفة شراء فعلية موثوقة؛ سجّل فاتورة شراء سابقة أو حدّد مورداً وتكلفة الصنف');return;}
  try{
   final created=<int>[];
   for(final entry in grouped.entries){
    created.add(await p.createShortageOrder(supplierId:entry.key,items:entry.value));
   }
   _msg('تم إنشاء '+created.length.toString()+' أمر شراء. أصناف تم تجاوزها لعدم توفر تكلفة: '+skipped.toString());
  }catch(e){_msg(e.toString());}
 }
 Future<void> _convertOrder(InventoryAndPurchaseProvider p,Map<String,Object?> order)async{
  final poId=order['id'] as int;
  final rows=await DatabaseHelper.instance.rawQuery(
   'SELECT poi.*,d.trade_name_ar,d.requires_refrigeration FROM purchase_order_items poi JOIN drugs d ON d.id=poi.drug_id WHERE poi.po_id=? ORDER BY poi.id',
   [poId],
  );
  final remaining=rows.where((row)=>(row['qty_packs'] as int)>(row['received_packs'] as int)).toList();
  if(remaining.isEmpty){_msg('تم استلام جميع أصناف أمر الشراء');return;}
  final hasCold=remaining.any((row)=>(row['requires_refrigeration'] as int? ?? 0)==1);
  final hasAmbient=remaining.any((row)=>(row['requires_refrigeration'] as int? ?? 0)!=1);
  if(hasCold&&hasAmbient){_msg('قسّم أمر الشراء إلى أمرين منفصلين للأصناف المبردة وغير المبردة قبل الاستلام');return;}
  final warehouseCandidates=p.warehouses.where((warehouse)=>hasCold?warehouse.whType=='FRIDGE':warehouse.whType=='MAIN_STORE').toList();
  if(warehouseCandidates.isEmpty){_msg(hasCold?'مستودع الثلاجة غير مهيأ':'المخزن الرئيسي غير مهيأ');return;}
  final warehouse=warehouseCandidates.first;
  final controllers=<int,({TextEditingController batch,TextEditingController expiry})>{};
  for(final row in remaining){
   final id=row['id'] as int;
   controllers[id]=(batch:TextEditingController(),expiry:TextEditingController());
  }
  final invoiceNo=TextEditingController();
  final shelves=p.shelves.where((shelf)=>shelf.warehouseId==warehouse.id&&( !hasCold||shelf.isFridge)).toList();
  if(shelves.isEmpty){for(final pair in controllers.values){pair.batch.dispose();pair.expiry.dispose();}invoiceNo.dispose();_msg('لا يوجد رف مناسب في المستودع المحدد');return;}
  final confirmed=await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(
   title:Text('استلام أمر الشراء ${order['po_no']}'),
   content:SizedBox(width:560,child:ListView(shrinkWrap:true,children:[
    Text('المستودع: ${warehouse.nameAr}'),
    TextField(controller:invoiceNo,decoration:const InputDecoration(labelText:'رقم فاتورة المورد (اختياري)')),
    ...remaining.map((row){
     final id=row['id'] as int;final quantity=(row['qty_packs'] as int)-(row['received_packs'] as int);
     return Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text('${row['trade_name_ar']} • ${quantity} باكت متبقٍ'),
      TextField(controller:controllers[id]!.batch,decoration:const InputDecoration(labelText:'رقم التشغيلة المستلمة')),
      TextField(controller:controllers[id]!.expiry,decoration:const InputDecoration(labelText:'الصلاحية YYYY-MM-DD')),
     ]));
    }),
   ])),
   actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('إنشاء فاتورة الاستلام'))],
  ));
  if(confirmed==true){
   final items=<PurchaseLineInput>[];
   for(final row in remaining){
    final id=row['id'] as int;final quantity=(row['qty_packs'] as int)-(row['received_packs'] as int);
    final expiryDate=DateTime.tryParse(controllers[id]!.expiry.text.trim());
    final batchNumber=controllers[id]!.batch.text.trim();
    if(batchNumber.isEmpty||expiryDate==null||expiryDate.isBefore(DateTime.now().subtract(const Duration(days:1)))){
     _msg('أدخل رقم تشغيلة وصلاحية صحيحة لكل صنف');items.clear();break;
    }
    final expectedBonus=(row['expected_bonus_packs'] as int? ?? 0);
    final ordered=(row['qty_packs'] as int);
    final bonusRemaining=ordered==0?0:(expectedBonus*quantity/ordered).floor();
    final effectiveCost=(row['expected_cost_pack'] as num).toDouble();
    final paidPackPrice=effectiveCost*(quantity+bonusRemaining)/quantity;
    items.add(PurchaseLineInput(
     drugId:row['drug_id'] as int,
     batchNo:batchNumber,
     expiryDate:controllers[id]!.expiry.text.trim(),
     warehouseId:warehouse.id,
     qtyPacksPaid:quantity,
     bonusPacks:bonusRemaining,
     packPrice:paidPackPrice,
     locationId:shelves.first.id,
    ));
   }
   if(items.length==remaining.length){
    try{
     final session=context.read<SessionAndErpProvider>();
     p.branchId=session.branchId;
     final invoiceId=await p.postPurchase(
      supplierId:order['supplier_party_id'] as int,
      warehouseId:warehouse.id,
      invoiceNo:'',
      paymentType:'CREDIT',
      paid:0,
      items:items,
      bonusIncluded:true,
      supplierInvoiceNo:invoiceNo.text.trim(),
      purchaseOrderId:poId,
     );
     await session.refresh();
     _msg('تم تحويل أمر الشراء إلى فاتورة رقم '+invoiceId.toString());
    }catch(error){_msg(error.toString());}
   }
  }
  invoiceNo.dispose();
  for(final pair in controllers.values){pair.batch.dispose();pair.expiry.dispose();}
 }
 void _msg(String v)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(v)));
}