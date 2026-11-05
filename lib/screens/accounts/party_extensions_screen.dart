// lib/screens/accounts/party_extensions_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/database/database_helper.dart';
import '../../providers/session_and_erp_provider.dart';

class PartyExtensionsScreen extends StatefulWidget {
  const PartyExtensionsScreen({super.key});
  @override State<PartyExtensionsScreen> createState()=>_PartyExtensionsScreenState();
}
class _PartyExtensionsScreenState extends State<PartyExtensionsScreen> with SingleTickerProviderStateMixin{
  late final tabs=TabController(length:3,vsync:this);
  @override void dispose(){tabs.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Column(children:[TabBar(controller:tabs,tabs:const [Tab(text:'جدولة الأدوية المزمنة'),Tab(text:'مندوبي الشركات'),Tab(text:'المقاصة المالية')]),Expanded(child:TabBarView(controller:tabs,children:[_chronic(),_reps(),_settlements()]))]);
  Widget _chronic(){
    final p=context.watch<SessionAndErpProvider>();
    return FutureBuilder<List<Map<String,Object?>>>(future:DatabaseHelper.instance.rawQuery('SELECT s.*,p.name_ar customer_name,d.trade_name_ar drug_name FROM chronic_medication_schedules s JOIN parties p ON p.id=s.customer_party_id JOIN drugs d ON d.id=s.drug_id WHERE s.branch_id=? ORDER BY s.next_due_date',[p.branchId]),builder:(context,snapshot)=>ListView(padding:const EdgeInsets.all(12),children:[
      Row(children:[const Expanded(child:Text('مواعيد دورات الأدوية المزمنة',style:TextStyle(fontWeight:FontWeight.bold))),FilledButton(onPressed:()=>_addSchedule(p),child:const Text('جدولة دواء'))]),
      const Text('الصرف الفعلي يمر عبر الكاشير والفحص السريري وFEFO؛ الجدولة لا تخصم المخزون وحدها.',style:TextStyle(color:Colors.white60)),
      ...(snapshot.data??[]).map((r)=>Card(child:ListTile(title:Text('${r['customer_name']} • ${r['drug_name']}'),subtitle:Text('${r['quantity_units']} وحدة • كل ${r['cycle_days']} يوم • الاستحقاق ${r['next_due_date']}'),trailing:Text(r['status'].toString()))))
    ]));
  }
  Future<void> _addSchedule(SessionAndErpProvider p)async{
    final customers=p.parties.where((x)=>x.partyType=='CUSTOMER').toList();final drugs=await DatabaseHelper.instance.rawQuery('SELECT id,trade_name_ar FROM drugs WHERE branch_id=? AND is_deleted=0 AND is_active=1 ORDER BY trade_name_ar',[p.branchId]);if(customers.isEmpty||drugs.isEmpty)return;
    int customer=customers.first.id!,drug=drugs.first['id'] as int;final qty=TextEditingController(text:'1'),cycle=TextEditingController(text:'30'),due=TextEditingController(text:DateTime.now().add(const Duration(days:30)).toIso8601String().substring(0,10));
    await showDialog<void>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,set)=>AlertDialog(title:const Text('جدولة دواء مزمن'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      DropdownButtonFormField<int>(value:customer,items:customers.map((x)=>DropdownMenuItem(value:x.id,child:Text(x.nameAr))).toList(),onChanged:(v)=>set(()=>customer=v??customer)),
      DropdownButtonFormField<int>(value:drug,items:drugs.map((x)=>DropdownMenuItem(value:x['id'] as int,child:Text(x['trade_name_ar'].toString()))).toList(),onChanged:(v)=>set(()=>drug=v??drug)),
      TextField(controller:qty,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'الكمية بالحبات')),TextField(controller:cycle,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'مدة الدورة بالأيام')),TextField(controller:due,decoration:const InputDecoration(labelText:'موعد الدورة القادمة'))
    ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),FilledButton(onPressed:()async{try{await DatabaseHelper.instance.insert('chronic_medication_schedules',{'customer_party_id':customer,'drug_id':drug,'quantity_units':int.parse(qty.text),'cycle_days':int.parse(cycle.text),'next_due_date':due.text,'status':'ACTIVE','branch_id':p.branchId});if(ctx.mounted)Navigator.pop(ctx);if(mounted)setState((){});}catch(e){if(ctx.mounted)ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content:Text(e.toString())));}},child:const Text('حفظ'))])));
    qty.dispose();cycle.dispose();due.dispose();
  }
  Widget _reps(){
    final p=context.watch<SessionAndErpProvider>();
    return FutureBuilder<List<Map<String,Object?>>>(future:DatabaseHelper.instance.rawQuery("SELECT * FROM parties WHERE branch_id=? AND party_type='REPRESENTATIVE' AND is_deleted=0 ORDER BY name_ar",[p.branchId]),builder:(context,snapshot)=>ListView(padding:const EdgeInsets.all(12),children:[
      Row(children:[const Expanded(child:Text('مندوبي شركات الأدوية',style:TextStyle(fontWeight:FontWeight.bold))),FilledButton(onPressed:()=>_addRep(p),child:const Text('إضافة مندوب'))]),
      ...(snapshot.data??[]).map((r)=>FutureBuilder<List<Map<String,Object?>>>(future:DatabaseHelper.instance.query('representative_visit_days',where:'representative_party_id=?',whereArgs:[r['id']],orderBy:'weekday'),builder:(context,visits)=>Card(child:ListTile(title:Text(r['name_ar'].toString()),subtitle:Text((visits.data??[]).map((d)=>_day(d['weekday'] as int)).join(' • ').isEmpty?'لم تحدد أيام الزيارة':(visits.data??[]).map((d)=>_day(d['weekday'] as int)).join(' • ')),trailing:IconButton(onPressed:()=>_setVisits(r,visits.data??[]),icon:const Icon(Icons.edit_calendar))))))
    ]));
  }
  String _day(int n)=>['','الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت','الأحد'][n.clamp(1,7)];
  Future<void> _addRep(SessionAndErpProvider p)async{
    final name=TextEditingController(),code=TextEditingController(text:'REP-${DateTime.now().millisecondsSinceEpoch}'),phone=TextEditingController();
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:const Text('إضافة مندوب'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:name,decoration:const InputDecoration(labelText:'الاسم')),TextField(controller:code,decoration:const InputDecoration(labelText:'الكود')),TextField(controller:phone,decoration:const InputDecoration(labelText:'الهاتف'))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),FilledButton(onPressed:()async{await p.createParty(PartyModel(partyType:'REPRESENTATIVE',code:code.text,nameAr:name.text,phone:phone.text));if(ctx.mounted)Navigator.pop(ctx);if(mounted)setState((){});},child:const Text('حفظ'))]));
    name.dispose();code.dispose();phone.dispose();
  }
  Future<void> _setVisits(Map<String,Object?> rep,List<Map<String,Object?>> old)async{
    final selected=old.map((e)=>e['weekday'] as int).toSet();await showDialog<void>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,set)=>AlertDialog(title:Text('أيام زيارة ${rep['name_ar']}'),content:Wrap(children:[for(var day=1;day<=7;day++)SizedBox(width:130,child:CheckboxListTile(dense:true,value:selected.contains(day),title:Text(_day(day)),onChanged:(v)=>set((){if(v==true){selected.add(day);}else{selected.remove(day);}})))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),FilledButton(onPressed:()async{final db=await DatabaseHelper.instance.database;await db.delete('representative_visit_days',where:'representative_party_id=?',whereArgs:[rep['id']]);for(final d in selected){await db.insert('representative_visit_days',{'representative_party_id':rep['id'],'weekday':d});}if(ctx.mounted)Navigator.pop(ctx);if(mounted)setState((){});},child:const Text('حفظ'))])));
  }
  Widget _settlements(){
    final p=context.watch<SessionAndErpProvider>();final parties=p.parties.where((x)=>x.totalAlayh>0||x.totalLah>0).toList();return ListView(padding:const EdgeInsets.all(12),children:[
      const Text('المقاصة بين طرفين',style:TextStyle(fontWeight:FontWeight.bold,fontSize:17)),const Text('اختر طرفاً رصيده عليه وطرفاً رصيده له. تتم التسوية بقيود متوازنة دون حركة نقدية.'),
      FilledButton(onPressed:parties.length<2?null:()=>_settle(p,parties),child:const Text('إنشاء مقاصة')),
      FutureBuilder<List<Map<String,Object?>>>(future:DatabaseHelper.instance.rawQuery('SELECT s.*,a.name_ar source_name,b.name_ar target_name FROM party_settlements s JOIN parties a ON a.id=s.from_party_id JOIN parties b ON b.id=s.to_party_id WHERE s.branch_id=? ORDER BY s.id DESC',[p.branchId]),builder:(context,snapshot)=>Column(children:(snapshot.data??[]).map((r)=>ListTile(title:Text('${r['settlement_no']} • ${(r['amount'] as num).toStringAsFixed(2)}'),subtitle:Text('${r['source_name']} ⇄ ${r['target_name']}'))).toList()))
    ]);
  }
  Future<void> _settle(SessionAndErpProvider p,List<PartyModel> parties)async{
    int from=parties.firstWhere((x)=>x.totalAlayh>0,orElse:()=>parties.first).id!;int to=parties.firstWhere((x)=>x.totalLah>0,orElse:()=>parties.last).id!;final amount=TextEditingController(),note=TextEditingController(text:'مقاصة بين طرفين');
    await showDialog<void>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,set)=>AlertDialog(title:const Text('تسوية مالية'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      DropdownButtonFormField<int>(value:from,decoration:const InputDecoration(labelText:'الطرف الذي عليه رصيد'),items:parties.map((x)=>DropdownMenuItem(value:x.id,child:Text(x.nameAr))).toList(),onChanged:(v)=>set(()=>from=v??from)),
      DropdownButtonFormField<int>(value:to,decoration:const InputDecoration(labelText:'الطرف الذي له رصيد'),items:parties.map((x)=>DropdownMenuItem(value:x.id,child:Text(x.nameAr))).toList(),onChanged:(v)=>set(()=>to=v??to)),
      TextField(controller:amount,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'المبلغ')),TextField(controller:note,decoration:const InputDecoration(labelText:'البيان'))
    ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),FilledButton(onPressed:()async{try{final v=double.parse(amount.text);final db=await DatabaseHelper.instance.database;await db.transaction((tx)async{final balances=await tx.rawQuery('SELECT party_id,net FROM v_party_balance WHERE party_id IN(?,?)',[from,to]);final a=(balances.firstWhere((x)=>x['party_id']==from)['net'] as num).toDouble(),b=(balances.firstWhere((x)=>x['party_id']==to)['net'] as num).toDouble();if(from==to||a<=0||b>=0||v>a||v>b.abs())throw StateError('تحقق من الطرفين ومبلغ المقاصة');final now=DateTime.now().toIso8601String();final je=await tx.insert('journal_entries',{'uuid':'offset-je-${DateTime.now().microsecondsSinceEpoch}','branch_id':p.branchId,'created_at':now,'updated_at':now,'entry_no':'OFFSET-${DateTime.now().millisecondsSinceEpoch}','entry_date':now,'description':note.text,'source_type':'PARTY_SETTLEMENT','is_posted':1});final ar=(await tx.query('chart_of_accounts',columns:['id'],where:"code='1201'",limit:1)).first['id'] as int,ap=(await tx.query('chart_of_accounts',columns:['id'],where:"code='2101'",limit:1)).first['id'] as int;await tx.insert('journal_lines',{'uuid':'offset-line-a-${DateTime.now().microsecondsSinceEpoch}','branch_id':p.branchId,'created_at':now,'updated_at':now,'journal_entry_id':je,'account_id':ap,'party_id':to,'dr_amount':v,'cr_amount':0,'memo':note.text});await tx.insert('journal_lines',{'uuid':'offset-line-b-${DateTime.now().microsecondsSinceEpoch}','branch_id':p.branchId,'created_at':now,'updated_at':now,'journal_entry_id':je,'account_id':ar,'party_id':from,'dr_amount':0,'cr_amount':v,'memo':note.text});for(final row in [{'party_id':from,'alayh_amount':0,'lah_amount':v},{'party_id':to,'alayh_amount':v,'lah_amount':0}]){await tx.insert('lah_alayh_ledger',{'uuid':'offset-ledger-${DateTime.now().microsecondsSinceEpoch}-${row['party_id']}','branch_id':p.branchId,'created_at':now,'updated_at':now,'party_id':row['party_id'],'entry_date':now,'entry_type':'SETTLEMENT','alayh_amount':row['alayh_amount'],'lah_amount':row['lah_amount'],'doc_type':'SETTLEMENT','doc_id':je,'journal_entry_id':je,'statement_ar':note.text});}await tx.insert('party_settlements',{'settlement_no':'OFFSET-${DateTime.now().millisecondsSinceEpoch}','from_party_id':from,'to_party_id':to,'amount':v,'settlement_date':now,'note':note.text,'journal_entry_id':je,'branch_id':p.branchId});});if(ctx.mounted)Navigator.pop(ctx);await p.refresh();if(mounted)setState((){});}catch(e){if(ctx.mounted)ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content:Text(e.toString())));}},child:const Text('اعتماد المقاصة'))])));
    amount.dispose();note.dispose();
  }
}
