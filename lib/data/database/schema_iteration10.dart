import 'package:sqflite/sqflite.dart';

/// Local foundation for linking branch-owned drugs to a centrally managed
/// catalogue. This migration deliberately does not import catalogue records
/// or modify any operational drug values.
abstract final class SchemaIteration10 {
  static Future<void> upgrade(DatabaseExecutor db) async {
    final drugTable = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='drugs'",
    );
    if (drugTable.isEmpty) {
      throw StateError('Cannot add catalogue identity: drugs table is missing');
    }

    final columns = await db.rawQuery('PRAGMA table_info(drugs)');
    final names = columns.map((row) => row['name'] as String).toSet();

    if (!names.contains('catalog_uuid')) {
      await db.execute('ALTER TABLE drugs ADD COLUMN catalog_uuid TEXT');
    }
    if (!names.contains('catalog_version')) {
      await db.execute('ALTER TABLE drugs ADD COLUMN catalog_version INTEGER');
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalog_cache (
        catalog_uuid TEXT PRIMARY KEY,
        catalog_version INTEGER NOT NULL CHECK(catalog_version >= 1),
        trade_name_ar TEXT NOT NULL,
        trade_name_en TEXT,
        scientific_name TEXT,
        active_ingredient_name TEXT,
        manufacturer_name TEXT,
        dosage_form TEXT,
        strength_text TEXT,
        barcode_international TEXT,
        barcode_local TEXT,
        search_text TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        source_name TEXT,
        source_url TEXT,
        review_status TEXT NOT NULL DEFAULT 'UNVERIFIED'
          CHECK(review_status IN ('UNVERIFIED','REVIEWED','REJECTED')),
        published_at TEXT,
        cached_at TEXT NOT NULL,
        expires_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalog_sync_state (
        scope_key TEXT PRIMARY KEY,
        last_catalog_version INTEGER NOT NULL DEFAULT 0
          CHECK(last_catalog_version >= 0),
        etag TEXT,
        last_success_at TEXT,
        last_error_at TEXT,
        last_error_message TEXT,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_catalog_cache_trade_name_ar '
      'ON catalog_cache(trade_name_ar)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_catalog_cache_scientific_name '
      'ON catalog_cache(scientific_name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_catalog_cache_ingredient '
      'ON catalog_cache(active_ingredient_name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_catalog_cache_barcode_int '
      'ON catalog_cache(barcode_international)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_catalog_cache_barcode_local '
      'ON catalog_cache(barcode_local)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_drugs_catalog_uuid '
      'ON drugs(branch_id, catalog_uuid) '
      'WHERE catalog_uuid IS NOT NULL AND is_deleted=0',
    );
  }
}
