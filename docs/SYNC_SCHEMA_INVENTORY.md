# جرد مخطط SQLite وتصنيف المزامنة — P0-04

المصدر المراجع: `3dd6ec22e335d544ba4869e7e9597e836c129a73`؛ قاعدة البيانات v16.

هذا جرد لجميع تعريفات TABLE وVIRTUAL TABLE وVIEW وأهداف RENAME في ملفات lib/**/*.dart، بما فيها الترحيلات والخدمات والمستودعات. تعدد تعريف جدول في الترحيلات لا يزيد العدد.

**الإجمالي: 91 اسمًا**: 86 أسماء جداول عادية (تشمل أسماء الترحيل القديمة والإنشاء المشروط)، و1 جدول افتراضي، و4 عروض. ليست جميعها موجودة معاً في كل قاعدة جهاز.

| التصنيف | العدد |
|---|---:|
| قابل للمزامنة بالحقول المعتمدة | 16 |
| محلي | 16 |
| حساس / غير معتمد للنقل | 53 |
| مشتق | 6 |

## حدود الاعتماد

- «قابل للمزامنة» يصف قائمة السماح البرمجية الحالية فقط، ولا يثبت سلامة دورة مالية أو تشغيل جهازين. الحقول تحكمها sync_payload_policy.dart.
- لا يغيّر هذا الجرد قائمة السماح أو قاعدة البيانات، ولا يفعّل Firebase.
- الجداول المالية والشخصية غير المعتمدة تبقى محظورة. أرصدة وحركات المخزون المرتبطة بها تحتاج P0-05 وP0-06 قبل اعتماد التشغيل.
- فحص المصدر لا ينفذ Dart ولا SQL ولا يدعي استخراج كل عمود أو كل علاقة. اختبار قاعدة البيانات يقارن الجداول والعروض الفعلية في إنشاء v16 بالجرد؛ تغير صيغة DDL أو استعمال أسماء ديناميكية يتطلب تحديث الفاحص ومراجعة صريحة.
- الأسماء القديمة تنشأ حسب مسار الترحيل؛ branch_identity_provisioning ينشأ عند اعتماد الهوية، وcatalog_cache_fts ينشأ عند توفر FTS5.
- sqlite_sequence وsqlite_stat* كائنات داخلية تديرها SQLite. جداول FTS5 الداخلية catalog_cache_fts_data وcatalog_cache_fts_idx وcatalog_cache_fts_docsize وcatalog_cache_fts_config مشتقة من الفهرس وليست جداول أعمال أو أهداف مزامنة مستقلة.

## الجرد التفصيلي

