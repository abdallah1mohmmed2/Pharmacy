/// Explicit inventory of financial operation types that are NOT yet eligible
/// for transport. This is a contract gate, not a posting implementation.
abstract final class FinancialDomainGate {
  static const requiredMembers = <String, Set<String>>{
    'CASH_SALE': {
      'sales_invoices',
      'sales_invoice_items',
      'sales_payments',
      'journal_entries',
      'journal_lines',
      'cash_transactions',
      'lah_alayh_ledger',
      'stock_movements'
    },
    'PURCHASE': {
      'purchase_invoices',
      'purchase_invoice_items',
      'batches_fefo',
      'stock_movements',
      'lah_alayh_ledger',
      'cash_transactions'
    },
    'SALES_RETURN': {
      'sales_returns',
      'sales_return_items',
      'stock_movements',
      'journal_entries',
      'journal_lines'
    },
    'PURCHASE_RETURN': {
      'purchase_returns',
      'purchase_return_items',
      'stock_movements',
      'lah_alayh_ledger'
    },
    'STOCKTAKING': {
      'stocktaking_sessions',
      'stocktaking_lines',
      'stock_movements'
    },
    'DISPOSAL': {'disposals', 'disposal_items', 'stock_movements'},
    'STOCK_TRANSFER': {
      'stock_transfers',
      'stock_transfer_items',
      'stock_movements'
    },
    'TREASURY': {'cash_transactions', 'journal_entries', 'journal_lines'},
    'EXPENSE': {
      'expenses',
      'cash_transactions',
      'journal_entries',
      'journal_lines'
    },
    'SHIFT_CLOSE': {
      'cashier_shifts',
      'cash_transactions',
      'journal_entries',
      'journal_lines'
    },
    'PAYROLL': {'payroll_runs', 'journal_entries', 'journal_lines'},
    'EMPLOYEE_ADVANCE': {'vouchers', 'lah_alayh_ledger', 'cash_transactions'},
    'PARTNER_DISTRIBUTION': {
      'partner_distributions',
      'partner_distribution_lines',
      'journal_entries',
      'journal_lines'
    },
    'PARTNER_WITHDRAWAL': {
      'cash_transactions',
      'journal_entries',
      'journal_lines'
    },
  };

  /// Every non-voucher operation is denied until its own capture, replay,
  /// server verification and two-database tests are implemented.
  static bool get productionTransportEnabled => false;

  static void requireTransportApproved(String operationType) {
    if (!requiredMembers.containsKey(operationType)) {
      throw StateError('UNKNOWN_FINANCIAL_DOMAIN');
    }
    throw StateError('FINANCIAL_DOMAIN_NOT_APPROVED');
  }

  /// Structural preflight only. It is NOT sufficient to authorize transport:
  /// schema, amounts, references, identities and transaction integrity must
  /// be checked against a versioned domain-specific contract.
  static void validateMemberNames(
      String operationType, Iterable<String> members) {
    final expected = requiredMembers[operationType];
    if (expected == null) throw StateError('UNKNOWN_FINANCIAL_DOMAIN');
    final supplied = members.toSet();
    if (supplied.length != members.length ||
        supplied.length != expected.length ||
        !supplied.containsAll(expected)) {
      throw StateError('INCOMPLETE_FINANCIAL_DOMAIN');
    }
  }
}
