// lib/screens/pos/s05_drug_alternatives_sheet.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/drug_model.dart';
import '../../providers/clinical_and_rx_provider.dart';
import '../../data/database/database_helper.dart';

class S05DrugAlternativesSheet extends StatefulWidget {
  const S05DrugAlternativesSheet({super.key,required this.original,required this.onSelect});
  final DrugModel original;
  final ValueChanged<DrugModel> onSelect;
  static Future<void> show(BuildContext context,DrugModel original,ValueChanged<DrugModel> onSelect)=>showModalBottomSheet<void>(context:context,isScrollControlled:true,backgroundColor:const Color(0xff1E1E1E),builder:(_)=>S05DrugAlternativesSheet(original:original,onSelect:onSelect));
  @override State<S05DrugAlternativesSheet> createState()=>_S05DrugAlternativesSheetState();
}
class _S05DrugAlternativesSheetState extends State<S05DrugAlternativesSheet>{
  bool exactOnly=false,inStock=false,cheapest=false,safeOnly=false;
  Set<int> safeIds={},checkedIds={};
  @override void initState(){super.initState();WidgetsBinding.instance.addPostFrameCallback((_)=>_load());}
  Future<void> _load()async{
    final provider=context.read<ClinicalAndRxProvider>();
    final rows=await provider.loadAlternatives(widget.original.id??0,inStockOnly:inStock,cheapestFirst:cheapest);
    final checked=<int>{};
    final safe=<int>{};
    for(final alternative in rows){
      final matches=await DatabaseHelper.instance.query('drugs',where:'id=?',whereArgs:[alternative.drugId],limit:1);
      if(matches.isEmpty)continue;
      final verdict=await provider.evaluateCandidate(DrugModel.fromMap(matches.first));
      checked.add(alternative.drugId);
      if(!verdict.hasUnresolvedCritical)safe.add(alternative.drugId);
    }
    if(mounted)setState((){safeIds=safe;checkedIds=checked;});
  }
  @override Widget build(BuildContext context){
    final clinical=context.watch<ClinicalAndRxProvider>();
    final rows=clinical.alternatives.where((a)=>(!exactOnly||a.matchType=='EXACT')&&(!safeOnly||safeIds.contains(a.drugId))).toList();
    return SafeArea(child:Padding(padding:EdgeInsets.only(left:16,right:16,top:16,bottom:MediaQuery.viewInsetsOf(context).bottom+16),child:SizedBox(height:MediaQuery.sizeOf(context).height*.82,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text('البدائل الدوائية — ${widget.original.tradeNameAr}',style:Theme.of(context).textTheme.titleLarge),
      Wrap(spacing:6,children:[
        FilterChip(label:const Text('مطابق تماماً'),selected:exactOnly,onSelected:(v)=>setState(()=>exactOnly=v)),
        FilterChip(label:const Text('المتوفر فقط'),selected:inStock,onSelected:(v){setState(()=>inStock=v);_load();}),
        FilterChip(label:const Text('الأرخص سعراً'),selected:cheapest,onSelected:(v){setState(()=>cheapest=v);_load();}),
        FilterChip(label:const Text('آمن للمريض الحالي'),selected:safeOnly,onSelected:(v){setState(()=>safeOnly=v);_load();}),
      ]),
      const SizedBox(height:8),
      Expanded(child:clinical.loading?const Center(child:CircularProgressIndicator()):rows.isEmpty?const Center(child:Text('لا توجد بدائل مسجلة للمادة الفعالة.')):ListView.builder(itemCount:rows.length,itemBuilder:(context,index){final a=rows[index];return Card(child:ListTile(title:Text(a.nameAr),subtitle:Text('${a.strengthText} • ${a.dosageForm} • ${a.matchType} • الرصيد ${a.availableUnits} • أقرب صلاحية ${a.nearestExpiry??'—'} • سعر الشريط ${a.sellPriceStrip.toStringAsFixed(2)} • ${!checkedIds.contains(a.drugId)?'جارٍ الفحص':safeIds.contains(a.drugId)?'✔ آمن':'⚠ يوجد تنبيه'}'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text(a.sellPricePack.toStringAsFixed(2)),Text((a.priceDiffPack>=0?'+':'')+a.priceDiffPack.toStringAsFixed(2),style:TextStyle(color:a.priceDiffPack<=0?const Color(0xff66BB6A):const Color(0xffFFB74D)))]),IconButton(tooltip:'مقارنة 19 نقطة',onPressed:()=>_compare(a),icon:const Icon(Icons.compare_arrows))]),onTap:()=>_choose(a.drugId)));})),
      const Text('يُعاد فحص البديل سريرياً قبل تثبيته في السلة.'),
    ]))));
  }

  Future<void> _compare(dynamic alternative)async{
    final rows=await DatabaseHelper.instance.query('drugs',where:'id=?',whereArgs:[alternative.drugId],limit:1);
    if(rows.isEmpty||!mounted)return;
    final other=DrugModel.fromMap(rows.first);final a=widget.original;
    final values=< (String,String,String)>[
      ('الهوية والتركيب',a.tradeNameAr,other.tradeNameAr),
      ('الاسم العلمي',a.scientificName,other.scientificName),
      ('المادة الفعالة',a.activeIngredientId?.toString()??'—',other.activeIngredientId?.toString()??'—'),
      ('الشكل والتركيز','${a.dosageForm} • ${a.strengthText}','${other.dosageForm} • ${other.strengthText}'),
      ('طريقة الإعطاء',a.route,other.route),
      ('دواعي الاستعمال',a.indications,other.indications),
      ('الجرعة',a.dosageAdministration,other.dosageAdministration),
      ('موانع الاستعمال',a.contraindications,other.contraindications),
      ('التحذيرات',a.warningsPrecautions,other.warningsPrecautions),
      ('التفاعلات',a.interactionsSummary,other.interactionsSummary),
      ('الآثار الشائعة',a.sideEffectsCommon,other.sideEffectsCommon),
      ('الآثار الخطيرة',a.sideEffectsSerious,other.sideEffectsSerious),
      ('الكلى',a.renalStatus,other.renalStatus),
      ('الكبد',a.hepaticStatus,other.hepaticStatus),
      ('الأطفال',a.pediatricStatus,other.pediatricStatus),
      ('الحمل',a.pregnancyCategory,other.pregnancyCategory),
      ('الرضاعة',a.lactationRisk,other.lactationRisk),
      ('التخزين',a.storageConditions,other.storageConditions),
      ('الرقابة والوصفة','${a.isControlled} • ${a.requiresPrescription}','${other.isControlled} • ${other.requiresPrescription}'),
    ];
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:const Text('مقارنة النقاط السريرية والتجارية'),content:SizedBox(width:700,child:SingleChildScrollView(child:Column(children:[for(final row in values)Card(child:Padding(padding:const EdgeInsets.all(8),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text(row.$1,style:const TextStyle(fontWeight:FontWeight.bold)),Row(children:[Expanded(child:Text(row.$2)),const SizedBox(width:10),Expanded(child:Text(row.$3))])])))]))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إغلاق'))]));
  }
  Future<void> _choose(int drugId)async{
    final rows=await DatabaseHelper.instance.query('drugs',where:'id=?',whereArgs:[drugId],limit:1);
    if(rows.isEmpty||!mounted)return;
    final replacement=DrugModel.fromMap(rows.first);
    final verdict=await context.read<ClinicalAndRxProvider>().evaluateCandidate(replacement);
    if(!mounted)return;
    if(verdict.hasUnresolvedCritical){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('هذا البديل يتضمن حظراً سريرياً؛ لم يتم اختياره.')));return;}
    widget.onSelect(replacement);
    Navigator.pop(context);
  }
}
