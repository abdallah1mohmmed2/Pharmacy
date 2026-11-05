import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'schema_builder.dart';
import 'seed_data.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance=DatabaseHelper._();
  Database? _db;
  Future<Database> get database async => _db ??= await _open();
  Future<Database> _open() async {
    if(Platform.isWindows || Platform.isLinux || Platform.isMacOS){sqfliteFfiInit();databaseFactory=databaseFactoryFfi;}
    final directory=Platform.isWindows
        ? p.join((await getApplicationSupportDirectory()).path,'databases')
        : await getDatabasesPath();
    await Directory(directory).create(recursive:true);
    final db=await openDatabase(p.join(directory,'global_pharmacy_erp.db'),version:1,onConfigure:(database)async{
      await database.execute('PRAGMA foreign_keys = ON');
      await database.execute('PRAGMA journal_mode = WAL');
      await database.execute('PRAGMA synchronous = NORMAL');
      await database.execute('PRAGMA busy_timeout = 5000');
      await database.execute('PRAGMA temp_store = MEMORY');
    },onCreate:(database,version)async{
      await SchemaBuilder.build(database);
      await SeedData.run(database);
    });
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('PRAGMA busy_timeout = 5000');
    return db;
  }
  Future<List<Map<String,Object?>>> query(String table,{String? where,List<Object?>? whereArgs,String? orderBy,int? limit}) async => (await database).query(table,where:where,whereArgs:whereArgs,orderBy:orderBy,limit:limit);
  Future<List<Map<String,Object?>>> rawQuery(String sql,[List<Object?>? args]) async => (await database).rawQuery(sql,args);
  Future<int> insert(String table,Map<String,Object?> values) async => (await database).insert(table,values,conflictAlgorithm:ConflictAlgorithm.abort);
  Future<int> update(String table,Map<String,Object?> values,{required String where,List<Object?>? whereArgs}) async => (await database).update(table,values,where:where,whereArgs:whereArgs);
  Future<void> close() async {await _db?.close();_db=null;}
}
