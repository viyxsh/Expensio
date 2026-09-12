import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// A user-created category: name + emoji + an auto-assigned colour.
class CustomCategory {
  final String name;
  final String emoji;
  final int colorValue;

  const CustomCategory({
    required this.name,
    required this.emoji,
    required this.colorValue,
  });

  Map<String, dynamic> toJson() =>
      {'name': name, 'emoji': emoji, 'color': colorValue};

  factory CustomCategory.fromJson(Map<String, dynamic> j) => CustomCategory(
        name: (j['name'] ?? '').toString(),
        emoji: (j['emoji'] ?? '📦').toString(),
        colorValue: (j['color'] as num?)?.toInt() ?? 0xFF7C6F64,
      );
}

/// Local store for user-created categories, persisted in the shared
/// 'settings' Hive box as one JSON list (per device, both app modes).
class CategoryStore {
  CategoryStore._();

  static const String _key = 'custom_categories';
  static const String _overridesKey = 'category_color_overrides';

  /// Auto-assigned tile colours for custom categories, cycled in order.
  static const List<int> palette = [
    0xFFEF5350, 0xFFEC407A, 0xFFAB47BC, 0xFF7E57C2,
    0xFF5C6BC0, 0xFF42A5F5, 0xFF29B6F6, 0xFF26C6DA,
    0xFF26A69A, 0xFF66BB6A, 0xFF9CCC65, 0xFFFFEE58,
    0xFFFFCA28, 0xFFFFA726, 0xFFFF7043, 0xFF8D6E63,
  ];

  static List<CustomCategory> _custom = const [];
  static Map<String, int> _overrides = const {};
  static bool _loaded = false;

  static List<CustomCategory> get all => _custom;

  /// A user-chosen colour for a (built-in or custom) category, if any.
  static int? colorOverride(String name) => _overrides[name];

  static CustomCategory? byName(String name) {
    final q = name.trim().toLowerCase();
    for (final c in _custom) {
      if (c.name.trim().toLowerCase() == q) return c;
    }
    return null;
  }

  static Future<void> init() async {
    try {
      final box = Hive.box('settings');
      final raw = box.get(_key) as String?;
      _custom = raw == null
          ? const []
          : (jsonDecode(raw) as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map(CustomCategory.fromJson)
              .toList();
      final oRaw = box.get(_overridesKey) as String?;
      _overrides = oRaw == null
          ? const {}
          : (jsonDecode(oRaw) as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toInt()));
      _loaded = true;
    } catch (e) {
      debugPrint('[Categories] init failed: $e');
    }
  }

  static Future<void> add(String name, String emoji,
      {int? colorValue}) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    // Skip if the same name already exists (case-insensitive).
    if (byName(clean) != null) return;
    final color = colorValue ?? palette[_custom.length % palette.length];
    _custom = [..._custom,
      CustomCategory(name: clean, emoji: emoji, colorValue: color)];
    await _persist();
  }

  /// Sets the colour of any category. Custom categories are updated in
  /// place; built-in ones get a persisted override.
  static Future<void> setColor(String name, int colorValue) async {
    final custom = byName(name);
    if (custom != null) {
      _custom = [
        for (final c in _custom)
          if (identical(c, custom))
            CustomCategory(
                name: c.name, emoji: c.emoji, colorValue: colorValue)
          else
            c,
      ];
      await _persist();
      return;
    }
    _overrides = {..._overrides, name: colorValue};
    await _persistOverrides();
  }

  static Future<void> _persist() async {
    try {
      await Hive.box('settings').put(
          _key, jsonEncode([for (final c in _custom) c.toJson()]));
    } catch (e) {
      debugPrint('[Categories] persist failed: $e');
    }
  }

  static Future<void> _persistOverrides() async {
    try {
      await Hive.box('settings')
          .put(_overridesKey, jsonEncode(_overrides));
    } catch (e) {
      debugPrint('[Categories] persist overrides failed: $e');
    }
  }

  static bool get isReady => _loaded;
}
