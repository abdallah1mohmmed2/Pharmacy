import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../models/catalog_drug_model.dart';
import '../services/central_catalog_api.dart';

class CatalogSearchRepository {
  CatalogSearchRepository({
    required Database database,
    CentralCatalogDataSource? remote,
    this.maxPageSize = 30,
    this.maxCacheEntries = 10000,
    this.preferFts5 = true,
  })  : _database = database,
        _remote = remote;

  final Database _database;
  final CentralCatalogDataSource? _remote;
  final int maxPageSize;
  final int maxCacheEntries;
  final bool preferFts5;

  bool _ftsReady = false;
  bool _ftsChecked = false;

  Future<CatalogSearchPage> search({
    required String query,
    String? cursor,
    int limit = 30,
  }) async {
    final normalized = query.trim();
    final barcode = _looksLikeBarcode(normalized) ? normalized : null;
    if (barcode == null && normalized.length < 2) {
      return const CatalogSearchPage(
        items: [],
        source: CatalogSearchSource.localCache,
      );
    }

    final safeLimit = min(max(limit, 1), min(maxPageSize, 30));
    final localItems = cursor == null
        ? await searchLocal(
            query: normalized,
            barcode: barcode,
            limit: safeLimit,
          )
        : <CatalogDrugSummary>[];

    final remote = _remote;
    if (remote == null) {
      return CatalogSearchPage(
        items: localItems,
        source: CatalogSearchSource.localCache,
      );
    }

    try {
      final page = await remote.search(
        query: normalized,
        barcode: barcode,
        cursor: cursor,
        limit: safeLimit,
      );
      final boundedItems = page.items.take(safeLimit).toList(growable: false);
      await cacheItems(boundedItems);
      await _recordSuccessfulSync(page);
      return CatalogSearchPage(
        items: boundedItems,
        nextCursor: page.nextCursor,
        source: CatalogSearchSource.remote,
        etag: page.etag,
        catalogVersion: page.catalogVersion,
      );
    } catch (error) {
      return CatalogSearchPage(
        items: localItems,
        source: CatalogSearchSource.localCache,
        offlineFallback: true,
        remoteError: error.toString(),
      );
    }
  }

  Future<void> _recordSuccessfulSync(CatalogSearchPage page) async {
    final itemVersion = page.items.fold<int>(
      0,
      (current, item) => max(current, item.catalogVersion),
    );
    final incomingVersion = max(page.catalogVersion ?? 0, itemVersion);
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.transaction((txn) async {
      final rows = await txn.query(
        'catalog_sync_state',
        where: 'scope_key = ?',
        whereArgs: const ['central_catalog'],
        limit: 1,
      );
      final currentVersion = rows.isEmpty
          ? 0
          : (rows.first['last_catalog_version'] as int? ?? 0);
      final canAdvance = incomingVersion >= currentVersion;
      if (rows.isEmpty) {
        await txn.insert('catalog_sync_state', {
          'scope_key': 'central_catalog',
          'last_catalog_version': incomingVersion,
          'etag': page.etag,
          'last_success_at': now,
          'updated_at': now,
        });
      } else {
        await txn.update(
          'catalog_sync_state',
          {
            'last_catalog_version':
                canAdvance ? incomingVersion : currentVersion,
            'etag': canAdvance ? (page.etag ?? rows.first['etag']) : rows.first['etag'],
            'last_success_at': now,
            'updated_at': now,
            'last_error_at': null,
            'last_error_message': null,
          },
          where: 'scope_key = ?',
          whereArgs: const ['central_catalog'],
        );
      }
    });
  }

  Future<List<CatalogDrugSummary>> searchLocal({
    required String query,
    String? barcode,
    int limit = 30,
  }) async {
    final safeLimit = min(max(limit, 1), min(maxPageSize, 30));
    if (barcode != null) {
      final rows = await _database.query(
        'catalog_cache',
        where: 'barcode_international = ? OR barcode_local = ?',
        whereArgs: [barcode, barcode],
        orderBy: 'catalog_version DESC',
        limit: safeLimit,
      );
      return rows.map(CatalogDrugSummary.fromCache).toList(growable: false);
    }

    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) return const [];
    await _ensureFtsIndex();

