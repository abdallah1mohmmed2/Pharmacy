import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/catalog_drug_model.dart';

enum CatalogEndpointMode { automatic, dynamicApi, firebaseStaticShards }

abstract interface class CentralCatalogDataSource {
  Future<CatalogSearchPage> search({
    required String query,
    String? barcode,
    String? cursor,
    int limit = 30,
  });
}

class CentralCatalogApi implements CentralCatalogDataSource {
  CentralCatalogApi({
    required Uri baseUri,
    http.Client? client,
    Map<String, String> headers = const {},
    this.timeout = const Duration(seconds: 12),
    this.endpointMode = CatalogEndpointMode.automatic,
  })  : _baseUri = baseUri,
        _client = client ?? http.Client(),
        _headers = headers;

  final Uri _baseUri;
  final http.Client _client;
  final Map<String, String> _headers;
  final Duration timeout;
  final CatalogEndpointMode endpointMode;

  @override
  Future<CatalogSearchPage> search({
    required String query,
    String? barcode,
    String? cursor,
    int limit = 30,
  }) async {
    final safeLimit = limit.clamp(1, 30);
    final normalizedQuery = _normalizeQuery(query);
    final exactBarcode = barcode ?? (_isBarcode(query.trim()) ? query.trim() : null);

    if (endpointMode != CatalogEndpointMode.firebaseStaticShards) {
      try {
        final page = await _dynamicSearch(
          query: normalizedQuery,
          barcode: exactBarcode,
          cursor: cursor,
          limit: safeLimit,
        );
        return page;
      } on CatalogApiException catch (error) {
        if (endpointMode == CatalogEndpointMode.dynamicApi ||
            error.statusCode != 404) {
          rethrow;
        }
      }
    }

    if (endpointMode == CatalogEndpointMode.dynamicApi) {
      throw const CatalogApiException('Dynamic catalogue endpoint is unavailable');
    }

    return _staticSearch(
      query: normalizedQuery,
      barcode: exactBarcode,
      cursor: cursor,
      limit: safeLimit,
    );
  }

  Future<CatalogSearchPage> _dynamicSearch({
    required String query,
    required String? barcode,
    required String? cursor,
    required int limit,
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if (barcode != null) {
      params['barcode'] = barcode;
    } else {
      params['q'] = query;
    }
    if (cursor != null && cursor.isNotEmpty) params['cursor'] = cursor;

    final endpoint = _baseUri.resolve('/v1/catalog/search').replace(
          queryParameters: params,
        );
    final response = await _get(endpoint);
    if (response.statusCode != 200) {
      throw CatalogApiException(
        'Catalog API returned HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    return _parsePage(response, limit: limit);
  }

  Future<CatalogSearchPage> _staticSearch({
    required String query,
    required String? barcode,
    required String? cursor,
    required int limit,
  }) async {
    late Uri endpoint;
    if (barcode != null) {
      endpoint = _baseUri.resolve(
        '/v1/catalog/barcodes/${Uri.encodeComponent(barcode)}.json',
      );
    } else {
      if (query.runes.length < 2) {
        return const CatalogSearchPage(
          items: [],
          source: CatalogSearchSource.remote,
        );
      }
      final shard = cursor != null && cursor.isNotEmpty
          ? _safeShardName(cursor)
          : _prefixFor(query);
      endpoint = _baseUri.resolve(
        '/v1/catalog/search/${Uri.encodeComponent(shard)}.json',
      );
    }

    final response = await _get(endpoint);
    if (response.statusCode != 200) {
      throw CatalogApiException(
        'Firebase catalogue shard returned HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    final page = _parsePage(response, limit: limit);
    final filtered = barcode != null
        ? page.items.where((item) =>
            item.barcodeInternational == barcode ||
            item.barcodeInternational == null)
        : _filterByQuery(page.items, query);
    return CatalogSearchPage(
      items: filtered.take(limit).toList(growable: false),
      nextCursor: page.nextCursor,
      source: CatalogSearchSource.remote,
      etag: page.etag,
      catalogVersion: page.catalogVersion,
    );
  }

  Future<http.Response> _get(Uri endpoint) => _client
      .get(endpoint, headers: {'Accept': 'application/json', ..._headers})
      .timeout(timeout);

  CatalogSearchPage _parsePage(http.Response response, {required int limit}) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final responseHeaders = response.headers;
    if (decoded is List) {
      final items = decoded
          .map((item) => CatalogDrugSummary.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .take(limit)
          .toList(growable: false);
      return CatalogSearchPage(
        items: items,
        source: CatalogSearchSource.remote,
        etag: responseHeaders['etag'],
      );
    }
    if (decoded is! Map) {
      throw const FormatException('Invalid catalog search response');
    }

    final envelope = Map<String, dynamic>.from(decoded);
    final rawItems = envelope['items'] ?? envelope['data'];
    if (rawItems is! List) {
      throw const FormatException('Catalog response must contain items[]');
    }
    final items = rawItems
        .map((item) => CatalogDrugSummary.fromJson(
            Map<String, dynamic>.from(item as Map)))
        .take(limit)
        .toList(growable: false);
    final cursorValue = envelope['next_cursor'] ?? envelope['nextCursor'];
    final versionValue = envelope['catalog_version'] ?? envelope['catalogVersion'];
    final etag = envelope['etag']?.toString() ?? responseHeaders['etag'];
    return CatalogSearchPage(
      items: items,
      nextCursor: cursorValue?.toString(),
      source: CatalogSearchSource.remote,
      etag: etag,
      catalogVersion: versionValue is num ? versionValue.toInt() : null,
    );
  }

  static List<CatalogDrugSummary> _filterByQuery(
    List<CatalogDrugSummary> items,
    String query,
  ) {
    final terms = query.split(RegExp(r'\\s+')).where((term) => term.isNotEmpty);
    if (query.runes.length <= 2) return items;
    return items.where((item) {
      final searchable = _normalizeQuery([
        item.tradeNameAr,
        item.tradeNameEn,
        item.scientificName,
        item.activeIngredientName,
        item.searchText,
      ].whereType<String>().join(' '));
      return terms.every(searchable.contains);
    }).toList(growable: false);
  }

  static String _normalizeQuery(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\\u064B-\\u065F\\u0670]'), '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'\\s+'), ' ');
  }

  static String _prefixFor(String query) =>
      String.fromCharCodes(_normalizeQuery(query).runes.take(2));

  static String _safeShardName(String cursor) {
    if (!RegExp(r'^[\\p{L}\\p{N}_-]{1,80}$', unicode: true).hasMatch(cursor)) {
      throw const FormatException('Invalid catalogue shard cursor');
    }
    return cursor;
  }

  static bool _isBarcode(String value) => RegExp(r'^\\d{8,14}$').hasMatch(value);
}

class CatalogApiException implements Exception {
  const CatalogApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
