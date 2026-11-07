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
  final searchController=TextEditingController();
  String query='';
  @override void dispose(){searchController.dispose();super.dispose();}
  @override void initState(){super.initState();WidgetsBinding.instance.addPostFrameCallback((_)=>context.read<InventoryAndPurchaseProvider>().loadAll());}
  @override Widget build(BuildContext context){
    final p=context.watch<InventoryAndPurchaseProvider>();
    return Padding(
      padding:const EdgeInsets.all(12),
      child:Column(children:[
        Row(children:[
          const Expanded(child:Text('المخزون والتشغيلات والأرفف',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold))),
          IconButton(onPressed:()=>_manageShelves(p),icon:const Icon(Icons.grid_view),tooltip:'إدارة مواقع الأرفف'),
          IconButton(onPressed:()=>_temperature(p),icon:const Icon(Icons.thermostat),tooltip:'تسجيل حرارة الثلاجة'),
          IconButton(onPressed:()=>_movementCard(p),icon:const Icon(Icons.receipt_long),tooltip:'كارت حركة الصنف'),
        ]),
        CompactSearchAndFilterBar(
          controller:searchController,
          hintText:'ابحث باسم الدواء أو رقم التشغيلة أو الرف',
          onChanged:(value)=>setState(()=>query=value.trim().toLowerCase()),
          activeFilterCount:byDrug?0:1,
          onFilter:()=>setState(()=>byDrug=!byDrug),
        ),
        const SizedBox(height:8),
        SegmentedButton<bool>(
          segments:const [
            ButtonSegment(value:true,label:Text('حسب الصنف')),
            ButtonSegment(value:false,label:Text('حسب التشغيلة')),
          ],
          selected:{byDrug},
          onSelectionChanged:(value)=>setState(()=>byDrug=value.first),
        ),
        const SizedBox(height:8),
        if(p.error!=null)Text(p.error!,style:const TextStyle(color:Colors.redAccent)),
        Expanded(
          child:p.loading
            ?const Center(child:CircularProgressIndicator())
            :byDrug?_drugList(p):_batchList(p),
        ),
      ]),
    );
  }
  Widget _drugList(InventoryAndPurchaseProvider p){
    final groups=<int,List<BatchFefoModel>>{};
    for(final batch in p.batches){
      if(query.isNotEmpty&&
        !batch.drugName.toLowerCase().contains(query)&&
        !batch.batchNo.toLowerCase().contains(query)&&
        !batch.shelfCode.toLowerCase().contains(query))continue;
      groups.putIfAbsent(batch.drugId,()=>[]).add(batch);
    }
    if(groups.isEmpty)return const Center(child:Text('لا توجد تشغيلات مطابقة للبحث.'));
    return ListView.builder(
      keyboardDismissBehavior:ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount:groups.length,
      itemBuilder:(context,index){
        final entry=groups.entries.elementAt(index);
        final batches=entry.value;
        final first=batches.first;
        final total=batches.fold<int>(0,(sum,batch)=>sum+batch.totalUnits);
        return SmartExpandableCard(
          title:first.drugName,
          primary:'$total حبة متاحة',
          secondary:'${batches.length} تشغيلات',
          leading:const CircleAvatar(
            backgroundColor:Color(0x224DB6AC),
            child:Icon(Icons.inventory_2_outlined,color:Color(0xFF4DB6AC)),
          ),
          details:batches.map(_batchTile).toList(),
        );
      },
    );
  }

  Widget _batchList(InventoryAndPurchaseProvider p){
    final batches=p.batches.where((batch)=>query.isEmpty||
      batch.drugName.toLowerCase().contains(query)||
      batch.batchNo.toLowerCase().contains(query)||
      batch.shelfCode.toLowerCase().contains(query)).toList();
    if(batches.isEmpty)return const Center(child:Text('لا توجد تشغيلات مطابقة للبحث.'));
    return ListView.builder(
      keyboardDismissBehavior:ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount:batches.length,
      itemBuilder:(context,index)=>_batchTile(batches[index]),
    );
  }

  Widget _batchTile(BatchFefoModel batch){
    final coldColor=batch.daysUntilExpiry<0?Colors.red:
      batch.daysUntilExpiry<=30?Colors.deepOrange:
      batch.daysUntilExpiry<=60?Colors.orange:
      batch.daysUntilExpiry<=90?Colors.amber:Colors.green;
    return SmartExpandableCard(
      title:'${batch.drugName} — ${batch.batchNo}',
      primary:'${batch.totalUnits} حبة',
      secondary:'الصلاحية ${batch.expiryDate}',
      leading:const Icon(Icons.qr_code_2,color:Color(0xFF4DB6AC)),
      trailing:Chip(
        backgroundColor:coldColor.withOpacity(.16),
        label:Text(batch.daysUntilExpiry<0?'منتهي':'${batch.daysUntilExpiry} يوم',
          style:TextStyle(color:coldColor,fontSize:11)),
      ),
      details:[
        Text('باكتات مغلقة: ${batch.sealedPacks} • حبات سائبة: ${batch.looseUnits}'),
        Text('التكلفة: ${batch.packCost.toStringAsFixed(2)}'),
        Text('موقع الرف: ${batch.shelfCode.isEmpty?'غير محدد':batch.shelfCode}'),
      ],
      actions:[
        OutlinedButton.icon(
          onPressed:()=>_moveShelf(batch),
          icon:const Icon(Icons.move_down),
          label:const Text('نقل إلى رف'),
        ),
      ],
    );
  }

  Widget _expiryBadge(BatchFefoModel b){final color=b.daysUntilExpiry<0?Colors.red:b.daysUntilExpiry<=30?Colors.deepOrange:b.daysUntilExpiry<=60?Colors.orange:b.daysUntilExpiry<=90?Colors.amber:Colors.green;return Chip(backgroundColor:color.withOpacity(.18),label:Text(b.daysUntilExpiry<0?'منتهي':b.daysUntilExpiry.toString()+' يوم',style:TextStyle(color:color,fontSize:11)));}
  Future<void> _moveShelf(BatchFefoModel batch)async{
    final p=context.read<InventoryAndPurchaseProvider>();final drugRows=await DatabaseHelper.instance.query('drugs',where:'id=?',whereArgs:[batch.drugId]);final cold=drugRows.isNotEmpty&&(drugRows.first['requires_refrigeration'] as int? ?? 0)==1;
    final options=p.shelves.where((s)=>s.warehouseId==batch.warehouseId&&(!cold||s.isFridge)).toList();if(options.isEmpty){_message('لا يوجد رف متوافق مع شروط تخزين هذا الدواء');return;}
    int selected=options.first.id;
    final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(title:const Text('نقل التشغيلة إلى رف'),content:DropdownButton<int>(value:selected,isExpanded:true,items:options.map((s)=>DropdownMenuItem(value:s.id,child:Text(s.code))).toList(),onChanged:(v)=>set(()=>selected=v??selected)),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('حفظ'))])));
    if(ok==true){final db=await DatabaseHelper.instance.database;await db.update('batches_fefo',{'location_id':selected},where:'id=?',whereArgs:[batch.id]);await p.loadAll();}
  }
  Future<void> _manageShelves(InventoryAndPurchaseProvider p)async{
    if(p.warehouses.isEmpty){_message('أضف مستودعاً أولاً');return;}
    final code=TextEditingController();final description=TextEditingController();
    int warehouse=p.warehouses.first.id;bool isFridge=p.warehouses.first.whType=='FRIDGE';
    final saved=await showDialog<bool>(context:context,builder:(dialogContext)=>StatefulBuilder(builder:(dialogContext,setDialog)=>AlertDialog(
      title:const Text('إدارة مواقع الأرفف'),
      content:SizedBox(width:420,height:MediaQuery.sizeOf(context).height*.65,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<int>(value:warehouse,decoration:const InputDecoration(labelText:'المستودع'),items:p.warehouses.map((w)=>DropdownMenuItem(value:w.id,child:Text(w.nameAr))).toList(),onChanged:(value)=>setDialog((){warehouse=value??warehouse;isFridge=p.warehouses.firstWhere((w)=>w.id==warehouse).whType=='FRIDGE';})),
        TextField(controller:code,decoration:const InputDecoration(labelText:'رمز الرف مثال A-01-02')),
        TextField(controller:description,decoration:const InputDecoration(labelText:'الوصف')),
        SwitchListTile(value:isFridge,onChanged:p.warehouses.firstWhere((w)=>w.id==warehouse).whType=='FRIDGE'?null:(value)=>setDialog(()=>isFridge=value),title:const Text('رف مبرد')),
        const Divider(),
        const Text('الأرفف الحالية'),
        ...p.shelves.where((s)=>s.warehouseId==warehouse).map((s)=>ListTile(dense:true,title:Text(s.code),subtitle:Text(s.description),trailing:Icon(s.isFridge?Icons.ac_unit:Icons.inventory_2))),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('إغلاق')),FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('إضافة رف'))],
    )));
    if(saved==true){
      final normalized=code.text.trim().toUpperCase();
      if(normalized.isEmpty){_message('أدخل رمز الرف');}
      else{
        try{
          final selectedWarehouse=p.warehouses.firstWhere((w)=>w.id==warehouse);
          if(selectedWarehouse.whType=='FRIDGE'&&!isFridge)throw StateError('مستودع الثلاجة يتطلب أرففاً مبردة');
          await DatabaseHelper.instance.insert('shelf_locations',{'warehouse_id':warehouse,'code':normalized,'description':description.text.trim(),'is_fridge':isFridge?1:0});
          await p.loadAll();_message('تمت إضافة موقع الرف');
        }catch(error){_message(error.toString());}
      }
    }
    code.dispose();description.dispose();
  }
  Future<void> _temperature(InventoryAndPurchaseProvider p)async{
    final fridges=p.warehouses.where((w)=>w.whType=='FRIDGE').toList();if(fridges.isEmpty){_message('لم يتم إعداد مستودع الثلاجة');return;}
    final temp=TextEditingController();final humidity=TextEditingController();final action=TextEditingController();int warehouse=fridges.first.id;
    final save=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(title:const Text('قراءة سلسلة التبريد'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[DropdownButton<int>(value:warehouse,items:fridges.map((w)=>DropdownMenuItem(value:w.id,child:Text(w.nameAr))).toList(),onChanged:(v)=>set(()=>warehouse=v??warehouse)),TextField(controller:temp,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'الحرارة °م')),TextField(controller:humidity,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'الرطوبة %')),TextField(controller:action,decoration:const InputDecoration(labelText:'الإجراء التصحيحي'))])),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('تسجيل'))])));
    if(save==true){final value=double.tryParse(temp.text);if(value==null){_message('أدخل درجة حرارة صحيحة');return;}await p.recordTemperature(warehouseId:warehouse,tempC:value,humidity:double.tryParse(humidity.text),action:action.text);_message(value<2||value>8?'تم تسجيل قراءة خارج النطاق الآمن':'تم تسجيل القراءة');}
  }
  Future<void> _movementCard(InventoryAndPurchaseProvider p)async{final rows=p.movements;if(rows.isEmpty){_message('لا توجد حركات مخزنية');return;}await showDialog<void>(context:context,builder:(c)=>AlertDialog(title:const Text('كارت حركة المخزون'),content:SizedBox(width:520,child:ListView.builder(shrinkWrap:true,itemCount:rows.length,itemBuilder:(c,i){final row=rows[i];return ListTile(title:Text(row['trade_name_ar'].toString()+' • '+row['batch_no'].toString()),subtitle:Text(row['movement_type'].toString()+' • '+row['movement_at'].toString()),trailing:Text(row['qty_units'].toString()+' حبة'));})),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('إغلاق'))]));}
  void _message(String value)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(value)));
}
