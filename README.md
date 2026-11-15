# Global Enterprise Pharmacy ERP

تطبيق إدارة صيدلية Flutter بواجهة عربية RTL وقاعدة SQLite محلية وموسوعة دوائية ذات 19 نقطة.

## التشغيل
- Flutter stable وDart 3.3 أو أحدث.
- أنشئ ملفات المنصات أول مرة: `flutter create --platforms=android,windows --org com.globalpharmacy .`
- Android: `flutter pub get` ثم `flutter run`.
- Windows: `flutter config --enable-windows-desktop` ثم `flutter run -d windows`.

## حساب التأسيس التجريبي
- المستخدم: admin
- كلمة المرور التجريبية: 123456
- رمز اعتماد المدير التجريبي: 9999

يجب تغيير بيانات الدخول واستبدال تخزين كلمات المرور قبل الإنتاج. البيانات الطبية المبدئية ليست بديلاً عن النشرات الرسمية أو التحقق السريري.

## قاعدة النشرات المرجعية OpenFDA

[تحميل نسخة 2026-11-13 كاملة](https://github.com/abdallah1mohmmed2/Pharmacy/releases/tag/openfda-labels-2026-11-13) — 264,748 نشرة في 14 ملف ZIP.

راجع [دليل التنزيل والتحقق والاستخدام](data/openfda/README.md). البيانات خارج حزمة التطبيق، وتحتاج مطابقة ومراجعة قبل استخدامها لتحديث معلومات الأصناف.

