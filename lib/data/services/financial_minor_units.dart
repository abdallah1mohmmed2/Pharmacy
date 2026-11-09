/// Strict, currency-agnostic decimal arithmetic for financial wire values.
///
/// This does not approve a currency or infer its precision. The caller must
/// obtain [fractionDigits] from an independently approved currency policy.
abstract final class FinancialMinorUnits {
  static const int maxMinor = 999999999999;

  static int parseDecimal(String value, {required int fractionDigits}) {
    if (fractionDigits < 0 || fractionDigits > 3) {
      throw const FormatException('UNAPPROVED_FRACTION_DIGITS');
    }
    if (!RegExp(r'^(0|[1-9][0-9]*)(?:\.[0-9]+)?$').hasMatch(value)) {
      throw const FormatException('INVALID_DECIMAL_AMOUNT');
    }
    final parts = value.split('.');
    final fractional = parts.length == 2 ? parts[1] : '';
    if (fractional.length > fractionDigits &&
        fractional.substring(fractionDigits).contains(RegExp(r'[1-9]'))) {
      throw const FormatException('EXCESS_DECIMAL_PRECISION');
    }
    final normalized = fractional.padRight(fractionDigits, '0');
    final minor =
        BigInt.parse(parts.first) * BigInt.from(10).pow(fractionDigits) +
            (fractionDigits == 0
                ? BigInt.zero
                : BigInt.parse(normalized.substring(0, fractionDigits)));
    if (minor < BigInt.zero || minor > BigInt.from(maxMinor)) {
      throw const FormatException('AMOUNT_OUT_OF_RANGE');
    }
    return minor.toInt();
  }

  static String toDecimal(int minor, {required int fractionDigits}) {
    if (fractionDigits < 0 || fractionDigits > 3) {
      throw const FormatException('UNAPPROVED_FRACTION_DIGITS');
    }
    if (minor < 0 || minor > maxMinor) {
      throw const FormatException('AMOUNT_OUT_OF_RANGE');
    }
    if (fractionDigits == 0) return minor.toString();
    final scale = [1, 10, 100, 1000][fractionDigits];
    final whole = minor ~/ scale;
    final remainder = (minor % scale).toString().padLeft(fractionDigits, '0');
    return '$whole.$remainder';
  }

  /// Enforce exact canonical representation at the chosen precision.
  /// Never silently round or truncate a nonzero fractional minor unit.
  static int checkedMinor(Object? raw, {required int fractionDigits}) {
    if (raw is! int || raw < 0 || raw > maxMinor) {
      throw const FormatException('INVALID_MINOR_AMOUNT');
    }
    if (fractionDigits < 0 || fractionDigits > 3) {
      throw const FormatException('UNAPPROVED_FRACTION_DIGITS');
    }
    return raw;
  }
}
