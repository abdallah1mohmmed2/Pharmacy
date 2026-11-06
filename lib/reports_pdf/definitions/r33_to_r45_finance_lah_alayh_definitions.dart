// lib/reports_pdf/definitions/r33_to_r45_finance_lah_alayh_definitions.dart
import '../datasources/purchase_and_finance_queries.dart';
import '../models_and_contracts.dart';

ReportColumn _c(String key,String label,{ColType type=ColType.text,bool sum=false,bool cost=false,double width=1}) =>
    ReportColumn(key:key,label:label,type:type,widthWeight:width,sumInTotals:sum,costSensitive:cost);
const _dates=<ReportParam>[
  ReportParam(key:'date_from',label:'من تاريخ',kind:ReportParamKind.date),
  ReportParam(key:'date_to',label:'إلى تاريخ',kind:ReportParamKind.date),
];

class R45PartnerDistributionDefinition extends ReportDefinition {
  R45PartnerDistributionDefinition(PurchaseAndFinanceQueries q)
      : super(
          number:45,
          title:'توزيع أرباح الشركاء النهائي',
          category:ReportCategory.financeAndParties,
          query:q.r45,
          params:const [ReportParam(key:'distribution_id',label:'توزيع الأرباح',kind:ReportParamKind.number)],
          signatures:SignatureSpec.finance,
          columns:const [],
          description:'يعرض نمط التوزيع المعتمد فقط، ويخفي أساس التوزيع غير المستخدم.',
        );

  @override
  Future<ReportDataSet> run(ReportParams params) async {
    final rows=await query(params);
    final mode=rows.isEmpty?'shares':rows.first['distribution_mode']?.toString()??'shares';
    final basisLabel=mode=='percentage'?'النسبة%':'عدد الحصص';
    final columns=<ReportColumn>[
      _c('partner','الشريك'),_c('capital','رأس المال',type:ColType.currency,cost:true),
      _c('basis_value',basisLabel,type:mode=='percentage'?ColType.percent:ColType.decimal),
      _c('profit_share','نصيبه من الربح [له]',type:ColType.currency,sum:true),
      _c('withdrawals_alayh','مسحوباته الشخصية [عليه]',type:ColType.currency,sum:true),
      _c('net_payable','الصافي المستحق [المتبقي له/عليه]',type:ColType.currency,sum:true),
    ];
    return ReportDataSet(
      reportNumber:45,title:title,columns:columns,rows:rows,
      totals:const TotalsSpec(sumKeys:['profit_share','withdrawals_alayh','net_payable'])
          .calculate(rows,columns),
      generatedAt:params.generatedAt,
    );
  }
}

