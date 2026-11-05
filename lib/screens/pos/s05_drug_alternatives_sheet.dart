// lib/screens/pos/s05_drug_alternatives_sheet.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/drug_model.dart';
import '../../providers/clinical_and_rx_provider.dart';
import '../../providers/pos_and_drugs_provider.dart';
import '../../data/database/database_helper.dart';

class S05DrugAlternativesSheet extends StatefulWidget {
  const S05DrugAlternativesSheet({super.key,required this.original,required this.onSelect});
  final DrugModel original;
  final ValueChanged<DrugModel> onSelect;
  static Future<void> show(BuildContext context,DrugModel original,ValueChanged<DrugModel> onSelect)=>showModalBottomSheet<void>(context:context,isScrollControlled:true,backgroundColor:const Color(0xff1E1E1E),builder:(_)=>S05DrugAlternativesSheet(original:original,onSelect:onSelect));
  @override State<S05DrugAlternativesSheet> createState()=>_S05DrugAlternativesSheetState();
}
class _S05DrugAlternativesSheetState extends State<S05DrugAlternativesSheet>{
  bool exactOnly=false,inStock=false,cheapest=false;
  @override void initState(){super.initState();WidgetsBinding.instance.addPostFrameCallback((_)=>_load());}
  Future<void> _load()=>context.read<ClinicalAndRxProvider>().loadAlternatives(widget.original.id??0,inStockOnly:inStock,cheapestFirst:cheapest);
  @override Widget build(BuildContext context){
    final clinical=context.watch<ClinicalAndRxProvider>();
    final rows=clinical.alternatives.where((a)=>!exactOnly||a.matchType=='EXACT').toList();
    return SafeArea(child:Padding(padding:EdgeInsets.only(left:16,right:16,top:16,bottom:MediaQuery.viewInsetsOf(context).bottom+16),child:SizedBox(height:MediaQuery.sizeOf(context).height*.82,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text('البدائل الدوائية — ${widget.original.tradeNameAr}',style:Theme.of(context).textTheme.titleLarge),
      Wrap(spacing:6,children:[
        FilterChip(label:const Text('مطابق تماماً'),selected:exactOnly,onSelected:(v)=>setState(()=>exactOnly=v)),
        FilterChip(label:const Text('المتوفر فقط'),selected:inStock,onSelected:(v){setState(()=>inStock=v);_load();}),
        FilterChip(label:const Text('الأرخص سعراً'),selected:cheapest,onSelected:(v){setState(()=>cheapest=v);_load();}),
      ]),
      const SizedBox(height:8),
      Expanded(child:clinical.loading?const Center(child:CircularProgressIndicator()):rows.isEmpty?const Center(child:Text('لا توجد بدائل مسجلة للمادة الفعالة.')):ListView.builder(itemCount:rows.length,itemBuilder:(context,index){final a=rows[index];return Card(child:ListTile(title:Text(a.nameAr),subtitle:Text('${a.strengthText} • ${a.dosageForm} • ${a.matchType} • الرصيد ${a.availableUnits} • أقرب صلاحية ${a.nearestExpiry??'—'}'),trailing:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text(a.sellPricePack.toStringAsFixed(2)),Text((a.priceDiffPack>=0?'+':'')+a.priceDiffPack.toStringAsFixed(2),style:TextStyle(color:a.priceDiffPack<=0?const Color(0xff66BB6A):const Color(0xffFFB74D)))]),onTap:()=>_choose(a.drugId)));})),
      const Text('يُعاد فحص البديل سريرياً قبل تثبيته في السلة.'),
    ]))));
  }
  Future<void> _choose(int drugId)async{
    final rows=await DatabaseHelper.instance.query('drugs',where:'id=?',whereArgs:[drugId],limit:1);
    if(rows.isEmpty||!mounted)return;
    final replacement=DrugModel.fromMap(rows.first);
    final verdict=await context.read<ClinicalAndRxProvider>().evaluateCart([replacement]);
    if(!mounted)return;
    if(verdict.blocked){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('هذا البديل يتضمن حظراً سريرياً؛ لم يتم اختياره.')));return;}
    widget.onSelect(replacement);
    Navigator.pop(context);
  }
}
