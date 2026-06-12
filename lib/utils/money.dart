import '../services/app_settings.dart';

/// Centralised money handling. All monetary values are stored and computed as
/// integer **minor units** (cents/paise) to avoid floating-point drift. Major
/// units (doubles) are only used at the UI boundary for input and charts.
class Money {
  Money._();

  /// Parse a user-entered major-unit string (e.g. "12.50") into cents.
  /// Returns null when the text is not a valid number.
  static int? tryParseToCents(String s) {
    final v = double.tryParse(s.trim());
    if (v == null) return null;
    return (v * 100).round();
  }

  /// Convert a major-unit double (e.g. an OCR-derived total) into cents.
  static int fromMajor(double major) => (major * 100).round();

  /// Convert cents back to a major-unit double — only for charts/compact labels.
  static double toMajor(int cents) => cents / 100.0;

  /// Plain numeric string without a currency symbol, e.g. "1234.50".
  static String format(int cents, {int decimals = 2}) =>
      (cents / 100).toStringAsFixed(decimals);

  /// Numeric string prefixed with the active currency symbol, e.g. "Rs 1234.50".
  static String withSymbol(int cents, {int decimals = 2}) =>
      '${AppSettings.currencySymbol} ${format(cents, decimals: decimals)}';

  /// Split [total] cents into [n] parts that sum **exactly** to [total].
  /// The first `remainder` parts each receive one extra cent so no money is
  /// lost or invented when a total doesn't divide evenly.
  static List<int> splitEqual(int total, int n) {
    if (n <= 0) return const [];
    final base = total ~/ n;
    final remainder = total - base * n;
    return List.generate(n, (i) => base + (i < remainder ? 1 : 0));
  }
}