    List<Map<String, Object?>> rows;
    if (_ftsReady) {
      final expression = normalized
          .split(RegExp(r'\\s+'))
          .where((part) => part.isNotEmpty)
          .map((part) => '"${part.replaceAll('"', '""')}"')
          .join(' AND ');
      try {
        rows = await _database.rawQuery(
          'SELECT c.* FROM catalog_cache c '
          'JOIN catalog_cache_fts f ON f.rowid = c.rowid '
          'WHERE catalog_cache_fts MATCH ? '
          'ORDER BY c.cached_at DESC LIMIT ?',
          [expression, safeLimit],
        );
      } catch (_) {
        _ftsReady = false;
        rows = await _fallbackSearch(normalized, safeLimit);
      }
    } else {
      rows = await _fallbackSearch(normalized, safeLimit);
    }
    return rows.map(CatalogDrugSummary.fromCache).toList(growable: false);
  }

  Future<List<Map<String, Object?>>> _fallbackSearch(
    String query,
    int limit,
  ) async {
    final terms = query.split(RegExp(r'\\s+')).where((e) => e.isNotEmpty);
    final clauses = <String>[];
    final args = <Object?>[];
    for (final term in terms) {
      clauses.add('search_text LIKE ?');
      args.add('%$term%');
    }
    args.add(limit);
    return _database.rawQuery(
      'SELECT * FROM catalog_cache WHERE ${clauses.join(' AND ')} '
      'ORDER BY cached_at DESC LIMIT ?',
      args,
    );
  }

  Future<void> cacheItems(List<CatalogDrugSummary> items) async {
    if (items.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.transaction((txn) async {
      for (final item in items) {
        final existing = await txn.query(
          'catalog_cache',
          columns: ['catalog_version'],
          where: 'catalog_uuid = ?',
          whereArgs: [item.catalogUuid],
          limit: 1,
        );
        if (existing.isNotEmpty &&
            (existing.first['catalog_version'] as int) > item.catalogVersion) {
          continue;
        }
        await txn.insert(
          'catalog_cache',
          item.toCacheMap(cachedAt: now),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await txn.rawDelete(
        'DELETE FROM catalog_cache WHERE catalog_uuid IN ('
        'SELECT catalog_uuid FROM catalog_cache '
        'WHERE catalog_uuid NOT IN ('
        'SELECT catalog_uuid FROM drugs WHERE catalog_uuid IS NOT NULL) '
        'ORDER BY cached_at DESC LIMIT -1 OFFSET ?)',
        [max(0, maxCacheEntries)],
      );
    });
  }

  Future<CatalogDrugSummary?> getCachedDrug(String catalogUuid) async {
    final rows = await _database.query(
      'catalog_cache',
      where: 'catalog_uuid = ?',
      whereArgs: [catalogUuid],
      limit: 1,
    );
    return rows.isEmpty ? null : CatalogDrugSummary.fromCache(rows.first);
  }

  Future<void> _ensureFtsIndex() async {
    if (_ftsChecked) return;
    _ftsChecked = true;
    if (!preferFts5) return;
    try {
      await _database.execute(
        "CREATE VIRTUAL TABLE IF NOT EXISTS catalog_cache_fts "
        "USING fts5(search_text, content='catalog_cache', content_rowid='rowid')",
      );
      await _database.execute('''
        CREATE TRIGGER IF NOT EXISTS catalog_cache_fts_ai
        AFTER INSERT ON catalog_cache BEGIN
          INSERT INTO catalog_cache_fts(rowid, search_text)
          VALUES (new.rowid, new.search_text);
        END
      ''');
      await _database.execute('''
        CREATE TRIGGER IF NOT EXISTS catalog_cache_fts_ad
        AFTER DELETE ON catalog_cache BEGIN
          INSERT INTO catalog_cache_fts(catalog_cache_fts, rowid, search_text)
          VALUES ('delete', old.rowid, old.search_text);
        END
      ''');
      await _database.execute('''
        CREATE TRIGGER IF NOT EXISTS catalog_cache_fts_au
        AFTER UPDATE ON catalog_cache BEGIN
          INSERT INTO catalog_cache_fts(catalog_cache_fts, rowid, search_text)
          VALUES ('delete', old.rowid, old.search_text);
          INSERT INTO catalog_cache_fts(rowid, search_text)
          VALUES (new.rowid, new.search_text);
        END
      ''');
      await _database.execute(
        "INSERT INTO catalog_cache_fts(catalog_cache_fts) VALUES ('rebuild')",
      );
      _ftsReady = true;
    } catch (_) {
      _ftsReady = false;
    }
  }

  bool _looksLikeBarcode(String value) =>
      RegExp(r'^\\d{8,14}$').hasMatch(value);
}
