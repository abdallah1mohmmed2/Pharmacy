# F06 — اختبار سند CASH الحقيقي بين قاعدتي SQLite

**الحالة:** IN_PROGRESS — اختبار مرفوع، ينتظر CI النهائي.

## نطاق التنفيذ

- يستخدم الاختبار `PostingAndSalesService.postVoucher` الحقيقي في قاعدة A (YER بدقة صفر) بدلاً من إنشاء غلاف مصطنع.
- يقرأ `financial_operation_outbox` من معاملة المصدر، ويطبّق `FinancialVoucherOperation.applyVerified` على قاعدة B مختلفة بأرقام SQLite محلية مختلفة.
- يفحص تطابق UUID السند والمبلغ والعملة، وحل party/cash IDs المحلية، و`vouchers.journal_entry_id` و`journal_entries.source_id` و`journal_lines.journal_entry_id` و`lah_alayh_ledger.doc_id` و`cash_transactions.doc_id`.
- يفحص بندَي القيد، `CashVoucherIntegrityValidator`، سلامة `PRAGMA foreign_key_check`، وجود إيصال Inbox واحد، وعدم مضاعفة المستند أو القيد أو الحركة.
- اختبارات القبض والصرف والتكرار والrollback القائمة محفوظة؛ لم تُنسخ أو تُعاد كتابتها.

## التغيير

أضيف اختبار تكامل `F06 complete real CASH posting maps all financial references across DBs` إلى `test/financial_voucher_operation_integration_test.dart`؛ لا تغيير في مسار الترحيل أو قاعدة البيانات الإنتاجية.

## معيار القبول

- [x] سند حقيقي من المصدر إلى الوجهة بقاعدتين مختلفتين.
- [x] فحوص مراجع محلية، توازن، FK، وحيدية الإسقاطات.
- [ ] CI ناجح على HEAD النهائي.

لا تفعيل للمزامنة المالية الإنتاجية؛ خادم relay الموثوق لم يُعتمد بعد.
