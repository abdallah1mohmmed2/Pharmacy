import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/clinical_and_rx_models.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/drug_model.dart';
import 'package:global_enterprise_pharmacy_erp/data/models/erp_models.dart';
import 'package:global_enterprise_pharmacy_erp/data/services/posting_and_sales_service.dart';
import 'package:global_enterprise_pharmacy_erp/providers/pos_and_drugs_provider.dart';

class _DelayedPosting extends PostingAndSalesService {
  _DelayedPosting(this.result);
  final Completer<int> result;
  int callCount = 0;

  @override
  Future<int> postSale({
    required int branchId,
    required int cashierUserId,
    required List<CartItemModel> items,
    required String saleType,
    required List<
            ({
              int cashAccountId,
              double amount,
              String method,
              String? walletRef
            })>
        payments,
    int customerPartyId = 0,
    double discountAmount = 0,
    required ClinicalVerdict clinicalVerdict,
  }) {
    callCount++;
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('repeated checkout is blocked while first posting is pending', () async {
    final posting = _DelayedPosting(Completer<int>());
    final provider = PosAndDrugsProvider(posting: posting);
    provider.addDrug(
      const DrugModel(id: 7, branchId: 1, sellPricePack: 1500),
      unit: 'PACK',
    );
    final emptyVerdict = ClinicalVerdict(const []);
    Future<int> submit() => provider.checkout(
          cashierId: 1,
          saleType: 'CASH',
          payments: const [
            (cashAccountId: 1, amount: 1500.0, method: 'CASH', walletRef: null),
          ],
          clinicalVerdict: emptyVerdict,
        );

    final first = submit();
    expect(provider.checkoutPending, isTrue);
    expect(posting.callCount, 1);
    await expectLater(submit(), throwsStateError);
    expect(posting.callCount, 1);
    final failure = expectLater(first, throwsStateError);
    posting.result.completeError(StateError('database rejected invoice'));
    await failure;
    expect(provider.checkoutPending, isFalse);
    expect(provider.cart, hasLength(1),
        reason: "failed posting must keep the customer cart");
  });

  test('invalid discounts are rejected before posting', () async {
    final posting = _DelayedPosting(Completer<int>());
    final provider = PosAndDrugsProvider(posting: posting);
    provider.addDrug(
      const DrugModel(id: 7, branchId: 1, sellPricePack: 1500),
      unit: 'PACK',
    );
    await expectLater(
      provider.checkout(
        cashierId: 1,
        saleType: 'CASH',
        payments: const [],
        discount: 1501,
        clinicalVerdict: ClinicalVerdict(const []),
      ),
      throwsStateError,
    );
    expect(posting.callCount, 0);
    expect(provider.checkoutPending, isFalse);
  });
}
