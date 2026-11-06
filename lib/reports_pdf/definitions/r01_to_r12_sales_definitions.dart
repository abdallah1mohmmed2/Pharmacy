// lib/reports_pdf/definitions/r01_to_r12_sales_definitions.dart
import '../datasources/sales_and_inventory_queries.dart';
import '../models_and_contracts.dart';

ReportColumn _c(String key,String label,{ColType type=ColType.text,double width=1,bool sum=false,bool cost=false,ColAlign align=ColAlign.start}) =>
    ReportColumn(key:key,label:label,type:type,widthWeight:width,sumInTotals:sum,costSensitive:cost,align:align);

const _dates = <ReportParam>[
  ReportParam(key:'date_from',label:'من تاريخ',kind:ReportParamKind.date),
  ReportParam(key:'date_to',label:'إلى تاريخ',kind:ReportParamKind.date),
];

List<ReportDefinition> buildR01ToR12SalesDefinitions(SalesAndInventoryQueries q) => [
  ConfiguredReportDefinition(number:1,title:'المبيعات اليومي التفصيلي',category:ReportCategory.salesAndProfit,query:q.r01,params:_dates,signatures:SignatureSpec.sales,columns:[
    _c('invoice_no','رقم الفاتورة'),_c('invoice_time','الوقت'),_c('customer','العميل'),_c('cashier','الكاشير'),_c('payment_method','طريقة الدفع'),
    _c('gross','الإجمالي قبل الخصم',type:ColType.currency,sum:true),_c('discount','الخصم',type:ColType.currency,sum:true),_c('net','الصافي',type:ColType.currency,sum:true),_c('paid','المدفوع',type:ColType.currency,sum:true),_c('remaining','المتبقي عليه',type:ColType.currency,sum:true),
  ],totals:const TotalsSpec(sumKeys:['gross','discount','net','paid','remaining'])),
  ConfiguredReportDefinition(number:2,title:'المبيعات الإجمالي حسب الفترة',category:ReportCategory.salesAndProfit,query:q.r02,params:[..._dates,const ReportParam(key:'grouping',label:'التجميع',kind:ReportParamKind.category,defaultValue:'daily',options:['daily','monthly'])],signatures:SignatureSpec.sales,columns:[
    _c('period','الفترة'),_c('invoice_count','عدد الفواتير',type:ColType.integer,sum:true),_c('gross_sales','إجمالي المبيعات',type:ColType.currency,sum:true),_c('discounts','الخصومات',type:ColType.currency,sum:true),_c('returns','المرتجعات',type:ColType.currency,sum:true),_c('net_sales','صافي المبيعات',type:ColType.currency,sum:true),_c('average_invoice','متوسط الفاتورة',type:ColType.currency),
  ],totals:TotalsSpec(sumKeys:['invoice_count','gross_sales','discounts','returns','net_sales'],derivedValues:{'average_invoice':(v)=>v['invoice_count']!>0?v['net_sales']!/v['invoice_count']!:0})),
  ConfiguredReportDefinition(number:3,title:'مبيعات كل كاشير وصيدلي',category:ReportCategory.salesAndProfit,query:q.r03,params:_dates,signatures:SignatureSpec.sales,columns:[
    _c('cashier','الكاشير'),_c('invoice_count','عدد الفواتير',type:ColType.integer,sum:true),_c('gross_sales','إجمالي المبيعات',type:ColType.currency,sum:true),_c('cash_total','النقد',type:ColType.currency,sum:true),_c('wallets_total','المحافظ',type:ColType.currency,sum:true),_c('credit_total','الآجل',type:ColType.currency,sum:true),_c('discounts','الخصومات',type:ColType.currency,sum:true),_c('returns','المرتجعات',type:ColType.currency,sum:true),_c('shift_difference','عجز/زيادة الورديات',type:ColType.currency,sum:true),_c('average_invoice','متوسط الفاتورة',type:ColType.currency),
  ],totals:TotalsSpec(sumKeys:['invoice_count','gross_sales','cash_total','wallets_total','credit_total','discounts','returns','shift_difference'],derivedValues:{'average_invoice':(v)=>v['invoice_count']!>0?(v['gross_sales']!-v['discounts']!-v['returns']!)/v['invoice_count']!:0})),
  ConfiguredReportDefinition(number:4,title:'المبيعات حسب طريقة الدفع',category:ReportCategory.salesAndProfit,query:q.r04,params:_dates,signatures:SignatureSpec.sales,columns:[
    _c('payment_method','طريقة الدفع'),_c('operation_count','عدد العمليات',type:ColType.integer,sum:true),_c('amount','المبلغ',type:ColType.currency,sum:true),_c('percentage','النسبة من الإجمالي',type:ColType.percent),
  ],totals:TotalsSpec(sumKeys:['operation_count','amount'],derivedValues:{'percentage':(v)=>v['amount']!>0?100:0})),
  ConfiguredReportDefinition(number:5,title:'حوالات المحافظ الإلكترونية وأرقام الإشعارات',category:ReportCategory.salesAndProfit,query:q.r05,params:_dates,signatures:SignatureSpec.sales,columns:[
    _c('tx_date','التاريخ',type:ColType.dateTime),_c('document_no','رقم الفاتورة/السند'),_c('wallet','المحفظة'),_c('notification_no','رقم الإشعار'),_c('sender_phone','هاتف المرسل'),_c('amount','المبلغ',type:ColType.currency,sum:true),_c('cashier','الكاشير'),_c('duplicate_alert','تنبيه التكرار',type:ColType.boolean),
  ],totals:const TotalsSpec(sumKeys:['amount'])),
  ConfiguredReportDefinition(number:6,title:'الأرباح الهامشية لكل فاتورة',category:ReportCategory.salesAndProfit,query:q.r06,params:_dates,signatures:SignatureSpec.sales,columns:[
    _c('invoice_no','رقم الفاتورة'),_c('invoice_date','التاريخ',type:ColType.dateTime),_c('net_sales','صافي المبيعات',type:ColType.currency,sum:true),_c('cogs','تكلفة البضاعة',type:ColType.currency,sum:true,cost:true),_c('gross_profit','مجمل الربح',type:ColType.currency,sum:true,cost:true),_c('margin_pct','هامش الربح',type:ColType.percent,cost:true),
  ],totals:TotalsSpec(sumKeys:['net_sales','cogs','gross_profit'],derivedValues:{'margin_pct':(v)=>v['net_sales']!>0?v['gross_profit']!*100/v['net_sales']!:0})),
  ConfiguredReportDefinition(number:7,title:'الأصناف الأكثر مبيعاً كمية وربحاً',category:ReportCategory.salesAndProfit,query:q.r07,params:_dates,signatures:SignatureSpec.sales,columns:[
    _c('rank','الترتيب',type:ColType.integer),_c('drug','الصنف'),_c('category','الفئة'),_c('units_sold','الكمية المباعة بالحبة والباكت',type:ColType.decimal,sum:true),_c('sales_value','قيمة المبيعات',type:ColType.currency,sum:true),_c('cost_value','التكلفة',type:ColType.currency,sum:true,cost:true),_c('profit','الربح',type:ColType.currency,sum:true,cost:true),_c('margin_pct','هامش الربح',type:ColType.percent,cost:true),_c('contribution_pct','نسبة المساهمة',type:ColType.percent,cost:true),
  ],totals:TotalsSpec(sumKeys:['units_sold','sales_value','cost_value','profit'],derivedValues:{'margin_pct':(v)=>v['sales_value']!>0?v['profit']!*100/v['sales_value']!:0,'contribution_pct':(v)=>v['profit']!>0?100:0})),
  ConfiguredReportDefinition(number:8,title:'الأصناف الراكدة غير المباعة',category:ReportCategory.salesAndProfit,query:q.r08,params:[const ReportParam(key:'idle_days',label:'أيام الركود',kind:ReportParamKind.number,defaultValue:60)],signatures:SignatureSpec.inventory,columns:[
    _c('drug','الصنف'),_c('balance','الرصيد',type:ColType.integer,sum:true),_c('cost_value','قيمة التكلفة',type:ColType.currency,sum:true,cost:true),_c('last_sale','تاريخ آخر بيع',type:ColType.date),_c('idle_days','أيام الركود',type:ColType.integer),_c('nearest_expiry','أقرب صلاحية',type:ColType.date),
  ],totals:const TotalsSpec(sumKeys:['balance','cost_value'])),
  ConfiguredReportDefinition(number:9,title:'مبيعات الفرط مقابل الباكتات',category:ReportCategory.salesAndProfit,query:q.r09,params:_dates,signatures:SignatureSpec.sales,columns:[
    _c('drug','الصنف'),_c('pack_qty','كمية الباكت',type:ColType.decimal,sum:true),_c('pack_value','قيمة الباكت',type:ColType.currency,sum:true),_c('strip_qty','كمية الأشرطة',type:ColType.decimal,sum:true),_c('strip_value','قيمة الأشرطة',type:ColType.currency,sum:true),_c('unit_qty','كمية الحبات',type:ColType.decimal,sum:true),_c('unit_value','قيمة الحبات',type:ColType.currency,sum:true),_c('total_value','إجمالي القيمة',type:ColType.currency,sum:true),_c('loose_pct','نسبة الفرط',type:ColType.percent),
  ],totals:TotalsSpec(sumKeys:['pack_qty','pack_value','strip_qty','strip_value','unit_qty','unit_value','total_value'],derivedValues:{'loose_pct':(v)=>v['total_value']!>0?(v['strip_value']!+v['unit_value']!)*100/v['total_value']!:0})),
  ConfiguredReportDefinition(number:10,title:'الخصومات الممنوحة للعملاء',category:ReportCategory.salesAndProfit,query:q.r10,params:_dates,signatures:SignatureSpec.sales,columns:[
    _c('date','التاريخ',type:ColType.dateTime),_c('invoice_no','الفاتورة'),_c('customer','العميل'),_c('cashier','الكاشير'),_c('gross','الإجمالي قبل الخصم',type:ColType.currency,sum:true),_c('discount_pct','نسبة الخصم',type:ColType.percent),_c('discount','مبلغ الخصم',type:ColType.currency,sum:true),_c('approving_manager','المدير المجيز للتجاوز'),
  ],totals:TotalsSpec(sumKeys:['gross','discount'],derivedValues:{'discount_pct':(v)=>v['gross']!>0?v['discount']!*100/v['gross']!:0})),
  ConfiguredReportDefinition(number:11,title:'مرتجعات المبيعات وأسبابها',category:ReportCategory.salesAndProfit,query:q.r11,params:_dates,signatures:SignatureSpec.sales,columns:[
    _c('return_no','رقم المرتجع'),_c('return_date','التاريخ',type:ColType.dateTime),_c('original_invoice','الفاتورة الأصلية'),_c('drug','الصنف'),_c('quantity','الكمية',type:ColType.decimal,sum:true),_c('refund_value','قيمة الرد',type:ColType.currency,sum:true),_c('refund_method','طريقة الرد'),_c('reason','السبب'),_c('inspection_decision','قرار الفحص'),
  ],totals:const TotalsSpec(sumKeys:['quantity','refund_value'])),
  ConfiguredReportDefinition(number:12,title:'ذروة المبيعات حسب ساعات اليوم',category:ReportCategory.salesAndProfit,query:q.r12,params:_dates,signatures:SignatureSpec.sales,columns:[
    _c('hour','الساعة',type:ColType.integer),_c('invoice_count','عدد الفواتير',type:ColType.integer,sum:true),_c('sales_total','إجمالي المبيعات',type:ColType.currency,sum:true),_c('average_invoice','متوسط الفاتورة',type:ColType.currency),_c('day_percentage','نسبة الساعة من اليوم',type:ColType.percent),
  ],totals:TotalsSpec(sumKeys:['invoice_count','sales_total'],derivedValues:{'average_invoice':(v)=>v['invoice_count']!>0?v['sales_total']!/v['invoice_count']!:0,'day_percentage':(v)=>v['sales_total']!>0?100:0})),
];
