import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:global_enterprise_pharmacy_erp/data/database/schema_iteration10.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/catalog_drug_model.dart';
import 'package:global_enterprise_pharmacy_erp/data/repositories/catalog_search_repository.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/central_catalog_api.dart';

class _FakeCatalogApi implements CentralCatalogDataSource {
  _FakeCatalogApi(this.page);
  CatalogSearchPage page;
  Object? failure;
  String? lastBarcode;
  int? lastLimit;
  String? lastCursor;
  int calls = 0;

  @override
  Future<CatalogSearchPage> search({
    required String query,
    String? barcode,
    String? cursor,
    int limit = 30,
  }) async {
    calls++;
    lastBarcode = barcode;
    lastLimit = limit;
    lastCursor = cursor;
    if (failure != null) throw failure!;
    return page;
  }
}

CatalogDrugSummary _drug({
  String uuid = 'drug-1',
  String name = 'أموكسيسيلين',
  String barcode = '6281000000001',
  int version = 1,
}) =>
    CatalogDrugSummary.fromJson({
      'catalog_uuid': uuid,
      'catalog_version': version,
      'trade_name_ar': name,
      'trade_name_en': 'Amoxicillin',
      'scientific_name': 'Amoxicillin',
      'active_ingredient': 'Amoxicillin',
      'active_ingredient_name': 'Amoxicillin',
      'barcode_international': barcode,
      'source_name': 'Verified source',
      'review_status': 'REVIEWED',
    });

Map<String, dynamic> _envelope({
  required List<Map<String, dynamic>> items,
  String? cursor,
  int version = 20261108,
  String etag = 'W/"cat-v20261108-p1"',
}) =>
    {
      'ok': true,
      'catalog_version': version,
      'etag': etag,
      'count': items.length,
      'next_cursor': cursor,
      'items': items,
    };

