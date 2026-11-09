# F10–F16 — تدقيق موحد لعقود العمليات المالية (قبل التنفيذ)

**الحالة:** تدقيق مصدر مكتمل؛ **الربط عبر جهازين BLOCKED** حتى تنفيذ عقود المجال واختبارها. هذه الوثيقة ليست شهادة إتمام F10–F16.

## نتيجة مراجعة الشيفرة الفعلية

فُحصت الخدمات السبع في `lib/data/services`. خدمة السند النقدي وحدها تستخدم `FinancialVoucherOperation` لالتقاط عملية مالية كاملة. الخدمات أدناه تحتوي معاملات SQLite محلية لكنها **لا تكتب** `financial_operation_outbox` بعقد موثوق ضمن نفس المعاملة. لذلك يمنع نسخ صفوفها المالية عبر المزامنة العامة أو افتراض أن نجاح سند CASH يغطيها.

| المهمة | مصدر الأمر الحقيقي | أعضاء الغلاف المطلوب إثباتهم | شرط التطبيق على الوجهة |
|---|---|---|---|
| F10 | `posting_and_sales_service.dart:postSale` | sales_invoices، sales_invoice_items، sales_payments، cash_transactions، lah_alayh_ledger، journal_entries، journal_lines، صرف الدفعات المخزنية | UUID مستقل لكل عضو، مطابقة مجموع البنود/الخصم/الضريبة/الدفع، التوازن والمخزون، بلا استدعاء postSale |
| F11 | `purchase_and_bonus_service.dart:postInvoice` | purchase_invoices، purchase_invoice_items، batches_fefo، stock_movements، supplier ledger، cash_transactions والقيود حيث تنشأ | المورد/الصنف/الدفعة معرفات عامة، تكلفة/سعر متوافقان، لا UUID مشتق من ID محلي |
| F12 | `rx_and_returns_service.dart:createSalesReturn` و`purchase_and_bonus_service.dart:postPurchaseReturn` | رأس المرتجع وبنوده، مرجع الأصل، عكس حركة الصندوق/الطرف/المخزون والقيد | أصل معتمد أولاً؛ منع تجاوز الكمية المرتجعة، عكس ذري، عدم ترحيل جديد على الوجهة |
| F13 | `inventory_operations_service.dart:approveStocktaking/createDisposal/dispatchTransfer/receiveTransfer` | جلسة الجرد وفروقاتها أو الإتلاف وبنوده أو التحويل وإرساله واستلامه، stock_movements والقيد | لا last-write-wins للأرصدة؛ تحويل الفرعين يتطلب بروتوكول مرحلتين/حالات مستقل، لا معاملة موزعة وهمية |
| F14 | `shift_and_treasury_service.dart:transfer/recordExpense/closeShiftBlind` | أصل حركة الصندوق والمصروف/الوردية، التسوية والقيد وبنوده | لا نقل current_balance/expectedCash كحقائق مستقلة؛ منع حركة ثانية عند replay |
| F15 | `hr_and_payroll_service.dart:postEmployeeAdvance/approvePayroll/payPayroll` | سلفة/استحقاق/دفع، حركة صندوق، ledger، قيد وبنوده | عزل معرفات الموظفين وحقول الأجور/الحضور، صلاحيات خاصة ومراجعة خصوصية قبل السماح |
| F16 | `partner_distribution_service.dart:postPartnerDistribution/recordPartnerWithdrawal` | توزيع وبنوده أو سحب، حركة صندوق، journal_entries/lines، مرجع الشريك | UUID الشريك والفرع، توازن وتفرد السحب وعدم تكرار القيد |

## حواجز مشتركة ملزمة

1. الالتقاط يجب أن يحدث **داخل معاملة كتابة المصدر**، وإلا فلا يجوز إنشاء envelope لاحقاً من الحالة المتغيرة.
2. `operation_uuid` وUUID كل عضو/اعتماد عام وثابت؛ أرقام SQLite المحلية لا تعبر الأجهزة. السجلات القديمة ذات المعرفات المشتقة من local ID تحتاج استراتيجية ترحيل صريحة لا تعديل اعتباطي.
3. كل نوع له `operation_type` و`schema_version` و`member manifest` محدد الحقول والعدد؛ رفض عضو ناقص أو زائد أو تلاعب بالمبلغ حتى لو تغير hash.
4. تطبيق مباشر ذري للأعضاء وInbox؛ لا استدعاء دوال ترحيل الأعمال على الوجهة، ولا استبدال أرصدة الصندوق والمخزون المشتقة.
5. عند تعارض UUID/hash أو اعتماد مفقود: rollback كامل، مؤشر relay لا يتقدم؛ إعادة المحاولة آمنة.
6. العملة المالية YER و`fraction_digits=0` في هذا المشروع؛ رفض الكسور والتجاوز وعدم التوازن.
7. منع تفعيل نقل هذه الأنواع حتى اعتماد تحقق الخادم F17 وفحوص المجال F18–F20. خصوصية F15 حاجز إضافي.

## ترتيب التنفيذ لتقليل المخاطر

F10 ثم F11 ثم F12 (يعتمد على الأصل)، F13 (بروتوكول تحويل خاص)، F14، F15 (خصوصية أولاً)، F16. لكل نوع: خريطة مخطط SQLite، عقد JSON، التقاط ذري، تطبيق مباشر، اختبارات قاعدتين/انقطاع/تعارض/توازن، CI أخضر على HEAD. لا تُغلق أي مهمة باختبار مستند نقدي فقط.

## ما لم يُنفذ بعد

لم تُضف عقود النقل للأنواع السبعة أو التقاطها أو إسقاطاتها؛ لا توجد شهادة اختبار قاعدة A إلى B لهذه الأنواع. **لا تُعلن F10–F16 DONE** بناءً على هذا التدقيق.
