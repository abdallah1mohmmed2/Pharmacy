// lib/data/services/partner_distribution_service.dart
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';

class PolicyViolation implements Exception {
  const PolicyViolation(this.code);
  final String code;
  @override String toString()=>code;
}

class PartnerPolicy {
  const PartnerPolicy(this.mode);
  final String mode;
  bool get percentageEditable=>mode=='percentage';
  bool get sharesEditable=>mode=='shares';
  void validate({int? sharesCount,double? percentage}) {
    if(mode=='shares'&&percentage!=null)throw const PolicyViolation('PARTNER_PCT_LOCKED_IN_SHARES_MODE');
    if(mode=='percentage'&&sharesCount!=null)throw const PolicyViolation('PARTNER_SHARES_LOCKED_IN_PERCENTAGE_MODE');
    if(mode!='shares'&&mode!='percentage')throw StateError('نمط توزيع الأرباح غير معروف');
    if(sharesCount!=null&&sharesCount<0)throw ArgumentError('عدد الحصص لا يمكن أن يكون سالباً');
    if(percentage!=null&&(percentage<0||percentage>100))throw ArgumentError('النسبة يجب أن تكون بين صفر و100');
  }
}

class PartnerDistributionService {
  PartnerDistributionService({DatabaseHelper? helper}):_helper=helper??DatabaseHelper.instance;
  final DatabaseHelper _helper;
  String _now()=>DateTime.now().toIso8601String();
  String _uuid(String p)=>'$p-${DateTime.now().microsecondsSinceEpoch}';
  double _n(Object? v)=>v is num?v.toDouble():double.tryParse('$v')??0;

  Future<PartnerPolicy> policy() async {
    final rows=await _helper.query('app_settings',where:"setting_key='accounting.partner_distribution_mode'",limit:1);
    final mode=rows.isEmpty?'shares':rows.first['value_text'] as String;
    if(mode!='shares'&&mode!='percentage')throw StateError('قيمة نمط توزيع الشركاء غير صالحة');
    return PartnerPolicy(mode);
  }

  Future<void> validatePartnerFields({int? sharesCount,double? percentage}) async => (await policy()).validate(sharesCount:sharesCount,percentage:percentage);

  Future<Map<String,double>> calculatePeriodNetProfit({required int branchId,required String periodCode,double additionalLosses=0,double inventoryGain=0}) async {
    if(!RegExp(r'^\d{4}-\d{2}$').hasMatch(periodCode))throw ArgumentError('صيغة الفترة يجب أن تكون YYYY-MM');
    final db=await _helper.database;
    final sales=await db.rawQuery("SELECT COALESCE(SUM(subtotal),0) gross,COALESCE(SUM(discount_amount),0) discounts,COALESCE(SUM(total_cost),0) cogs FROM sales_invoices WHERE branch_id=? AND status='COMPLETED' AND substr(invoice_date,1,7)=?",[branchId,periodCode]);
    final returns=await db.rawQuery("SELECT COALESCE(SUM(total_refund),0) refunds FROM sales_returns WHERE substr(return_date,1,7)=?",[periodCode]);
    final expense=await db.rawQuery("SELECT COALESCE(SUM(amount),0) total FROM expenses WHERE branch_id=? AND substr(expense_date,1,7)=?",[branchId,periodCode]);
    final dailyWages=await db.rawQuery("SELECT COALESCE(SUM(a.wage_earned),0) total FROM employee_attendance a JOIN employees e ON e.id=a.employee_id WHERE e.branch_id=? AND substr(a.work_date,1,7)=? AND e.pay_type='DAILY'",[branchId,periodCode]);
    final monthlyWages=await db.rawQuery("SELECT COALESCE(SUM(e.pay_rate),0) total FROM employees e WHERE e.branch_id=? AND e.pay_type='MONTHLY' AND e.termination_date IS NULL AND e.hire_date<=?",[branchId,'$periodCode-31']);
    final revenue=_n(sales.first['gross']);final discounts=_n(sales.first['discounts']);final refund=_n(returns.first['refunds']);
    final netSales=revenue-discounts-refund;final cogs=_n(sales.first['cogs']);
    final expenses=_n(expense.first['total']);final wages=_n(dailyWages.first['total'])+_n(monthlyWages.first['total']);
    final totalExpenses=expenses+wages+additionalLosses;
    final netProfit=netSales-cogs-totalExpenses+inventoryGain;
    return {'gross_sales':revenue,'discounts':discounts,'returns':refund,'net_sales':netSales,'cogs':cogs,'operating_expenses':expenses,'wages':wages,'additional_losses':additionalLosses,'inventory_gain':inventoryGain,'total_expenses_and_losses':totalExpenses,'net_profit':netProfit};
  }

