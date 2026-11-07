// test/iteration6_schema_test.dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_builder.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/seed_data.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration2.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration3.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration4.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration5.dart';
import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration6.dart';
import 'package:global_enterprise_pharmacy_erp/core/constants/setting_keys.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/settings_and_audit_service.dart';

void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 setUpAll(()=>sqfliteFfiInit());
 test('Iteration 6 creates all 35 settings, seven roles and immutable audit log',() async {
  final db=await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,options:OpenDatabaseOptions(version:9,onConfigure:(d)async{await d.execute('PRAGMA foreign_keys=ON');},onCreate:(d,_)async{
   await SchemaBuilder.build(d);await SeedData.run(d);await SchemaIteration2.upgrade(d);await SchemaIteration3.upgrade(d);await SchemaIteration4.upgrade(d);await SchemaIteration5.upgrade(d);await SchemaIteration6.upgrade(d);
  }));
  try{
   final settings=await db.rawQuery('SELECT setting_no,setting_key FROM system_settings ORDER BY setting_no');
   expect(settings,hasLength(35));
   expect(settings.map((r)=>r['setting_no']).toList(),List.generate(35,(i)=>i+1));
   expect(SettingKeys.all,hasLength(35));
   final roles=await db.query('roles');expect(roles,hasLength(7));
   final permissions=await db.rawQuery('SELECT COUNT(*) AS n FROM role_permissions');expect(permissions.first['n'],217);
   final costPermissions=await db.query('role_permissions',where:'permission_code=? AND is_allowed=1',whereArgs:['reports.cost.view']);
   expect(costPermissions.map((r)=>r['role_code']),containsAll(['OWNER','MANAGER','ACCOUNTANT']));
   final userColumns=await db.rawQuery('PRAGMA table_info(users)');
   expect(userColumns.any((r)=>r['name']=='system_role_code'),isTrue);
   await db.insert('audit_logs',{'event_at':'2026-11-07T00:00:00Z','action':'CREATE','entity_type':'test','prev_hash':'GENESIS','row_hash':'test-hash'});
   await expectLater(db.update('audit_logs',{'reason':'tampered'},where:'id=1'),throwsA(isA<DatabaseException>()));
   await expectLater(db.delete('audit_logs',where:'id=1'),throwsA(isA<DatabaseException>()));
  }finally{await db.close();}
 });
 test('version 8 database upgrades in place to the complete iteration 6 schema',() async {
  final directory=await Directory.systemTemp.createTemp('pharmacy-i6-upgrade-');
  final path=p.join(directory.path,'upgrade.db');
  Database? oldDb;
  Database? migratedDb;
  try{
   oldDb=await databaseFactoryFfi.openDatabase(path,options:OpenDatabaseOptions(version:8,onConfigure:(d)async{await d.execute('PRAGMA foreign_keys=ON');},onCreate:(d,_)async{
    await SchemaBuilder.build(d);await SeedData.run(d);await SchemaIteration2.upgrade(d);await SchemaIteration3.upgrade(d);await SchemaIteration4.upgrade(d);await SchemaIteration5.upgrade(d);
   }));
   await oldDb.close();oldDb=null;
   migratedDb=await databaseFactoryFfi.openDatabase(path,options:OpenDatabaseOptions(version:9,onConfigure:(d)async{await d.execute('PRAGMA foreign_keys=ON');},onUpgrade:(d,oldVersion,newVersion)async{if(oldVersion<9)await SchemaIteration6.upgrade(d);}));
   final settings=await migratedDb.query('system_settings');expect(settings,hasLength(35));
   final auditTables=await migratedDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='audit_logs_legacy_i5_migrated'");
   expect(auditTables,isNotEmpty);
   final roles=await migratedDb.query('roles');expect(roles,hasLength(7));
  }finally{
   await migratedDb?.close();await oldDb?.close();await directory.delete(recursive:true);
  }
 });
 test('SHA-256 audit chain verifies records and detects altered data',() async {
  final db=await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,options:OpenDatabaseOptions(version:9,onConfigure:(d)async{await d.execute('PRAGMA foreign_keys=ON');},onCreate:(d,_)async{
   await SchemaBuilder.build(d);await SeedData.run(d);await SchemaIteration2.upgrade(d);await SchemaIteration3.upgrade(d);await SchemaIteration4.upgrade(d);await SchemaIteration5.upgrade(d);await SchemaIteration6.upgrade(d);
  }));
  try{
   final audit=AuditService(executor:db);
   await audit.record(action:'CREATE',userId:1,entityType:'test',entityId:1,newValues:{'value':1});
   await audit.record(action:'UPDATE',userId:1,entityType:'test',entityId:1,oldValues:{'value':1},newValues:{'value':2});
   final valid=await audit.verifyChainIntegrity();expect(valid.isValid,isTrue);expect(valid.checkedRows,2);
   await db.execute('DROP TRIGGER trg_audit_no_update');
   await db.update('audit_logs',{'new_values_json':'{"value":999}'},where:'id=1');
   final invalid=await audit.verifyChainIntegrity();expect(invalid.isValid,isFalse);expect(invalid.firstInvalidId,1);
  }finally{await db.close();}
 });
 test('closed fiscal period trigger rejects journal entry creation',() async {
  final db=await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,options:OpenDatabaseOptions(version:9,onConfigure:(d)async{await d.execute('PRAGMA foreign_keys=ON');},onCreate:(d,_)async{
   await SchemaBuilder.build(d);await SeedData.run(d);await SchemaIteration2.upgrade(d);await SchemaIteration3.upgrade(d);await SchemaIteration4.upgrade(d);await SchemaIteration5.upgrade(d);await SchemaIteration6.upgrade(d);
  }));
  try{
   await db.insert('fiscal_periods',{'period_code':'2026-01','period_type':'MONTH','start_date':'2026-01-01','end_date':'2026-01-31','status':'CLOSED'});
   await expectLater(db.insert('journal_entries',{'uuid':'closed-period-test','branch_id':1,'created_at':'2026-01-15T10:00:00','updated_at':'2026-01-15T10:00:00','entry_no':'CLOSED-TEST','entry_date':'2026-01-15','description':'اختبار','source_type':'TEST','is_posted':1}),throwsA(isA<DatabaseException>()));
  }finally{await db.close();}
 });
}
