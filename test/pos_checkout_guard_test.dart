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
  List<CartItemModel>? postedItems;

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
    int? warehouseId,
    int customerPartyId = 0,
    double discountAmount = 0,
    required ClinicalVerdict clinicalVerdict,
  }) {
    callCount++;
    postedItems = items;
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

    provider.currentTab.warehouseId = 1;
    final first = submit();
    expect(provider.checkoutPending, isTrue);
    expect(posting.callCount, 1);
    await expectLater(submit(), throwsStateError);
    expect(posting.callCount, 1);
    final failure = expectLater(first, throwsStateError);
    posting.result.completeError(StateError('database rejected invoice'));
    await failure;
    expect(provider.checkoutPending, isFalse);
    expect(
      provider.cart,
      hasLength(1),
      reason: "failed posting must keep the customer cart",
    );
  });

  test('invalid discounts are rejected before posting', () async {
    final posting = _DelayedPosting(Completer<int>());
    final provider = PosAndDrugsProvider(posting: posting);
    provider.addDrug(
      const DrugModel(id: 7, branchId: 1, sellPricePack: 1500),
      unit: 'PACK',
    );
    provider.currentTab.warehouseId = 1;
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
  test(
    'pending checkout freezes cart and posts an independent snapshot',
    () async {
      final posting = _DelayedPosting(Completer<int>());
      final provider = PosAndDrugsProvider(posting: posting);
      provider.addDrug(
        const DrugModel(id: 7, sellPricePack: 1500),
        unit: 'PACK',
      );
      final item = provider.cart.single;
      provider.currentTab.warehouseId = 1;
    final first = provider.checkout(
        cashierId: 1,
        saleType: 'CASH',
        payments: const [
          (cashAccountId: 1, amount: 1500.0, method: 'CASH', walletRef: null),
        ],
        clinicalVerdict: ClinicalVerdict(const []),
      );
      provider.changeQuantity(item, 9);
      provider.changeUnit(item, 'UNIT');
      provider.removeItem(item);
      provider.closeCurrent();
      provider.holdCurrent();
      expect(provider.createTab(), isFalse);
      expect(provider.cart, hasLength(1));
      expect(item.quantity, 1);
      expect(item.sellUnit, 'PACK');
      expect(provider.currentTab.held, isFalse);
      // An old reference cannot mutate the objects already sent for posting.
      item.quantity = 99;
      expect(posting.postedItems!.single.quantity, 1);
      final failure = expectLater(first, throwsStateError);
      posting.result.completeError(StateError('temporary failure'));
      await failure;
      expect(provider.checkoutPending, isFalse);
      provider.changeQuantity(item, 2);
      expect(item.quantity, 2);
    },
  );

  test('invalid numeric input never reaches the database', () async {
    final posting = PostingAndSalesService();
    Future<int> submit({
      double discount = 0,
      double quantity = 1,
      double payment = 100,
    }) =>
        posting.postSale(
          branchId: 1,
          cashierUserId: 1,
          saleType: 'CASH',
          items: [
            CartItemModel(
              drug: const DrugModel(id: 7, sellPriceUnit: 100),
              sellUnit: 'UNIT',
              quantity: quantity,
            ),
          ],
          payments: [
            (
              cashAccountId: 1,
              amount: payment,
              method: 'CASH',
              walletRef: null
            ),
          ],
          discountAmount: discount,
          clinicalVerdict: ClinicalVerdict(const []),
        );
    for (final discount in [-1.0, 101.0, double.nan, double.infinity]) {
      await expectLater(submit(discount: discount), throwsStateError);
    }
    for (final quantity in [0.0, -1.0, double.nan, double.infinity]) {
      await expectLater(submit(quantity: quantity), throwsStateError);
    }
    for (final payment in [-1.0, double.nan, double.infinity]) {
      await expectLater(submit(payment: payment), throwsStateError);
    }
  });
}
