import 'dart:convert';

class CatalogDrugSummary {
  const CatalogDrugSummary({
    required this.catalogUuid,
    required this.catalogVersion,
    required this.tradeNameAr,
    required this.searchText,
    required this.payloadJson,
    this.tradeNameEn,
    this.scientificName,
    this.activeIngredientName,
    this.manufacturerName,
    this.dosageForm,
    this.strengthText,
    this.barcodeInternational,
    this.barcodeLocal,
    this.sourceName,
    this.sourceUrl,
    this.reviewStatus = 'UNVERIFIED',
    this.publishedAt,
  });

  final String catalogUuid;
  final int catalogVersion;
  final String tradeNameAr;
  final String? tradeNameEn;
  final String? scientificName;
  final String? activeIngredientName;
  final String? manufacturerName;
  final String? dosageForm;
  final String? strengthText;
  final String? barcodeInternational;
  final String? barcodeLocal;
  final String searchText;
  final String payloadJson;
  final String? sourceName;
  final String? sourceUrl;
  final String reviewStatus;
  final String? publishedAt;

  factory CatalogDrugSummary.fromJson(Map<String, dynamic> json) {
    final uuid = (json['catalog_uuid'] ?? json['uuid'] ?? '').toString().trim();
    final version = json['catalog_version'] ?? json['version'];
    final name = (json['trade_name_ar'] ?? json['tradeNameAr'] ?? '').toString().trim();
    if (uuid.isEmpty) throw const FormatException('catalog_uuid is required');
    if (version is! num || version < 1) {
      throw const FormatException('catalog_version must be a positive number');
    }
    if (name.isEmpty) throw const FormatException('trade_name_ar is required');

    String? optional(String key, [String? alternate]) {
      final value = json[key] ?? (alternate == null ? null : json[alternate]);
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    final fields = [
      name,
      optional('trade_name_en', 'tradeNameEn'),
      optional('scientific_name', 'scientificName'),
      optional('active_ingredient_name', 'activeIngredientName'),
      optional('manufacturer_name', 'manufacturerName'),
      optional('dosage_form', 'dosageForm'),
      optional('strength_text', 'strengthText'),
      optional('barcode_international', 'barcodeInternational'),
      optional('barcode_local', 'barcodeLocal'),
    ].whereType<String>();
    final payload = jsonEncode(json);

    return CatalogDrugSummary(
      catalogUuid: uuid,
      catalogVersion: version.toInt(),
      tradeNameAr: name,
      tradeNameEn: optional('trade_name_en', 'tradeNameEn'),
      scientificName: optional('scientific_name', 'scientificName'),
      activeIngredientName: optional('active_ingredient_name', 'activeIngredientName'),
      manufacturerName: optional('manufacturer_name', 'manufacturerName'),
      dosageForm: optional('dosage_form', 'dosageForm'),
      strengthText: optional('strength_text', 'strengthText'),
      barcodeInternational: optional('barcode_international', 'barcodeInternational'),
      barcodeLocal: optional('barcode_local', 'barcodeLocal'),
      searchText: [json['search_text'], ...fields].whereType<String>().join(' ').toLowerCase(),
      payloadJson: payload,
      sourceName: optional('source_name', 'sourceName'),
      sourceUrl: optional('source_url', 'sourceUrl'),
      reviewStatus: optional('review_status', 'reviewStatus') ?? 'UNVERIFIED',
      publishedAt: optional('published_at', 'publishedAt'),
    );
  }

  factory CatalogDrugSummary.fromCache(Map<String, Object?> row) {
    return CatalogDrugSummary(
      catalogUuid: row['catalog_uuid'] as String,
      catalogVersion: row['catalog_version'] as int,
      tradeNameAr: row['trade_name_ar'] as String,
      tradeNameEn: row['trade_name_en'] as String?,
      scientificName: row['scientific_name'] as String?,
      activeIngredientName: row['active_ingredient_name'] as String?,
      manufacturerName: row['manufacturer_name'] as String?,
      dosageForm: row['dosage_form'] as String?,
      strengthText: row['strength_text'] as String?,
      barcodeInternational: row['barcode_international'] as String?,
      barcodeLocal: row['barcode_local'] as String?,
      searchText: row['search_text'] as String,
      payloadJson: row['payload_json'] as String,
      sourceName: row['source_name'] as String?,
      sourceUrl: row['source_url'] as String?,
      reviewStatus: row['review_status'] as String? ?? 'UNVERIFIED',
      publishedAt: row['published_at'] as String?,
    );
  }

  Map<String, Object?> toCacheMap({required String cachedAt}) => {
        'catalog_uuid': catalogUuid,
        'catalog_version': catalogVersion,
        'trade_name_ar': tradeNameAr,
        'trade_name_en': tradeNameEn,
        'scientific_name': scientificName,
        'active_ingredient_name': activeIngredientName,
        'manufacturer_name': manufacturerName,
        'dosage_form': dosageForm,
        'strength_text': strengthText,
        'barcode_international': barcodeInternational,
        'barcode_local': barcodeLocal,
        'search_text': searchText.toLowerCase(),
        'payload_json': payloadJson,
        'source_name': sourceName,
        'source_url': sourceUrl,
        'review_status': reviewStatus,
        'published_at': publishedAt,
        'cached_at': cachedAt,
      };

  Map<String, dynamic> toJson() =>
      Map<String, dynamic>.from(jsonDecode(payloadJson) as Map);
}

enum CatalogSearchSource { remote, localCache }

class CatalogSearchPage {
  const CatalogSearchPage({
    required this.items,
    required this.source,
    this.nextCursor,
    this.offlineFallback = false,
    this.remoteError,
  });

  final List<CatalogDrugSummary> items;
  final String? nextCursor;
  final CatalogSearchSource source;
  final bool offlineFallback;
  final String? remoteError;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}
