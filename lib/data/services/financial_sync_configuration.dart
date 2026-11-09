import 'package:http/http.dart' as http;

import '../database/database_helper.dart';
import 'financial_voucher_operation.dart';
import 'financial_voucher_relay_worker.dart';

/// Explicit opt-in boundary. Creating this configuration does not schedule
/// synchronization or enable production transport.
class FinancialSyncConfiguration {
  const FinancialSyncConfiguration({
    this.enabled = false,
    this.endpoint,
    this.authorizedBranchId,
    this.idTokenProvider,
  });

  final bool enabled;
  final Uri? endpoint;
  final int? authorizedBranchId;
  final Future<String> Function()? idTokenProvider;

  /// Fail closed before any HTTP request, even for an otherwise valid URL.
  Future<FinancialVoucherSyncCycle> syncOnce({
    required DatabaseHelper helper,
    required http.Client client,
    required int branchId,
  }) async {
    if (!enabled) {
      throw const FinancialVoucherSyncException('FINANCIAL_SYNC_DISABLED');
    }
    if (authorizedBranchId == null || authorizedBranchId != branchId) {
      throw const FinancialVoucherSyncException('FINANCIAL_BRANCH_NOT_AUTHORIZED');
    }
    final uri = endpoint;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        !uri.path.endsWith('/v1/operations')) {
      throw const FinancialVoucherSyncException('INVALID_FINANCIAL_ENDPOINT');
    }
    final tokenProvider = idTokenProvider;
    if (tokenProvider == null) {
      throw const FinancialVoucherSyncException('FINANCIAL_AUTH_REQUIRED');
    }
    final token = await tokenProvider();
    if (token.trim().isEmpty || token.contains(RegExp(r'\\s'))) {
      throw const FinancialVoucherSyncException('FINANCIAL_AUTH_REQUIRED');
    }
    return FinancialVoucherRelayWorker(
      helper: helper,
      client: client,
      endpoint: uri,
      trustedRelayConfigured: true,
    ).syncOnce(branchId: branchId, idToken: token);
  }
}
