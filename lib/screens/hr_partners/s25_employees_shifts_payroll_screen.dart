// lib/screens/hr_partners/s25_employees_shifts_payroll_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/database/database_helper.dart';
import '../../providers/treasury_hr_partner_provider.dart';
import '../../providers/session_and_erp_provider.dart';
import '../../core/widgets/shared_widgets.dart';

class S25EmployeesShiftsPayrollScreen extends StatefulWidget {
  const S25EmployeesShiftsPayrollScreen({super.key});
  @override State<S25EmployeesShiftsPayrollScreen> createState()=>_S25EmployeesShiftsPayrollScreenState();
}
class _S25EmployeesShiftsPayrollScreenState extends State<S25EmployeesShiftsPayrollScreen> with SingleTickerProviderStateMixin{
  late final tabs=TabController(length:3,vsync:this);String period=DateTime.now().toIso8601String().substring(0,7);int? selectedEmployee;
  @override void dispose(){tabs.dispose();super.dispose();}
  @override Widget build(BuildContext context){final p=context.watch<TreasuryHrPartnerProvider>();return Scaffold(backgroundColor:Colors.transparent,body:Column(children:[
    const Padding(padding:EdgeInsets.all(16),child:Align(alignment:Alignment.centerRight,child:Text('شؤون الموظفين والرواتب',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)))),
    TabBar(controller:tabs,tabs:const [Tab(text:'الموظفون والحسابات'),Tab(text:'المناوبات والحضور'),Tab(text:'مسير الرواتب')]),
    Expanded(child:TabBarView(controller:tabs,children:[_employees(p),_attendance(p),_payroll(p)]))
  ]));}
  Widget _employees(TreasuryHrPartnerProvider p)=>ListView(padding:const EdgeInsets.all(12),children:p.employees.map((e){
    final lah=(e['total_lah'] as num).toDouble(),alayh=(e['total_alayh'] as num).toDouble(),net=lah-alayh;
    return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Expanded(child:Text(e['name_ar'].toString(),style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16))),Chip(label:Text(e['pay_type']=='DAILY'?'أجر يومي':'راتب شهري'))]),
      Text('الوظيفة: ${e['job_title']} • الأجر: ${(e['pay_rate'] as num).toStringAsFixed(2)}'),
      PartyBalanceChip(totalAlayh:alayh,totalLah:lah,compact:true),
      Wrap(spacing:8,children:[
        TextButton.icon(onPressed:()=>_statement(e),icon:const Icon(Icons.receipt_long),label:const Text('كشف الحساب')),
        TextButton.icon(onPressed:()=>_advance(p,e),icon:const Icon(Icons.payments),label:const Text('صرف سلفة (عليه)')),
        TextButton.icon(onPressed:()=>_adjust(p,e,true),icon:const Icon(Icons.add_circle_outline),label:const Text('مكافأة (له)')),
        TextButton.icon(onPressed:()=>_adjust(p,e,false),icon:const Icon(Icons.remove_circle_outline),label:const Text('خصم / جزاء (عليه)'))
      ])
    ])));
  }).toList());
  Widget _attendance(TreasuryHrPartnerProvider p){
    final today=DateTime.now().toIso8601String().substring(0,10);
    return ListView(padding:const EdgeInsets.all(12),children:[
      Text('تسجيل حضور بتاريخ $today'),
      ...p.employees.map((e)=>Card(child:ListTile(title:Text(e['name_ar'].toString()),subtitle:Text(e['job_title'].toString()),trailing:FilledButton.tonal(onPressed:()=>p.registerAttendance(employeeId:e['id'] as int,date:today,status:'PRESENT',shiftId:p.workShifts.isEmpty?null:p.workShifts.first['id'] as int).then((_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تم تسجيل حضور ${e['name_ar']} وإثبات اليومية إن كان الأجر يومياً')));}),child:const Text('حاضر'))))),
      const SizedBox(height:10),FilledButton.icon(onPressed:()async{for(final e in p.employees.where((x)=>x['pay_type']=='DAILY')){await p.registerAttendance(employeeId:e['id'] as int,date:today,status:'PRESENT',shiftId:p.workShifts.isEmpty?null:p.workShifts.first['id'] as int);}if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم إثبات يوميات العمال الحاضرين')));},icon:const Icon(Icons.done_all),label:const Text('إثبات يومية العمال الحاضرين'))
    ]);
  }
  Widget _payroll(TreasuryHrPartnerProvider p){
    return ListView(padding:const EdgeInsets.all(12),children:[
      TextField(decoration:InputDecoration(labelText:'الفترة (YYYY-MM)',hintText:period),controller:TextEditingController(text:period),onChanged:(v)=>period=v),
      DropdownButtonFormField<int>(value:selectedEmployee,decoration:const InputDecoration(labelText:'الموظف'),items:p.employees.map((e)=>DropdownMenuItem(value:e['id'] as int,child:Text(e['name_ar'].toString()))).toList(),onChanged:(v)=>setState(()=>selectedEmployee=v)),
      FilledButton(onPressed:selectedEmployee==null?null:()async{try{await p.generatePayroll(employeeId:selectedEmployee!,period:period);if(mounted)setState((){});}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}},child:const Text('توليد مسير الراتب')),
      const SizedBox(height:10),
      FutureBuilder<List<Map<String,Object?>>>(future:DatabaseHelper.instance.rawQuery('SELECT r.*,p.name_ar FROM payroll_runs r JOIN employees e ON e.id=r.employee_id JOIN parties p ON p.id=e.party_id WHERE substr(r.period_code,1,7)=? ORDER BY r.id DESC',[period]),builder:(context,snapshot){
        final rows=snapshot.data??[];
        return Column(children:rows.map((r){final lah=(r['gross_lah'] as num).toDouble()+(r['bonuses_lah'] as num).toDouble();final alayh=(r['advances_alayh'] as num).toDouble()+(r['deductions_alayh'] as num).toDouble();return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(r['name_ar'].toString(),style:const TextStyle(fontWeight:FontWeight.bold)),Text('الاستحقاق والإضافي (له): ${lah.toStringAsFixed(2)}'),Text('السلف والخصومات (عليه): ${alayh.toStringAsFixed(2)}'),Text('الصافي المستحق للصرف: ${(r['net_amount'] as num).toStringAsFixed(2)}',style:const TextStyle(color:Color(0xFF66BB6A),fontWeight:FontWeight.bold)),Text('الحالة: ${r['status']}'),
          Wrap(children:[if(r['status']=='DRAFT')TextButton(onPressed:()async{await p.approvePayroll(r['id'] as int);setState((){});},child:const Text('اعتماد المسير')),if(r['status']=='APPROVED')TextButton(onPressed:()async{try{final cash=p.cashAccounts.firstWhere((a)=>a['account_kind']=='CASHIER_DRAWER',orElse:()=>p.cashAccounts.first);await p.payPayroll(id:r['id'] as int,cashAccountId:cash['id'] as int);if(mounted)setState((){});}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}},child:const Text('صرف الصافي'))])
        ])));}).toList());
      })
    ]);
  }
  Future<void> _statement(Map<String,Object?> employee)async{
    final entries=await DatabaseHelper.instance.rawQuery('SELECT entry_date,entry_type,alayh_amount,lah_amount,statement_ar,doc_type,doc_id FROM lah_alayh_ledger WHERE party_id=? ORDER BY entry_date,id',[employee['party_id']]);
    if(!mounted)return;
    final rows=entries.map((r)=>LahAlayhRow(date:r['entry_date'].toString().split('T').first,statement:r['statement_ar'].toString(),document:'${r['doc_type']} #${r['doc_id']??''}',alayh:(r['alayh_amount'] as num),lah:(r['lah_amount'] as num))).toList();
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:Text('كشف حساب • ${employee['name_ar']}'),content:SizedBox(width:850,height:480,child:LahAlayhTable(rows:rows)),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إغلاق'))]));
  }
  Future<void> _advance(TreasuryHrPartnerProvider p,Map<String,Object?> employee)async{
    final amount=TextEditingController();final session=context.read<SessionAndErpProvider>();bool manager=false;
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:const Text('صرف سلفة موظف'),content:TextField(controller:amount,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'مبلغ السلفة')),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),FilledButton(onPressed:()async{try{final cash=p.cashAccounts.firstWhere((a)=>a['account_kind']=='CASHIER_DRAWER',orElse:()=>p.cashAccounts.first);await p.advance(employeeId:employee['id'] as int,cashAccountId:cash['id'] as int,amount:double.parse(amount.text),managerApproved:manager);if(ctx.mounted)Navigator.pop(ctx);}catch(e){if(e.toString().contains('سقف المسموح')&&ctx.mounted){final pin=TextEditingController();final ok=await showDialog<bool>(context:ctx,builder:(d)=>AlertDialog(title:const Text('اعتماد المدير'),content:TextField(controller:pin,obscureText:true,decoration:const InputDecoration(labelText:'رمز المدير')),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('إلغاء')),FilledButton(onPressed:()async{final valid=await session.verifyManagerPin(pin.text);if(d.mounted)Navigator.pop(d,valid);},child:const Text('تحقق'))]));pin.dispose();if(ok==true){manager=true;try{final cash=p.cashAccounts.firstWhere((a)=>a['account_kind']=='CASHIER_DRAWER',orElse:()=>p.cashAccounts.first);await p.advance(employeeId:employee['id'] as int,cashAccountId:cash['id'] as int,amount:double.parse(amount.text),managerApproved:true);if(ctx.mounted)Navigator.pop(ctx);}catch(err){if(ctx.mounted)ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content:Text(err.toString())));}}}else if(ctx.mounted)ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content:Text(e.toString())));}},child:const Text('صرف'))]));
    amount.dispose();
  }
  Future<void> _adjust(TreasuryHrPartnerProvider p,Map<String,Object?> employee,bool bonus)async{
    final amount=TextEditingController();final reason=TextEditingController();
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:Text(bonus?'تسجيل مكافأة':'تسجيل خصم أو جزاء'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:amount,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'المبلغ')),TextField(controller:reason,decoration:const InputDecoration(labelText:'السبب / البيان'))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),FilledButton(onPressed:()async{try{await p.adjustment(employeeId:employee['id'] as int,amount:double.parse(amount.text),bonus:bonus,reason:reason.text);if(ctx.mounted)Navigator.pop(ctx);}catch(e){if(ctx.mounted)ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content:Text(e.toString())));}},child:const Text('حفظ'))]));
    amount.dispose();reason.dispose();
  }
}
