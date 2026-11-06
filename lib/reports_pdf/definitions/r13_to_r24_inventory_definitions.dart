// lib/reports_pdf/definitions/r13_to_r24_inventory_definitions.dart
import '../datasources/sales_and_inventory_queries.dart';
import '../models_and_contracts.dart';

ReportColumn _c(String key,String label,{ColType type=ColType.text,double width=1,bool sum=false,bool cost=false}) =>
    ReportColumn(key:key,label:label,type:type,widthWeight:width,sumInTotals:sum,costSensitive:cost);
const _dates=<ReportParam>[
  ReportParam(key:'date_from',label:'من تاريخ',kind:ReportParamKind.date),
  ReportParam(key:'date_to',label:'إلى تاريخ',kind:ReportParamKind.date),
];

List<ReportDefinition> buildR13ToR24InventoryDefinitions(SalesAndInventoryQueries q)=>[
  ConfiguredReportDefinition(number:13,title:'الجرد المخزني الشامل بالتكلفة وسعر البيع',category:ReportCategory.inventoryAndExpiry,query:q.r13,signatures:SignatureSpec.inventory,forceLandscape:true,columns:[
    _c('drug','الصنف'),_c('strength','التركيز'),_c('sealed_packs','باكتات مغلقة',type:ColType.integer,sum:true),_c('loose_units','حبات سائبة',type:ColType.integer,sum:true),_c('total_units','الرصيد بالحبة',type:ColType.integer,sum:true),_c('pack_cost','تكلفة الباكت',type:ColType.currency,cost:true),_c('cost_value','قيمة التكلفة',type:ColType.currency,sum:true,cost:true),_c('sell_pack','سعر بيع الباكت',type:ColType.currency),_c('sale_value','قيمة البيع',type:ColType.currency,sum:true),_c('expected_profit','الربح المتوقع',type:ColType.currency,sum:true,cost:true),
  ],totals:const TotalsSpec(sumKeys:['sealed_packs','loose_units','total_units','cost_value','sale_value','expected_profit'])),
  ConfiguredReportDefinition(number:14,title:'الأدوية المنتهية الصلاحية فعلياً والخسائر',category:ReportCategory.inventoryAndExpiry,query:q.r14,signatures:SignatureSpec.inventory,columns:[
    _c('drug','الصنف'),_c('batch_no','التشغيلة'),_c('expiry_date','الصلاحية',type:ColType.date),_c('days_expired','أيام الانتهاء',type:ColType.integer),_c('balance','الرصيد',type:ColType.integer,sum:true),_c('unit_cost','تكلفة الوحدة',type:ColType.currency,cost:true),_c('loss_value','قيمة الخسارة',type:ColType.currency,sum:true,cost:true),_c('location','الموقع'),_c('supplier','المورد'),
  ],totals:const TotalsSpec(sumKeys:['balance','loss_value'])),
  ConfiguredReportDefinition(number:15,title:'الأدوية قريبة الانتهاء خلال 30 و60 و90 يوماً',category:ReportCategory.inventoryAndExpiry,query:q.r15,params:[const ReportParam(key:'expiry_days',label:'حد الصلاحية بالأيام',kind:ReportParamKind.number,defaultValue:90)],signatures:SignatureSpec.inventory,columns:[
    _c('segment','الشريحة'),_c('drug','الصنف'),_c('batch_no','التشغيلة'),_c('expiry_date','الصلاحية',type:ColType.date),_c('days_remaining','الأيام المتبقية',type:ColType.integer),_c('balance','الرصيد',type:ColType.integer,sum:true),_c('cost_value','قيمة التكلفة',type:ColType.currency,sum:true,cost:true),_c('average_daily_sales','متوسط البيع اليومي',type:ColType.decimal),_c('expected_clearance_days','أيام التصريف المتوقعة',type:ColType.decimal),_c('recommended_action','الإجراء المقترح'),
  ],totals:const TotalsSpec(sumKeys:['balance','cost_value'])),
  ConfiguredReportDefinition(number:16,title:'حركة صنف تفصيلي - كارت الصنف',category:ReportCategory.inventoryAndExpiry,query:q.r16,params:[const ReportParam(key:'drug_id',label:'الدواء',kind:ReportParamKind.drug,required:true),..._dates],signatures:SignatureSpec.inventory,columns:[
    _c('movement_date','التاريخ',type:ColType.dateTime),_c('movement_type','نوع الحركة'),_c('document','المستند'),_c('batch_no','التشغيلة'),_c('incoming','وارد',type:ColType.decimal,sum:true),_c('outgoing','صادر',type:ColType.decimal,sum:true),_c('running_balance','الرصيد التراكمي',type:ColType.decimal),_c('unit_cost','تكلفة الوحدة',type:ColType.currency,cost:true),
  ],totals:const TotalsSpec(sumKeys:['incoming','outgoing'])),
  ConfiguredReportDefinition(number:17,title:'النواقص والحد الأدنى للطلب',category:ReportCategory.inventoryAndExpiry,query:q.r17,signatures:SignatureSpec.inventory,columns:[
    _c('drug','الصنف'),_c('current_balance','الرصيد الحالي',type:ColType.integer),_c('minimum_stock','الحد الأدنى',type:ColType.integer),_c('shortage','مقدار العجز',type:ColType.integer,sum:true),_c('average_daily_sales','متوسط البيع اليومي',type:ColType.decimal),_c('suggested_order_packs','الكمية المقترحة بالباكت',type:ColType.decimal,sum:true),_c('preferred_supplier','المورد الأفضل'),_c('expected_cost','التكلفة المتوقعة',type:ColType.currency,sum:true,cost:true),
  ],totals:const TotalsSpec(sumKeys:['shortage','suggested_order_packs','expected_cost'])),
  ConfiguredReportDefinition(number:18,title:'الأدوية حسب الموقع والرف',category:ReportCategory.inventoryAndExpiry,query:q.r18,signatures:SignatureSpec.inventory,columns:[
    _c('location','الموقع والرف'),_c('drug','الصنف'),_c('batch_no','التشغيلة'),_c('expiry_date','الصلاحية',type:ColType.date),_c('balance','الرصيد',type:ColType.integer,sum:true),_c('cost_value','قيمة التكلفة',type:ColType.currency,sum:true,cost:true),
  ],totals:const TotalsSpec(sumKeys:['balance','cost_value'])),
  ConfiguredReportDefinition(number:19,title:'جرد التشغيلات التفصيلي - Batch Balances',category:ReportCategory.inventoryAndExpiry,query:q.r19,signatures:SignatureSpec.inventory,forceLandscape:true,columns:[
    _c('drug','الصنف'),_c('batch_no','رقم التشغيلة'),_c('expiry_date','الصلاحية',type:ColType.date),_c('status','الحالة'),_c('sealed_packs','باكتات مغلقة',type:ColType.integer,sum:true),_c('loose_units','حبات سائبة',type:ColType.integer,sum:true),_c('total_units','إجمالي الحبات',type:ColType.integer,sum:true),_c('pack_cost','تكلفة الباكت',type:ColType.currency,cost:true),_c('total_value','إجمالي القيمة',type:ColType.currency,sum:true,cost:true),
  ],totals:const TotalsSpec(sumKeys:['sealed_packs','loose_units','total_units','total_value'])),
  ConfiguredReportDefinition(number:20,title:'الفروقات الجردية - العجز والزيادة',category:ReportCategory.inventoryAndExpiry,query:q.r20,params:[const ReportParam(key:'session_id',label:'جلسة الجرد',kind:ReportParamKind.number,required:true)],signatures:SignatureSpec.inventory,columns:[
    _c('drug','الصنف'),_c('batch_no','التشغيلة'),_c('book_balance','الرصيد الدفتري',type:ColType.integer,sum:true),_c('actual_count','العد الفعلي',type:ColType.integer,sum:true),_c('difference','الفرق',type:ColType.integer,sum:true),_c('difference_type','عجز/زيادة'),_c('unit_cost','تكلفة الوحدة',type:ColType.currency,cost:true),_c('difference_value','قيمة الفرق',type:ColType.currency,sum:true,cost:true),_c('reason','السبب'),
  ],totals:const TotalsSpec(sumKeys:['book_balance','actual_count','difference','difference_value'])),
  ConfiguredReportDefinition(number:21,title:'الأدوية التالفة والمعدومة',category:ReportCategory.inventoryAndExpiry,query:q.r21,params:_dates,signatures:SignatureSpec.inventory,columns:[
    _c('document_no','رقم المحضر'),_c('date','التاريخ',type:ColType.dateTime),_c('drug','الصنف'),_c('batch_no','التشغيلة'),_c('quantity','الكمية',type:ColType.integer,sum:true),_c('reason','السبب'),_c('disposal_method','طريقة الإتلاف'),_c('loss_value','قيمة الخسارة',type:ColType.currency,sum:true,cost:true),_c('witness','الشاهد'),
  ],totals:const TotalsSpec(sumKeys:['quantity','loss_value'])),
  ConfiguredReportDefinition(number:22,title:'التحويلات المخزنية',category:ReportCategory.inventoryAndExpiry,query:q.r22,params:_dates,signatures:SignatureSpec.inventory,columns:[
    _c('transfer_no','رقم التحويل'),_c('date','التاريخ',type:ColType.dateTime),_c('from_warehouse','من مستودع'),_c('to_warehouse','إلى مستودع'),_c('drug','الصنف'),_c('batch_no','التشغيلة'),_c('sent_qty','الكمية المرسلة',type:ColType.integer,sum:true),_c('received_qty','الكمية المستلمة',type:ColType.integer,sum:true),_c('receiving_difference','فرق الاستلام',type:ColType.integer,sum:true),_c('value','القيمة',type:ColType.currency,sum:true,cost:true),_c('status','الحالة'),
  ],totals:const TotalsSpec(sumKeys:['sent_qty','received_qty','receiving_difference','value'])),
  ConfiguredReportDefinition(number:23,title:'تقييم المخزون حسب التصنيف الدوائي',category:ReportCategory.inventoryAndExpiry,query:q.r23,signatures:SignatureSpec.inventory,columns:[
    _c('therapeutic_category','الفئة العلاجية'),_c('drug_count','عدد الأصناف',type:ColType.integer,sum:true),_c('total_units','إجمالي الحبات',type:ColType.integer,sum:true),_c('cost_value','قيمة التكلفة',type:ColType.currency,sum:true,cost:true),_c('sale_value','قيمة البيع',type:ColType.currency,sum:true),_c('inventory_percentage','نسبة من إجمالي المخزون',type:ColType.percent),
  ],totals:const TotalsSpec(sumKeys:['drug_count','total_units','cost_value','sale_value'])),
  ConfiguredReportDefinition(number:24,title:'معدل دوران المخزون',category:ReportCategory.inventoryAndExpiry,query:q.r24,params:_dates,signatures:SignatureSpec.inventory,columns:[
    _c('drug','الصنف'),_c('opening_stock','مخزون أول المدة',type:ColType.integer),_c('closing_stock','مخزون آخر المدة',type:ColType.integer),_c('average_stock','متوسط المخزون',type:ColType.decimal),_c('cogs','تكلفة البضاعة المباعة',type:ColType.currency,sum:true,cost:true),_c('turnover_rate','معدل الدوران',type:ColType.decimal),_c('days_inventory','أيام البقاء في المخزن',type:ColType.decimal),
  ],totals:const TotalsSpec(sumKeys:['cogs'])),
];
