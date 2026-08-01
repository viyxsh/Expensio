import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/bill_item_model.dart';

class GeminiService {
  static String get _apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';

  // Use a current model you actually have access to.
  static const String _model = 'gemini-2.5-flash-lite';

  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  static Future<List<BillItem>> parseBillText(String ocrText) async {
    if (_apiKey.isEmpty) throw Exception('missing_api_key');
    if (ocrText.trim().isEmpty) throw Exception('no_text');

    // Trim noisy OCR so you don't waste tokens
    final compactText = _compactOcrText(ocrText);

    final requestBody = {
      'contents': [
        {
          'parts': [
            {'text': _buildPrompt(compactText)}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0,
        'topK': 1,
        'topP': 1,
        'maxOutputTokens': 1500,
        'responseMimeType': 'application/json',
        'responseSchema': {
          'type': 'object',
          'properties': {
            'is_receipt': {
              'type': 'boolean',
              'description':
                  'True only if the document is an actual receipt, bill, '
                      'or invoice recording a real transaction',
            },
            'items': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'name': {'type': 'string'},
                  'quantity': {
                    'type': 'integer',
                    'description':
                        'Only if explicitly printed. Null when not shown.'
                  },
                  'price': {
                    'type': 'number',
                    'description':
                        'Only the exact printed value. Null when missing, '
                            'illegible, or ambiguous.'
                  },
                  'category': {
                    'type': 'string',
                    'enum': [
                      'Groceries',
                      'Food & Drink',
                      'Electronics',
                      'Clothing',
                      'Transport',
                      'Health',
                      'Entertainment',
                      'Utilities',
                      'General',
                    ]
                  },
                },
                // price/quantity intentionally NOT required: they must stay
                // null instead of being guessed.
                'required': ['name', 'category'],
              }
            }
          },
          'required': ['is_receipt', 'items'],
        },
      },
    };

    final response = await _postWithRetry(requestBody);
    final Map<String, dynamic> responseJson =
    jsonDecode(response.body) as Map<String, dynamic>;

    final candidate = (responseJson['candidates'] as List?)?.isNotEmpty == true
        ? responseJson['candidates'][0] as Map<String, dynamic>
        : null;

    if (candidate == null) {
      debugPrint('[Gemini] No candidates: ${response.body}');
      throw Exception('empty_response');
    }

    final finishReason = candidate['finishReason']?.toString();
    final finishMessage = candidate['finishMessage']?.toString();
    final text = candidate['content']?['parts']?[0]?['text'] as String?;

    debugPrint('[Gemini] finishReason=$finishReason finishMessage=$finishMessage');
    debugPrint('[Gemini] rawText=$text');

    if (text == null || text.trim().isEmpty) {
      throw Exception('empty_response');
    }

    // If model stopped for a bad reason, fail early.
    if (finishReason == 'MAX_TOKENS') {
      throw Exception('truncated_response');
    }
    if (finishReason == 'MALFORMED_RESPONSE') {
      throw Exception('malformed_response');
    }

    try {
      return _parseGeminiResponse(text);
    } on FormatException catch (e, st) {
      debugPrint('[Gemini] JSON parse error: $e\nRaw text: $text\n$st');
      throw Exception('parse_error');
    }
  }

  static Future<http.Response> _postWithRetry(
      Map<String, dynamic> requestBody, {
        int maxAttempts = 3,
      }) async {
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final response = await http.post(
        Uri.parse('$_baseUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final candidate = (body['candidates'] as List?)?.isNotEmpty == true
            ? body['candidates'][0] as Map<String, dynamic>
            : null;
        final finishReason = candidate?['finishReason']?.toString();
        final text = candidate?['content']?['parts']?[0]?['text'] as String?;

        final looksIncomplete = text != null &&
            text.trim().isNotEmpty &&
            !_looksLikeCompleteJson(text);

        // Retry partial/truncated JSON responses.
        if ((finishReason == 'MAX_TOKENS' || looksIncomplete) &&
            attempt < maxAttempts) {
          final delayMs =
              (pow(2, attempt) * 1000).toInt() + Random().nextInt(400);
          debugPrint(
              '[Gemini] Partial JSON detected. Retrying in ${delayMs}ms...');
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        }

        return response;
      }

      Map<String, dynamic>? err;
      try {
        err = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}

      debugPrint('[Gemini] HTTP ${response.statusCode} body=${response.body}');

      if (response.statusCode == 429) {
        if (attempt < maxAttempts) {
          final delayMs =
              (pow(2, attempt) * 1000).toInt() + Random().nextInt(400);
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        }
        throw Exception('quota_exceeded');
      }

      if (response.statusCode == 400) throw Exception('bad_request');
      if (response.statusCode == 403) throw Exception('auth_error');
      if (response.statusCode == 404) throw Exception('model_not_found');

      throw Exception('api_error_${response.statusCode}_${err?['error']?['status'] ?? ''}');
    }

    throw Exception('api_failed');
  }

  static String _buildPrompt(String ocrText) => '''
You are given OCR text from a photographed document. Decide first whether it
is actually a receipt, and only then extract line items.

IS IT A RECEIPT?
- Set "is_receipt" to true ONLY for an actual receipt, bill, or invoice that
  records a real transaction (e.g. shows prices/amounts, a seller, a date, or
  payment information).
- Do NOT treat a document as a receipt merely because it contains product
  names, quantities, IDs/SKUs, or tabular data. Inventories, packing slips,
  delivery notes, catalogs, price lists, spreadsheets, and random tables of
  data are NOT receipts — set "is_receipt" to false and return an empty
  items array.

EXTRACTING ITEMS (only when is_receipt is true):
- Extract each purchased line item with its name.
- PRICE: use only the exact value printed on the document. If a price is
  missing, illegible, ambiguous, or you would have to guess, compute, or
  estimate it in any way, set "price" to null. NEVER infer, invent, calculate,
  or default a missing price to zero.
- QUANTITY: use the explicitly printed quantity. When none is shown, set
  "quantity" to null rather than assuming one.
- CATEGORY: pick the best fit from the allowed values.

Receipt text:
$ocrText

Return JSON only.
''';

  static String _compactOcrText(String input) {
    final lines = input
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .where((e) => !RegExp(r'^(gst|cgst|sgst|subtotal|sub total|total|tax|invoice|table|kot|server)\b',
        caseSensitive: false)
        .hasMatch(e))
        .toList();

    // Keep it bounded so OCR garbage does not blow up tokens
    return lines.join('\n').substring(
      0,
      min(lines.join('\n').length, 3500),
    );
  }

  static bool _looksLikeCompleteJson(String text) {
    final t = text.trim();
    return t.startsWith('{') && t.endsWith('}');
  }

  static List<BillItem> _parseGeminiResponse(String rawText) {
    final parsed = jsonDecode(rawText) as Map<String, dynamic>;

    // The model decides receipt-vs-not; product names, quantities, IDs, or
    // tabular data alone are not proof of a transaction.
    if (parsed['is_receipt'] != true) {
      throw Exception('not_a_receipt');
    }

    final items = (parsed['items'] as List<dynamic>? ?? const []);
    return items
        .map((e) => BillItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}