  Future<List<Map<String,Object?>>> planDistribution({required int branchId,required String periodCode,required double distributableProfit}) async {
    if(distributableProfit<0)throw StateError('لا يمكن توزيع خسارة كأنها أرباح');
    final p=await policy();final db=await _helper.database;
    final partners=await db.rawQuery('SELECT p.*,t.name_ar FROM partners p JOIN parties t ON t.id=p.party_id WHERE p.branch_id=? AND p.is_active=1 AND t.is_deleted=0 ORDER BY p.id',[branchId]);
    if(partners.isEmpty)throw StateError('لا يوجد شركاء نشطون');
    double basisTotal=0;
    if(p.mode=='shares'){
      basisTotal=partners.fold<double>(0,(s,r)=>s+_n(r['shares_count']));
      if(basisTotal<=0)throw StateError('إجمالي حصص الشركاء النشطين يجب أن يكون أكبر من صفر');
    }else{
      basisTotal=partners.fold<double>(0,(s,r)=>s+_n(r['percentage']));
      if((basisTotal-100).abs()>0.000001)throw StateError('مجموع نسب الشركاء النشطين يجب أن يساوي 100%');
    }
    final result=<Map<String,Object?>>[];double allocated=0;int largestIndex=0;double largestBasis=-1;
    for(final partner in partners){
      final basis=p.mode=='shares'?_n(partner['shares_count']):_n(partner['percentage']);
      if(basis>largestBasis){largestBasis=basis;largestIndex=result.length;}
      final amount=((distributableProfit*(basis/basisTotal))*100).roundToDouble()/100;allocated+=amount;
      final withdrawals=await db.rawQuery("SELECT COALESCE(SUM(alayh_amount),0) total FROM lah_alayh_ledger WHERE party_id=? AND substr(entry_date,1,7)=? AND entry_type IN('PARTNER_WITHDRAWAL','PARTNER_PERSONAL_WITHDRAWAL')",[partner['party_id'],periodCode]);
      final withdrawn=_n(withdrawals.first['total']);
      result.add({'partner_id':partner['id'],'party_id':partner['party_id'],'name_ar':partner['name_ar'],'basis_value':basis,'share_amount_lah':amount,'withdrawals_alayh':withdrawn,'net_payable':amount-withdrawn});
    }
    final remainder=((distributableProfit-allocated)*100).roundToDouble()/100;
    if(remainder.abs()>=0.005&&result.isNotEmpty){final row=result[largestIndex];final corrected=_n(row['share_amount_lah'])+remainder;row['share_amount_lah']=corrected;row['net_payable']=corrected-_n(row['withdrawals_alayh']);}
    return result;
  }

  Future<int> createDistribution({required int branchId,required String periodCode,required double reservePct,double additionalLosses=0,double inventoryGain=0}) async {
    if(reservePct<0||reservePct>100)throw ArgumentError('الاحتياطي يجب أن يكون بين 0 و100');
    final profit=await calculatePeriodNetProfit(branchId:branchId,periodCode:periodCode,additionalLosses:additionalLosses,inventoryGain:inventoryGain);
    final net=_n(profit['net_profit']);if(net<0)throw StateError('الفترة حققت خسارة مقدارها ${net.abs().toStringAsFixed(2)} ولا يوجد ربح قابل للتوزيع');
    final distributable=((net*(1-reservePct/100))*100).roundToDouble()/100;
    final p=await policy();final lines=await planDistribution(branchId:branchId,periodCode:periodCode,distributableProfit:distributable);
    final db=await _helper.database;
    return db.transaction((tx)async{
      final no='DIST-${DateTime.now().millisecondsSinceEpoch}';
      final id=await tx.insert('partner_distributions',{'distribution_no':no,'period_code':periodCode,'distribution_mode':p.mode,'total_revenue':_n(profit['net_sales']),'total_cogs':_n(profit['cogs']),'total_expenses_and_losses':_n(profit['total_expenses_and_losses']),'net_profit':net,'reserve_pct':reservePct,'distributable_profit':distributable,'status':'DRAFT','branch_id':branchId});
      for(final line in lines){await tx.insert('partner_distribution_lines',{'distribution_id':id,'partner_id':line['partner_id'],'basis_value':line['basis_value'],'share_amount_lah':line['share_amount_lah'],'withdrawals_alayh':line['withdrawals_alayh'],'net_payable':line['net_payable']});}
      return id;
    });
  }

