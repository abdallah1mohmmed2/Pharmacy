/// Shared inbound/outbound synchronization allowlist.
///
/// Financial documents, personal/clinical data, identity, security, audit and
/// device-local state remain disabled until their dedicated contracts are
/// reviewed. Add tables only after schema and data-classification review.
abstract final class SyncTablePolicy {
  static const Set<String> outboundTables = {
    // Shared medicine catalog and reference data.
    'active_ingredients',
    'drug_categories',
    'manufacturers',
    'drugs',

    // Non-personal stock and warehouse operations.
    'warehouses',
    'shelf_locations',
    'batches_fefo',
    // Append-only stock effects must travel inside their approved atomic
    // operation contract, never as orphaned generic rows.
    // Sale allocations depend on a protected financial invoice and cannot
    // be replayed independently via row synchronization.
    'stocktaking_sessions',
    'stocktaking_lines',
    'disposals',
    'disposal_items',
    'stock_transfers',
    'stock_transfer_items',
    'price_history',
  };

  static const inboundTables = outboundTables;

  static bool allowsInbound(String tableName) =>
      inboundTables.contains(tableName);

  static bool allowsOutbound(String tableName) =>
      outboundTables.contains(tableName);
}
