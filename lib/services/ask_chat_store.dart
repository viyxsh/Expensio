import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Local storage for Ask chat sessions (Gemini-style history).
///
/// Each chat is one JSON string in an untyped Hive box, so no generated
/// adapters are needed and the store works identically in local and cloud
/// modes. Persisted per message: user texts and assistant components.
/// Action confirm-cards and error bubbles are transient and not persisted.
class AskChatStore {
  AskChatStore._();

  static const String _boxName = 'ask_chats';
  static Box<String>? _box;

  static Box<String> get _boxSafe {
    final b = _box;
    if (b != null && b.isOpen) return b;
    throw Exception('ask_chats_box_not_open');
  }

  static Future<void> init() async {
    try {
      _box = await Hive.openBox<String>(_boxName);
    } catch (e) {
      debugPrint('[AskChats] init failed: $e');
    }
  }

  // ----------------------------------------------------------------- meta

  static String get _now => DateTime.now().toIso8601String();

  /// Derives a chat title from its first user message, Gemini-style.
  static String titleFromMessage(String text) {
    final words = text.trim().split(RegExp(r'\s+'));
    final head = words.take(6).join(' ');
    return head.length > 42 ? '${head.substring(0, 42)}…' : head;
  }

  static List<Map<String, dynamic>> listChats() {
    try {
      final chats = _boxSafe.values
          .map((raw) {
            try {
              return jsonDecode(raw) as Map<String, dynamic>;
            } catch (_) {
              return null;
            }
          })
          .whereType<Map<String, dynamic>>()
          .toList();
      chats.sort((a, b) => _str(b['updatedAt']).compareTo(_str(a['updatedAt'])));
      return chats;
    } catch (e) {
      debugPrint('[AskChats] list failed: $e');
      return [];
    }
  }

  // ------------------------------------------------------------ mutations

  /// Creates a chat with [id] titled from the first user message.
  static Future<void> createChat(String id, String firstMessage) async {
    final entry = {
      'id': id,
      'title': titleFromMessage(firstMessage),
      'createdAt': _now,
      'updatedAt': _now,
      'messages': <Map<String, dynamic>>[
        {'kind': 'user', 'text': firstMessage},
      ],
    };
    await _write(id, entry);
  }

  /// Replaces the persisted message list of [id]. [entries] are already
  /// JSON-ready maps (user texts and component payloads).
  static Future<void> saveMessages(
      String id, List<Map<String, dynamic>> entries) async {
    final existing = _read(id);
    if (existing == null) return; // chat was deleted mid-flight; drop it
    existing['messages'] = entries;
    existing['updatedAt'] = _now;
    await _write(id, existing);
  }

  static Future<void> touch(String id) async {
    final existing = _read(id);
    if (existing == null) return;
    existing['updatedAt'] = _now;
    await _write(id, existing);
  }

  static Future<void> deleteChat(String id) async {
    try {
      await _boxSafe.delete(id);
    } catch (e) {
      debugPrint('[AskChats] delete failed: $e');
    }
  }

  // ------------------------------------------------------------- messages

  /// The persisted messages of [id], JSON-ready. Empty when missing.
  static List<Map<String, dynamic>> messagesOf(String id) {
    final entry = _read(id);
    if (entry == null) return const [];
    return (entry['messages'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  // ------------------------------------------------------------ internals

  static Map<String, dynamic>? _read(String id) {
    try {
      final raw = _boxSafe.get(id);
      if (raw == null) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[AskChats] read failed: $e');
      return null;
    }
  }

  static Future<void> _write(String id, Map<String, dynamic> entry) async {
    try {
      await _boxSafe.put(id, jsonEncode(entry));
    } catch (e) {
      debugPrint('[AskChats] write failed: $e');
    }
  }

  static String _str(dynamic v) => (v ?? '').toString();
}