  Future<void> postPartnerDistribution({required int distributionId}) async {
    final db=await _helper.database;
    await db.transaction((tx)async{
      final distributions=await tx.query('partner_distributions',where:"id=? AND status='DRAFT'",whereArgs:[distributionId],limit:1);
      if(distributions.isEmpty)throw StateError('التوزيع غير موجود أو تم ترحيله مسبقاً');
      final d=distributions.first;final branchId=d['branch_id'] as int;final lines=await tx.query('partner_distribution_lines',where:'distribution_id=?',whereArgs:[distributionId]);
      if(lines.isEmpty)throw StateError('لا توجد تفاصيل توزيع');
      final total=_n(d['distributable_profit']);final retained=await _gl(tx,'3201');final payable=await _gl(tx,'2301');
      final je=await tx.insert('journal_entries',{'uuid':_uuid('je'),'branch_id':branchId,'created_at':_now(),'updated_at':_now(),'entry_no':'DIST-JE-${DateTime.now().microsecondsSinceEpoch}','entry_date':_now(),'description':'توزيع أرباح الفترة ${d['period_code']}','source_type':'PARTNER_DISTRIBUTION','source_id':distributionId,'is_posted':1});
      if(total>0){await _line(tx,branchId,je,retained,dr:total,memo:'توزيع أرباح');await _line(tx,branchId,je,payable,cr:total,memo:'مستحقات الشركاء');}
      for(final line in lines){
        final partner=(await tx.query('partners',where:'id=?',whereArgs:[line['partner_id']],limit:1)).first;final partyId=partner['party_id'] as int;final amount=_n(line['share_amount_lah']);
        if(amount>0){await tx.insert('lah_alayh_ledger',{'uuid':_uuid('profit-share'),'branch_id':branchId,'created_at':_now(),'updated_at':_now(),'party_id':partyId,'entry_date':_now(),'entry_type':'PROFIT_SHARE','alayh_amount':0,'lah_amount':amount,'doc_type':'PARTNER_DISTRIBUTION','doc_id':distributionId,'journal_entry_id':je,'statement_ar':'نصيب أرباح الفترة ${d['period_code']}'});}
      }
      await tx.update('partner_distributions',{'status':'POSTED','journal_entry_id':je},where:'id=?',whereArgs:[distributionId]);
    });
  }

  Future<void> switchDistributionMode({required String newMode,required bool managerApproved}) async {
    if(newMode!='shares'&&newMode!='percentage')throw ArgumentError('نمط التوزيع غير صالح');
    if(!managerApproved)throw StateError('يتطلب تغيير نمط التوزيع اعتماد المالك أو المدير');
    final db=await _helper.database;
    await db.transaction((tx)async{
      final row=await tx.query('app_settings',columns:['value_text'],where:"setting_key='accounting.partner_distribution_mode'",limit:1);
      final current=row.isEmpty?'shares':row.first['value_text'] as String;
      if(current==newMode)return;
      if(newMode=='shares'){
        await tx.update('partners',{'percentage':null,'needs_input':1},where:'1=1');
      }else{
        await tx.update('partners',{'shares_count':null,'needs_input':1},where:'1=1');
      }
      await tx.insert('app_settings',{'setting_key':'accounting.partner_distribution_mode','value_text':newMode,'updated_at':_now()},conflictAlgorithm:ConflictAlgorithm.replace);
    });
  }

  Future<void> savePartner({required int partyId,required int branchId,double capitalAmount=0,int? sharesCount,double? percentage,bool needsInput=false,String? joinDate,bool isActive=true}) async {
    final p=await policy();p.validate(sharesCount:sharesCount,percentage:percentage);
    final db=await _helper.database;
    await db.insert('partners',{'party_id':partyId,'capital_amount':capitalAmount,'shares_count':sharesCount,'percentage':percentage,'needs_input':needsInput?1:0,'join_date':joinDate??_now().substring(0,10),'is_active':isActive?1:0,'branch_id':branchId},conflictAlgorithm:ConflictAlgorithm.abort);
  }

  Future<int> _gl(TransactionExecutor tx,String code) async {final r=await tx.query('chart_of_accounts',columns:['id'],where:'code=?',whereArgs:[code],limit:1);if(r.isEmpty)throw StateError('الحساب المحاسبي $code غير موجود');return r.first['id'] as int;}
  Future<void> _line(TransactionExecutor tx,int branchId,int je,int account,{double dr=0,double cr=0,int? partyId,String? memo}) async {await tx.insert('journal_lines',{'uuid':_uuid('jl'),'branch_id':branchId,'created_at':_now(),'updated_at':_now(),'journal_entry_id':je,'account_id':account,'party_id':partyId,'dr_amount':dr,'cr_amount':cr,'memo':memo});}
}
