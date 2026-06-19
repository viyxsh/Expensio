import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

class AppSettings {
  static const _boxName = 'settings';
  static const _currencyKey = 'currency_code';
  static const _settlementReminderKey = 'notif_settlement';
  static const _dailyReminderKey = 'notif_daily';
  static const _chartsExpandedKey = 'tx_charts_expanded';
  static const _themeModeKey = 'theme_mode';
  static const _budgetOverallKey = 'budget_overall'; // cents, 0 = unset
  static const _budgetCategoriesKey = 'budget_categories'; // JSON {cat: cents}

  static Box get _box => Hive.box(_boxName);

  static const List<Map<String, String>> currencies = [
    {'code': 'INR', 'name': 'Indian Rupee',      'symbol': 'Rs'},
    {'code': 'USD', 'name': 'US Dollar',          'symbol': '\$'},
    {'code': 'EUR', 'name': 'Euro',               'symbol': '€'},
    {'code': 'GBP', 'name': 'British Pound',      'symbol': '£'},
    {'code': 'JPY', 'name': 'Japanese Yen',       'symbol': '¥'},
    {'code': 'CAD', 'name': 'Canadian Dollar',    'symbol': 'CA\$'},
    {'code': 'AUD', 'name': 'Australian Dollar',  'symbol': 'A\$'},
    {'code': 'SGD', 'name': 'Singapore Dollar',   'symbol': 'S\$'},
    {'code': 'AED', 'name': 'UAE Dirham',         'symbol': 'AED'},
    {'code': 'SAR', 'name': 'Saudi Riyal',        'symbol': 'SAR'},
  ];

  static String get currencyCode =>
      _box.get(_currencyKey, defaultValue: 'INR') as String;

  static String get currencySymbol {
    final code = currencyCode;
    return currencies.firstWhere(
      (c) => c['code'] == code,
      orElse: () => currencies.first,
    )['symbol']!;
  }

  static String get currencyName {
    final code = currencyCode;
    return currencies.firstWhere(
      (c) => c['code'] == code,
      orElse: () => currencies.first,
    )['name']!;
  }

  static Future<void> setCurrency(String code) =>
      _box.put(_currencyKey, code);

  static bool get settlementReminders =>
      _box.get(_settlementReminderKey, defaultValue: false) as bool;

  static bool get dailyReminders =>
      _box.get(_dailyReminderKey, defaultValue: false) as bool;

  static Future<void> setSettlementReminders(bool v) =>
      _box.put(_settlementReminderKey, v);

  static Future<void> setDailyReminders(bool v) =>
      _box.put(_dailyReminderKey, v);

  static bool get chartsExpanded =>
      _box.get(_chartsExpandedKey, defaultValue: true) as bool;

  static Future<void> setChartsExpanded(bool v) =>
      _box.put(_chartsExpandedKey, v);

  /// 'system' | 'light' | 'dark'. Defaults to dark (the app's original look).
  static String get themeMode =>
      _box.get(_themeModeKey, defaultValue: 'dark') as String;

  static Future<void> setThemeMode(String mode) =>
      _box.put(_themeModeKey, mode);

  // Budgets (all amounts in cents). 0 / absent means "no budget set".

  static int get overallBudget =>
      _box.get(_budgetOverallKey, defaultValue: 0) as int;

  static Future<void> setOverallBudget(int cents) =>
      _box.put(_budgetOverallKey, cents < 0 ? 0 : cents);

  static Map<String, int> get categoryBudgets {
    final raw = _box.get(_budgetCategoriesKey);
    if (raw is String && raw.isNotEmpty) {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, (v as num).toInt()));
    }
    return {};
  }

  /// Set (or clear, when [cents] <= 0) the budget for a single category.
  static Future<void> setCategoryBudget(String category, int cents) {
    final m = categoryBudgets;
    if (cents <= 0) {
      m.remove(category);
    } else {
      m[category] = cents;
    }
    return _box.put(_budgetCategoriesKey, jsonEncode(m));
  }
}
