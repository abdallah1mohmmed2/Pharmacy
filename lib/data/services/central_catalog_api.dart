import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/catalog_drug_model.dart';

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
  })  : _baseUri = baseUri,
        _client = client ?? http.Client(),
        _headers = headers;

  final Uri _baseUri;
  final http.Client _client;
  final Map<String, String> _headers;
  final Duration timeout;

  @override
  Future<CatalogSearchPage> search({
    required String query,
    String? barcode,
    String? cursor,
    int limit = 30,
  }) async {
    final safeLimit = limit.clamp(1, 30);
    final params = <String, String>{'limit': '$safeLimit'};
    if (barcode != null && barcode.isNotEmpty) {
      params['barcode'] = barcode;
    } else {
      params['q'] = query.trim();
    }
    if (cursor != null && cursor.isNotEmpty) params['cursor'] = cursor;

    final endpoint = _baseUri.resolve('/v1/catalog/search').replace(
          queryParameters: params,
        );
    final response = await _client
        .get(endpoint, headers: {'Accept': 'application/json', ..._headers})
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw CatalogApiException(
        'Catalog API returned HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is List) {
      return CatalogSearchPage(
        items: decoded
            .map((item) => CatalogDrugSummary.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(growable: false),
        source: CatalogSearchSource.remote,
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
        .toList(growable: false);
    final cursorValue = envelope['next_cursor'] ?? envelope['nextCursor'];
    return CatalogSearchPage(
      items: items,
      nextCursor: cursorValue?.toString(),
      source: CatalogSearchSource.remote,
    );
  }
}

class CatalogApiException implements Exception {
  const CatalogApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
