import 'package:sqflite/sqflite.dart';

/// Removes only records carrying UUIDs from the original demonstration seed.
/// Records linked to real invoices, stock operations, or account activity survive.
abstract final class SchemaIteration9 {
  static const _drugUuids = <String>[
    'drug-DR-0001', 'drug-DR-0002', 'drug-DR-0003',
    'drug-DR-0004', 'drug-DR-0005', 'drug-DR-0006',
  ];
  static const _partyUuids = <String>[
    'party-C-001', 'party-C-002', 'party-S-001', 'party-S-002',
  ];

  static Future<void> upgrade(DatabaseExecutor db) async {
    await _removeSeedOpeningBalances(db);
    await _removeSeedPartiesWhenUnused(db);
    await _removeUnreferencedSeedStock(db);
    await _removeSeedDrugsWhenUnused(db);
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", [table],
    );
    return rows.isNotEmpty;
  }

  static Future<bool> _hasReference(
    DatabaseExecutor db, String table, String column, int id,
  ) async {
    if (!await _tableExists(db, table)) return false;
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (!columns.any((row) => row['name'] == column)) return false;
    return (await db.rawQuery(
      'SELECT 1 FROM $table WHERE $column=? LIMIT 1', [id],
    )).isNotEmpty;
  }

  static Future<void> _removeSeedOpeningBalances(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'lah_alayh_ledger')) return;
    final rows = await db.query(
      'lah_alayh_ledger',
      columns: ['journal_entry_id'],
      where: "uuid IN ('opening-C-001','opening-C-002','opening-S-001','opening-S-002')",
    );
    final ids = rows.map((row) => row['journal_entry_id']).whereType<int>().toSet();
    await db.delete(
      'lah_alayh_ledger',
      where: "uuid IN ('opening-C-001','opening-C-002','opening-S-001','opening-S-002')",
    );
    for (final id in ids) {
      if (await _tableExists(db, 'journal_lines')) {
        await db.delete('journal_lines',
          where: 'journal_entry_id=?', whereArgs: [id]);
      }
      if (await _tableExists(db, 'journal_entries')) {
        await db.delete('journal_entries',
          where: 'id=? AND uuid LIKE ?', whereArgs: [id, 'opening-je-%']);
      }
    }
  }

  static Future<void> _removeSeedPartiesWhenUnused(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'parties')) return;
    final parties = await db.query('parties', columns: ['id'],
      where: 'uuid IN (${List.filled(_partyUuids.length, '?').join(',')})',
      whereArgs: _partyUuids);
    const refs = <(String, String)>[
      ('sales_invoices', 'customer_party_id'),
      ('purchase_invoices', 'supplier_party_id'),
      ('purchase_orders', 'supplier_party_id'),
      ('purchase_returns', 'supplier_party_id'),
      ('vouchers', 'party_id'),
      ('lah_alayh_ledger', 'party_id'),
      ('journal_lines', 'party_id'),
    ];
    for (final row in parties) {
      final id = row['id'] as int;
      var used = false;
      for (final ref in refs) {
        if (await _hasReference(db, ref.$1, ref.$2, id)) { used = true; break; }
      }
      if (!used) await db.delete('parties', where: 'id=?', whereArgs: [id]);
    }
  }

  static Future<void> _removeUnreferencedSeedStock(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'drugs') ||
        !await _tableExists(db, 'batches_fefo') ||
        !await _tableExists(db, 'stock_movements')) return;
    final drugRows = await db.query('drugs', columns: ['id'],
      where: 'uuid IN (${List.filled(_drugUuids.length, '?').join(',')})',
      whereArgs: _drugUuids);
    final drugIds = drugRows.map((row) => row['id'] as int).toList();
    if (drugIds.isEmpty) return;
    final marks = List.filled(drugIds.length, '?').join(',');
    final batches = await db.rawQuery(
      "SELECT id FROM batches_fefo WHERE drug_id IN ($marks) AND batch_no LIKE 'SEED-%'",
      drugIds);
    final safeIds = <int>[];
    const batchRefs = <(String, String)>[
      ('sales_invoice_item_batches', 'batch_id'),
      ('stocktaking_lines', 'batch_id'),
      ('disposal_items', 'batch_id'),
      ('purchase_return_items', 'batch_id'),
      ('stock_transfer_items', 'from_batch_id'),
      ('stock_transfer_items', 'to_batch_id'),
    ];
    for (final batch in batches) {
      final id = batch['id'] as int;
      var used = false;
      for (final ref in batchRefs) {
        if (await _hasReference(db, ref.$1, ref.$2, id)) { used = true; break; }
      }
      if (!used) safeIds.add(id);
    }
    if (safeIds.isEmpty) return;
    final batchMarks = List.filled(safeIds.length, '?').join(',');
    await db.execute('DROP TRIGGER IF EXISTS trg_stock_movements_no_delete');
    await db.delete('stock_movements',
      where: 'batch_id IN ($batchMarks)', whereArgs: safeIds);
    await db.delete('batches_fefo',
      where: 'id IN ($batchMarks)', whereArgs: safeIds);
    await db.execute(
      "CREATE TRIGGER IF NOT EXISTS trg_stock_movements_no_delete BEFORE DELETE ON stock_movements BEGIN SELECT RAISE(ABORT,'stock_movements is append-only'); END");
    await db.rawUpdate(
      'UPDATE drugs SET stock_total_units=COALESCE((SELECT SUM(total_units) FROM batches_fefo WHERE batches_fefo.drug_id=drugs.id),0) WHERE id IN ($marks)',
      drugIds);
  }

  static Future<void> _removeSeedDrugsWhenUnused(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'drugs')) return;
    final rows = await db.query('drugs', columns: ['id'],
      where: 'uuid IN (${List.filled(_drugUuids.length, '?').join(',')})',
      whereArgs: _drugUuids);
    const refs = <(String, String)>[
      ('sales_invoice_items', 'drug_id'),
      ('purchase_invoice_items', 'drug_id'),
      ('purchase_order_items', 'drug_id'),
      ('price_history', 'drug_id'),
      ('drug_interactions', 'drug_a_id'),
      ('drug_interactions', 'drug_b_id'),
      ('batches_fefo', 'drug_id'),
      ('stock_movements', 'drug_id'),
    ];
    for (final row in rows) {
      final id = row['id'] as int;
      var used = false;
      for (final ref in refs) {
        if (await _hasReference(db, ref.$1, ref.$2, id)) { used = true; break; }
      }
      if (!used) await db.delete('drugs', where: 'id=?', whereArgs: [id]);
    }
  }
}
