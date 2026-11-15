// lib/data/database/schema_iteration8.dart
import 'package:sqflite/sqflite.dart';
import 'schema_iteration6.dart';

/// Rebuilds fiscal-period triggers without relying on SQLite JSON1 functions.
abstract final class SchemaIteration8 {
  static Future<void> upgrade(DatabaseExecutor db) async {
    await SchemaIteration6.reinstallPeriodTriggers(db);
  }
}
