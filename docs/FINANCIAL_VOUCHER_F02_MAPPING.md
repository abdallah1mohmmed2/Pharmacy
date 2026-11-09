# F02 — خريطة أعضاء وحقول السند النقدي الفعلي

**التاريخ:** 2026-11-09  
**الحالة:** مراجعة المصدر مكتملة (توثيق فقط)  
**النطاق:** `RECEIPT` و`PAYMENT` مع `method='CASH'` فقط. لا يشمل البيع أو التسوية أو البنك أو المحفظة.  
**مصادر الحقيقة:** `lib/data/services/posting_and_sales_service.dart`، `lib/data/services/financial_voucher_operation.dart`، `lib/data/services/cash_voucher_integrity_validator.dart`، `lib/data/database/schema_iteration13.dart`.

## 1. حد العملية وما هو منفذ

- `PostingAndSalesService.postVoucher` ينشئ السند وحركة الطرف وحركة الصندوق والقيد وبنديه في معاملة SQLite واحدة. بعد ربط `vouchers.journal_entry_id`، يستدعي `FinancialVoucherOperation.capturePostedCashVoucher` داخل **نفس المعاملة** فقط إذا `financialSyncFractionDigits != null` و`method == 'CASH'`. الإعداد `null` افتراضياً؛ لا تُفعّل المزامنة تلقائياً.
- الالتقاط يقرأ الأعضاء من المصدر، يشغّل `CashVoucherIntegrityValidator.validate`، يكوّن غلافاً ثابتاً، ويحفظ `payload_json` و`payload_hash` في `financial_operation_outbox`، مع `operation_uuid = voucher.uuid`.
- الاستقبال `FinancialVoucherOperation.applyVerified` يتطلب trusted relay وهوية فرع مطابقة، ويتحقق من hash والحقول والاعتماديات ثم يدرج الإسقاطات مع إيصال `financial_operation_inbox` في معاملة واحدة. لا يستدعي `postVoucher` مجدداً.
- هذا موجود مسبقاً؛ **لم يُعاد تنفيذه في F02**.

## 2. خريطة الأعضاء التي تنتقل فعلياً

| العضو | مصدر SQLite / الرابط المحلي | الحقول المنقولة في غلاف v1 | UUID والعلاقة على الوجهة | تحقق موجود / حدّه |
|---|---|---|---|---|
| حد العملية والفرع | `branches.id/uuid` + `vouchers.uuid` | `schema_version`, `operation_uuid`, `branch_uuid`, `fraction_digits` | UUID الفرع، وUUID السند هو UUID العملية | schema=1، branch UUID متطابق، hash SHA-256؛ hash ليس توقيعاً |
| السند | `vouchers`: `id`, `uuid`, `voucher_type`, `voucher_date`, `party_id`, `cash_account_id`, `amount`, `method`, `journal_entry_id` | `voucher.uuid/type/date/party_uuid/cash_uuid/amount_minor` | `party_uuid` و`cash_uuid` يحلان إلى IDs محلية؛ `journal_entry_id` يُنشأ محلياً | CASH وRECEIPT/PAYMENT فقط، مبلغ موجب؛ رقم السند المحلي لا ينتقل |
| القيد | `journal_entries`: `id`, `uuid`, `source_type='VOUCHER'`, `source_id=voucher.id`, `is_posted=1`, `entry_date` | `journal.uuid/date` | `source_id` يعاد ربطه بـID السند الجديد محلياً | قيد واحد مرحّل للمستند؛ لا نقل لرقم القيد المحلي |
| بندا القيد | `journal_lines`: `uuid`, `journal_entry_id`, `account_id`, `party_id`, `dr_amount`, `cr_amount` | `lines[]`: `uuid/account_uuid/party_uuid/dr_minor/cr_minor` | UUID لكل بند وحساب GL، وربط الطرف إن كان بند الطرف | **بندان بالضبط**؛ المدين والدائن متساويان، وبند الصندوق مقابل بند الطرف |
| حركة حساب الطرف | `lah_alayh_ledger`: `uuid`, `party_id`, `entry_type`, `alayh_amount`, `lah_amount`, `doc_type='VOUCHER'`, `doc_id=voucher.id` | `ledger.uuid` | يعيد المستقبِل بناء قيم الحركة من نوع السند والمبلغ وUUID الطرف؛ `doc_id` يصبح ID السند الجديد | حركة واحدة بالاتجاه الصحيح؛ حقول الحركة غير منقولة حرفياً |
| حركة الصندوق | `cash_transactions`: `uuid`, `cash_account_id`, `direction`, `amount`, `tx_type`, `doc_type='VOUCHER'`, `doc_id=voucher.id`, `balance_after` | `cash.uuid` | `cash_account_id` يُحل من `cash_uuid`؛ `doc_id` يصبح ID السند الجديد | حركة واحدة؛ `balance_after` يُحسب محلياً لا يُنسخ |
| الطرف — اعتماد خارجي | `parties.id/uuid` | `voucher.party_uuid` (ويتكرر في بند الطرف) | يجب وجود نفس UUID في الفرع المستقبِل | رفض عند غياب الطرف؛ لا ينشئه الغلاف |
| حساب الصندوق — اعتماد خارجي | `cash_accounts.id/uuid/gl_account_id/account_kind` | `voucher.cash_uuid` | وجود UUID صالح ونوع `CASHIER_DRAWER` أو `MAIN_SAFE` | رفض عند غياب الحساب أو نوعه غير المقبول |
| حسابا الأستاذ — اعتماد خارجي | `chart_of_accounts.id/uuid/code` | `lines[].account_uuid` | GL الصندوق من `cash_accounts.gl_account_id`؛ GL الطرف بالكود `1201` للقبض و`2101` للصرف | رفض اختلاف الحسابات أو الاتجاه أو التصادم؛ الاعتماد على الأكواد يتطلب master data موحّدة |

