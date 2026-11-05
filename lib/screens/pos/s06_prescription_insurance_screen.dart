// lib/screens/pos/s06_prescription_insurance_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/database/database_helper.dart';
import '../../providers/clinical_and_rx_provider.dart';
import '../../providers/session_and_erp_provider.dart';

class S06PrescriptionInsuranceScreen extends StatefulWidget {
  const S06PrescriptionInsuranceScreen({super.key});
  @override State<S06PrescriptionInsuranceScreen> createState()=>_S06PrescriptionInsuranceScreenState();
}
class _S06PrescriptionInsuranceScreenState extends State<S06PrescriptionInsuranceScreen>{
  final rxNo=TextEditingController(),doctor=TextEditingController(),license=TextEditingController(),facility=TextEditingController(),validDays=TextEditingController(text:'30');
  int? patientId,policyId;String type='NORMAL';List<Map<String,Object?>> rxRows=[],alertRows=[];bool saving=false;
  @override void initState(){super.initState();WidgetsBinding.instance.addPostFrameCallback((_)async{await context.read<ClinicalAndRxProvider>().loadAll();await _load();});}
  @override void dispose(){rxNo.dispose();doctor.dispose();license.dispose();facility.dispose();validDays.dispose();super.dispose();}
  Future<void> _load()async{final db=await DatabaseHelper.instance.database;final rows=await db.rawQuery('SELECT r.*,p.full_name FROM prescriptions r JOIN patients p ON p.id=r.patient_id ORDER BY r.id DESC LIMIT 100');final alerts=await db.rawQuery('SELECT l.*,d.trade_name_ar,p.full_name FROM clinical_alert_logs l LEFT JOIN drugs d ON d.id=l.drug_id LEFT JOIN patients p ON p.id=l.patient_id ORDER BY l.id DESC LIMIT 100');if(mounted)setState((){rxRows=rows;alertRows=alerts;});}
  @override Widget build(BuildContext context){
    final p=context.watch<ClinicalAndRxProvider>();final session=context.watch<SessionAndErpProvider>();final session=context.read<SessionAndErpProvider>();
    final patient=p.patients.where((x)=>x.id==patientId).toList();final policies=p.policies.where((x)=>x.id==policyId).toList();final policy=policies.isEmpty?null:policies.first;
    return Scaffold(body:ListView(padding:const EdgeInsets.all(16),children:[
      Text('صرف الوصفات الطبية والتأمين الصحي',style:Theme.of(context).textTheme.titleLarge),
      const SizedBox(height:12),
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
        DropdownButtonFormField<int>(value:patientId,decoration:const InputDecoration(labelText:'المريض'),items:p.patients.map((x)=>DropdownMenuItem(value:x.id,child:Text(x.fullName))).toList(),onChanged:(v)=>setState(()=>patientId=v)),
        TextField(controller:rxNo,decoration:const InputDecoration(labelText:'رقم الوصفة')),
        TextField(controller:doctor,decoration:const InputDecoration(labelText:'اسم الطبيب')),
        TextField(controller:license,decoration:const InputDecoration(labelText:'رقم ترخيص الطبيب')),
        TextField(controller:facility,decoration:const InputDecoration(labelText:'المنشأة الطبية')),
        TextField(controller:validDays,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'صلاحية الوصفة بالأيام')),
        DropdownButtonFormField<String>(value:type,decoration:const InputDecoration(labelText:'نوع الوصفة'),items:const [DropdownMenuItem(value:'NORMAL',child:Text('عادية')),DropdownMenuItem(value:'CONTROLLED',child:Text('مراقبة')),DropdownMenuItem(value:'CHRONIC_REFILL',child:Text('مزمنة')),DropdownMenuItem(value:'INSURANCE',child:Text('تأمين'))],onChanged:(v)=>setState(()=>type=v??'NORMAL')),
        DropdownButtonFormField<int>(value:policyId,decoration:const InputDecoration(labelText:'بوليصة التأمين (اختياري)'),items:p.policies.map((x)=>DropdownMenuItem(value:x.id,child:Text(x.policyNo))).toList(),onChanged:(v)=>setState(()=>policyId=v)),
        if(policy!=null)Wrap(spacing:8,children:[Chip(label:Text('تغطية ${policy.coveragePct}%')),Chip(label:Text('تحمل المريض ${policy.copayPct}%')),Chip(label:Text('السقف المتبقي ${policy.remainingLimit.toStringAsFixed(2)}'))]),
        if(policy!=null&&p.companies.any((x)=>x.id==policy.insuranceCompanyId))...[
          Builder(builder:(context){final company=p.companies.firstWhere((x)=>x.id==policy.insuranceCompanyId);final party=session.parties.where((x)=>x.id==company.partyId).toList();return party.isEmpty?Text('شركة التأمين: ${company.nameAr}'):Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('رصيد شركة التأمين: ${company.nameAr}'),PartyBalanceChip(totalAlayh:party.first.totalAlayh,totalLah:party.first.totalLah)]);}),
        ],
        if(patient.isNotEmpty)Text('المريض: ${patient.first.fullName}'),
        const SizedBox(height:8),
        FilledButton.icon(onPressed:saving?null:_create,icon:const Icon(Icons.save),label:const Text('حفظ الوصفة')),
      ]))),
      const SizedBox(height:12),Text('الوصفات المسجلة',style:Theme.of(context).textTheme.titleMedium),
      for(final row in rxRows)Card(child:ListTile(title:Text('${row['rx_no']} • ${row['full_name']}'),subtitle:Text('${row['doctor_name']} • ${row['rx_type']} • ${row['status']}'),trailing:Text(row['valid_until'].toString().substring(0,10)))),
      const SizedBox(height:16),Text('سجل الرقابة والتنبيهات السريرية',style:Theme.of(context).textTheme.titleMedium),
      for(final row in alertRows)Card(child:ListTile(title:Text('${row['level']} • ${row['alert_category']}'),subtitle:Text('${row['message_ar']}'),trailing:Text(row['user_decision']?.toString()??'غير محسوم'))),
    ]));
  }
  Future<void> _create()async{
    if(patientId==null||rxNo.text.trim().isEmpty||doctor.text.trim().isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('أدخل المريض ورقم الوصفة والطبيب')));return;}
    setState(()=>saving=true);
    try{
      final db=await DatabaseHelper.instance.database;final now=DateTime.now();final days=int.tryParse(validDays.text)??30;
      await db.insert('prescriptions',{'rx_no':rxNo.text.trim(),'patient_id':patientId,'customer_party_id':context.read<ClinicalAndRxProvider>().patients.firstWhere((p)=>p.id==patientId).partyId,'doctor_name':doctor.text.trim(),'doctor_license_no':license.text.trim(),'facility_name':facility.text.trim(),'rx_date':now.toIso8601String(),'valid_until':now.add(Duration(days:days)).toIso8601String(),'rx_type':type,'insurance_policy_id':policyId,'refills_allowed':0,'refills_used':0,'status':'OPEN'});
      rxNo.clear();doctor.clear();license.clear();facility.clear();await _load();
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم حفظ الوصفة. أضف بنودها من تفاصيل الوصفة قبل الصرف.')));
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
    if(mounted)setState(()=>saving=false);
  }
}
