// lib/reports_pdf/definitions/r25_to_r32_purchase_definitions.dart
import '../datasources/purchase_and_finance_queries.dart';
import '../models_and_contracts.dart';

ReportColumn _c(String key,String label,{ColType type=ColType.text,bool sum=false,bool cost=false,double width=1}) =>
    ReportColumn(key:key,label:label,type:type,widthWeight:width,sumInTotals:sum,costSensitive:cost);
const _dates=<ReportParam>[
  ReportParam(key:'date_from',label:'من تاريخ',kind:ReportParamKind.date),
  ReportParam(key:'date_to',label:'إلى تاريخ',kind:ReportParamKind.date),
];

List<ReportDefinition> buildR25ToR32PurchaseDefinitions(PurchaseAndFinanceQueries q)=>[
  ConfiguredReportDefinition(number:25,title:'المشتريات التفصيلي حسب الفترة',category:ReportCategory.purchasesAndSuppliers,query:q.r25,params:_dates,signatures:SignatureSpec.purchases,forceLandscape:true,columns:[
    _c('invoice_no','رقم الفاتورة'),_c('supplier_invoice_no','فاتورة المورد'),_c('invoice_date','التاريخ',type:ColType.dateTime),_c('supplier','المورد'),_c('drug','الصنف'),_c('batch_no','التشغيلة'),_c('expiry_date','الصلاحية',type:ColType.date),_c('paid_packs','الكمية المدفوعة',type:ColType.decimal,sum:true),_c('bonus_packs','البونص',type:ColType.decimal,sum:true),_c('pack_price','سعر الباكت',type:ColType.currency,cost:true),_c('discount_pct','الخصم',type:ColType.percent),_c('line_total','إجمالي السطر',type:ColType.currency,sum:true,cost:true),_c('effective_pack_cost','التكلفة الفعلية للباكت بعد البونص',type:ColType.currency,cost:true),
  ],totals:const TotalsSpec(sumKeys:['paid_packs','bonus_packs','line_total'])),
  ConfiguredReportDefinition(number:26,title:'المشتريات الإجمالي حسب المورد والمذخر',category:ReportCategory.purchasesAndSuppliers,query:q.r26,params:_dates,signatures:SignatureSpec.purchases,columns:[
    _c('supplier','المورد'),_c('invoice_count','عدد الفواتير',type:ColType.integer,sum:true),_c('purchases_total','إجمالي المشتريات',type:ColType.currency,sum:true),_c('discounts','الخصومات',type:ColType.currency,sum:true),_c('returns','المرتجعات',type:ColType.currency,sum:true),_c('net_purchases','صافي المشتريات',type:ColType.currency,sum:true),_c('paid_alayh','المدفوع عليه',type:ColType.currency,sum:true),_c('remaining_lah','المتبقي له',type:ColType.currency,sum:true),
  ],totals:const TotalsSpec(sumKeys:['invoice_count','purchases_total','discounts','returns','net_purchases','paid_alayh','remaining_lah'])),
  ConfiguredReportDefinition(number:27,title:'البونص المجاني المكتسب وقيمته المالية',category:ReportCategory.purchasesAndSuppliers,query:q.r27,params:_dates,signatures:SignatureSpec.purchases,columns:[
    _c('supplier','المورد'),_c('drug','الصنف'),_c('paid_packs','الكمية المدفوعة',type:ColType.decimal,sum:true),_c('bonus_packs','باكتات البونص',type:ColType.decimal,sum:true),_c('bonus_pct','نسبة البونص',type:ColType.percent),_c('bonus_cost_value','قيمة البونص بالتكلفة',type:ColType.currency,sum:true,cost:true),_c('bonus_sale_value','قيمة البونص بسعر البيع',type:ColType.currency,sum:true),_c('pack_cost_reduction','مقدار خفض تكلفة الباكت',type:ColType.currency,cost:true),
  ],totals:const TotalsSpec(sumKeys:['paid_packs','bonus_packs','bonus_cost_value','bonus_sale_value'])),
  ConfiguredReportDefinition(number:28,title:'مقارنة أسعار شراء الصنف بين الموردين',category:ReportCategory.purchasesAndSuppliers,query:q.r28,params:[const ReportParam(key:'drug_id',label:'الدواء',kind:ReportParamKind.drug)],signatures:SignatureSpec.purchases,columns:[
    _c('drug','الصنف'),_c('supplier','المورد'),_c('latest_price','آخر سعر شراء',type:ColType.currency,cost:true),_c('lowest_price','أقل سعر',type:ColType.currency,cost:true),_c('bonus_pct','البونص المعتاد',type:ColType.percent),_c('net_pack_cost','التكلفة الفعلية الصافية للباكت',type:ColType.currency,cost:true),_c('best_supplier_rank','الترتيب كأفضل مورد',type:ColType.integer),
  ],totals:const TotalsSpec()),
  ConfiguredReportDefinition(number:29,title:'مرتجعات المشتريات للمذاخر وفروق التسوية',category:ReportCategory.purchasesAndSuppliers,query:q.r29,params:_dates,signatures:SignatureSpec.purchases,columns:[
    _c('return_no','رقم المرتجع'),_c('return_date','التاريخ',type:ColType.dateTime),_c('supplier','المورد'),_c('drug','الصنف'),_c('batch_no','التشغيلة'),_c('quantity','الكمية',type:ColType.decimal,sum:true),_c('batch_cost','تكلفة التشغيلة',type:ColType.currency,sum:true,cost:true),_c('agreed_refund','قيمة الاسترداد المتفق عليها',type:ColType.currency,sum:true),_c('settlement_difference','فرق التسوية',type:ColType.currency,sum:true,cost:true),_c('settlement_method','طريقة التسوية'),
  ],totals:const TotalsSpec(sumKeys:['quantity','batch_cost','agreed_refund','settlement_difference'])),
  ConfiguredReportDefinition(number:30,title:'الأدوية القابلة للاستبدال مع المورد قبل انتهائها',category:ReportCategory.purchasesAndSuppliers,query:q.r30,params:[const ReportParam(key:'expiry_days',label:'الأيام المتبقية للصلاحية',kind:ReportParamKind.number,defaultValue:90)],signatures:SignatureSpec.purchases,columns:[
    _c('drug','الصنف'),_c('batch_no','التشغيلة'),_c('expiry_date','الصلاحية',type:ColType.date),_c('days_remaining','الأيام المتبقية',type:ColType.integer),_c('balance','الرصيد',type:ColType.integer,sum:true),_c('original_supplier','المورد الأصلي'),_c('purchase_invoice','رقم فاتورة الشراء'),_c('expected_refund','قيمة الاسترداد المتوقعة',type:ColType.currency,sum:true,cost:true),
  ],totals:const TotalsSpec(sumKeys:['balance','expected_refund'])),
  ConfiguredReportDefinition(number:31,title:'تغير تكلفة الشراء للأدوية',category:ReportCategory.purchasesAndSuppliers,query:q.r31,params:_dates,signatures:SignatureSpec.purchases,columns:[
    _c('drug','الصنف'),_c('previous_cost','التكلفة السابقة',type:ColType.currency,cost:true),_c('new_cost','التكلفة الجديدة',type:ColType.currency,cost:true),_c('difference','الفرق',type:ColType.currency,cost:true),_c('change_pct','نسبة التغير',type:ColType.percent,cost:true),_c('change_date','تاريخ التغيير',type:ColType.dateTime),_c('document','المستند'),
  ],totals:const TotalsSpec()),
  ConfiguredReportDefinition(number:32,title:'أوامر الشراء المعلقة',category:ReportCategory.purchasesAndSuppliers,query:q.r32,params:_dates,signatures:SignatureSpec.purchases,columns:[
    _c('order_no','رقم الأمر'),_c('order_date','التاريخ',type:ColType.dateTime),_c('supplier','المورد'),_c('drug','الصنف'),_c('requested_packs','المطلوب بالباكت',type:ColType.decimal,sum:true),_c('received_packs','المستلم',type:ColType.decimal,sum:true),_c('remaining_packs','المتبقي',type:ColType.decimal,sum:true),_c('expected_cost','التكلفة المتوقعة',type:ColType.currency,sum:true,cost:true),_c('status','الحالة'),
  ],totals:const TotalsSpec(sumKeys:['requested_packs','received_packs','remaining_packs','expected_cost'])),
];
