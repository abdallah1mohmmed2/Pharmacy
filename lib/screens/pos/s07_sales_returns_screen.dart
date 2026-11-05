// lib/screens/pos/s07_sales_returns_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/database/database_helper.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../providers/clinical_and_rx_provider.dart';
import '../../providers/session_and_erp_provider.dart';

class S07SalesReturnsScreen extends StatefulWidget {
  const S07SalesReturnsScreen({super.key});
  @override State<S07SalesReturnsScreen> createState()=>_S07SalesReturnsScreenState();
}
class _S07SalesReturnsScreenState extends State<S07SalesReturnsScreen>{
  final search=TextEditingController(),qty=TextEditingController(text:'1'),refund=TextEditingController(),reason=TextEditingController(),walletRef=TextEditingController();
  Map<String,Object?>? invoice,selected;List<Map<String,Object?>> items=[],returnRows=[];String refundMethod='CASH',disposition='RESTOCK',reasonCode='OTHER';int? cashId;bool openedLiquid=false,busy=false;
  @override void dispose(){search.dispose();qty.dispose();refund.dispose();reason.dispose();walletRef.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final session=context.watch<SessionAndErpProvider>();
    final selectedDrug=selected;
    final refrigerated=(selectedDrug?['requires_refrigeration'] as int? ?? 0)==1;
    final liquid=['SYRUP','DROPS'].contains(selectedDrug?['dosage_form']);
    final restockAllowed=!refrigerated&&!(liquid&&openedLiquid);
    return Scaffold(body:ListView(padding:const EdgeInsets.all(16),children:[
      Text('مرتجع المبيعات وفحص التشغيلة',style:Theme.of(context).textTheme.titleLarge),
      Row(children:[Expanded(child:TextField(controller:search,decoration:const InputDecoration(labelText:'رقم الفاتورة الأصلية'))),IconButton(onPressed:_find,icon:const Icon(Icons.search))]),
      if(invoice!=null)Card(child:ListTile(title:Text('فاتورة ${invoice!['invoice_no']}'),subtitle:Text('التاريخ ${invoice!['invoice_date']} • العميل ${invoice!['customer_name']??'عميل نقدي'}'))),
      if(invoice!=null&&invoice!['customer_party_id']!=null)...[
        Builder(builder:(context){final party=session.parties.where((p)=>p.id==invoice!['customer_party_id']).toList();return party.isEmpty?const SizedBox.shrink():PartyBalanceChip(totalAlayh:party.first.totalAlayh,totalLah:party.first.totalLah);}),
      ],
      if(returnRows.isNotEmpty)ExpansionTile(title:const Text('المرتجعات السابقة لهذه الفاتورة'),children:[for(final row in returnRows)ListTile(title:Text('${row['return_no']} • ${row['total_refund']}'),subtitle:Text('${row['reason_code']} • ${row['refund_method']}'))]),
      for(final item in items)Card(child:RadioListTile<int>(value:item['id'] as int,groupValue:selected?['id'] as int?,onChanged:(_){setState((){selected=item;qty.text='1';refund.text=(item['unit_price_sell_unit'] as num? ?? 0).toString();disposition='RESTOCK';});},title:Text(item['trade_name_ar'] as String? ?? ''),subtitle:Text('المباع ${item['qty_units']} حبة • التشغيلة ${item['batch_no']??'غير محددة'} • المرتجع سابقاً ${item['returned_qty_units']??0}'))),
      if(selected!=null)...[
        TextField(controller:qty,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'الكمية المرتجعة بالحبة')),
        TextField(controller:refund,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'قيمة الرد')),
        DropdownButtonFormField<String>(value:reasonCode,decoration:const InputDecoration(labelText:'سبب الإرجاع'),items:const [DropdownMenuItem(value:'WRONG_ITEM',child:Text('صنف خاطئ')),DropdownMenuItem(value:'DOCTOR_CHANGED',child:Text('تغيير الطبيب')),DropdownMenuItem(value:'ADVERSE_REACTION',child:Text('أثر جانبي')),DropdownMenuItem(value:'DAMAGED',child:Text('تالف')),DropdownMenuItem(value:'EXPIRED_AT_SALE',child:Text('منتهي عند البيع')),DropdownMenuItem(value:'OTHER',child:Text('أخرى'))],onChanged:(v)=>setState(()=>reasonCode=v??'OTHER')),
        TextField(controller:reason,decoration:const InputDecoration(labelText:'تفاصيل الفحص / السبب')),
        SwitchListTile(value:openedLiquid,onChanged:(v)=>setState(()=>openedLiquid=v),title:const Text('شراب أو قطرة مفتوحة')),
        DropdownButtonFormField<String>(value:disposition,decoration:const InputDecoration(labelText:'قرار فحص التشغيلة'),items:[if(restockAllowed)const DropdownMenuItem(value:'RESTOCK',child:Text('إعادة للمخزون الصالح')),const DropdownMenuItem(value:'QUARANTINE',child:Text('تحويل لمستودع الحجر')),const DropdownMenuItem(value:'DISPOSE',child:Text('إتلاف فوري'))],onChanged:(v)=>setState(()=>disposition=v??'QUARANTINE')),
        if(!restockAllowed)const Text('إعادة التخزين الصالح مقفلة لأن الدواء مبرّد أو سائل مفتوح.',style:TextStyle(color:Color(0xffEF5350))),
        DropdownButtonFormField<String>(value:refundMethod,decoration:const InputDecoration(labelText:'طريقة رد المبلغ'),items:const [DropdownMenuItem(value:'CASH',child:Text('نقداً')),DropdownMenuItem(value:'WALLET',child:Text('محفظة إلكترونية')),DropdownMenuItem(value:'CREDIT_TO_ACCOUNT',child:Text('إضافة لحساب العميل — له'))],onChanged:(v)=>setState(()=>refundMethod=v??'CASH')),
        if(refundMethod=='WALLET')TextField(controller:walletRef,decoration:const InputDecoration(labelText:'رقم إشعار المحفظة')),
        if(refundMethod!='CREDIT_TO_ACCOUNT')DropdownButtonFormField<int>(value:cashId,decoration:const InputDecoration(labelText:'الصندوق / المحفظة'),items:session.cashAccounts.map((a)=>DropdownMenuItem(value:a.id,child:Text(a.nameAr))).toList(),onChanged:(v)=>setState(()=>cashId=v)),
        FilledButton.icon(onPressed:busy?null:()=>_complete(session.currentUser?['id'] as int?),icon:const Icon(Icons.assignment_return),label:const Text('إتمام المرتجع')),
      ]
    ]));
  }
  Future<void> _find()async{
    final rows=await DatabaseHelper.instance.rawQuery('SELECT si.*,p.name_ar AS customer_name FROM sales_invoices si LEFT JOIN parties p ON p.id=si.customer_party_id WHERE si.invoice_no=? OR p.name_ar LIKE ? ORDER BY si.id DESC LIMIT 1',[search.text.trim(),'%${search.text.trim()}%']);
    if(rows.isEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('لم يتم العثور على الفاتورة')));return;}
    final invoiceId=rows.first['id'] as int;
    final data=await DatabaseHelper.instance.rawQuery('SELECT sii.*,d.trade_name_ar,d.dosage_form,d.requires_refrigeration,b.batch_no,b.id AS batch_id,COALESCE(sib.returned_qty_units,0) AS returned_qty_units FROM sales_invoice_items sii JOIN drugs d ON d.id=sii.drug_id LEFT JOIN sales_invoice_item_batches sib ON sib.invoice_item_id=sii.id LEFT JOIN batches_fefo b ON b.id=sib.batch_id WHERE sii.invoice_id=?',[invoiceId]);
    final history=await DatabaseHelper.instance.query('sales_returns',where:'original_invoice_id=?',whereArgs:[invoiceId],orderBy:'id DESC');
    if(mounted)setState((){invoice=rows.first;items=data;returnRows=history;selected=null;});
  }
  Future<void> _complete(int? userId)async{
    if(selected==null||invoice==null)return;
    setState(()=>busy=true);
    try{
      final qtyValue=int.tryParse(qty.text)??0;final amount=double.tryParse(refund.text)??-1;
      final id=await context.read<ClinicalAndRxProvider>().completeReturn(invoiceId:invoice!['id'] as int,invoiceItemId:selected!['id'] as int,qtyUnits:qtyValue,refundAmount:amount,reasonCode:reasonCode,reasonText:reason.text,refundMethod:refundMethod,disposition:disposition,approvedBy:userId,cashAccountId:cashId,batchId:selected!['batch_id'] as int?,openedLiquid:openedLiquid,walletRef:refundMethod=='WALLET'?walletRef.text.trim():null);
      if(mounted){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تم تسجيل المرتجع رقم $id')));await context.read<SessionAndErpProvider>().refresh();await _find();}
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
    if(mounted)setState(()=>busy=false);
  }
}
