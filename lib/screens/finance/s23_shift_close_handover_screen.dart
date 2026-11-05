// lib/screens/finance/s23_shift_close_handover_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/database/database_helper.dart';
import '../../providers/treasury_hr_partner_provider.dart';

class S23ShiftCloseHandoverScreen extends StatefulWidget {
  const S23ShiftCloseHandoverScreen({super.key});
  @override State<S23ShiftCloseHandoverScreen> createState()=>_S23ShiftCloseHandoverScreenState();
}
class _S23ShiftCloseHandoverScreenState extends State<S23ShiftCloseHandoverScreen>{
  static const denominations=[1000,500,200,100,50,20,10];
  late final Map<int,TextEditingController> counts={for(final d in denominations)d:TextEditingController(text:'0')};
  final walletCounts=<int,TextEditingController>{};String handling='POST_TO_CASHIER';double? expected,difference;int? nextUserId,treasuryId;List<Map<String,Object?>> users=[];
  double get actual=>counts.entries.fold(0,(s,e)=>s+e.key*(int.tryParse(e.value.text)??0));
  @override void dispose(){for(final c in counts.values)c.dispose();for(final c in walletCounts.values)c.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final p=context.watch<TreasuryHrPartnerProvider>();final shift=p.activeShift;
    return Scaffold(backgroundColor:Colors.transparent,body:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('إغلاق الوردية واستلام وتسليم العهدة',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      const SizedBox(height:12),
      if(shift==null)_openShift(context,p) else ...[
        Card(child:ListTile(leading:const Icon(Icons.lock_clock,color:Color(0xFF4DB6AC)),title:Text('وردية رقم ${shift.shiftNo}'),subtitle:Text('بدأت: ${shift.openedAt}'),trailing:const Chip(label:Text('مفتوحة')))),
        const Text('عدّ الفئات النقدية — الإغلاق الأعمى',style:TextStyle(fontSize:17,fontWeight:FontWeight.bold)),
        const Text('لن يظهر النقد المتوقع قبل إدخال العد الفعلي.',style:TextStyle(color:Colors.white60)),
        const SizedBox(height:8),
        Wrap(spacing:10,runSpacing:10,children:denominations.map((d)=>SizedBox(width:130,child:TextField(controller:counts[d],keyboardType:TextInputType.number,decoration:InputDecoration(labelText:'فئة $d',suffixText:'عدد'),onChanged:(_)=>setState(()=>difference=null)))).toList()),
        Card(child:ListTile(title:const Text('إجمالي النقد المعدود'),trailing:Text(actual.toStringAsFixed(2),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold,color:Color(0xFF66BB6A))))),
        const SizedBox(height:12),const Text('مطابقة إشعارات المحافظ',style:TextStyle(fontWeight:FontWeight.bold)),
        ...p.cashAccounts.where((a)=>a['account_kind']=='WALLET').map((a){final id=a['id'] as int;walletCounts.putIfAbsent(id,()=>TextEditingController(text:(a['current_balance'] as num).toString()));return TextField(controller:walletCounts[id],keyboardType:TextInputType.number,decoration:InputDecoration(labelText:'الرصيد المعدود — ${a['name_ar']}'));}),
        const SizedBox(height:12),
        DropdownButtonFormField<String>(value:handling,decoration:const InputDecoration(labelText:'معالجة فرق الصندوق'),items:const [DropdownMenuItem(value:'POST_TO_CASHIER',child:Text('ترحيل الفرق على حساب الكاشير')),DropdownMenuItem(value:'SUSPENSE',child:Text('تعليق العجز للمراجعة')),DropdownMenuItem(value:'NONE',child:Text('إغلاق دون ترحيل آلي'))],onChanged:(v)=>setState(()=>handling=v??handling)),
        FilledButton.icon(onPressed:()async{final e=await p.expectedCash(shift.id!);setState((){expected=e;difference=((actual-e)*100).roundToDouble()/100;});},icon:const Icon(Icons.calculate),label:const Text('إظهار نتيجة المطابقة بعد العد')),
        if(expected!=null)Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('النقد المتوقع: ${expected!.toStringAsFixed(2)}'),Text('النقد الفعلي: ${actual.toStringAsFixed(2)}'),
          Text(difference!.abs()<0.005?'مطابق ✔':difference!<0?'عجز: ${difference!.abs().toStringAsFixed(2)}':'زيادة: ${difference!.toStringAsFixed(2)}',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold,color:difference!.abs()<0.005?const Color(0xFF66BB6A):difference!<0?const Color(0xFFEF5350):const Color(0xFF66BB6A))),
          if(difference!<0&&handling=='POST_TO_CASHIER')Text('سيُسجَّل على ${p.employees.firstWhere((e)=>e['party_id']==shift.cashierPartyId,orElse:()=>{'name_ar':'الكاشير'})['name_ar']}: عليه ${difference!.abs().toStringAsFixed(2)}',style:const TextStyle(color:Color(0xFFEF5350)))
        ]))),
        const SizedBox(height:12),
        FutureBuilder<List<Map<String,Object?>>>(future:DatabaseHelper.instance.query('users',where:'branch_id=? AND is_active=1 AND is_deleted=0',whereArgs:[p.branchId]),builder:(context,snapshot){users=snapshot.data??users;return DropdownButtonFormField<int?>(value:nextUserId,decoration:const InputDecoration(labelText:'تسليم الوردية إلى كاشير آخر (اختياري)'),items:[const DropdownMenuItem<int?>(value:null,child:Text('إغلاق / توريد للخزينة')), ...users.where((u)=>u['id']!=shift.userId).map((u)=>DropdownMenuItem<int?>(value:u['id'] as int,child:Text(u['full_name'].toString())))],onChanged:(v)=>setState(()=>nextUserId=v));}),
        if(nextUserId==null)DropdownButtonFormField<int?>(value:treasuryId,decoration:const InputDecoration(labelText:'التوريد إلى الخزينة الرئيسية (اختياري)'),items:[const DropdownMenuItem<int?>(value:null,child:Text('لا تنفذ تحويل آلي')), ...p.cashAccounts.where((a)=>a['account_kind']=='MAIN_SAFE').map((a)=>DropdownMenuItem<int?>(value:a['id'] as int,child:Text(a['name_ar'].toString())))],onChanged:(v)=>setState(()=>treasuryId=v)),
        FilledButton.icon(onPressed:expected==null?null:()async{try{final wallets={for(final e in walletCounts.entries)e.key.toString():double.tryParse(e.value.text)??0};await p.closeShift(shiftId:shift.id!,denominations:{for(final e in counts.entries)e.key.toString():int.tryParse(e.value.text)??0},handling:handling,wallets:wallets,nextUserId:nextUserId);if(nextUserId==null&&treasuryId!=null&&actual>0){final drawer=shift.drawerAccountId!;await p.transfer(fromAccountId:drawer,toAccountId:treasuryId!,amount:actual,note:'توريد عهدة وردية ${shift.shiftNo}');}if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم اعتماد إغلاق الوردية')));}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}},icon:const Icon(Icons.verified),label:const Text('اعتماد إغلاق الوردية'))
      ]
    ]));
  }
  Widget _openShift(BuildContext context,TreasuryHrPartnerProvider p){
    int? drawer=p.cashAccounts.firstWhere((a)=>a['account_kind']=='CASHIER_DRAWER',orElse:()=>p.cashAccounts.isEmpty?{'id':null}:p.cashAccounts.first)['id'] as int?;int? work=p.workShifts.isEmpty?null:p.workShifts.first['id'] as int?;final opening=TextEditingController(text:'0');
    return Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[
      const Text('لا توجد وردية مفتوحة. افتح وردية جديدة لاستلام العهدة.'),
      DropdownButtonFormField<int?>(value:drawer,decoration:const InputDecoration(labelText:'درج الكاشير'),items:p.cashAccounts.map((a)=>DropdownMenuItem<int?>(value:a['id'] as int,child:Text(a['name_ar'].toString()))).toList(),onChanged:(v)=>setState(()=>drawer=v)),
      DropdownButtonFormField<int?>(value:work,decoration:const InputDecoration(labelText:'الوردية الوظيفية'),items:p.workShifts.map((a)=>DropdownMenuItem<int?>(value:a['id'] as int,child:Text(a['name_ar'].toString()))).toList(),onChanged:(v)=>setState(()=>work=v)),
      TextField(controller:opening,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'العهدة الافتتاحية')),
      FilledButton(onPressed:drawer==null?null:()async{try{await p.openShift(drawerAccountId:drawer!,openingCash:double.tryParse(opening.text)??0,workShiftId:work);if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم فتح الوردية')));}catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}},child:const Text('فتح الوردية'))
    ])));
  }
}
