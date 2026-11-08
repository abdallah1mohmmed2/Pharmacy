# Firebase Authentication وCustom Claims واختبار Emulator

## عقد الهوية
- كل حساب Firebase Auth مرتبط بفرع واحد في هذا الإصدار.
- branch_id يحمل UUID العالمي للفرع، وليس رقم SQLite المحلي.
- branch_role إحدى القيم: owner أو manager أو staff.
- لا ينشئ تطبيق العميل Custom Claims ولا يعدلها.
- لا تحفظ كلمة مرور Firebase في SQLite أو إعداد 35؛ يتولى Firebase Auth SDK إدارة الجلسة وتجديد ID token.
- يجب أن يتطابق UUID الفرع في ID token مع مسار مستندات Firestore.

## إعداد تطبيق Flutter
إعداد 35 يحتفظ بمعرف المشروع وبيانات Firebase العامة فقط: project_id وapi_key وapp_id وmessaging_sender_id. أضيف FirebaseBranchAuthService لتكوين Firebase Auth وتسجيل الدخول بالبريد وكلمة المرور والحصول على ID token. لا تعتبر المزامنة جاهزة حتى توصيل واجهة تسجيل الدخول والخروج وحفظ حالة الجلسة واختبارها على Android وWindows.

## إصدار Claims
من بيئة إدارية موثوقة بعد تفعيل Firebase Authentication وإنشاء المستخدم:

    cd firebase
    npm install firebase-admin
    export GOOGLE_APPLICATION_CREDENTIALS=/secure/path/service-account.json
    node scripts/set-branch-claims.js <AUTH_UID> <BRANCH_UUID> manager

لا ترفع ملف service-account إلى GitHub ولا تضفه إلى إعدادات التطبيق أو artifacts. بعد تحديث claims يجب تجديد ID token (getIdToken(true)) حتى تظهر المطالبات الجديدة. تحقق من UID والفرع والدور قبل تشغيل الأمر.

## اختبار محلي
    cd firebase
    npm ci
    npm run test:rules

تعمل الاختبارات على Firestore Emulator بمشروع تجريبي demo-pharmacy-erp ولا تتصل بمشروع إنتاجي. تغطي إنشاء الدفعات للفرع المطابق، ومنع الكتابة لفرع آخر، ومنع تعديل الدفعة، ومنع المستخدم غير الإداري من لوحة المؤشرات، ومنع الوصول دون مصادقة.

## حدود الاعتماد
نجاح اختبارات Emulator لا يثبت إصدار claims في مشروع الإنتاج ولا يثبت تسجيل الدخول الفعلي بحساب منشأة. يلزم اختبار تكاملي بحساب Firebase تجريبي، وتوثيق UID/UUID mapping، ثم اختبار المزامنة end-to-end قبل الاعتماد. لا يوجد نشر أو تعديل على مشروع Firebase ضمن هذه المرحلة.
