# قاعدة نشرات OpenFDA المرجعية

نسخة كاملة من **Drug Labeling**، إصدار **2026-11-13**: **264,748 نشرة** في **14 ملف ZIP**، بحجم يقارب **1.87 GB (1.75 GiB)** مضغوطًا. هذه أعداد نشرات وليست أعداد مواد فعالة أو أدوية فريدة.

## التنزيل

[تحميل جميع الملفات من إصدار البيانات](https://github.com/abdallah1mohmmed2/Pharmacy/releases/tag/openfda-labels-2026-11-13)

نزّل ملفات `drug-label-*.json.zip` جميعها. كل ملف مستقل ويحتوي JSON؛ لا تحتاج دمج ملفات ZIP. الإصدار يتضمن `manifest.json` و`verification.json` و`SHA256SUMS` للتحقق من المصدر والأعداد والبصمات.

بديل: من جذر المستودع، مع Python 3 وcurl:

```sh
python -m pip install -r tools/openfda-requirements.txt
python tools/download_openfda_labels.py --output openfda-labels
```

لإعادة فحص الملفات المنزلة دون تنزيلها:

```sh
python tools/download_openfda_labels.py --output openfda-labels --verify-only
```

الأداة تستخدم قائمة إصدار مثبتة؛ تتحقق من SHA-256 وعدد سجلات كل ملف وسلامة ZIP. إذا تغيرت ملفات المصدر الأسبوعية، سيفشل التحقق بدل قبول نسخة مختلفة بصمت. ملفات الإصدار في GitHub هي النسخة المحفوظة. فشل التحقق يوقف نشر الإصدار.

## الاستفادة في Pharmacy

- `indications_and_usage`: دواعي الاستعمال.
- `contraindications`، `warnings_and_cautions`، `boxed_warning`: الموانع والتحذيرات.
- `dosage_and_administration`، `drug_interactions`، `adverse_reactions`: الجرعات والتداخلات والآثار الجانبية.
- `pregnancy`، `nursing_mothers`، `pediatric_use`، `geriatric_use`: الفئات الخاصة.
- `storage_and_handling`: التخزين.
- `set_id`، `version`، `effective_time`: تتبع النشرة وإصدارها؛ قد تغيب بعض الحقول.

الحقول ليست متاحة في جميع النشرات. ملفات المصدر محفوظة كما هي، دون اختصار أو ترجمة أو حذف. هذه قاعدة مرجعية خارج حزمة التطبيق، وليست ملف استيراد أصناف Pharmacy. لا تقوم هذه الإضافة بمطابقة الأصناف أو تغيير المخزون والأسعار أو اعتماد بيانات طبية. المطابقة لاحقًا تتطلب المكونات والتركيز والشكل وطريق الإعطاء ونوع التحرر، مع مصدر ومراجعة لكل نقل. لا تستبدل شركة المنتج المحلي بشركة النشرة الأمريكية.

## المصدر والترخيص

- المصدر: [FDA Drug Labeling](https://open.fda.gov/apis/drug/label/).
- فهرس التنزيل: https://api.fda.gov/download.json
- [ترخيص OpenFDA](https://open.fda.gov/license/) و[شروط الاستخدام](https://open.fda.gov/terms/): الأصل Public Domain / CC0، مع مراعاة أي استثناءات محددة.
- البيانات مقدمة من U.S. Food and Drug Administration؛ لا تعني استحسان FDA لهذا المشروع.

وجود نشرة في OpenFDA لا يثبت اعتماد المنتج أو تطابقه مع منتج محلي. بعض المنتجات غير معتمدة، وقد تختلف النشرة عن المنتج المتداول. لا تعتمد على OpenFDA وحده لاتخاذ قرارات الرعاية الطبية.

## التحديث

لتحديث الإصدار: اجلب فهرس FDA، نزّل الأجزاء كاملة، تحقق منها، وثبّت الأعداد والبصمات الجديدة في `manifest.json` قبل إنشاء إصدار جديد. لا تخلط أجزاء إصدارات مختلفة. إجراء GitHub Actions المرفق ينشر النسخة المثبتة فقط؛ لا يحدّثها تلقائيًا إلى بيانات طبية أحدث.