List<ReportDefinition> buildR33ToR45FinanceDefinitions(PurchaseAndFinanceQueries q)=>[
  ConfiguredReportDefinition(number:33,title:'كشف حساب عميل تفصيلي - له وعليه والمتبقي',category:ReportCategory.financeAndParties,query:q.r33,params:[const ReportParam(key:'party_id',label:'العميل',kind:ReportParamKind.customer,required:true),..._dates],signatures:SignatureSpec.finance,columns:[
    _c('date','التاريخ',type:ColType.dateTime),_c('statement','البيان'),_c('document','المستند'),_c('alayh','عليه',type:ColType.currency,sum:true),_c('lah','له',type:ColType.currency,sum:true),_c('remaining','المتبقي',type:ColType.currency),
  ],totals:const TotalsSpec(sumKeys:['alayh','lah'])),
  ConfiguredReportDefinition(number:34,title:'أرصدة جميع العملاء',category:ReportCategory.financeAndParties,query:q.r34,signatures:SignatureSpec.finance,columns:[
    _c('customer','العميل'),_c('phone','الجوال'),_c('total_alayh','إجمالي عليه',type:ColType.currency,sum:true),_c('total_lah','إجمالي له',type:ColType.currency,sum:true),_c('remaining','المتبقي عليه/له',type:ColType.currency,sum:true),_c('credit_limit','الحد الائتماني',type:ColType.currency),_c('credit_usage_pct','نسبة استهلاك الحد',type:ColType.percent),_c('last_movement','آخر حركة',type:ColType.dateTime),
  ],totals:const TotalsSpec(sumKeys:['total_alayh','total_lah','remaining'])),
  ConfiguredReportDefinition(number:35,title:'أعمار الديون للعملاء المتأخرين',category:ReportCategory.financeAndParties,query:q.r35,signatures:SignatureSpec.finance,columns:[
    _c('customer','العميل'),_c('days_0_30','0–30 يوماً',type:ColType.currency,sum:true),_c('days_31_60','31–60 يوماً',type:ColType.currency,sum:true),_c('days_61_90','61–90 يوماً',type:ColType.currency,sum:true),_c('days_91_180','91–180 يوماً',type:ColType.currency,sum:true),_c('days_over_180','أكثر من 180 يوماً',type:ColType.currency,sum:true),_c('total_remaining_alayh','إجمالي المتبقي عليه',type:ColType.currency,sum:true),_c('last_payment','آخر سداد',type:ColType.date),
  ],totals:const TotalsSpec(sumKeys:['days_0_30','days_31_60','days_61_90','days_91_180','days_over_180','total_remaining_alayh'])),
  ConfiguredReportDefinition(number:36,title:'كشف حساب مورد وشركة أدوية تفصيلي',category:ReportCategory.financeAndParties,query:q.r36,params:[const ReportParam(key:'party_id',label:'المورد',kind:ReportParamKind.supplier,required:true),..._dates],signatures:SignatureSpec.finance,columns:[
    _c('date','التاريخ',type:ColType.dateTime),_c('statement','البيان'),_c('document','المستند'),_c('alayh','عليه',type:ColType.currency,sum:true),_c('lah','له',type:ColType.currency,sum:true),_c('remaining','المتبقي',type:ColType.currency),
  ],totals:const TotalsSpec(sumKeys:['alayh','lah'])),
  ConfiguredReportDefinition(number:37,title:'أرصدة جميع الموردين',category:ReportCategory.financeAndParties,query:q.r37,signatures:SignatureSpec.finance,columns:[
    _c('supplier','المورد'),_c('phone','الهاتف'),_c('total_alayh','إجمالي عليه',type:ColType.currency,sum:true),_c('total_lah','إجمالي له',type:ColType.currency,sum:true),_c('remaining','المتبقي له/عليه',type:ColType.currency,sum:true),_c('oldest_due_date','أقدم فاتورة مستحقة',type:ColType.date),_c('overdue_days','أيام التأخر',type:ColType.integer),
  ],totals:const TotalsSpec(sumKeys:['total_alayh','total_lah','remaining'])),
  ConfiguredReportDefinition(number:38,title:'حركة الصندوق والخزينة والمحافظ اليومي',category:ReportCategory.financeAndParties,query:q.r38,params:_dates,signatures:SignatureSpec.finance,columns:[
    _c('time','الوقت',type:ColType.dateTime),_c('account','الحساب'),_c('movement_type','نوع الحركة'),_c('document','المستند'),_c('statement','البيان'),_c('incoming','وارد',type:ColType.currency,sum:true),_c('outgoing','صادر',type:ColType.currency,sum:true),_c('running_balance','الرصيد التراكمي',type:ColType.currency),
  ],totals:const TotalsSpec(sumKeys:['incoming','outgoing'])),
  ConfiguredReportDefinition(number:39,title:'إغلاق الورديات ومطابقة العجز والزيادة للكاشير',category:ReportCategory.financeAndParties,query:q.r39,params:_dates,signatures:SignatureSpec.finance,columns:[
    _c('shift_no','رقم الوردية'),_c('cashier','الكاشير'),_c('opened_at','الفتح',type:ColType.dateTime),_c('closed_at','الإغلاق',type:ColType.dateTime),_c('opening_cash','الافتتاحي',type:ColType.currency,sum:true),_c('cash_sales','نقد المبيعات',type:ColType.currency,sum:true),_c('expected_cash','المتوقع',type:ColType.currency,sum:true),_c('counted_cash','الفعلي المعدود',type:ColType.currency,sum:true),_c('difference','الفرق عجز/زيادة',type:ColType.currency,sum:true),_c('handling','المعالجة عليه/له'),
  ],totals:const TotalsSpec(sumKeys:['opening_cash','cash_sales','expected_cash','counted_cash','difference'])),
  ConfiguredReportDefinition(number:40,title:'المصروفات التشغيلية مفصلة حسب البند',category:ReportCategory.financeAndParties,query:q.r40,params:_dates,signatures:SignatureSpec.finance,columns:[
    _c('date','التاريخ',type:ColType.dateTime),_c('voucher','رقم السند'),_c('category','البند'),_c('statement','البيان'),_c('beneficiary','المستفيد'),_c('payment_account','حساب الدفع'),_c('amount','المبلغ',type:ColType.currency,sum:true),_c('expense_pct','النسبة من إجمالي المصروفات',type:ColType.percent),
  ],totals:const TotalsSpec(sumKeys:['amount'])),
  ConfiguredReportDefinition(number:41,title:'سندات القبض والصرف والتسويات',category:ReportCategory.financeAndParties,query:q.r41,params:_dates,signatures:SignatureSpec.finance,columns:[
    _c('voucher_no','رقم السند'),_c('voucher_type','النوع قبض/صرف/تسوية'),_c('date','التاريخ',type:ColType.dateTime),_c('party','الطرف'),_c('method','الطريقة'),_c('notification_no','رقم الإشعار'),_c('statement','البيان'),_c('amount','المبلغ',type:ColType.currency,sum:true),
  ],totals:const TotalsSpec(sumKeys:['amount'])),
  ConfiguredReportDefinition(number:42,title:'قائمة الدخل المبسطة - الأرباح والخسائر الصافية',category:ReportCategory.financeAndParties,query:q.r42,params:_dates,signatures:SignatureSpec.finance,columns:[
    _c('line','البند المالي'),_c('amount','المبلغ',type:ColType.currency,sum:true),_c('margin_pct','نسبة صافي الربح',type:ColType.percent),
  ],totals:const TotalsSpec()),
  ConfiguredReportDefinition(number:43,title:'المركز المالي المبسط للصيدلية',category:ReportCategory.financeAndParties,query:q.r43,signatures:SignatureSpec.finance,columns:[
    _c('section','القسم المالي'),_c('amount','القيمة',type:ColType.currency,sum:true),
  ],totals:const TotalsSpec(sumKeys:['amount'])),
  ConfiguredReportDefinition(number:44,title:'كشف حساب موظف ورواتبه - له وعليه والصافي',category:ReportCategory.financeAndParties,query:q.r44,params:[const ReportParam(key:'party_id',label:'الموظف',kind:ReportParamKind.employee,required:true),..._dates],signatures:SignatureSpec.finance,columns:[
    _c('date','التاريخ',type:ColType.dateTime),_c('statement','البيان'),_c('document','المستند'),_c('alayh','عليه - سلف وخصومات وعجز',type:ColType.currency,sum:true),_c('lah','له - رواتب ويوميات ومكافآت',type:ColType.currency,sum:true),_c('remaining','المتبقي التراكمي',type:ColType.currency),
  ],totals:const TotalsSpec(sumKeys:['alayh','lah'])),
  R45PartnerDistributionDefinition(q),
];
