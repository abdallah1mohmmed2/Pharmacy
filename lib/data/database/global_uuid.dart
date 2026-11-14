/// Validation for the globally provisioned branch identifier.
abstract final class GlobalUuid {
  static final RegExp _pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static bool isValid(String value) => _pattern.hasMatch(value);
}