Future<Database> _database() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('CREATE TABLE drugs (branch_id INTEGER, is_deleted INTEGER)');
  await SchemaIteration10.upgrade(db);
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('CentralCatalogApi endpoints', () {
    test('keeps the standard /v1/catalog/search contract and metadata', () async {
      Uri? requested;
      final client = MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode(_envelope(items: [_drug().toJson()])),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = CentralCatalogApi(
        baseUri: Uri.parse('https://catalog.test'),
        client: client,
      );

      final page = await api.search(query: 'amoxicillin', limit: 100);

      expect(requested!.path, '/v1/catalog/search');
      expect(requested!.queryParameters['q'], 'amoxicillin');
      expect(requested!.queryParameters['limit'], '30');
      expect(page.items, hasLength(1));
      expect(page.etag, 'W/"cat-v20261108-p1"');
      expect(page.catalogVersion, 20261108);
      client.close();
    });

    test('falls back to the exact Firebase barcode shard after dynamic 404', () async {
      final requestedPaths = <String>[];
      final client = MockClient((request) async {
        requestedPaths.add(request.url.path);
        if (request.url.path == '/v1/catalog/search') {
          return http.Response('not found', 404);
        }
        return http.Response(
          jsonEncode(_envelope(items: [_drug().toJson()])),
          200,
          headers: {'etag': '"static-etag"', 'content-type': 'application/json'},
        );
      });
      final api = CentralCatalogApi(
        baseUri: Uri.parse('https://catalog.test'),
        client: client,
      );

      final page = await api.search(query: '6281000000001');

      expect(requestedPaths, [
        '/v1/catalog/search',
        '/v1/catalog/barcodes/6281000000001.json',
      ]);
      expect(page.items.single.barcodeInternational, '6281000000001');
      expect(page.etag, 'W/"cat-v20261108-p1"');
      client.close();
    });

    test('loads prefix and cursor shards, then filters longer text locally', () async {
      final requestedPaths = <String>[];
      final client = MockClient((request) async {
        requestedPaths.add(request.url.path);
        if (request.url.path == '/v1/catalog/search') {
          return http.Response('not found', 404);
        }
        if (request.url.path.endsWith('/am.json')) {
          return http.Response(
            jsonEncode(_envelope(
              items: [
                _drug(uuid: 'amox-1', name: 'Amoxicillin 500 mg').toJson(),
                _drug(uuid: 'amox-2', name: 'Amoxicillin Clavulanate').toJson(),
              ],
              cursor: 'am_p2',
            )),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(_envelope(
            items: [_drug(uuid: 'amox-3', name: 'Amoxicillin 1g').toJson()],
          )),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = CentralCatalogApi(
        baseUri: Uri.parse('https://catalog.test'),
        client: client,
      );

      final first = await api.search(query: 'amoxicillin clavulanate');
      final second = await api.search(
        query: 'amoxicillin clavulanate',
        cursor: first.nextCursor,
      );

      expect(requestedPaths, [
        '/v1/catalog/search',
        '/v1/catalog/search/am.json',
        '/v1/catalog/search',
        '/v1/catalog/search/am_p2.json',
      ]);
      expect(first.items, hasLength(1));
      expect(first.items.single.catalogUuid, 'amox-2');
      expect(first.nextCursor, 'am_p2');
      expect(second.items, isEmpty);
      client.close();
    });
  });

  test('remote search is paginated and remote results are cached', () async {
    final db = await _database();
    try {
      final remote = _FakeCatalogApi(CatalogSearchPage(
        items: [_drug()],
        nextCursor: 'next-page',
        source: CatalogSearchSource.remote,
      ));
      final repository = CatalogSearchRepository(
        database: db,
        remote: remote,
        preferFts5: false,
      );

      final result = await repository.search(
        query: 'أموكسيسيلين',
        cursor: 'cursor-1',
        limit: 500,
      );

      expect(result.source, CatalogSearchSource.remote);
      expect(result.items, hasLength(1));
      expect(result.hasMore, isTrue);
      expect(remote.lastLimit, 30);
      expect(remote.lastCursor, 'cursor-1');
      expect(await repository.getCachedDrug('drug-1'), isNotNull);
    } finally {
      await db.close();
    }
  });

  test('successful sync stores etag and catalog version', () async {
    final db = await _database();
    try {
      final remote = _FakeCatalogApi(const CatalogSearchPage(
        items: [],
        source: CatalogSearchSource.remote,
        etag: '"etag-v8"',
        catalogVersion: 8,
      ));
      final repository = CatalogSearchRepository(
        database: db,
        remote: remote,
        preferFts5: false,
      );
      await repository.search(query: 'amoxicillin');
      final state = (await db.query(
        'catalog_sync_state',
        where: 'scope_key = ?',
        whereArgs: ['central_catalog'],
      )).single;
      expect(state['last_catalog_version'], 8);
      expect(state['etag'], '"etag-v8"');
      expect(state['last_success_at'], isNotNull);
    } finally {
      await db.close();
    }
  });

  test('older catalogue response cannot roll back cache or sync version', () async {
    final db = await _database();
    try {
      final repository = CatalogSearchRepository(
        database: db,
        preferFts5: false,
      );
      await repository.cacheItems([
        _drug(version: 9, name: 'أموكسيسيلين إصدار أحدث'),
      ]);
      final newerApi = _FakeCatalogApi(const CatalogSearchPage(
        items: [],
        source: CatalogSearchSource.remote,
        etag: '"etag-v9"',
        catalogVersion: 9,
      ));
      final newerRepository = CatalogSearchRepository(
        database: db,
        remote: newerApi,
        preferFts5: false,
      );
      await newerRepository.search(query: 'amoxicillin');
      final olderApi = _FakeCatalogApi(CatalogSearchPage(
        items: [_drug(version: 4, name: 'اسم قديم')],
        source: CatalogSearchSource.remote,
        etag: '"etag-v4"',
        catalogVersion: 4,
      ));
      final olderRepository = CatalogSearchRepository(
        database: db,
        remote: olderApi,
        preferFts5: false,
      );
      await olderRepository.search(query: 'amoxicillin');

      final cached = await olderRepository.getCachedDrug('drug-1');
      final sync = (await db.query(
        'catalog_sync_state',
        where: 'scope_key = ?',
        whereArgs: ['central_catalog'],
      )).single;
      expect(cached!.catalogVersion, 9);
      expect(cached.tradeNameAr, 'أموكسيسيلين إصدار أحدث');
      expect(sync['last_catalog_version'], 9);
      expect(sync['etag'], '"etag-v9"');
    } finally {
      await db.close();
    }
  });

  test('barcode uses exact lookup and falls back to local cache offline', () async {
    final db = await _database();
    try {
      final remote = _FakeCatalogApi(const CatalogSearchPage(
        items: [],
        source: CatalogSearchSource.remote,
      ))..failure = StateError('offline');
      final repository = CatalogSearchRepository(
        database: db,
        remote: remote,
        preferFts5: false,
      );
      await repository.cacheItems([_drug()]);
      final result = await repository.search(query: '6281000000001');

      expect(remote.lastBarcode, '6281000000001');
      expect(result.offlineFallback, isTrue);
      expect(result.items, hasLength(1));
      expect(result.items.single.catalogUuid, 'drug-1');
    } finally {
      await db.close();
    }
  });

  test('local text search returns cached results and does not fetch short input', () async {
    final db = await _database();
    try {
      final remote = _FakeCatalogApi(const CatalogSearchPage(
        items: [],
        source: CatalogSearchSource.remote,
      ));
      final repository = CatalogSearchRepository(
        database: db,
        remote: remote,
        preferFts5: false,
      );
      await repository.cacheItems([_drug()]);
      final result = await repository.searchLocal(query: 'amoxicillin');
      expect(result, hasLength(1));

      final short = await repository.search(query: 'a');
      expect(short.items, isEmpty);
      expect(remote.calls, 0);
    } finally {
      await db.close();
    }
  });

  test('cache prunes old search results without deleting selected pharmacy drugs', () async {
    final db = await _database();
    try {
      final repository = CatalogSearchRepository(
        database: db,
        maxCacheEntries: 1,
        preferFts5: false,
      );
      await db.insert('drugs', {
        'branch_id': 1,
        'is_deleted': 0,
        'catalog_uuid': 'drug-old',
      });
      await repository.cacheItems([
        _drug(uuid: 'drug-old', name: 'Old drug'),
        _drug(uuid: 'drug-new', name: 'New drug'),
      ]);
      final cachedIds = (await db.query('catalog_cache', columns: ['catalog_uuid']))
          .map((row) => row['catalog_uuid'])
          .toSet();
      expect(cachedIds, contains('drug-old'));
      expect(cachedIds, contains('drug-new'));
    } finally {
      await db.close();
    }
  });

  test('FTS5 is used when available and fallback remains safe otherwise', () async {
    final db = await _database();
    try {
      final repository = CatalogSearchRepository(database: db, preferFts5: true);
      await repository.cacheItems([_drug()]);
      final result = await repository.searchLocal(query: 'amoxicillin');
      expect(result, hasLength(1));
    } finally {
      await db.close();
    }
  });

  test('cache never rolls back when an older catalogue version arrives late', () async {
    final db = await _database();
    try {
      final repository = CatalogSearchRepository(
        database: db,
        preferFts5: false,
      );
      await repository.cacheItems([_drug(version: 2, name: 'أموكسيسيلين محدث')]);
      await repository.cacheItems([_drug(version: 1, name: 'اسم قديم')]);
      final cached = await repository.getCachedDrug('drug-1');
      expect(cached!.catalogVersion, 2);
      expect(cached.tradeNameAr, 'أموكسيسيلين محدث');
    } finally {
      await db.close();
    }
  });
}
