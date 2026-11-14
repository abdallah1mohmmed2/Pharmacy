/// Normalize keyboard variants without changing medicine or batch identifiers.
String purchaseDigits(String value) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  final output = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    final a = arabic.indexOf(char), p = persian.indexOf(char);
    output.write(a >= 0 ? a : p >= 0 ? p : char);
  }
  return output.toString().replaceAll(RegExp('[\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '').trim();
}

String _numberText(String value) {
  var text = purchaseDigits(value).replaceAll('٬', '').replaceAll('٫', '.').replaceAll('،', ',');
  if (RegExp(r'^[+-]?\d{1,3}(,\d{3})+(\.\d+)?$').hasMatch(text)) {
    text = text.replaceAll(',', '');
  } else if (!text.contains('.') && ','.allMatches(text).length == 1) {
    text = text.replaceAll(',', '.');
  }
  return text;
}

double? parsePurchaseNumber(String value) {
  final text = _numberText(value);
  if (!RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$').hasMatch(text)) return null;
  final number = double.tryParse(text);
  return number != null && number.isFinite ? number : null;
}

int? parsePurchaseCount(String value) {
  final text = _numberText(value);
  if (!RegExp(r'^[+-]?\d+(?:\.0+)?$').hasMatch(text)) return null;
  return int.tryParse(text.replaceFirst(RegExp(r'\.0+$'), ''));
}

/// A month-only medicine expiry is represented by that month's final day.
DateTime? parsePurchaseExpiry(String value) {
  final text = purchaseDigits(value).replaceAll(RegExp(r'\s+'), '');
  final parts = text.split(RegExp(r'[-/.]'));
  int? year, month, day;
  if (parts.length == 3 && parts.every((p) => RegExp(r'^\d+$').hasMatch(p))) {
    if (parts.first.length == 4) {
      year = int.tryParse(parts[0]); month = int.tryParse(parts[1]); day = int.tryParse(parts[2]);
    } else if (parts.last.length == 4) {
      day = int.tryParse(parts[0]); month = int.tryParse(parts[1]); year = int.tryParse(parts[2]);
    }
  } else if (parts.length == 2 && parts.every((p) => RegExp(r'^\d+$').hasMatch(p))) {
    if (parts.last.length == 4) {
      month = int.tryParse(parts[0]); year = int.tryParse(parts[1]);
    } else if (parts.first.length == 4) {
      year = int.tryParse(parts[0]); month = int.tryParse(parts[1]);
    }
    if (year != null && month != null && month >= 1 && month <= 12 && year >= 1900 && year <= 9999) {
      return DateTime(year, month + 1, 0);
    }
  }
  if (year == null || month == null || day == null || year < 1900 || year > 9999 || month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day ? date : null;
}

String purchaseExpiryIso(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
