import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/inventory_and_purchase_provider.dart';
import '../../data/database/database_helper.dart';

class S15StockTransfersScreen extends StatefulWidget{const S15StockTransfersScreen({super.key});@override State<S15StockTransfersScreen> createState()=>_S15StockTransfersScreenState();}
class _S15StockTransfersScreenState extends State<S15StockTransfersScreen>{
 int? from,to,batch;final qty=TextEditingController();
 @override void dispose(){qty.dispose();super.dispose();}
 @override Widget build(BuildContext context){final p=context.watch<InventoryAndPurchaseProvider>();final sourceBatches=p.batches.where((b)=>b.warehouseId==from&&b.totalUnits>0).toList();return Padding(padding:const EdgeInsets.all(12),child:Column(children:[const Text('التحويلات المخزنية',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),Row(children:[Expanded(child:DropdownButtonFormField<int>(value:from,decoration:const InputDecoration(labelText:'من مستودع'),items:p.warehouses.map((w)=>DropdownMenuItem(value:w.id,child:Text(w.nameAr))).toList(),onChanged:(v)=>setState(()=>from=v))),const SizedBox(width:8),Expanded(child:DropdownButtonFormField<int>(value:to,decoration:const InputDecoration(labelText:'إلى مستودع'),items:p.warehouses.where((w)=>w.id!=from).map((w)=>DropdownMenuItem(value:w.id,child:Text(w.nameAr))).toList(),onChanged:(v)=>setState(()=>to=v)))]),DropdownButtonFormField<int>(value:batch,decoration:const InputDecoration(labelText:'التشغيلة'),items:sourceBatches.map((b)=>DropdownMenuItem(value:b.id,child:Text(b.drugName+' • '+b.batchNo+' • '+b.totalUnits.toString()))).toList(),onChanged:(v)=>setState(()=>batch=v)),TextField(controller:qty,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'الكمية بالحبة')),FilledButton(onPressed:()=>_create(p),child:const Text('إنشاء تحويل')),TextButton.icon(onPressed:()=>_suggest(p),icon:const Icon(Icons.auto_awesome),label:const Text('اقتراح تغذية رفوف الصيدلية تلقائياً')),const Divider(),Expanded(child:ListView(children:p.transfers.map((t)=>Card(child:ListTile(title:Text(t.transferNo),subtitle:Text(t.transferType+' • '+t.status),trailing:Wrap(children:[if(t.status=='DRAFT')IconButton(onPressed:()=>_dispatch(p,t.id),icon:const Icon(Icons.send)),if(t.status=='IN_TRANSIT')IconButton(onPressed:()=>_receive(p,t.id),icon:const Icon(Icons.inventory_2))])))).toList()))]));}
 Future<void> _create(InventoryAndPurchaseProvider p)async{if(from==null||to==null||batch==null){_message('حدد المستودعين والتشغيلة');return;}final amount=int.tryParse(qty.text)??0;if(amount<=0){_message('أدخل كمية صحيحة');return;}try{await p.createTransfer(fromWarehouse:from!,toWarehouse:to!,items:[(batchId:batch!,qtyUnits:amount)]);qty.clear();_message('تم إنشاء التحويل');}catch(e){_message(e.toString());}}
 Future<void> _dispatch(InventoryAndPurchaseProvider p,int id)async{try{await p.dispatchTransfer(id);_message('تم إرسال التحويل وخصم الكمية من المستودع المصدر');}catch(e){_message(e.toString());}}
 Future<void> _receive(InventoryAndPurchaseProvider p,int id)async{
  final db=await DatabaseHelper.instance.database;
  final rows=await db.rawQuery('SELECT i.id,i.qty_units,i.received_qty_units,b.batch_no,d.trade_name_ar FROM stock_transfer_items i JOIN batches_fefo b ON b.id=i.from_batch_id JOIN drugs d ON d.id=b.drug_id WHERE i.transfer_id=? ORDER BY i.id',[id]);
  if(rows.isEmpty){_message('لا توجد بنود في هذا التحويل');return;}
  final controllers=<int,TextEditingController>{};
  for(final row in rows){controllers[row['id'] as int]=TextEditingController(text:(row['qty_units'] as int).toString());}
  final accepted=await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(
   title:const Text('مطابقة الاستلام الفعلي'),
   content:SizedBox(width:520,child:ListView(shrinkWrap:true,children:rows.map((row){
    final itemId=row['id'] as int;
    return Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
     Text(row['trade_name_ar'].toString()+' • '+row['batch_no'].toString()),
     Text('الكمية المرسلة: '+row['qty_units'].toString()+' حبة',style:const TextStyle(color:Colors.white70)),
     TextField(controller:controllers[itemId],keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'الكمية المستلمة فعلياً بالحبة')),
    ]));
   }).toList())),
   actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('تأكيد الاستلام'))],
  ));
  if(accepted==true){
   final received=<int,int>{};
   for(final row in rows){
    final itemId=row['id'] as int;
    final qty=int.tryParse(controllers[itemId]!.text);
    if(qty==null||qty<0||qty>(row['qty_units'] as int)){for(final controller in controllers.values){controller.dispose();}_message('تأكد من أن كل كمية مستلمة بين صفر والكمية المرسلة');return;}
    received[itemId]=qty;
   }
   try{
    await p.receiveTransfer(id,received:received);
    final sent=rows.fold<int>(0,(sum,row)=>sum+(row['qty_units'] as int));
    final actual=received.values.fold<int>(0,(sum,value)=>sum+value);
    _message('تم تسجيل الاستلام. فرق الاستلام: '+(sent-actual).toString()+' حبة');
   }catch(e){_message(e.toString());}
  }
  for(final controller in controllers.values){controller.dispose();}
 }
 Future<void> _suggest(InventoryAndPurchaseProvider p)async{
  final pharmacy=p.warehouses.where((w)=>w.whType=='PHARMACY_FLOOR').toList();
  final main=p.warehouses.where((w)=>w.whType=='MAIN_STORE').toList();
  if(pharmacy.isEmpty||main.isEmpty){_message('المستودع الرئيسي أو صالة الصيدلية غير مهيأ');return;}
  final db=await DatabaseHelper.instance.database;
  final levels=await db.rawQuery(
   "SELECT d.id,d.min_stock_units,d.requires_refrigeration,COALESCE(SUM(CASE WHEN b.warehouse_id=? AND b.status='ACTIVE' AND b.expiry_date>=date('now') THEN b.total_units ELSE 0 END),0) pharmacy_units FROM drugs d LEFT JOIN batches_fefo b ON b.drug_id=d.id GROUP BY d.id",
   [pharmacy.first.id],
  );
  final items=<({int batchId,int qtyUnits})>[];
  for(final level in levels){
   if((level['requires_refrigeration'] as int? ?? 0)==1)continue;
   final minimum=(level['min_stock_units'] as int? ?? 0);
   final current=(level['pharmacy_units'] as int? ?? 0);
   var needed=minimum*2-current;
   if(needed<=0)continue;
   final drugId=level['id'] as int;
   final source=p.batches.where((b)=>b.drugId==drugId&&b.warehouseId==main.first.id&&b.status=='ACTIVE'&&!b.isExpired).toList()
    ..sort((a,b)=>a.expiryDate.compareTo(b.expiryDate));
   for(final batch in source){
    if(needed<=0)break;
    final amount=batch.totalUnits<needed?batch.totalUnits:needed;
    if(amount>0){items.add((batchId:batch.id,qtyUnits:amount));needed-=amount;}
   }
  }
  if(items.isEmpty){_message('لا توجد كميات صالحة في المخزن الرئيسي تحتاجها صالة الصيدلية');return;}
  try{await p.createTransfer(fromWarehouse:main.first.id,toWarehouse:pharmacy.first.id,items:items);_message('تم إنشاء مقترح تغذية الرفوف من التشغيلات الأقرب انتهاءً');}
  catch(error){_message(error.toString());}
 }
 void _message(String v)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(v)));
}
