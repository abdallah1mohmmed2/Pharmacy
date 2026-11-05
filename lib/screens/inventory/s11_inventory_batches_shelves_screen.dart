import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/inventory_and_purchase_provider.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/inventory_and_purchase_models.dart';

class S11InventoryBatchesShelvesScreen extends StatefulWidget {
  const S11InventoryBatchesShelvesScreen({super.key});
  @override State<S11InventoryBatchesShelvesScreen> createState()=>_S11InventoryBatchesShelvesScreenState();
}
class _S11InventoryBatchesShelvesScreenState extends State<S11InventoryBatchesShelvesScreen> {
  bool byDrug=true;
  @override void initState(){super.initState();WidgetsBinding.instance.addPostFrameCallback((_)=>context.read<InventoryAndPurchaseProvider>().loadAll());}
  @override Widget build(BuildContext context){
    final p=context.watch<InventoryAndPurchaseProvider>();
    return Scaffold(body:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
      Row(children:[const Expanded(child:Text('المخزون والتشغيلات والأرفف',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold))),IconButton(onPressed:()=>_temperature(p),icon:const Icon(Icons.thermostat),tooltip:'تسجيل حرارة الثلاجة'),IconButton(onPressed:()=>_movementCard(p),icon:const Icon(Icons.receipt_long),tooltip:'كارت حركة الصنف')]),
      SegmentedButton<bool>(segments:const [ButtonSegment(value:true,label:Text('حسب الصنف')),ButtonSegment(value:false,label:Text('حسب التشغيلة'))],selected:{byDrug},onSelectionChanged:(v)=>setState(()=>byDrug=v.first)),
      const SizedBox(height:8),
      if(p.error!=null)Text(p.error!,style:const TextStyle(color:Colors.redAccent)),
      Expanded(child:p.loading?const Center(child:CircularProgressIndicator()):byDrug?_drugList(p):_batchList(p)),
    ])));
  }
  Widget _drugList(InventoryAndPurchaseProvider p){
    final groups=<int,List<BatchFefoModel>>{};for(final b in p.batches){groups.putIfAbsent(b.drugId,()=>[]).add(b);}
    return ListView(children:groups.entries.map((entry){final first=entry.value.first;final total=entry.value.fold<int>(0,(sum,b)=>sum+b.totalUnits);return Card(child:ExpansionTile(title:Text(first.drugName),subtitle:Text('الرصيد '+total.toString()+' حبة • '+entry.value.length.toString()+' تشغيلات'),children:entry.value.map(_batchTile).toList()));}).toList());
  }
  Widget _batchList(InventoryAndPurchaseProvider p)=>ListView(children:p.batches.map(_batchTile).toList());
  Widget _batchTile(BatchFefoModel b)=>Card(child:ListTile(title:Text(b.drugName+' — '+b.batchNo),subtitle:Text('الصلاحية '+b.expiryDate+' • '+b.sealedPacks.toString()+' باكت مغلق • '+b.looseUnits.toString()+' حبة سائبة\nالتكلفة '+b.packCost.toStringAsFixed(2)+' • الرف '+(b.shelfCode.isEmpty?'غير محدد':b.shelfCode)),isThreeLine:true,trailing:Column(mainAxisAlignment:MainAxisAlignment.center,children:[_expiryBadge(b),IconButton(onPressed:()=>_moveShelf(b),icon:const Icon(Icons.move_down))])));
  Widget _expiryBadge(BatchFefoModel b){final color=b.daysUntilExpiry<0?Colors.red:b.daysUntilExpiry<=30?Colors.deepOrange:b.daysUntilExpiry<=60?Colors.orange:b.daysUntilExpiry<=90?Colors.amber:Colors.green;return Chip(backgroundColor:color.withOpacity(.18),label:Text(b.daysUntilExpiry<0?'منتهي':b.daysUntilExpiry.toString()+' يوم',style:TextStyle(color:color,fontSize:11)));}
  Future<void> _moveShelf(BatchFefoModel batch)async{
    final p=context.read<InventoryAndPurchaseProvider>();final drugRows=await DatabaseHelper.instance.query('drugs',where:'id=?',whereArgs:[batch.drugId]);final cold=drugRows.isNotEmpty&&(drugRows.first['requires_refrigeration'] as int? ?? 0)==1;
    final options=p.shelves.where((s)=>s.warehouseId==batch.warehouseId&&(!cold||s.isFridge)).toList();if(options.isEmpty){_message('لا يوجد رف متوافق مع شروط تخزين هذا الدواء');return;}
    int selected=options.first.id;
    final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(title:const Text('نقل التشغيلة إلى رف'),content:DropdownButton<int>(value:selected,isExpanded:true,items:options.map((s)=>DropdownMenuItem(value:s.id,child:Text(s.code))).toList(),onChanged:(v)=>set(()=>selected=v??selected)),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('حفظ'))])));
    if(ok==true){final db=await DatabaseHelper.instance.database;await db.update('batches_fefo',{'location_id':selected},where:'id=?',whereArgs:[batch.id]);await p.loadAll();}
  }
  Future<void> _temperature(InventoryAndPurchaseProvider p)async{
    final fridges=p.warehouses.where((w)=>w.whType=='FRIDGE').toList();if(fridges.isEmpty){_message('لم يتم إعداد مستودع الثلاجة');return;}
    final temp=TextEditingController();final humidity=TextEditingController();final action=TextEditingController();int warehouse=fridges.first.id;
    final save=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(title:const Text('قراءة سلسلة التبريد'),content:Column(mainAxisSize:MainAxisSize.min,children:[DropdownButton<int>(value:warehouse,items:fridges.map((w)=>DropdownMenuItem(value:w.id,child:Text(w.nameAr))).toList(),onChanged:(v)=>set(()=>warehouse=v??warehouse)),TextField(controller:temp,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'الحرارة °م')),TextField(controller:humidity,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'الرطوبة %')),TextField(controller:action,decoration:const InputDecoration(labelText:'الإجراء التصحيحي'))]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('تسجيل'))])));
    if(save==true){final value=double.tryParse(temp.text);if(value==null){_message('أدخل درجة حرارة صحيحة');return;}await p.recordTemperature(warehouseId:warehouse,tempC:value,humidity:double.tryParse(humidity.text),action:action.text);_message(value<2||value>8?'تم تسجيل قراءة خارج النطاق الآمن':'تم تسجيل القراءة');}
  }
  Future<void> _movementCard(InventoryAndPurchaseProvider p)async{final rows=p.movements;if(rows.isEmpty){_message('لا توجد حركات مخزنية');return;}await showDialog<void>(context:context,builder:(c)=>AlertDialog(title:const Text('كارت حركة المخزون'),content:SizedBox(width:520,child:ListView.builder(shrinkWrap:true,itemCount:rows.length,itemBuilder:(c,i){final row=rows[i];return ListTile(title:Text(row['trade_name_ar'].toString()+' • '+row['batch_no'].toString()),subtitle:Text(row['movement_type'].toString()+' • '+row['movement_at'].toString()),trailing:Text(row['qty_units'].toString()+' حبة'));})),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('إغلاق'))]));}
  void _message(String value)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(value)));
}
