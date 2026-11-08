# Firebase Authentication وCustom Claims واختبار Emulator

## عقد الهوية
- كل حساب Firebase Auth مرتبط بفرع واحد في هذا الإصدار.
- branch_id يحمل UUID العالمي للفرع، وليس رقم SQLite المحلي.
- branch_role إحدى القيم: owner أو manager أو staff.
- لا ينشئ تطبيق العميل Custom Claims ولا يعدلها.
- لا تحفظ كلمة مرور Firebase في SQLite أو إعداد 35؛ يتولى Firebase Authentication REST إدارة الجلسة وتجديد ID token.
- يجب أن يتطابق UUID الفرع في ID token مع مسار مستندات Firestore.

## إعداد تطبيق Flutter
إعداد 35 يحتفظ بمعرف المشروع ومفتاح Firebase العام فقط. أضيفت واجهة تسجيل الدخول والخروج، ويحفظ FirebaseBranchAuthService refresh token في مخزن أسرار نظام التشغيل ويجدد ID token عند الحاجة. تُحدّث جدولة المزامنة بعد تسجيل الدخول والخروج. لا تُعد المزامنة معتمدة حتى نجاح اختبارات Flutter وEmulator والبناء على Android وWindows.

## إصدار Claims
من بيئة إدارية موثوقة بعد تفعيل Firebase Authentication وإنشاء المستخدم:

    cd firebase
    npm install firebase-admin
    export GOOGLE_APPLICATION_CREDENTIALS=/secure/path/service-account.json
    export BRANCH_UID_MAP_FILE=/secure/path/branch-uid-map.json
    node scripts/set-branch-claims.js <AUTH_UID>

يحتوي ملف الربط الخارجي (ولا يوضع في المستودع) على تعيين يراجعه مسؤول موثوق:
```json
{
  "FIREBASE_AUTH_UID": {
    "branch_id": "7b9f5e2a-4c31-4d82-9a10-123456789abc",
    "branch_role": "manager"
  }
}
```

الأداة لا تقبل branch_id أو branch_role من سطر الأوامر؛ بل تستمدهما من ملف الربط الخارجي، وترفض الملف الموجود داخل المستودع، وتتحقق من UUID والدور، ثم تتأكد من وجود UID في Firebase Authentication قبل تحديث claims. تعتمد المصادقة الإدارية على Application Default Credentials. لا ترفع ملف service-account أو ملف الربط إلى GitHub ولا تضفهما إلى إعدادات التطبيق أو artifacts. بعد تحديث claims يجب تجديد ID token (في هذا التطبيق يتم ذلك عبر تبادل refresh token عند الحاجة). اختبر أولاً على Auth Emulator؛ لا تشغّل الأداة على مشروع إنتاجي دون موافقة صريحة ومراجعة UID/UUID mapping.

## اختبار محلي
    cd firebase
    npm ci
    npm run test:rules

تعمل اختبارات Emulator باستخدام project_id المقدم `pharmacy-dafb6` مع توجيه Auth وFirestore إلى Emulator المحلي صراحةً. استخدام المعرف لا يعني الاتصال بخدمات Firebase الحية، ولا تنفذ هذه الأوامر نشرًا أو تعديلًا على المشروع. تغطي إنشاء الدفعات للفرع المطابق، ومنع الكتابة لفرع آخر، ومنع تعديل الدفعة، ومنع المستخدم غير الإداري من لوحة المؤشرات، ومنع الوصول دون مصادقة.

## حدود الاعتماد
نجاح اختبارات Emulator لا يثبت إصدار claims في مشروع الإنتاج ولا يثبت تسجيل الدخول الفعلي بحساب منشأة. يلزم اختبار تكاملي بحساب Firebase تجريبي، وتوثيق UID/UUID mapping، ثم اختبار المزامنة end-to-end قبل الاعتماد. لا يوجد نشر أو تعديل على مشروع Firebase ضمن هذه المرحلة.


تعمل اختبارات المصادقة على Auth Emulator أيضاً (المنفذ 9099)، وتختبر إصدار custom claims والتحقق منها بعد تسجيل الدخول. لا تستخدم هذه الاختبارات أي حساب إنتاجي.

اختبار Auth Emulator ينشئ حساباً تجريبياً ويصدر Claims ثم يتحقق من تسجيل الدخول وتجديد refresh token وبقاء المطالبات. اختبار Firestore REST يكتب ويقرأ دفعة ويختبر رفض الكتابة إلى فرع آخر. هذه الاختبارات لا تتصل بمشروع إنتاجي.


## شرط هوية الفرع قبل إصدار Claims أو تشغيل المزامنة

- يجب أن يكون `branch_id` UUID عالمياً موحداً لكل أجهزة الفرع، وليس رقم SQLite المحلي.
- قاعدة البذر الحالية تحتوي قيمة placeholder هي `branch-main`؛ لذلك يرفض FirestoreSyncWorker هذه الهوية ولا يسمح بالاتصال/المزامنة بها.
- لا يولّد التطبيق UUID عشوائياً عند كل تثبيت؛ فهذا سيعطي أجهزة الفرع الواحد هويات مختلفة.
- يجب توفير آلية تأسيس موثوقة تصدر UUID واحداً للفرع وتوزعه على جميع أجهزته، ثم تسجيل UID/UUID في ملف الربط الإداري الخارجي.
- لا تشغّل أداة إصدار Claims ولا تفعّل مزامنة الإنتاج قبل اكتمال هذه الآلية. لم يتم إصدار Claims إنتاجية أو نشر Firebase.


## نطاق المؤسسة والفرع

مرحلة البداية تستخدم Tenant واحداً وفرع صيدلية واحداً فقط. `branch_id` هو UUID عالمي ثابت ويظل حد العزل الفعلي في Custom Claims وFirestore Rules. يمكن لاحقاً أن يمثل Tenant صيدلية مستقلة بفرع واحد أو مؤسسة بعدة فروع. عند تفعيل تعدد الفروع يجب إضافة `tenant_id` وعضويات المستخدمين ونطاق صلاحيات واضح، ثم تحديث Claims وSecurity Rules والاختبارات معاً. لا تعتبر هذه الإمكانية المستقبلية مفعلة حالياً.


## مشروع Firebase المخصص للاختبار

- project_id الذي قدمه مالك المشروع: `pharmacy-dafb6`.
- أوامر الاختبار تستخدم `firebase emulators:exec` مع `--only auth,firestore`، وتوجه الاختبارات إلى Auth Emulator وFirestore Emulator المحليين.
- لا تستخدم هذه الأوامر `firebase deploy` ولا تنشئ/تعدل مستخدمين أو قواعد على Firebase الحي.
- لم تتم إضافة apiKey أو appId أو أي سر إلى المستودع. ربط Flutter بالمشروع الحي مؤجل إلى ما بعد تأسيس UUID الفرع، إعداد حساب الاختبار، وموافقة صريحة على إجراء اتصال حي.
