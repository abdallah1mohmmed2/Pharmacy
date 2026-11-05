// lib/screens/pos/s06_prescription_insurance_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/drug_model.dart';
import '../../providers/clinical_and_rx_provider.dart';
import '../../providers/pos_and_drugs_provider.dart';
import '../../providers/session_and_erp_provider.dart';
import 's04_clinical_guard_dialog.dart';

class S06PrescriptionInsuranceScreen extends StatefulWidget {
  const S06PrescriptionInsuranceScreen({super.key});
  @override State<S06PrescriptionInsuranceScreen> createState()=>_S06PrescriptionInsuranceScreenState();
}
class _S06PrescriptionInsuranceScreenState extends State<S06PrescriptionInsuranceScreen>{
  final rxNo=TextEditingController(),doctor=TextEditingController(),license=TextEditingController(),facility=TextEditingController(),validDays=TextEditingController(text:'30'),refillsAllowed=TextEditingController(text:'0'),qty=TextEditingController(text:'1'),dose=TextEditingController(),duration=TextEditingController(text:'1'),paid=TextEditingController(text:'0'),walletRef=TextEditingController();
  int? patientId,policyId,drugId,cashId,selectedRxId;String type='NORMAL',paymentMethod='CASH';List<Map<String,Object?>> rxRows=[],rxItems=[],alertRows=[],controlledRows=[];bool saving=false;
  @override void initState(){super.initState();WidgetsBinding.instance.addPostFrameCallback((_)async{await context.read<ClinicalAndRxProvider>().loadAll();await _load();});}
  @override void dispose(){for(final x in [rxNo,doctor,license,facility,validDays,refillsAllowed,qty,dose,duration,paid,walletRef]){x.dispose();}super.dispose();}
  Future<void> _load()async{
    final db=await DatabaseHelper.instance.database;
    final rows=await db.rawQuery('SELECT r.*,p.full_name FROM prescriptions r JOIN patients p ON p.id=r.patient_id ORDER BY r.id DESC LIMIT 100');
    final alerts=await db.rawQuery('SELECT l.*,d.trade_name_ar,p.full_name FROM clinical_alert_logs l LEFT JOIN drugs d ON d.id=l.drug_id LEFT JOIN patients p ON p.id=l.patient_id ORDER BY l.id DESC LIMIT 100');
    final controlled=await db.rawQuery('SELECT c.*,d.trade_name_ar FROM controlled_drug_log c JOIN drugs d ON d.id=c.drug_id ORDER BY c.id DESC LIMIT 100');
    if(mounted)setState((){rxRows=rows;alertRows=alerts;controlledRows=controlled;});
  }
  Future<void> _selectRx(int id)async{
    final rows=await DatabaseHelper.instance.rawQuery('SELECT i.*,d.trade_name_ar,d.sell_price_unit,d.is_controlled,d.category_id FROM prescription_items i JOIN drugs d ON d.id=i.drug_id WHERE i.prescription_id=? ORDER BY i.id',[id]);
    if(mounted)setState((){selectedRxId=id;rxItems=rows;final header=rxRows.where((r)=>r['id']==id).toList();if(header.isNotEmpty)policyId=header.first['insurance_policy_id'] as int?;});
  }
  @override Widget build(BuildContext context){
    final p=context.watch<ClinicalAndRxProvider>();final pos=context.watch<PosAndDrugsProvider>();final session=context.watch<SessionAndErpProvider>();
    final policies=p.policies.where((x)=>x.id==policyId).toList();final policy=policies.isEmpty?null:policies.first;
    final selectedRx=rxRows.where((r)=>r['id']==selectedRxId).toList();
    var availableCoverage=policy?.remainingLimit??0.0;
    final copayLines=<({Map<String,Object?> item,double gross,double insurer,double patient})>[];
    for(final item in rxItems){
      final remaining=((item['prescribed_qty_units'] as int)-(item['dispensed_qty_units'] as int)).clamp(0,1<<30);
      final gross=(item['sell_price_unit'] as num).toDouble()*remaining;
      var wanted=0.0;
      if(policy!=null){
        var excluded=false;
        try{excluded=(jsonDecode(policy.excludedCategoriesJson) as List).map((x)=>x.toString()).contains(item['category_id']?.toString()??'');}catch(_){}
        wanted=excluded?0:gross*policy.coveragePct/100;
      }
      final insurer=wanted.clamp(0,availableCoverage).toDouble();availableCoverage=(availableCoverage-insurer).clamp(0,double.infinity).toDouble();
      copayLines.add((item:item,gross:gross,insurer:insurer,patient:gross-insurer));
    }
    return Scaffold(body:ListView(padding:const EdgeInsets.all(16),children:[
      Text('صرف الوصفات الطبية والتأمين الصحي',style:Theme.of(context).textTheme.titleLarge),
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
        DropdownButtonFormField<int>(value:patientId,decoration:const InputDecoration(labelText:'المريض'),items:p.patients.map((x)=>DropdownMenuItem(value:x.id,child:Text(x.fullName))).toList(),onChanged:(v)=>setState(()=>patientId=v)),
        TextField(controller:rxNo,decoration:const InputDecoration(labelText:'رقم الوصفة')),
        TextField(controller:doctor,decoration:const InputDecoration(labelText:'اسم الطبيب')),
        TextField(controller:license,decoration:const InputDecoration(labelText:'رقم ترخيص الطبيب')),
        TextField(controller:facility,decoration:const InputDecoration(labelText:'المنشأة الطبية')),
        TextField(controller:validDays,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'صلاحية الوصفة بالأيام')),
        TextField(controller:refillsAllowed,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'مرات إعادة الصرف المسموحة')),
        DropdownButtonFormField<String>(value:type,decoration:const InputDecoration(labelText:'نوع الوصفة'),items:const [DropdownMenuItem(value:'NORMAL',child:Text('عادية')),DropdownMenuItem(value:'CONTROLLED',child:Text('مراقبة')),DropdownMenuItem(value:'CHRONIC_REFILL',child:Text('مزمنة')),DropdownMenuItem(value:'INSURANCE',child:Text('تأمين'))],onChanged:(v)=>setState(()=>type=v??'NORMAL')),
        DropdownButtonFormField<int>(value:policyId,decoration:const InputDecoration(labelText:'بوليصة التأمين (اختياري)'),items:p.policies.map((x){final company=p.companies.where((c)=>c.id==x.insuranceCompanyId).toList();return DropdownMenuItem(value:x.id,child:Text('${x.policyNo} • ${company.isEmpty?'شركة تأمين':company.first.nameAr}'));}).toList(),onChanged:(v)=>setState(()=>policyId=v)),
        if(policy!=null)...[
          Wrap(spacing:8,children:[Chip(label:Text('تغطية ${policy.coveragePct}%')),Chip(label:Text('تحمل المريض ${policy.copayPct}%')),Chip(label:Text('السقف المتبقي ${policy.remainingLimit.toStringAsFixed(2)}'))]),
          Builder(builder:(context){final company=p.companies.firstWhere((x)=>x.id==policy.insuranceCompanyId);final party=session.parties.where((x)=>x.id==company.partyId).toList();return party.isEmpty?Text('شركة التأمين: ${company.nameAr}'):Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('رصيد شركة التأمين: ${company.nameAr}'),PartyBalanceChip(totalAlayh:party.first.totalAlayh,totalLah:party.first.totalLah)]);}),
        ],
        FilledButton.icon(onPressed:saving?null:_create,icon:const Icon(Icons.save),label:const Text('حفظ الوصفة')),
      ]))),
      const SizedBox(height:12),Text('الوصفات المسجلة',style:Theme.of(context).textTheme.titleMedium),
      for(final row in rxRows)Card(child:ListTile(selected:selectedRxId==row['id'],onTap:()=>_selectRx(row['id'] as int),title:Text('${row['rx_no']} • ${row['full_name']}'),subtitle:Text('${row['doctor_name']} • ${row['rx_type']} • ${row['status']}'),trailing:Text(row['valid_until'].toString().substring(0,10)))),
      if(selectedRx.isNotEmpty)...[
        const Divider(),Text('بنود الوصفة ${selectedRx.first['rx_no']}',style:Theme.of(context).textTheme.titleMedium),
        DropdownButtonFormField<int>(value:drugId,decoration:const InputDecoration(labelText:'الدواء'),items:pos.drugs.map((d)=>DropdownMenuItem(value:d.id,child:Text(d.tradeNameAr))).toList(),onChanged:(v)=>setState(()=>drugId=v)),
        TextField(controller:qty,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'الكمية الموصوفة بالحبة')),
        TextField(controller:dose,decoration:const InputDecoration(labelText:'تعليمات الجرعة')),
        TextField(controller:duration,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'المدة بالأيام')),
        FilledButton.icon(onPressed:saving?null:_addItem,icon:const Icon(Icons.add),label:const Text('إضافة بند للوصفة')),
        for(final item in rxItems)Card(child:ListTile(title:Text(item['trade_name_ar'] as String),subtitle:Text('الموصوف ${item['prescribed_qty_units']} • المصروف ${item['dispensed_qty_units']} • المتبقي ${(item['prescribed_qty_units'] as int)-(item['dispensed_qty_units'] as int)}'))),
        if(copayLines.isNotEmpty)...[
          const SizedBox(height:8),Text('توزيع حصة الوصفة',style:Theme.of(context).textTheme.titleSmall),
          for(final line in copayLines)Card(child:ListTile(title:Text(line.item['trade_name_ar'] as String),subtitle:Text('الإجمالي ${line.gross.toStringAsFixed(2)} • شركة التأمين ${line.insurer.toStringAsFixed(2)} • المريض ${line.patient.toStringAsFixed(2)}'))),
          Card(child:Padding(padding:const EdgeInsets.all(10),child:Text('الإجمالي ${copayLines.fold<double>(0,(s,x)=>s+x.gross).toStringAsFixed(2)} = حصة التأمين ${copayLines.fold<double>(0,(s,x)=>s+x.insurer).toStringAsFixed(2)} + حصة المريض ${copayLines.fold<double>(0,(s,x)=>s+x.patient).toStringAsFixed(2)}'))),
        ],
        const Divider(),
        Text('تحصيل حصة المريض (يمكن ترك المتبقي على حسابه)',style:Theme.of(context).textTheme.titleSmall),
        TextField(controller:paid,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'المبلغ المحصل الآن')),
        DropdownButtonFormField<String>(value:paymentMethod,decoration:const InputDecoration(labelText:'وسيلة التحصيل'),items:const [DropdownMenuItem(value:'CASH',child:Text('نقداً')),DropdownMenuItem(value:'WALLET',child:Text('محفظة إلكترونية'))],onChanged:(v)=>setState(()=>paymentMethod=v??'CASH')),
        DropdownButtonFormField<int>(value:cashId,decoration:const InputDecoration(labelText:'الصندوق / المحفظة'),items:session.cashAccounts.map((a)=>DropdownMenuItem(value:a.id,child:Text(a.nameAr))).toList(),onChanged:(v)=>setState(()=>cashId=v)),
        if(paymentMethod=='WALLET')TextField(controller:walletRef,decoration:const InputDecoration(labelText:'رقم إشعار المحفظة')),
        FilledButton.icon(onPressed:saving?null:()=>_dispense(p,session.currentUser?['id'] as int?,session.branchId),icon:const Icon(Icons.medication),label:const Text('اعتماد وصرف الوصفة')),
      ],
      const SizedBox(height:16),Text('سجل الرقابة والتنبيهات السريرية',style:Theme.of(context).textTheme.titleMedium),
      for(final row in alertRows)Card(child:ListTile(title:Text('${row['level']} • ${row['alert_category']}'),subtitle:Text('${row['message_ar']}'),trailing:Text(row['user_decision']?.toString()??'غير محسوم'))),
      const SizedBox(height:12),Text('سجل الأدوية المراقبة',style:Theme.of(context).textTheme.titleMedium),
      for(final row in controlledRows)Card(child:ListTile(title:Text('${row['trade_name_ar']} • ${row['qty_units']} حبة'),subtitle:Text('المريض: ${row['patient_name']} • المستلم: ${row['receiver_name']} • الطبيب: ${row['doctor_name']}'),trailing:Text('الرصيد ${row['running_balance_units']}'))),
    ]));
  }
  Future<void> _create()async{
    if(patientId==null||rxNo.text.trim().isEmpty||doctor.text.trim().isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('أدخل المريض ورقم الوصفة والطبيب')));return;}
    setState(()=>saving=true);
    try{
      final db=await DatabaseHelper.instance.database;final now=DateTime.now();final days=int.tryParse(validDays.text)??30;
      await db.insert('prescriptions',{'rx_no':rxNo.text.trim(),'patient_id':patientId,'customer_party_id':context.read<ClinicalAndRxProvider>().patients.firstWhere((p)=>p.id==patientId).partyId,'doctor_name':doctor.text.trim(),'doctor_license_no':license.text.trim(),'facility_name':facility.text.trim(),'rx_date':now.toIso8601String(),'valid_until':now.add(Duration(days:days)).toIso8601String(),'rx_type':type,'insurance_policy_id':policyId,'refills_allowed':int.tryParse(refillsAllowed.text)??0,'refills_used':0,'status':'OPEN'});
      final row=await db.query('prescriptions',columns:['id'],where:'rx_no=?',whereArgs:[rxNo.text.trim()],limit:1);
      rxNo.clear();await _load();if(row.isNotEmpty)await _selectRx(row.first['id'] as int);
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
    if(mounted)setState(()=>saving=false);
  }
  Future<void> _addItem()async{
    if(selectedRxId==null||drugId==null){return;}
    final quantity=int.tryParse(qty.text)??0;if(quantity<=0){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('أدخل كمية صحيحة')));return;}
    try{await DatabaseHelper.instance.insert('prescription_items',{'prescription_id':selectedRxId,'drug_id':drugId,'prescribed_qty_units':quantity,'dispensed_qty_units':0,'dose_instruction':dose.text.trim(),'duration_days':int.tryParse(duration.text)??1});await _selectRx(selectedRxId!);}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  }
  Future<void> _dispense(ClinicalAndRxProvider clinical,int? userId,int branchId)async{
    if(selectedRxId==null||userId==null)return;
    final db=await DatabaseHelper.instance.database;
    final rx=(await db.query('prescriptions',where:'id=?',whereArgs:[selectedRxId],limit:1)).first;
    final patient=clinical.patients.where((p)=>p.id==rx['patient_id']).toList();
    final partyId=patient.isNotEmpty?(patient.first.partyId??rx['customer_party_id'] as int?):rx['customer_party_id'] as int?;
    if(partyId==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('اربط ملف المريض بحساب عميل قبل الصرف')));return;}
    final remainingItems=rxItems.where((i)=>(i['prescribed_qty_units'] as int)>(i['dispensed_qty_units'] as int)).toList();
    if(remainingItems.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('لا توجد كميات متبقية للصرف')));return;}
    final drugRows=<Map<String,Object?>>[];for(final item in remainingItems){final rows=await db.query('drugs',where:'id=?',whereArgs:[item['drug_id']],limit:1);if(rows.isNotEmpty)drugRows.add(rows.first);}
    final drugs=drugRows.map(DrugModel.fromMap).toList();
    if(patient.isNotEmpty)clinical.selectPatient(patient.first);
    var verdict=await clinical.evaluateCart(drugs);
    if(verdict.hasUnresolvedCritical){final ok=await S04ClinicalGuardDialog.show(context,drugs:drugs);if(!ok||clinical.verdict.hasUnresolvedCritical)return;verdict=clinical.verdict;}
    final controlled=remainingItems.where((item)=>drugRows.any((d)=>(d['id']==item['drug_id'])&&(d['is_controlled'] as int? ?? 0)==1)).toList();
    final details=<int,({String patientName,String patientNationalId,String receiverName,String receiverNationalId,String doctorName,int? batchId})>{};
    if(controlled.isNotEmpty){
      final national=TextEditingController(),receiver=TextEditingController(),receiverId=TextEditingController();
      final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('توثيق الدواء المراقب'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:national,decoration:const InputDecoration(labelText:'الرقم الوطني للمريض')),TextField(controller:receiver,decoration:const InputDecoration(labelText:'اسم المستلم الرباعي')),TextField(controller:receiverId,decoration:const InputDecoration(labelText:'الرقم الوطني للمستلم'))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('متابعة'))]));
      if(ok!=true){national.dispose();receiver.dispose();receiverId.dispose();return;}
      for(final item in controlled){details[item['id'] as int]=(patientName:patient.isEmpty?'غير محدد':patient.first.fullName,patientNationalId:national.text,receiverName:receiver.text,receiverNationalId:receiverId.text,doctorName:rx['doctor_name'] as String,batchId:null);}
      national.dispose();receiver.dispose();receiverId.dispose();
    }
    final quantities=<int,int>{},totals=<int,double>{};
    for(final item in remainingItems){final id=item['id'] as int;final remaining=(item['prescribed_qty_units'] as int)-(item['dispensed_qty_units'] as int);quantities[id]=remaining;final drug=drugs.firstWhere((d)=>d.id==item['drug_id']);totals[id]=drug.sellPriceUnit*remaining;}
    final amount=double.tryParse(paid.text)??0;
    final payments=<({double amount,int? cashAccountId,String method,String? walletRef})>[];
    if(amount>0)payments.add((amount:amount,cashAccountId:cashId,method:paymentMethod,walletRef:paymentMethod=='WALLET'?walletRef.text.trim():null));
    setState(()=>saving=true);
    try{
      final invoiceId=await clinical.dispensePrescription(prescriptionId:selectedRxId!,quantitiesByItemId:quantities,patientPartyId:partyId,policyId:rx['insurance_policy_id'] as int?,patientPayments:payments,pharmacistUserId:userId,controlledDetails:details,lineTotalsByItemId:totals,branchId:branchId,clinicalVerdict:verdict);
      if(mounted){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تم الصرف وإنشاء فاتورة رقم $invoiceId')));paid.text='0';await _load();await _selectRx(selectedRxId!);}
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
    if(mounted)setState(()=>saving=false);
  }
}