| الاسم | النوع / دورة الإنشاء | التصنيف | المزامنة الحالية | السبب | مصادر التعريف |
|---|---|---|---|---|---|
| `active_ingredients` | table / schema | قابل للمزامنة بالحقول المعتمدة | مسموحة بالحقول المعتمدة | مرجع المواد الفعالة؛ نقل الحقول المعتمدة فقط. | [schema_builder.dart:10](../lib/data/database/schema_builder.dart#L10) |
| `app_settings` | table / schema | محلي | محظورة | إعدادات تشغيل محلية قد تتضمن JSON؛ لا ترفع عبر المزامنة العامة. | [schema_iteration4.dart:11](../lib/data/database/schema_iteration4.dart#L11) |
| `audit_logs` | table / schema | حساس / غير معتمد للنقل | محظورة | سجل تدقيق يتضمن قيم قبل/بعد وهوية مستخدم؛ قد يحتوي أسراراً ولا يرفع. | [schema_iteration5.dart:15](../lib/data/database/schema_iteration5.dart#L15)، [schema_iteration6.dart:79](../lib/data/database/schema_iteration6.dart#L79) |
| `audit_logs_legacy_i5` | table / legacy | حساس / غير معتمد للنقل | محظورة | اسم وسيط لسجل تدقيق قديم؛ يبقى محلياً وحساساً. | [schema_iteration6.dart:511](../lib/data/database/schema_iteration6.dart#L511) |
| `audit_logs_legacy_i5_migrated` | table / legacy | حساس / غير معتمد للنقل | محظورة | أرشيف تدقيق مرحّل يحتفظ ببيانات قديمة؛ لا يرفع. | [schema_iteration6.dart:332](../lib/data/database/schema_iteration6.dart#L332) |
| `backup_log` | table / schema | محلي | محظورة | مسارات نسخ احتياطية وبصمات ونتائج مرتبطة بالجهاز. | [schema_iteration6.dart:97](../lib/data/database/schema_iteration6.dart#L97) |
| `batches_fefo` | table / schema | قابل للمزامنة بالحقول المعتمدة | مسموحة بالحقول المعتمدة | التشغيلات والكميات؛ مسموح برمجياً مع بقاء اتساق حركة الشراء والرصيد قيد P0-05/P0-06. | [schema_iteration2.dart:9](../lib/data/database/schema_iteration2.dart#L9) |
| `branch_identity_provisioning` | table / conditional | محلي | محظورة | سجل اعتماد هوية محلي موثوق؛ توزيعه يتم بملف موقع، لا عبر بيانات المزامنة. | [branch_identity_provisioning_service.dart:138](../lib/data/services/branch_identity_provisioning_service.dart#L138) |
| `branches` | table / schema | حساس / غير معتمد للنقل | محظورة | هوية الفرع وعنوانه وترخيصه؛ تُعتمد بواسطة provisioning ولا تعدلها المزامنة العامة. | [schema_builder.dart:6](../lib/data/database/schema_builder.dart#L6) |
| `cash_accounts` | table / schema | حساس / غير معتمد للنقل | محظورة | الصناديق والمحافظ والأرصدة وبيانات الاتصال؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_builder.dart:19](../lib/data/database/schema_builder.dart#L19) |
| `cash_transactions` | table / schema | حساس / غير معتمد للنقل | محظورة | حركات الخزينة والرصيد الناتج؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_iteration4.dart:12](../lib/data/database/schema_iteration4.dart#L12) |
| `cashier_shifts` | table / schema | حساس / غير معتمد للنقل | محظورة | عهد وإقفال الكاشير وهوية المستخدم؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_iteration4.dart:14](../lib/data/database/schema_iteration4.dart#L14) |
| `catalog_cache` | table / schema | مشتق | محظورة | نسخة محلية قابلة لإعادة الجلب من مصدر الموسوعة؛ ليست مصدراً تشغيلياً للتبادل بين الأجهزة. | [schema_iteration10.dart:26](../lib/data/database/schema_iteration10.dart#L26) |
| `catalog_cache_fts` | virtual_table / conditional | مشتق | محظورة | فهرس FTS5 مشتق من catalog_cache وينشأ اختيارياً وقت البحث. | [catalog_search_repository.dart:245](../lib/data/repositories/catalog_search_repository.dart#L245) |
| `catalog_sync_state` | table / schema | محلي | محظورة | إصدار وETag خاصان بذاكرة الموسوعة المحلية. | [schema_iteration10.dart:51](../lib/data/database/schema_iteration10.dart#L51) |
| `chart_of_accounts` | table / schema | حساس / غير معتمد للنقل | محظورة | دليل الحسابات المرتبط بالقيود؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_builder.dart:15](../lib/data/database/schema_builder.dart#L15) |
| `chronic_medication_schedules` | table / schema | حساس / غير معتمد للنقل | محظورة | جدول أدوية مزمنة مرتبط بعميل ووصفة؛ بيانات شخصية وسريرية. | [schema_iteration4.dart:23](../lib/data/database/schema_iteration4.dart#L23) |
| `clinical_alert_logs` | table / schema | حساس / غير معتمد للنقل | محظورة | تنبيهات وقرارات سريرية مرتبطة بمرضى ومستخدمين؛ محظورة. | [schema_iteration3.dart:12](../lib/data/database/schema_iteration3.dart#L12) |
| `cold_chain_log` | table / schema | محلي | محظورة | سجل حرارة يتضمن recorded_by وتصحيحاً حراً؛ خارج العقد الحالي حتى مراجعة الحقول. | [schema_iteration2.dart:8](../lib/data/database/schema_iteration2.dart#L8) |
| `controlled_drug_log` | table / schema | حساس / غير معتمد للنقل | محظورة | أسماء وهويات المرضى والمستلمين والأطباء؛ محظورة. | [schema_iteration3.dart:13](../lib/data/database/schema_iteration3.dart#L13) |
| `disposal_items` | table / schema | قابل للمزامنة بالحقول المعتمدة | مسموحة بالحقول المعتمدة | تفاصيل كميات التالف وتكاليفها؛ اعتماد العملية المركبة قيد P0-05. | [schema_iteration2.dart:15](../lib/data/database/schema_iteration2.dart#L15) |
| `disposals` | table / schema | قابل للمزامنة بالحقول المعتمدة | مسموحة بالحقول المعتمدة | محاضر التالف؛ اسم الشاهد ومراجع الجهات والنصوص غير المعتمدة مستبعدة. ارتباط القيد المالي قيد P0-05. | [schema_iteration2.dart:14](../lib/data/database/schema_iteration2.dart#L14) |
| `drug_categories` | table / schema | قابل للمزامنة بالحقول المعتمدة | مسموحة بالحقول المعتمدة | تصنيفات الأدوية وعلاقاتها؛ ضمن العقد المشترك. | [schema_builder.dart:11](../lib/data/database/schema_builder.dart#L11) |
| `drug_hepatic_rules` | table / schema | حساس / غير معتمد للنقل | محظورة | قواعد جرعات الكبد السريرية؛ تحتاج اعتماداً منفصلاً. | [schema_iteration3.dart:9](../lib/data/database/schema_iteration3.dart#L9) |
| `drug_interactions` | table / schema | حساس / غير معتمد للنقل | محظورة | قواعد ومراجع تداخلات سريرية؛ تحتاج اعتماد مصدر وإصدار قبل التبادل. | [schema_iteration3.dart:7](../lib/data/database/schema_iteration3.dart#L7) |
| `drug_pediatric_rules` | table / schema | حساس / غير معتمد للنقل | محظورة | قواعد جرعات الأطفال؛ تحتاج اعتماداً سريرياً ومصدراً موثوقاً. | [schema_iteration3.dart:10](../lib/data/database/schema_iteration3.dart#L10) |
| `drug_renal_rules` | table / schema | حساس / غير معتمد للنقل | محظورة | قواعد جرعات الكلى السريرية؛ ليست ضمن إسقاط الكتالوج المعتمد. | [schema_iteration3.dart:8](../lib/data/database/schema_iteration3.dart#L8) |
| `drugs` | table / schema | قابل للمزامنة بالحقول المعتمدة | مسموحة بالحقول المعتمدة | سجل الصنف التشغيلي؛ إسقاط الحقول المعتمدة فقط دون النصوص السريرية وJSON. الأرصدة تحتاج تدقيق P0-05/P0-06. | [schema_builder.dart:48](../lib/data/database/schema_builder.dart#L48) |
| `employee_attendance` | table / schema | حساس / غير معتمد للنقل | محظورة | حضور وأجور مرتبطة بالموظف؛ بيانات شخصية ومالية. | [schema_iteration4.dart:18](../lib/data/database/schema_iteration4.dart#L18) |
| `employees` | table / schema | حساس / غير معتمد للنقل | محظورة | بيانات موظفين ورواتب وتراخيص؛ شخصية ومالية. | [schema_iteration4.dart:17](../lib/data/database/schema_iteration4.dart#L17) |
| `expense_categories` | table / schema | حساس / غير معتمد للنقل | محظورة | تصنيفات مصروفات وميزانية وحساب مقابل؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_iteration4.dart:15](../lib/data/database/schema_iteration4.dart#L15) |
| `expenses` | table / schema | حساس / غير معتمد للنقل | محظورة | مصروفات وجهة الصرف ومرفقاتها؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_iteration4.dart:16](../lib/data/database/schema_iteration4.dart#L16) |
| `financial_operation_inbox` | table / schema | محلي | محظورة | إيصال منع تطبيق السند المالي مرتين على هذا الجهاز؛ محلي وممنوع في المزامنة العامة. | [schema_iteration13.dart:34](../lib/data/database/schema_iteration13.dart#L34) |
| `financial_operation_outbox` | table / schema | حساس / غير معتمد للنقل | محظورة | غلاف عملية سند مالي يحتوي مراجع وأرصدة مالية؛ لا يمر عبر المزامنة العامة ولا يرسل قبل تحقق موثوق. | [schema_iteration13.dart:20](../lib/data/database/schema_iteration13.dart#L20) |
| `fiscal_periods` | table / schema | حساس / غير معتمد للنقل | محظورة | الفترات المحاسبية وإقفالها؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_iteration6.dart:111](../lib/data/database/schema_iteration6.dart#L111) |
| `import_jobs` | table / schema | محلي | محظورة | سجل استيراد وتصدير محلي يتضمن أسماء ملفات وتعيين أعمدة. | [schema_iteration6.dart:70](../lib/data/database/schema_iteration6.dart#L70) |
| `insurance_companies` | table / schema | حساس / غير معتمد للنقل | محظورة | مرجع تأمين مرتبط بطرف مالي؛ غير معتمد في العقد الحالي. | [schema_iteration3.dart:14](../lib/data/database/schema_iteration3.dart#L14) |
| `insurance_policies` | table / schema | حساس / غير معتمد للنقل | محظورة | أرقام بوالص وعميل وتغطية مالية وصحية؛ غير معتمدة. | [schema_iteration3.dart:15](../lib/data/database/schema_iteration3.dart#L15) |
| `journal_entries` | table / schema | حساس / غير معتمد للنقل | محظورة | رؤوس القيود المزدوجة؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_builder.dart:16](../lib/data/database/schema_builder.dart#L16) |
| `journal_lines` | table / schema | حساس / غير معتمد للنقل | محظورة | تفاصيل المدين والدائن؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_builder.dart:17](../lib/data/database/schema_builder.dart#L17) |
| `lah_alayh_ledger` | table / schema | حساس / غير معتمد للنقل | محظورة | دفتر أرصدة الأطراف؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_builder.dart:18](../lib/data/database/schema_builder.dart#L18) |
| `manufacturers` | table / schema | قابل للمزامنة بالحقول المعتمدة | مسموحة بالحقول المعتمدة | مرجع الشركات المصنعة؛ ضمن الحقول المعتمدة. | [schema_builder.dart:12](../lib/data/database/schema_builder.dart#L12) |
| `number_sequences` | table / schema | محلي | محظورة | عدادات ترقيم المستندات؛ نسخها كسجلات مستقلة قد يولد أرقاماً متصادمة. يحتاج سياسة ترقيم مستقلة. | [schema_builder.dart:9](../lib/data/database/schema_builder.dart#L9) |
| `parties` | table / schema | حساس / غير معتمد للنقل | محظورة | أسماء وهواتف وهويات وعناوين وأرصدة؛ يحتاج عقد خصوصية ومجال مالي. | [schema_builder.dart:14](../lib/data/database/schema_builder.dart#L14) |
| `partner_distribution_lines` | table / schema | حساس / غير معتمد للنقل | محظورة | استحقاقات كل شريك؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_iteration4.dart:22](../lib/data/database/schema_iteration4.dart#L22) |
| `partner_distributions` | table / schema | حساس / غير معتمد للنقل | محظورة | توزيع الأرباح المرتبط بالفترة والقيد؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_iteration4.dart:21](../lib/data/database/schema_iteration4.dart#L21) |
| `partners` | table / schema | حساس / غير معتمد للنقل | محظورة | هويات الشركاء ورأس المال والحصص؛ شخصية ومالية. | [schema_iteration4.dart:20](../lib/data/database/schema_iteration4.dart#L20) |
| `party_settlements` | table / schema | حساس / غير معتمد للنقل | محظورة | تسويات بين حسابات الأطراف؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_iteration4.dart:25](../lib/data/database/schema_iteration4.dart#L25) |
| `patients` | table / schema | حساس / غير معتمد للنقل | محظورة | بيانات شخصية وقياسات وحالات صحية؛ غير معتمدة للنقل. | [schema_iteration3.dart:11](../lib/data/database/schema_iteration3.dart#L11) |
| `payroll_runs` | table / schema | حساس / غير معتمد للنقل | محظورة | رواتب وسلف واستقطاعات؛ تنتظر عقداً مالياً وخصوصية. | [schema_iteration4.dart:19](../lib/data/database/schema_iteration4.dart#L19) |
| `prescription_items` | table / schema | حساس / غير معتمد للنقل | محظورة | جرعات وتفاصيل وصفة؛ بيانات سريرية مرتبطة بالمريض. | [schema_iteration3.dart:17](../lib/data/database/schema_iteration3.dart#L17) |
| `prescriptions` | table / schema | حساس / غير معتمد للنقل | محظورة | وصفات وبيانات طبيب ومريض وتأمين؛ محظورة. | [schema_iteration3.dart:16](../lib/data/database/schema_iteration3.dart#L16) |
| `price_history` | table / schema | قابل للمزامنة بالحقول المعتمدة | مسموحة بالحقول المعتمدة | تاريخ الأسعار والتكاليف؛ مراجع المستندات تحتاج عقد العلاقات في P0-05. | [schema_iteration2.dart:24](../lib/data/database/schema_iteration2.dart#L24) |
| `purchase_invoice_items` | table / schema | حساس / غير معتمد للنقل | محظورة | بنود الشراء والتكلفة والبونص؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_iteration2.dart:21](../lib/data/database/schema_iteration2.dart#L21) |
| `purchase_invoices` | table / schema | حساس / غير معتمد للنقل | محظورة | رؤوس فواتير الشراء والالتزامات؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_iteration2.dart:20](../lib/data/database/schema_iteration2.dart#L20) |
| `purchase_order_items` | table / schema | حساس / غير معتمد للنقل | محظورة | بنود أوامر الشراء وتكاليفها؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_iteration2.dart:19](../lib/data/database/schema_iteration2.dart#L19) |
| `purchase_orders` | table / schema | حساس / غير معتمد للنقل | محظورة | أوامر شراء مرتبطة بمورد؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_iteration2.dart:18](../lib/data/database/schema_iteration2.dart#L18) |
| `purchase_return_items` | table / schema | حساس / غير معتمد للنقل | محظورة | تفاصيل مرتجعات الشراء؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_iteration2.dart:23](../lib/data/database/schema_iteration2.dart#L23) |
| `purchase_returns` | table / schema | حساس / غير معتمد للنقل | محظورة | رؤوس مرتجعات الشراء والتسوية؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_iteration2.dart:22](../lib/data/database/schema_iteration2.dart#L22) |
| `report_favorites` | table / schema | محلي | محظورة | تفضيلات تقارير مستخدم الجهاز؛ محلية. | [schema_iteration5.dart:21](../lib/data/database/schema_iteration5.dart#L21) |
| `representative_visit_days` | table / schema | حساس / غير معتمد للنقل | محظورة | زيارات مرتبطة بهوية مندوب وملاحظات؛ غير معتمدة للنقل. | [schema_iteration4.dart:24](../lib/data/database/schema_iteration4.dart#L24) |
| `role_permissions` | table / schema | حساس / غير معتمد للنقل | محظورة | صلاحيات الأدوار؛ مسار إدارة موثوق مستقل. | [schema_iteration6.dart:123](../lib/data/database/schema_iteration6.dart#L123) |
| `roles` | table / schema | حساس / غير معتمد للنقل | محظورة | تعريف أدوار أمنية؛ لا تُقبل تعديلات قادمة من سجل مزامنة عام. | [schema_iteration6.dart:120](../lib/data/database/schema_iteration6.dart#L120) |
| `sales_invoice_item_batches` | table / schema | قابل للمزامنة بالحقول المعتمدة | مسموحة بالحقول المعتمدة | توزيع بنود البيع على التشغيلات؛ مسموح حالياً لكن invoice_item_id يرتبط بمجال مالي محظور ويلزم P0-05. | [schema_iteration2.dart:11](../lib/data/database/schema_iteration2.dart#L11) |
| `sales_invoice_items` | table / schema | حساس / غير معتمد للنقل | محظورة | بنود البيع وتكاليفها؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_builder.dart:22](../lib/data/database/schema_builder.dart#L22) |
| `sales_invoices` | table / schema | حساس / غير معتمد للنقل | محظورة | رؤوس فواتير البيع المرتبطة بعميل وكاشير؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_builder.dart:21](../lib/data/database/schema_builder.dart#L21) |
| `sales_payments` | table / schema | حساس / غير معتمد للنقل | محظورة | دفعات البيع ومراجع المحافظ؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_builder.dart:23](../lib/data/database/schema_builder.dart#L23) |
| `sales_return_items` | table / schema | حساس / غير معتمد للنقل | محظورة | بنود مرتجعات البيع والمبالغ والتشغيلات؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_iteration3.dart:19](../lib/data/database/schema_iteration3.dart#L19) |
| `sales_returns` | table / schema | حساس / غير معتمد للنقل | محظورة | مرتجعات البيع والعميل وسبب الإرجاع؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_iteration3.dart:18](../lib/data/database/schema_iteration3.dart#L18) |
| `shelf_locations` | table / schema | قابل للمزامنة بالحقول المعتمدة | مسموحة بالحقول المعتمدة | تعريفات الأرفف وعلاقتها بالمستودع؛ الوصف الحر مستبعد. | [schema_iteration2.dart:7](../lib/data/database/schema_iteration2.dart#L7) |
| `stock_movements` | table / schema | قابل للمزامنة بالحقول المعتمدة | مسموحة بالحقول المعتمدة | دفتر حركة المخزون؛ الملاحظة الحرة مستبعدة. النقل الذري مع المستند المالي لم يعتمد بعد. | [schema_iteration2.dart:10](../lib/data/database/schema_iteration2.dart#L10) |
| `stock_transfer_items` | table / schema | قابل للمزامنة بالحقول المعتمدة | مسموحة بالحقول المعتمدة | تفاصيل التحويل والتشغيلات؛ لا يثبت السماح اكتمال الاستلام الذري. | [schema_iteration2.dart:17](../lib/data/database/schema_iteration2.dart#L17) |
| `stock_transfers` | table / schema | قابل للمزامنة بالحقول المعتمدة | مسموحة بالحقول المعتمدة | رؤوس التحويل بين المستودعات؛ الاتساق مع تفاصيل العملية قيد P0-06. | [schema_iteration2.dart:16](../lib/data/database/schema_iteration2.dart#L16) |
| `stocktaking_lines` | table / schema | قابل للمزامنة بالحقول المعتمدة | مسموحة بالحقول المعتمدة | تفاصيل العد والفروق؛ تحتاج اتساق اعتماد الجرد مع قيوده المالية. | [schema_iteration2.dart:13](../lib/data/database/schema_iteration2.dart#L13) |
| `stocktaking_sessions` | table / schema | قابل للمزامنة بالحقول المعتمدة | مسموحة بالحقول المعتمدة | رؤوس الجرد؛ هوية المعتمد مستبعدة من الإسقاط. | [schema_iteration2.dart:12](../lib/data/database/schema_iteration2.dart#L12) |
| `sync_inbox` | table / schema | محلي | محظورة | حالة استقبال ومنع تكرار خاصة بقاعدة الجهاز؛ لا ترفع كجدول. | [schema_iteration11.dart:6](../lib/data/database/schema_iteration11.dart#L6) |
| `sync_inbox_batches` | table / schema | محلي | محظورة | سجل الدفعات المستقبلة محلياً؛ لا يعاد بثه. | [schema_iteration11.dart:27](../lib/data/database/schema_iteration11.dart#L27) |
| `sync_inbox_cursors` | table / schema | محلي | محظورة | مؤشر تقدم الاستقبال لكل جهاز؛ نسخه قد يسقط دفعات. | [schema_iteration11.dart:37](../lib/data/database/schema_iteration11.dart#L37) |
| `sync_queue` | table / schema | محلي | محظورة | طابور صادر محلي؛ قد يحتفظ بالبيانات الخام، يرفع الإسقاط المعتمد فقط وليس جدول الطابور. | [schema_iteration6.dart:102](../lib/data/database/schema_iteration6.dart#L102) |
| `system_settings` | table / schema | محلي | محظورة | إعدادات الجهاز والاتصال والمفاتيح المحتملة؛ تبقى محلية. | [schema_builder.dart:8](../lib/data/database/schema_builder.dart#L8)، [schema_iteration6.dart:11](../lib/data/database/schema_iteration6.dart#L11) |
| `system_settings_legacy_i5` | table / legacy | محلي | محظورة | نسخة إعدادات قديمة ناتجة عن ترحيل؛ قد تحتوي قيماً حساسة، لا ترفع. | [schema_iteration6.dart:502](../lib/data/database/schema_iteration6.dart#L502) |
| `tenants` | table / schema | حساس / غير معتمد للنقل | محظورة | هوية المؤسسة؛ موثوقة وثابتة بعد التأسيس وليست حدثاً تشغيلياً عادياً. | [schema_iteration12.dart:8](../lib/data/database/schema_iteration12.dart#L8) |
| `user_permissions` | table / schema | حساس / غير معتمد للنقل | محظورة | صلاحيات المستخدم؛ لا ترفع أو تطبق عبر المزامنة العامة. | [schema_iteration5.dart:19](../lib/data/database/schema_iteration5.dart#L19) |
| `users` | table / schema | حساس / غير معتمد للنقل | محظورة | حسابات وأسماء وتجزئات كلمات المرور ورموز المدير؛ ممنوع رفعها. | [schema_builder.dart:7](../lib/data/database/schema_builder.dart#L7) |
| `v_drug_alternatives` | view / schema | مشتق | محظورة | عرض بدائل دوائية محسوب من الأصناف والمخزون؛ لا ينقل كجدول. | [schema_iteration3.dart:26](../lib/data/database/schema_iteration3.dart#L26) |
| `v_fefo_batch_balances` | view / schema | مشتق | محظورة | عرض التشغيلات وترتيب الصلاحية؛ مشتق محلياً. | [schema_iteration2.dart:47](../lib/data/database/schema_iteration2.dart#L47) |
| `v_inventory_by_drug` | view / schema | مشتق | محظورة | عرض أرصدة مشتق من الأصناف والتشغيلات؛ لا يزامن. | [schema_iteration2.dart:45](../lib/data/database/schema_iteration2.dart#L45) |
| `v_party_balance` | view / schema | مشتق | محظورة | عرض محسوب من الأطراف والدفتر؛ يعاد حسابه محلياً. | [schema_builder.dart:36](../lib/data/database/schema_builder.dart#L36) |
| `vouchers` | table / schema | حساس / غير معتمد للنقل | محظورة | سندات القبض والدفع؛ محظور حالياً حتى عقد P0-05 وتتبع المعاملة في P0-06. | [schema_builder.dart:20](../lib/data/database/schema_builder.dart#L20) |
| `warehouses` | table / schema | قابل للمزامنة بالحقول المعتمدة | مسموحة بالحقول المعتمدة | تعريفات المستودعات؛ قائمة السماح الحالية. | [schema_iteration2.dart:6](../lib/data/database/schema_iteration2.dart#L6) |
| `work_shifts` | table / schema | محلي | محظورة | تعريف أوقات الدوام غير معتمد للمزامنة الحالية؛ يبقى محلياً حتى اعتماد مجال الموظفين. | [schema_iteration4.dart:13](../lib/data/database/schema_iteration4.dart#L13) |

## نقاط تسليم إلى P0-05 وP0-06

- sales_invoice_item_batches.invoice_item_id يشير إلى بنود بيع غير مسموح بمزامنتها حالياً؛ لا يكفي نقل توزيع التشغيلات منفرداً.
- batches_fefo.purchase_invoice_item_id وdisposals.journal_entry_id ومراجع doc_id/doc_line_id/source_doc_id تحتاج عقد تحويل مراجع وعمليات مركبة؛ بعضها ليس FK معلناً في SQLite.
- number_sequences يحتاج سياسة ترقيم متعددة الأجهزة، ولا يجوز حل تعارضاته بنسخ last_no.
- لا تُعاد توليد قيود journal_entries/journal_lines من إسقاط مالي مستقبَل؛ يثبت العقد المالي وحدة العملية ومنع التطبيق مرتين.

## إعادة التحقق

```sh
python tools/schema_inventory/check.py --check
python -m unittest discover -s tools/schema_inventory -p "test_*.py"
flutter test test/database_schema_test.dart
```

بعد تعديل التعريفات أو التصنيف، شغّل `python tools/schema_inventory/check.py --write` ثم راجع الفرق وشغّل --check. الفاحص لا يصنف جدولاً جديداً تلقائياً.
