// lib/screens/settings/s28_system_settings_backup_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/constants/setting_keys.dart';
import '../../providers/settings_and_system_provider.dart';
import '../../providers/session_and_erp_provider.dart';
import '../../data/database/database_helper.dart';

class S28SystemSettingsBackupScreen extends StatefulWidget {
 const S28SystemSettingsBackupScreen({super.key});
 @override State<S28SystemSettingsBackupScreen> createState()=>_S28SystemSettingsBackupScreenState();
}
class _S28SystemSettingsBackupScreenState extends State<S28SystemSettingsBackupScreen> {
 static const titles=['الهوية العامة','البيع والتسعير','الحماية السريرية','المخزون والصلاحية','المحاسبة والشركاء','الطباعة والورق','المستخدمون والصلاحيات','النسخ والاستعادة','المزامنة السحابية','سجل الرقابة الأمني','إغلاق الفترات المالية'];
 static const groups=[SettingGroup.general,SettingGroup.sales,SettingGroup.clinical,SettingGroup.inventory,SettingGroup.accounting,SettingGroup.printBackup];
 String? auditUserFilter,auditActionFilter,auditSeverityFilter;
 Future<String?> _managerPin({String title='تأكيد صلاحية المدير'}) async {
  final controller=TextEditingController();
  final result=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:Text(title),content:TextField(controller:controller,obscureText:true,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'رمز المدير')),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,controller.text),child:const Text('تأكيد'))]));
  controller.dispose();return result;
 }
 Future<void> _change(SettingSpec spec,Object value) async {
  final p=context.read<SettingsAndSystemProvider>();final session=context.read<SessionAndErpProvider>();
  String? pin;if(spec.requiresManager){pin=await _managerPin(title:key==SettingKey.partnerDistributionMode?'تأكيد صلاحية المالك':'تأكيد صلاحية المدير');if(pin==null||pin.isEmpty)return;}
  try{await p.changeSetting(spec.key,value,managerPin:pin,userId:session.currentUser?['id'] as int?,branchId:session.branchId);if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم حفظ الإعداد وتسجيله في سجل الرقابة')));}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
 }
 @override Widget build(BuildContext context)=>DefaultTabController(length:11,child:Scaffold(
  appBar:AppBar(title:const Text('إعدادات النظام والنسخ الاحتياطي'),bottom:const TabBar(isScrollable:true,tabs:[Tab(text:'1 • الهوية'),Tab(text:'2 • البيع'),Tab(text:'3 • سريري'),Tab(text:'4 • المخزون'),Tab(text:'5 • المحاسبة'),Tab(text:'6 • الطباعة'),Tab(text:'7 • الأدوار'),Tab(text:'8 • النسخ'),Tab(text:'9 • السحابة'),Tab(text:'10 • الرقابة'),Tab(text:'11 • الفترات')])),
  body:Consumer<SettingsAndSystemProvider>(builder:(context,p,_)=>p.loading?const Center(child:CircularProgressIndicator()):TabBarView(children:[
   for(var i=0;i<6;i++)_settingsGroup(groups[i],p),
   _rolesTab(p),_backupTab(p),_syncTab(p),_auditTab(p),_periodTab(p),
  ])),
 ));
 Widget _settingsGroup(SettingGroup group,SettingsAndSystemProvider p){
  final specs=SettingKeys.all.where((s)=>s.group==group&&(group!=SettingGroup.printBackup||s.number<=33)).toList();
  return ListView(padding:const EdgeInsets.all(12),children:[
   for(final spec in specs)_settingTile(spec,p),
   if(group==SettingGroup.general)Card(child:ListTile(leading:const Icon(Icons.preview),title:const Text('معاينة الترويسة والتذييل'),subtitle:Text('الترويسة: ${p.settings.getJson(SettingKey.reportHeaderFooter)['header']??''}\nالتذييل: ${p.settings.getJson(SettingKey.reportHeaderFooter)['footer']??''}'),isThreeLine:true)),
   if(group==SettingGroup.accounting)const Card(child:ListTile(leading:Icon(Icons.lock,color:Colors.green),title:Text('مصطلحات «له وعليه» مقفولة دائماً'),subtitle:Text('لا يمكن تعطيل هذا القيد من أي دور.'))),
   if(group==SettingGroup.printBackup)Card(child:ListTile(title:const Text('طباعة تجريبية'),subtitle:const Text('اختبر إعدادات الورق الحالية'),trailing:IconButton(onPressed:()=>ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('إرسال صفحة اختبار للطباعة يتطلب اختيار طابعة من نافذة الطباعة.'))),icon:const Icon(Icons.print)))),
  ]);
 }
 Widget _settingTile(SettingSpec spec,SettingsAndSystemProvider p){
  final value=p.settings.getValue(spec.key);
  if(spec.type==SettingValueType.boolean)return Card(child:SwitchListTile(value:value as bool,onChanged:spec.key==SettingKey.lahAlayhTermsOnly?null:(v)=>_change(spec,v),title:Text(spec.descriptionAr),subtitle:Text(spec.name)));
  if(spec.allowedValues.isNotEmpty)return Card(child:ListTile(title:Text(spec.descriptionAr),subtitle:Text(spec.name),trailing:DropdownButton<String>(value:value as String,items:spec.allowedValues.map((v)=>DropdownMenuItem(value:v,child:Text(_label(v)))).toList(),onChanged:(v){if(v!=null)_change(spec,v);})));
  return Card(child:ListTile(title:Text(spec.descriptionAr),subtitle:Text(spec.name),trailing:IconButton(onPressed:()=>_editValue(spec,value),icon:const Icon(Icons.edit))));
 }
 String _label(String v)=>switch(v){'shares'=>'الحصص','percentage'=>'النسب','none'=>'بدون تقريب','nearest_5'=>'أقرب 5','nearest_10'=>'أقرب 10','nearest_50'=>'أقرب 50','nearest_100'=>'أقرب 100','off'=>'إيقاف','warn'=>'تحذير','block'=>'حظر','manager_override'=>'تجاوز المدير','ask'=>'اسأل قبل الطباعة','always'=>'دائماً','weighted_average'=>'المتوسط المرجح','last_purchase'=>'آخر شراء','batch_specific'=>'حسب التشغيلة','dashboard'=>'لوحة التحكم','daily_dashboard'=>'لوحة يومية','notify_on_sale'=>'تنبيه عند البيع','post_to_cashier'=>'تحميل على الكاشير','expense'=>'مصروف','suspense'=>'حساب معلق','80mm'=>'80 مم','58mm'=>'58 مم','ar'=>'العربية','en'=>'English','bilingual'=>'ثنائي اللغة',_=>v};
 Future<void> _editValue(SettingSpec spec,Object? value) async {
  final controller=TextEditingController(text:value is Map||value is List?const JsonEncoder.withIndent('  ').convert(value):value?.toString()??'');
  final result=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:Text(spec.descriptionAr),content:TextField(controller:controller,minLines:2,maxLines:8,decoration:const InputDecoration(border:OutlineInputBorder())),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,controller.text),child:const Text('حفظ'))]));
  if(result==null)return;
  Object parsed=result;
  try{if(spec.type==SettingValueType.json)parsed=jsonDecode(result);else if(spec.type==SettingValueType.integer)parsed=int.parse(result);else if(spec.type==SettingValueType.real)parsed=double.parse(result);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('قيمة غير صحيحة: $e')));return;}
  await _change(spec,parsed);
 }
 Widget _rolesTab(SettingsAndSystemProvider p)=>ListView(padding:const EdgeInsets.all(12),children:[
  const Text('مصفوفة صلاحيات الأدوار السبعة',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
  for(final role in ['OWNER','MANAGER','PHARMACIST','CASHIER','STOREKEEPER','ACCOUNTANT','AUDITOR'])ExpansionTile(title:Text(_roleName(role)),children:[
   for(final row in p.roleRows.where((r)=>r['role_code']==role))SwitchListTile(dense:true,title:Text(row['permission_code'].toString()),value:(row['is_allowed'] as num)==1,onChanged:role=='OWNER'?null:(v)=>p.setRolePermission(role,row['permission_code'] as String,v,actorRole:context.read<SessionAndErpProvider>().currentUser?['role_code'] as String? ?? '')),
  ]),
  const Divider(),const Text('إدارة المستخدمين وحسابات الدخول',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
  FilledButton.icon(onPressed:_createUser,icon:const Icon(Icons.person_add),label:const Text('إضافة مستخدم')),
  for(final user in p.userRows)Card(child:ListTile(title:Text(user['full_name'].toString()),subtitle:Text('${user['username']} • ${_roleName(user['role_code'] as String)}'),trailing:Wrap(mainAxisSize:MainAxisSize.min,children:[
   IconButton(tooltip:'تغيير الدور',icon:const Icon(Icons.badge_outlined),onPressed:()=>_editUserRole(user)),
   IconButton(tooltip:'كلمة المرور ورمز المدير',icon:const Icon(Icons.key),onPressed:()=>_editUserSecurity(user)),
  ]))),
 ]);
 Future<void> _createUser() async {
  final name=TextEditingController(),username=TextEditingController(),password=TextEditingController();
  String role='CASHIER';
  final values=await showDialog<Map<String,String>>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setLocal)=>AlertDialog(title:const Text('إضافة مستخدم'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
   TextField(controller:name,decoration:const InputDecoration(labelText:'الاسم الكامل')),
   TextField(controller:username,decoration:const InputDecoration(labelText:'اسم المستخدم')),
   TextField(controller:password,obscureText:true,decoration:const InputDecoration(labelText:'كلمة المرور (8 خانات على الأقل)')),
   DropdownButtonFormField<String>(value:role,decoration:const InputDecoration(labelText:'الدور'),items:const ['OWNER','MANAGER','PHARMACIST','CASHIER','STOREKEEPER','ACCOUNTANT','AUDITOR'].map((v)=>DropdownMenuItem(value:v,child:Text(_roleName(v)))).toList(),onChanged:(v)=>setLocal(()=>role=v??'CASHIER')),
  ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,{'name':name.text,'username':username.text,'password':password.text,'role':role}),child:const Text('إنشاء'))])));
  if(values==null)return;
  final session=context.read<SessionAndErpProvider>();final pin=await _managerPin();
  if(pin==null||!await session.verifyManagerPin(pin))return;
  session.consumeVerifiedManagerUserId();
  try{await context.read<SettingsAndSystemProvider>().createUser(username:values['username']!,fullName:values['name']!,password:values['password']!,roleCode:values['role']!,branchId:session.branchId,actorUserId:session.currentUser?['id'] as int? ?? 0,actorRole:session.currentUser?['role_code'] as String? ?? '');if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم إنشاء المستخدم')));}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  name.dispose();username.dispose();password.dispose();
 }
 Future<void> _editUserRole(Map<String,Object?> user) async {
  String role=user['role_code'] as String;
  final selected=await showDialog<String>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setLocal)=>AlertDialog(title:const Text('تغيير دور المستخدم'),content:DropdownButtonFormField<String>(value:role,items:const ['OWNER','MANAGER','PHARMACIST','CASHIER','STOREKEEPER','ACCOUNTANT','AUDITOR'].map((v)=>DropdownMenuItem(value:v,child:Text(_roleName(v)))).toList(),onChanged:(v)=>setLocal(()=>role=v??role)),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,role),child:const Text('حفظ'))])));
  if(selected==null)return;
  final session=context.read<SessionAndErpProvider>();final pin=await _managerPin();if(pin==null||!await session.verifyManagerPin(pin))return;
  session.consumeVerifiedManagerUserId();
  try{await context.read<SettingsAndSystemProvider>().updateUserRole(targetUserId:user['id'] as int,roleCode:selected,actorUserId:session.currentUser?['id'] as int? ?? 0,actorRole:session.currentUser?['role_code'] as String? ?? '');}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
 }
 Future<void> _editUserSecurity(Map<String,Object?> user) async {
  final password=TextEditingController(),pinController=TextEditingController();
  final values=await showDialog<Map<String,String>>(context:context,builder:(ctx)=>AlertDialog(title:Text('تحديث بيانات ${user['username']}'),content:Column(mainAxisSize:MainAxisSize.min,children:[
   TextField(controller:password,obscureText:true,decoration:const InputDecoration(labelText:'كلمة مرور جديدة')),
   TextField(controller:pinController,obscureText:true,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'رمز مدير جديد (اختياري)')),
  ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,{'password':password.text,'pin':pinController.text}),child:const Text('حفظ'))]));
  if(values==null)return;
  final session=context.read<SessionAndErpProvider>();final verified=await _managerPin();if(verified==null||!await session.verifyManagerPin(verified))return;
  session.consumeVerifiedManagerUserId();
  try{await context.read<SettingsAndSystemProvider>().updateUserSecurity(targetUserId:user['id'] as int,actorUserId:session.currentUser?['id'] as int? ?? 0,actorRole:session.currentUser?['role_code'] as String? ?? '',newPassword:values['password'],newManagerPin:values['pin']);if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم تحديث بيانات الدخول')));}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  password.dispose();pinController.dispose();
 }
 String _roleName(String r)=>switch(r){'OWNER'=>'المالك','MANAGER'=>'المدير','PHARMACIST'=>'الصيدلي','CASHIER'=>'الكاشير','STOREKEEPER'=>'أمين المخزن','ACCOUNTANT'=>'المحاسب',_=>'المراجع'};
 Widget _backupTab(SettingsAndSystemProvider p)=>ListView(padding:const EdgeInsets.all(12),children:[
  _settingTile(SettingKeys.byKey(SettingKey.autoLocalOnClose),p),
  FilledButton.icon(onPressed:()=>_createBackup(p),icon:const Icon(Icons.backup),label:const Text('إنشاء نسخة احتياطية الآن')),
  const SizedBox(height:8),for(final row in p.backupLogs)Card(child:ListTile(leading:const Icon(Icons.verified_user),title:Text(row['file_path'].toString().split(Platform.pathSeparator).last),subtitle:Text('الحالة: ${row['result']} • الحجم: ${row['size_bytes']} بايت\nSHA-256: ${row['sha256']}'),isThreeLine:true,trailing:IconButton(icon:const Icon(Icons.restore),onPressed:()=>_restoreBackup(p,row['file_path'] as String)))),
 ]);
 Future<void> _createBackup(SettingsAndSystemProvider p) async {try{final r=await p.createBackup(userId:context.read<SessionAndErpProvider>().currentUser?['id'] as int?);if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تم إنشاء النسخة: ${r.file.path}')));}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}}
 Future<void> _restoreBackup(SettingsAndSystemProvider p,String path) async {
  final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('تأكيد الاستعادة'),content:const Text('سيتم استبدال قاعدة البيانات الحالية. أُنشئت نسخة احتياطية تلقائية قبل الاستعادة.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('استعادة'))]));
  if(yes!=true)return;try{await p.restoreBackup(File(path),userId:context.read<SessionAndErpProvider>().currentUser?['id'] as int?);if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('اكتملت الاستعادة وإعادة تحميل البيانات')));}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
 }
 Widget _syncTab(SettingsAndSystemProvider p)=>ListView(padding:const EdgeInsets.all(12),children:[
  _settingTile(SettingKeys.byKey(SettingKey.cloudSync),p),
  Wrap(spacing:8,children:[OutlinedButton.icon(onPressed:()async{final ok=await p.testCloudConnection();if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(ok?'الاتصال بالخادم ناجح':'تعذر الاتصال بالخادم')));},icon:const Icon(Icons.wifi),label:const Text('اختبار الاتصال')),FilledButton.icon(onPressed:()=>p.syncNow(),icon:const Icon(Icons.sync),label:const Text('مزامنة الآن'))]),
  const SizedBox(height:12),const Text('حالة طابور المزامنة',style:TextStyle(fontWeight:FontWeight.bold)),for(final row in p.syncSummary)ListTile(title:Text(row['status'].toString()),trailing:Text(row['count'].toString())),
 ]);
 Widget _auditTab(SettingsAndSystemProvider p){
  final users=p.auditLogs.map((e)=>e.userId?.toString()??'').where((e)=>e.isNotEmpty).toSet().toList()..sort();
  final actions=p.auditLogs.map((e)=>e.action).toSet().toList()..sort();
  final severities=p.auditLogs.map((e)=>e.severity).toSet().toList()..sort();
  final filtered=p.auditLogs.where((e)=>(auditUserFilter==null||e.userId?.toString()==auditUserFilter)&&(auditActionFilter==null||e.action==auditActionFilter)&&(auditSeverityFilter==null||e.severity==auditSeverityFilter)).toList();
  return ListView(padding:const EdgeInsets.all(12),children:[
   Wrap(spacing:8,runSpacing:8,children:[
    SizedBox(width:150,child:DropdownButtonFormField<String?>(value:auditUserFilter,decoration:const InputDecoration(labelText:'المستخدم'),items:[const DropdownMenuItem<String?>(value:null,child:Text('كل المستخدمين')),...users.map((v)=>DropdownMenuItem<String?>(value:v,child:Text(v)))],onChanged:(v)=>setState(()=>auditUserFilter=v))),
    SizedBox(width:170,child:DropdownButtonFormField<String?>(value:auditActionFilter,decoration:const InputDecoration(labelText:'نوع الحدث'),items:[const DropdownMenuItem<String?>(value:null,child:Text('كل الأحداث')),...actions.map((v)=>DropdownMenuItem<String?>(value:v,child:Text(v)))],onChanged:(v)=>setState(()=>auditActionFilter=v))),
    SizedBox(width:150,child:DropdownButtonFormField<String?>(value:auditSeverityFilter,decoration:const InputDecoration(labelText:'الخطورة'),items:[const DropdownMenuItem<String?>(value:null,child:Text('كل المستويات')),...severities.map((v)=>DropdownMenuItem<String?>(value:v,child:Text(v)))],onChanged:(v)=>setState(()=>auditSeverityFilter=v))),
   ]),
   const SizedBox(height:8),
   FilledButton.icon(onPressed:()async{final r=await p.verifyAuditChain();if(mounted)showDialog(context:context,builder:(ctx)=>AlertDialog(title:Text(r.isValid?'السلسلة سليمة':'تم اكتشاف اختلاف'),content:Text('السجلات المفحوصة: ${r.checkedRows}\nأول سجل غير سليم: ${r.firstInvalidId??'لا يوجد'}\nالبصمة المتوقعة: ${r.expectedHash??'-'}\nالبصمة الفعلية: ${r.actualHash??'-'}'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إغلاق'))]));},icon:const Icon(Icons.verified),label:const Text('فحص سلامة سلسلة SHA-256')),
   if(p.chainResult!=null)Card(child:ListTile(leading:Icon(p.chainResult!.isValid?Icons.check_circle:Icons.error,color:p.chainResult!.isValid?Colors.green:Colors.red),title:Text(p.chainResult!.isValid?'السلسلة سليمة 100%':'السلسلة تحتاج مراجعة'),subtitle:Text('تم فحص ${p.chainResult!.checkedRows} سجلاً'))),
   for(final row in filtered)Card(child:ExpansionTile(title:Text('${row.action} • ${row.entityLabel??row.entityType??''}'),subtitle:Text('${row.eventAt} • ${row.severity} • المستخدم ${row.userId??'-'}'),children:[if(row.oldValuesJson!=null)ListTile(title:const Text('القيم القديمة'),subtitle:SelectableText(row.oldValuesJson!)),if(row.newValuesJson!=null)ListTile(title:const Text('القيم الجديدة'),subtitle:SelectableText(row.newValuesJson!)),if(row.reason!=null)ListTile(title:const Text('السبب'),subtitle:Text(row.reason!)),ListTile(title:const Text('SHA-256'),subtitle:SelectableText(row.rowHash??''))])),
  ]);
 }
 Widget _periodTab(SettingsAndSystemProvider p)=>ListView(padding:const EdgeInsets.all(12),children:[
  FilledButton.icon(onPressed:()=>_createCurrentPeriod(),icon:const Icon(Icons.add),label:const Text('إنشاء فترة الشهر والسنة الحالية')),
  for(final row in p.periodRows)Card(child:ListTile(title:Text('${row['period_code']} • ${row['period_type']}'),subtitle:Text('${row['start_date']} إلى ${row['end_date']} • ${row['status']}'),trailing:row['status']=='OPEN'?IconButton(icon:const Icon(Icons.lock),onPressed:()=>_closePeriod(p,row['period_code'] as String)):const Icon(Icons.lock_outline))),
 ]);
 Future<void> _createCurrentPeriod() async {
  final now=DateTime.now(),monthStart=DateTime(now.year,now.month,1),monthEnd=DateTime(now.year,now.month+1,0),yearStart=DateTime(now.year,1,1),yearEnd=DateTime(now.year,12,31);
  final db=await DatabaseHelper.instance.database;
  for(final v in [{'period_code':'${now.year}-${now.month.toString().padLeft(2,'0')}','period_type':'MONTH','start_date':monthStart,'end_date':monthEnd},{'period_code':'${now.year}','period_type':'YEAR','start_date':yearStart,'end_date':yearEnd}]){
   await db.insert('fiscal_periods',{'period_code':v['period_code'],'period_type':v['period_type'],'start_date':(v['start_date'] as DateTime).toIso8601String().substring(0,10),'end_date':(v['end_date'] as DateTime).toIso8601String().substring(0,10)},conflictAlgorithm:ConflictAlgorithm.ignore);
  }
  await context.read<SettingsAndSystemProvider>().refreshSystemData();
 }
 Future<void> _closePeriod(SettingsAndSystemProvider p,String code) async {
  final session=context.read<SessionAndErpProvider>();final pin=await _managerPin();if(pin==null||!await session.verifyManagerPin(pin)){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('رمز المدير غير صحيح')));return;}
  session.consumeVerifiedManagerUserId();
  try{await p.closeFiscalPeriod(code,userId:session.currentUser?['id'] as int? ?? 0,createPreCloseBackup:()async{await p.createBackup(triggerType:'BEFORE_PERIOD_CLOSE',userId:session.currentUser?['id'] as int?);});if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم إغلاق الفترة المالية')));}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
 }
}