## 3. اتجاهات القيد والحركات

| نوع السند | بند الصندوق | بند الطرف | حركة الصندوق | دفتر الطرف |
|---|---|---|---|---|
| `RECEIPT` قبض | مدين `amount_minor` | دائن `amount_minor` | `IN` / `RECEIPT_VOUCHER` | `lah_amount=amount`, `alayh_amount=0` |
| `PAYMENT` صرف | دائن `amount_minor` | مدين `amount_minor` | `OUT` / `PAYMENT_VOUCHER` | `alayh_amount=amount`, `lah_amount=0` |

## 4. حقول محلية لا يجوز نقلها كمعرّفات عامة

| الحقل | الخطر | السلوك الحالي / الإجراء اللاحق |
|---|---|---|
| `journal_entries.source_id` | رقم السند محلي لكل قاعدة | يعاد ربطه بالـvoucher ID الجديد على الوجهة؛ F04 يوثق عقد المرجع والتحقق من الحالات القديمة |
| `cash_transactions.doc_id` و`lah_alayh_ledger.doc_id` | رقم سند محلي قابل للتكرار | يعاد إنشاؤه محلياً من `voucher.uuid`؛ لا يرسل الرقم |
| `vouchers.journal_entry_id` و`journal_lines.journal_entry_id` | FK محلي | يربط إلى journal ID الناتج في الوجهة |
| `party_id`, `cash_account_id`, `account_id` | IDs محلية | يُستخدم UUID الاعتماد ثم يُحل إلى ID محلي في الفرع |
| `cash_accounts.current_balance` و`cash_transactions.balance_after` | رصيد مشتق يختلف حسب ترتيب الأحداث | لا يُنقل الرصيد الجاهز؛ يُحدَّث محلياً بعد تطبيق الحركة؛ يلزم اختبار ترتيب الحركات في F07/F09 |
| `voucher_no` و`entry_no` | تسلسلات محلية | تنشئ الوجهة أرقام عرض مشتقة من UUID؛ لا تنقل أرقام المصدر |
| `cash_transactions.uuid` التاريخي | ترقية schema تضيف عمود UUID nullable؛ القديم قد يبقى NULL | الجديد في مسار السند يولد UUID؛ لا توليد عشوائي للقديم؛ يُبحث ترحيل provenance في F04 |
| UUID بيانات seed القديمة | قد لا تطابق `GlobalUuid.isValid` | التقاط السند يرفضها؛ يلزم تأسيس هوية موثوق قبل التفعيل |

## 5. تدقيق الاكتمال وما لا يثبته F02

**الموجود:** غلاف v1 يحتوي ستة أعضاء أعمال مميزين بالـUUID: سند واحد، قيد واحد، بندا قيد، حركة طرف واحدة، حركة صندوق واحدة. الاعتماديات الثلاثة: الطرف، حساب الصندوق، حسابا GL (حسابا الأستاذ اثنان؛ العدد الفعلي أربع سجلات اعتماد إذا كانت منفصلة). مجموع أعضاء الأعمال **6**، دون عدّ سجلات الاعتماد.

**الحدود التي ظهرت في المصدر:**
1. `fraction_digits` عدد 0–3 يمرره المستدعي، وليس عقد عملة يثبت رمز العملة أو دقتها على الطرفين؛ F03.
2. `cash_transactions.uuid` أضيف للبيانات الجديدة، والتاريخي NULL؛ `source_id/doc_id` محلية؛ F04.
3. الغلاف ينقل بعض الحقول صراحةً ويعيد بناء `ledger` و`cash` في الوجهة من النوع والمبلغ؛ يجب إثبات أن كل حقل مؤثر معتمد أو مستبعد قصداً، لا افتراض نسخ حرفي؛ F05.
4. `wallet_ref_no`، `cashier_shift_id`، وصف السند، ومعلومات العرض ليست ضمن الغلاف؛ يجب تقرير سياسة هذه الحقول قبل اعتماد مطابقة المستند الكاملة؛ F05.
5. المزامنة المالية غير مفعلة افتراضياً في الخدمة؛ ربط التهيئة والـcursor والصلاحيات في F08/F09.
6. خادم النقل والتحقق الأمني والتجارب على قاعدتين/جهازين لا تُعتمد بهذه المراجعة وحدها؛ F06–F07/F17–F20.

## 6. معيار قبول F02 والدليل

- [x] جرد كل أعضاء السند النقدي الفعلي من المصدر وربطهم بالحقول المرسلة.
- [x] فصل IDs المحلية عن UUID العامة وتحديد الاعتماديات الخارجية.
- [x] بيان اتجاه القيد لكل نوع سند والمبالغ المشتقة.
- [x] تسجيل الحقول غير المنقولة والفجوات وإسنادها للخطوات التالية.
- [x] عدم تعديل كود الأعمال أو قواعد Firebase أو تفعيل النقل.

**نوع التحقق:** مراجعة ثابتة للكود والوثائق، لا اختبارات تنفيذ جديدة ولا ادعاء نجاح CI على commit توثيقي. خط أساس CI السابق: [42689203871](https://github.com/abdallah1mohmmed2/Pharmacy/actions/runs/42689203871) و[42689214192](https://github.com/abdallah1mohmmed2/Pharmacy/actions/runs/42689214192) على `5cc70f9`.

**قرار:** F02 مكتملة بوصفها مهمة جرد/توثيق. **P0-05 وP0-06 مفتوحتان**؛ الخطوة التالية F03 (عقد العملة والدقة).
