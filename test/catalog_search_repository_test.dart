import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
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

  @override
  Future<CatalogSearchPage> search({
    required String query,
    String? barcode,
    String? cursor,
    int limit = 30,
  }) async {
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
      'scientific_name': 'Amoxicillin',
      'active_ingredient_name': 'Amoxicillin',
      'barcode_international': barcode,
      'source_name': 'Verified source',
      'review_status': 'REVIEWED',
    });

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
      final result = await repository.search(query: 'amoxicillin');
      expect(result.items, hasLength(1));
      expect(result.source, CatalogSearchSource.remote);

      final short = await repository.search(query: 'a');
      expect(short.items, isEmpty);
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
