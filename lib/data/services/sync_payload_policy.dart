import 'dart:convert';

/// Versioned outbound projection. New fields are private until reviewed.
/// Clinical narratives, JSON blobs, free-form notes and personal identifiers
/// are deliberately not part of this contract. Local rows remain unchanged.
abstract final class SyncPayloadPolicy {
  static const commonFields = <String>{
    'uuid',
    'branch_id',
    'created_at',
    'updated_at',
    'is_deleted',
    'sync_status',
    'sync_version',
  };

  static const fieldsByTable = <String, Set<String>>{
    'active_ingredients': {
      'inn_name',
      'name_ar',
      'chemical_formula',
      'atc_code_default',
    },
    'drug_categories': {
      'parent_id',
      'code',
      'name_ar',
      'name_en',
      'atc_prefix',
      'is_antibiotic',
    },
    'manufacturers': {
      'name_ar',
      'name_en',
      'country',
    },
    'drugs': {
      'internal_code',
      'is_active',
      'trade_name_ar',
      'trade_name_en',
      'manufacturer_id',
      'scientific_name',
      'active_ingredient_id',
      'category_id',
      'atc_code',
      'dosage_form',
      'strength_text',
      'strength_value',
      'strength_unit',
      'route',
      'is_strip_based',
      'strips_per_pack',
      'units_per_strip',
      'units_per_pack',
      'cost_price_pack',
      'last_purchase_cost_pack',
      'sell_price_pack',
      'sell_price_strip',
      'sell_price_unit',
      'strip_price_mode',
      'profit_margin_pct',
      'public_price_pack',
      'tax_rate_pct',
      'min_stock_units',
      'reorder_qty_packs',
      // Stock balance is derived from approved operations, not LWW rows.
      'storage_temp_min_c',
      'storage_temp_max_c',
      'requires_refrigeration',
      'protect_from_light',
      'barcode_international',
      'barcode_local',
      'registration_no',
      'is_controlled',
      'controlled_schedule',
      'requires_prescription',
      'prescription_restricted',
      'is_antibiotic',
      'catalog_uuid',
      'catalog_version',
    },
    'warehouses': {
      'code',
      'name_ar',
      'wh_type',
      'is_sellable',
    },
    'shelf_locations': {
      'warehouse_id',
      'code',
      'is_fridge',
    },
    'batches_fefo': {
      'drug_id',
      'warehouse_id',
      'location_id',
      'batch_no',
      'expiry_date',
      'manufacture_date',
      'unit_cost',
      'pack_cost',
      'purchase_invoice_item_id',
    },
    'stocktaking_sessions': {
      'session_no',
      'warehouse_id',
      'scope_type',
      'blind_count',
      'status',
      'approved_at',
    },
    'stocktaking_lines': {
      'session_id',
      'batch_id',
      'system_units',
      'counted_packs',
      'counted_loose_units',
      'counted_units',
      'is_counted',
      'diff_units',
      'unit_cost',
      'diff_value',
      'reason_code',
    },
    'disposals': {
      'disposal_no',
      'disposal_date',
      'reason',
      'status',
      'total_cost_value',
      'journal_entry_id',
    },
    'disposal_items': {
      'disposal_id',
      'batch_id',
      'qty_units',
      'unit_cost',
      'recoverable_from_supplier',
    },
    'stock_transfers': {
      'transfer_no',
      'transfer_type',
      'from_warehouse_id',
      'to_warehouse_id',
      'status',
      'received_at',
    },
    'stock_transfer_items': {
      'transfer_id',
      'from_batch_id',
      'to_batch_id',
      'qty_units',
      'received_qty_units',
      'unit_cost',
    },
    'price_history': {
      'drug_id',
      'change_type',
      'old_value',
      'new_value',
      'source_doc_type',
      'source_doc_id',
    },
  };

  /// Incoming events must already match the outbound projection. Reject an
  /// entire event rather than silently applying a partially untrusted record.
  static Map<String, Object?> validateIncoming(String table, Map source,
      {Set<String>? fieldsForTesting}) {
    final projected =
        project(table, source, fieldsForTesting: fieldsForTesting);
    if (source.keys
        .any((key) => key is! String || !projected.containsKey(key))) {
      throw const FormatException('SYNC_PAYLOAD_POLICY_REJECTED');
    }
    return projected;
  }

  static Map<String, Object?> project(String table, Object? source,
      {Set<String>? fieldsForTesting}) {
    final fields = fieldsForTesting ?? fieldsByTable[table];
    if (fields == null || source is! Map) {
      throw const FormatException('SYNC_PAYLOAD_POLICY_REJECTED');
    }
    final result = <String, Object?>{};
    for (final entry in source.entries) {
      if (entry.key is! String) continue;
      final key = entry.key as String;
      if (!commonFields.contains(key) && !fields.contains(key)) continue;
      final value = entry.value;
      // No nested objects or opaque JSON blobs cross this scalar contract.
      if (value != null &&
          value is! String &&
          value is! num &&
          value is! bool) {
        throw const FormatException('SYNC_PAYLOAD_POLICY_REJECTED');
      }
      if (value is num && !value.isFinite) {
        throw const FormatException('SYNC_PAYLOAD_POLICY_REJECTED');
      }
      if (value is String) {
        Object? decoded;
        try {
          decoded = jsonDecode(value);
        } on FormatException {/* plain text */}
        if (decoded is Map || decoded is List) {
          throw const FormatException('SYNC_PAYLOAD_POLICY_REJECTED');
        }
      }
      result[key] = value;
    }
    return result;
  }
}
