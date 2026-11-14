import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/sync_table_policy.dart';

void main() {
  group('SyncTablePolicy outbound allowlist', () {
    test('allows reviewed shared catalog and stock tables', () {
      for (final table in [
        'drugs',
        'active_ingredients',
        'drug_categories',
        'manufacturers',
        'warehouses',
        'shelf_locations',
        'batches_fefo',
        'stocktaking_sessions',
        'stocktaking_lines',
        'stock_transfers',
        'stock_transfer_items',
      ]) {
        expect(SyncTablePolicy.allowsOutbound(table), isTrue, reason: table);
      }
    });

    test('rejects identity, security, sensitive and device-local tables', () {
      for (final table in [
        'users',
        'branches',
        'system_settings',
        'audit_logs',
        'sync_queue',
        'sync_inbox',
        'backup_log',
        'patients',
        'parties',
        'prescriptions',
        'prescription_items',
        'clinical_alert_logs',
        'controlled_drug_log',
        'employees',
        'payroll_runs',
        'app_settings',
        'catalog_cache',
        'catalog_sync_state',
        'unknown_table',
      ]) {
        expect(SyncTablePolicy.allowsOutbound(table), isFalse,
            reason: '$table must not be uploaded');
      }
    });

    test('keeps financial records disabled pending the atomic finance contract',
        () {
      for (final table in [
        'journal_entries',
        'journal_lines',
        'lah_alayh_ledger',
        'cash_accounts',
        'vouchers',
        'sales_invoices',
        'sales_invoice_items',
        'sales_payments',
        'purchase_invoices',
        'purchase_invoice_items',
        'expenses',
        'cash_transactions',
        'stock_movements',
        'sales_invoice_item_batches',
        'party_settlements',
      ]) {
        expect(SyncTablePolicy.allowsOutbound(table), isFalse,
            reason: '$table awaits P0-05');
      }
    });
  });
}
