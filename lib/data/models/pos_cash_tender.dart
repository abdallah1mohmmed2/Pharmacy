/// The drawer receives the invoice net; excess tender is returned as change.
/// An empty field means the customer gave the exact amount.
double posCashChange({required double netTotal, required String receivedText}) {
  final received = receivedText.trim().isEmpty
      ? netTotal
      : double.tryParse(receivedText.trim());
  if (!netTotal.isFinite ||
      netTotal < 0 ||
      received == null ||
      !received.isFinite ||
      received < netTotal) {
    throw StateError('أدخل مبلغاً مستلماً صحيحاً لا يقل عن صافي الفاتورة');
  }
  return received - netTotal;
}
