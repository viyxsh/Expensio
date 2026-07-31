import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import 'app_settings.dart';

/// Exchange-rate handling for multi-currency support.
///
/// Transactions keep the currency they were recorded in; reports and totals
/// convert on the fly into the user's selected reporting currency.
///
/// Rates are relative to USD (1 USD = rates[code] units of `code`) and come
/// from open.er-api.com (free, no key). The last successful fetch is cached in
/// Hive so conversions keep working offline. A small built-in table is the
/// final fallback when there has never been a successful fetch.
class CurrencyService {
  CurrencyService._();

  static const _boxName = 'settings';
  static const _ratesKey = 'fx_rates_cache';
  static const _fetchedAtKey = 'fx_rates_fetched_at';
  static const _maxAge = Duration(hours: 12);

  /// Rates per 1 USD, e.g. rates['INR'] == 83.5 means 1 USD = 83.5 INR.
  static Map<String, double> _rates = _fallbackRates;
  static DateTime? _fetchedAt;
  static bool _refreshing = false;

  /// The user's reporting currency, mirrored from the settings box so
  /// [convert] never needs to touch Hive (keeps pure logic testable).
  static String _reportingCode = 'INR';
  static String get reportingCode => _reportingCode;

  /// Approximate mid-2026 values. Only used when no cached rates exist yet
  /// (first launch, offline). Values drift — live refresh corrects them.
  static const Map<String, double> _fallbackRates = {
    'USD': 1.0,
    'INR': 86.0,
    'EUR': 0.92,
    'GBP': 0.78,
    'JPY': 155.0,
    'CAD': 1.37,
    'AUD': 1.51,
    'SGD': 1.34,
    'AED': 3.67,
    'SAR': 3.75,
  };

  /// Loads cached rates into memory and kicks off a background refresh when
  /// they are stale. Safe to call multiple times.
  static Future<void> init() async {
    final box = Hive.box(_boxName);
    _reportingCode = AppSettings.currencyCode;
    // Track reporting-currency changes without touching Hive per conversion.
    box.listenable(keys: ['currency_code']).addListener(() {
      _reportingCode = AppSettings.currencyCode;
    });
    _readCache(box);
    if (_fetchedAt == null ||
        DateTime.now().difference(_fetchedAt!) > _maxAge) {
      // Fire-and-forget: UI keeps working with cached/fallback rates.
      refreshRates();
    }
  }

  static void _readCache(Box box) {
    try {
      final raw = box.get(_ratesKey);
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _rates = decoded
            .map((k, v) => MapEntry(k, (v as num).toDouble()));
      }
      final at = box.get(_fetchedAtKey);
      if (at is int) _fetchedAt = DateTime.fromMillisecondsSinceEpoch(at);
    } catch (_) {
      // Corrupt cache — fall back to built-in table.
      _rates = _fallbackRates;
      _fetchedAt = null;
    }
  }

  /// Fetches fresh rates. Returns true on success. Never throws.
  static Future<bool> refreshRates() async {
    if (_refreshing) return false;
    _refreshing = true;
    try {
      final res = await http
          .get(Uri.parse('https://open.er-api.com/v6/latest/USD'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return false;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final result = body['result'];
      final ratesRaw = body['rates'];
      if (result != 'success' || ratesRaw is! Map<String, dynamic>) {
        return false;
      }
      final rates = ratesRaw
          .map((k, v) => MapEntry(k, (v as num).toDouble()));
      if (!rates.containsKey('USD')) return false;

      _rates = rates;
      _fetchedAt = DateTime.now();
      final box = Hive.box(_boxName);
      await box.put(_ratesKey, jsonEncode(rates));
      await box.put(_fetchedAtKey, _fetchedAt!.millisecondsSinceEpoch);
      return true;
    } catch (_) {
      return false; // Offline or service down — keep using cache/fallback.
    } finally {
      _refreshing = false;
    }
  }

  static bool get isFresh =>
      _fetchedAt != null &&
      DateTime.now().difference(_fetchedAt!) <= _maxAge;

  static String symbolOf(String code) {
    for (final c in AppSettings.currencies) {
      if (c['code'] == code) return c['symbol']!;
    }
    return code;
  }

  /// Converts [cents] from currency [from] to [to]. When [to] is null the
  /// user's selected reporting currency is used. If either rate is unknown the
  /// amount is returned unchanged (best effort, never throws).
  static int convert(int cents, String from, {String? to}) {
    final target = to ?? _reportingCode;
    if (from == target || cents == 0) return cents;
    final rFrom = _rates[from];
    final rTo = _rates[target];
    if (rFrom == null || rTo == null || rFrom == 0) return cents;
    final usd = cents / rFrom;
    return (usd * rTo).round();
  }
}
