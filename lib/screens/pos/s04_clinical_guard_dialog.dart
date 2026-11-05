// lib/screens/pos/s04_clinical_guard_dialog.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/clinical_and_rx_models.dart';
import '../../data/models/drug_model.dart';
import '../../providers/clinical_and_rx_provider.dart';
import '../../providers/pos_and_drugs_provider.dart';
import '../../providers/session_and_erp_provider.dart';
import 's05_drug_alternatives_sheet.dart';

class S04ClinicalGuardDialog extends StatefulWidget {
  const S04ClinicalGuardDialog({super.key});
  static Future<bool> show(BuildContext context,{List<DrugModel>? drugs}) async {
    final pos=context.read<PosAndDrugsProvider>();
    await context.read<ClinicalAndRxProvider>().evaluateCart(drugs??pos.cart.map((e)=>e.drug).toList());
    if(!context.mounted)return false;
    return await showDialog<bool>(context:context,builder:(_)=>const S04ClinicalGuardDialog())??false;
  }
  @override State<S04ClinicalGuardDialog> createState()=>_S04ClinicalGuardDialogState();
}
class _S04ClinicalGuardDialogState extends State<S04ClinicalGuardDialog>{
  final reason=TextEditingController();
  final foods=TextEditingController();
  @override void dispose(){reason.dispose();foods.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final clinical=context.watch<ClinicalAndRxProvider>();
    final pos=context.watch<PosAndDrugsProvider>();
    final session=context.read<SessionAndErpProvider>();
    final patient=clinical.currentPatient;
    return AlertDialog(
      title:const Row(children:[Icon(Icons.health_and_safety,color:Color(0xffEF5350)),SizedBox(width:8),Expanded(child:Text('الحماية السريرية وفاحص التفاعلات'))]),
      content:SizedBox(width:720,child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        DropdownButtonFormField<int?>(value:patient?.id,decoration:const InputDecoration(labelText:'ملف المريض'),items:[const DropdownMenuItem<int?>(value:null,child:Text('بدون ملف مريض')), ...clinical.patients.map((p)=>DropdownMenuItem<int?>(value:p.id,child:Text(p.fullName)))],onChanged:(id)=>clinical.selectPatient(id==null?null:clinical.patients.firstWhere((p)=>p.id==id))),
        if(patient!=null)Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Wrap(spacing:8,runSpacing:8,children:[_tag('العمر',patient.ageYears==null?'غير محدد':'${patient.ageYears} سنة'),_tag('الوزن',patient.weightKg==null?'غير محدد':'${patient.weightKg} كجم'),_tag('CrCl',patient.crcl==null?'غير محسوب':'${patient.crcl!.toStringAsFixed(1)} مل/دقيقة'),_tag('الحمل',patient.isPregnant?'نعم':'لا'),_tag('الرضاعة',patient.isLactating?'نعم':'لا'),_tag('الكبد',patient.childPughClass??'غير محدد')])),
        TextField(controller:foods,decoration:const InputDecoration(labelText:'الأطعمة الحالية (افصل بينها بفاصلة)'),onChanged:(value)=>clinical.setFoodIntake(value.split(',').map((x)=>x.trim()).where((x)=>x.isNotEmpty).toList())),
        Align(alignment:AlignmentDirectional.centerEnd,child:TextButton(onPressed:()=>clinical.evaluateCart(pos.cart.map((x)=>x.drug).toList()),child:const Text('إعادة الفحص'))),
        const Divider(),
        if(clinical.verdict.alerts.isEmpty)const Padding(padding:EdgeInsets.all(20),child:Text('لا توجد تنبيهات مسجلة لهذه السلة حالياً.',textAlign:TextAlign.center)),
        for(final alert in clinical.verdict.alerts)Card(child:Padding(padding:const EdgeInsets.all(10),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Row(children:[_level(alert.level),const SizedBox(width:8),Expanded(child:Text(alert.category,style:const TextStyle(fontWeight:FontWeight.bold)))]),
          const SizedBox(height:6),Text(alert.messageAr),if(alert.recommendation.isNotEmpty)Text(alert.recommendation,style:const TextStyle(color:Colors.white70)),
          if(alert.userDecision!=null)Text('تم توثيق القرار: ${alert.userDecision}',style:const TextStyle(color:Color(0xff66BB6A))),
          if(alert.userDecision==null)Wrap(spacing:6,children:[
            if(alert.level==ClinicalLevel.info||alert.level==ClinicalLevel.caution)TextButton(onPressed:()=>_decide(clinical,alert,'ACKNOWLEDGED',session.currentUser?['id'] as int?),child:const Text('إقرار')),
            if(alert.level==ClinicalLevel.warning)FilledButton(onPressed:()async{if(reason.text.trim().length<5){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('اكتب سبباً لا يقل عن خمسة أحرف')));return;}await _decide(clinical,alert,'ACKNOWLEDGED',session.currentUser?['id'] as int?,reason.text.trim());},child:const Text('توثيق التجاوز')),
            TextButton(onPressed:()async{final id=alert.drugId;if(id!=null){final matches=pos.cart.where((x)=>x.drug.id==id).toList();if(matches.isNotEmpty){await _decide(clinical,alert,'CANCELLED_ITEM',session.currentUser?['id'] as int?);pos.removeItem(matches.first);}}},child:const Text('حذف الصنف')),
            TextButton(onPressed:()async{final id=alert.drugId;if(id!=null){final matches=pos.cart.where((x)=>x.drug.id==id).toList();if(matches.isNotEmpty){var replaced=false;await S05DrugAlternativesSheet.show(context,matches.first.drug,(replacement){pos.replaceCartItem(matches.first,replacement);replaced=true;});if(replaced)await _decide(clinical,alert,'SUBSTITUTED',session.currentUser?['id'] as int?);}}},child:const Text('استبدال ببديل آمن')),
            if(alert.level==ClinicalLevel.block)TextButton(onPressed:()async{final ok=await ManagerPinDialog.show(context,verifier:session.verifyManagerPin);if(ok&&reason.text.trim().length>=5)await _decide(clinical,alert,'OVERRIDDEN_WITH_PIN',session.currentUser?['id'] as int?,reason.text.trim(),session.currentUser?['id'] as int?);},child:const Text('تجاوز برمز المدير')),
          ]),
          if(alert.level==ClinicalLevel.warning||alert.level==ClinicalLevel.block)TextField(controller:reason,decoration:const InputDecoration(labelText:'سبب القرار (إلزامي)'),maxLines:2),
        ]))),
        const SizedBox(height:8),
        Text('التنبيهات غير المحسومة: ${clinical.verdict.alerts.where((a)=>(a.level==ClinicalLevel.warning||a.level==ClinicalLevel.block)&&a.userDecision==null).length}'),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('إغلاق')),FilledButton(onPressed:clinical.verdict.hasUnresolvedCritical?null:()=>Navigator.pop(context,true),child:const Text('اعتماد الفحص'))],
    );
  }
  Widget _tag(String label,String value)=>Chip(label:Text('$label: $value'));
  Widget _level(ClinicalLevel level){final color=switch(level){ClinicalLevel.block=>const Color(0xffEF5350),ClinicalLevel.warning=>const Color(0xffFFB74D),ClinicalLevel.caution=>const Color(0xff4DB6AC),ClinicalLevel.info=>Colors.blueGrey};return Chip(backgroundColor:color.withValues(alpha:.18),label:Text(level.name.toUpperCase(),style:TextStyle(color:color)));}
  Future<void> _decide(ClinicalAndRxProvider p,ClinicalAlertModel a,String decision,int? user,[String? why,int? manager])async{await p.decideAlert(a,decision:decision,userId:user,reason:why,managerUserId:manager);}
}
