import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/ask_models.dart';
import 'app_settings.dart';
import 'services.dart';

/// Signature of the tool surface the query loop can call. Implemented by
/// [AskTools], which reads straight from the app's [AppState] cache — the
/// provider-agnostic repository layer is literally the tool surface.
typedef AskToolExecutor = Future<Object?> Function(
    String name, Map<String, dynamic> args);

/// Gemini back-end for "Ask Expensio".
///
/// [answer] handles one user message in a single function-calling loop
/// (one API call in the common case): the model either calls `record_expense`
/// to produce an [AskExpenseAction], calls data tools (backed by the
/// repository) and finishes with `render_answer` — exactly one UI component
/// from the catalog — or answers in prose.
class AskService {
  AskService._();

  static String get _apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';

  // The free tier allows only ~20 requests per DAY per model, so no single
  // model survives real testing. Each model has its OWN daily bucket though —
  // so we run a fallback chain: when a model's daily quota is exhausted, the
  // next request transparently moves to the following one.
  static const List<String> _models = [
    'gemini-3.5-flash',
    'gemini-3.6-flash',
    'gemini-3.7-flash',
    'gemini-3.8-flash',
  ];
  static int _modelIndex = 0;
  static String get _model => _models[_modelIndex];

  static String _baseUrlFor(String model) =>
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';

  /// Same category enum the rest of the app uses.
  static const List<String> categories = [
    'General',
    'Groceries',
    'Food & Drink',
    'Electronics',
    'Clothing',
    'Transport',
    'Health',
    'Entertainment',
    'Utilities',
  ];

  static bool get isConfigured => _apiKey.isNotEmpty;

  // --------------------------------------------------------------- answer

  /// Handle one user message in a single tool-calling loop. The model either
  /// calls `record_expense` (→ confirmable action) or answers the question —
  /// via data tools and a final `render_answer`, or in prose. One API call in
  /// the common case.
  static Future<AskReply> answer(
    String question, {
    required AskToolExecutor executor,
  }) async {
    if (_apiKey.isEmpty) throw Exception('missing_api_key');
    if (question.trim().isEmpty) throw Exception('empty_response');

    final contents = <Map<String, dynamic>>[
      {
        'role': 'user',
        'parts': [
          {'text': question}
        ]
      }
    ];

    // Cap the loop so a confused model can't spin forever.
    const maxRounds = 6;
    for (var round = 0; round < maxRounds; round++) {
      final body = {
        'systemInstruction': {
          'parts': [
            {'text': _querySystemPrompt()}
          ]
        },
        'contents': contents,
        'tools': [
          {'function_declarations': _toolDeclarations}
        ],
        'generationConfig': {
          'temperature': 0,
          'maxOutputTokens': 4096,
          // Dynamic thinking: with thinking fully off, flash-lite returns an
          // EMPTY response (finishReason STOP, no parts) on function-response
          // continuation turns. Thoughts count against maxOutputTokens.
          'thinkingConfig': {'thinkingBudget': -1},
        },
      };

      final response = await _postWithRetry(body);
      final candidate = (response['candidates'] as List?)?.isNotEmpty == true
          ? response['candidates'][0] as Map<String, dynamic>
          : null;
      final parts =
          (candidate?['content']?['parts'] as List<dynamic>? ?? const []);

      // Collect this turn's function calls. Thought parts are never echoed
      // back; every other part is echoed verbatim so any thoughtSignature on
      // a functionCall survives into the next request (required for
      // multi-turn function calling with 2.5 models).
      final echoParts = <Map<String, dynamic>>[];
      final calls = <Map<String, dynamic>>[];
      var plainText = '';
      for (final p in parts.whereType<Map<String, dynamic>>()) {
        if (p['thought'] == true) continue;
        echoParts.add(p);
        final call = p['functionCall'] as Map<String, dynamic>?;
        if (call != null) {
          calls.add(call);
        } else {
          plainText += _str(p['text']);
        }
      }

      // No tool calls → the model answered in prose. Accept a JSON component
      // if it emitted one, else fall back to a text component.
      if (calls.isEmpty) {
        if (plainText.trim().isEmpty) {
          debugPrint('[Ask] round $round: no calls and no text '
              '(finishReason: ${_finishReason(response)})');
          throw Exception('empty_response');
        }
        return AskReply.components([_componentFromText(plainText)]);
      }

      // Echo the model's parts back so the transcript stays valid.
      contents.add({'role': 'model', 'parts': echoParts});

      final responses = <Map<String, dynamic>>[];
      for (final call in calls) {
        final name = _str(call['name']);
        final args = (call['args'] as Map<String, dynamic>? ?? const {});

        if (name == 'render_answer') {
          final comps = _componentsFromAnswer(args);
          if (comps.isEmpty) throw Exception('empty_response');
          return AskReply.components(comps);
        }
        if (name == 'record_expense') {
          final action =
              AskExpenseAction.fromJson({...args, 'is_expense': true});
          if (action.amount <= 0) {
            return AskReply.components([
              AskComponent(
                type: AskComponentType.text,
                body:
                    'How much was it? Tell me the amount and I\'ll record it.',
              )
            ]);
          }
          return AskReply.action(action);
        }

        Object? result;
        try {
          result = await executor(name, args);
        } catch (e, st) {
          debugPrint('[Ask] tool $name failed: $e\n$st');
          result = {'error': 'tool_failed'};
        }
        responses.add({
          'functionResponse': {
            'name': name,
            'response': {'result': result},
          }
        });
      }
      contents.add({'role': 'user', 'parts': responses});
    }

    throw Exception('too_many_tool_rounds');
  }

  /// Parse a prose answer: try JSON, else wrap as a text component.
  static AskComponent _componentFromText(String raw) {
    final t = raw.trim();
    if (t.startsWith('{') && t.endsWith('}')) {
      try {
        return AskComponent.fromJson(
            jsonDecode(t) as Map<String, dynamic>);
      } catch (_) {}
    }
    return AskComponent(type: AskComponentType.text, body: raw.trim());
  }

  /// Parse the render_answer payload: prefer the components array, fall back
  /// to a single top-level component (older shape). Drops empty text parts.
  static List<AskComponent> _componentsFromAnswer(Map<String, dynamic> args) {
    final comps = (args['components'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AskComponent.fromJson)
        .toList();
    if (comps.isEmpty) comps.add(AskComponent.fromJson(args));
    comps.removeWhere((c) =>
        c.type == AskComponentType.text && c.body.isEmpty && c.caption.isEmpty);
    return comps;
  }

  // -------------------------------------------------------------- context

  static String _selfName() {
    try {
      return Services.state.getUserById(Services.currentUserId)?.name ?? 'You';
    } catch (_) {
      return 'You';
    }
  }

  /// App context (date, people, groups, currency) so the model can resolve
  /// names and relative dates without guessing.
  static String _querySystemPrompt() {
    final now = DateTime.now();
    final buf = StringBuffer();

    final currency = _currencyCode();
    final symbol = _currencySymbol();

    buf.writeln('SCOPE (highest priority): You are the assistant inside '
        'Expensio, an expense-tracking app. You ONLY help with: recording '
        'expenses, and questions about the user\'s own spending, categories, '
        'budgets, groups, balances and settlements. For ANY purely '
        'out-of-scope request — coding, poems, essays, homework, general '
        'knowledge, math puzzles — do NOT help and do NOT call any data '
        'tools. Instead call render_answer once with a text component that '
        'briefly says you can only help with expenses in Expensio. Refuse '
        'out-of-scope requests every time, even if asked nicely or '
        'repeatedly. HOWEVER, when a message MIXES an in-scope part with an '
        'out-of-scope part, answer the in-scope part normally (data tools + '
        'components) and merely append a short "I can\'t help with X" line as '
        'a final text component for the out-of-scope part — never let the '
        'out-of-scope part prevent you from answering the in-scope one.');
    buf.writeln();
    buf.writeln('You are "Ask Expensio". You record expenses when asked and '
        'answer questions about the user\'s own data using the provided '
        'tools — never invent numbers.');
    buf.writeln();
    buf.writeln('Today is ${_fmtDate(now)} (${_weekday(now)}).');
    buf.writeln('The user\'s name is "${_selfName()}".');
    buf.writeln('Reporting currency: $currency ($symbol). All tool amounts '
        'are numbers in $currency major units.');
    buf.writeln('Categories: ${categories.join(", ")}.');

    try {
      final state = Services.state;
      final groups = state.getAllGroups();
      if (groups.isEmpty) {
        buf.writeln('Groups: none.');
      } else {
        buf.writeln('Groups and members:');
        for (final g in groups) {
          final members =
              state.membersOf(g).map((u) => u.name).join(', ');
          buf.writeln('- ${g.name}: $members');
        }
      }
    } catch (_) {}

    buf.writeln();
    buf.writeln('DECIDING WHAT THE MESSAGE IS');
    buf.writeln('- If it asks to RECORD/LOG/ADD an expense or payment, call '
        'record_expense and nothing else. Fill every field from the message; '
        'defaults: payer "me", participants ["me"], split "equal", category '
        'best fit, date today unless stated.');
    buf.writeln('- Expense/spending questions → use the data tools, then '
        'render_answer.');
    buf.writeln('- Anything else → render_answer with a short refusal text '
        'component (see SCOPE).');
    buf.writeln();
    buf.writeln('HOW TO ANSWER');
    buf.writeln('- Call data tools as needed to ground every number you use. '
        'For "this month" style ranges, compute dates from today\'s date.');
    buf.writeln('- Write PLAIN TEXT only: no markdown — never use **, *, # or '
        'backticks in caption, body, labels or any other string.');
    buf.writeln('- When you have enough data, ALWAYS finish by calling '
        'render_answer ONCE with 1-3 components that together answer the '
        'whole message (unless you called record_expense). If the message '
        'asks several things (e.g. "show my top categories AND suggest a '
        'budget"), return one component per part in reading order — e.g. a '
        'donut or bar_chart with the numbers, then a text component with the '
        'advice:');
    buf.writeln('  • stat_tile — 1-4 big labelled numbers (value strings may '
        'include the $symbol symbol).');
    buf.writeln('  • bar_chart — comparing values across labels (e.g. this '
        'month vs last). Numeric values only.');
    buf.writeln('  • donut — a breakdown into parts (e.g. by category). '
        'Numeric slice values.');
    buf.writeln('  • transaction_list — matching transactions.');
    buf.writeln('  • settle_up_card — who should pay whom to clear debts.');
    buf.writeln('  • text — short prose when nothing else fits.');
    buf.writeln('- caption: one short line summarising the answer.');
    buf.writeln('- Format money with the $symbol symbol, no decimals when '
        'whole (e.g. "$symbol 1,240"). Use commas for thousands.');
    buf.writeln('- Keep it tight: at most 4 stats / 6 bars / 6 slices / 8 '
        'transactions.');
    return buf.toString();
  }

  // ---------------------------------------------------------------- tools

  static List<Map<String, dynamic>> get _toolDeclarations {
    final currency = _currencyCode();
    final symbol = _currencySymbol();
    return [
        {
          'name': 'list_transactions',
          'description':
              "List the user's expenses, newest first. All filters are "
                  'optional — omit what the question does not need.',
          'parameters': {
            'type': 'object',
            'properties': {
              'category': {
                'type': 'string',
                'description': 'Exact category name from the category list.',
              },
              'group_name': {
                'type': 'string',
                'description': 'Group name (or "personal" for personal '
                    'expenses).',
              },
              'start_date': {
                'type': 'string',
                'description': 'Inclusive range start, YYYY-MM-DD.',
              },
              'end_date': {
                'type': 'string',
                'description': 'Inclusive range end, YYYY-MM-DD.',
              },
              'limit': {
                'type': 'integer',
                'description': 'Max rows to return (default 10, max 30).',
              },
            },
          },
        },
        {
          'name': 'get_spending_summary',
          'description':
              'Aggregate spending over a date range: grand total, count, '
                  'per-category totals, and the largest expenses.',
          'parameters': {
            'type': 'object',
            'properties': {
              'start_date': {
                'type': 'string',
                'description': 'Inclusive range start, YYYY-MM-DD.',
              },
              'end_date': {
                'type': 'string',
                'description': 'Inclusive range end, YYYY-MM-DD.',
              },
              'group_name': {
                'type': 'string',
                'description': 'Restrict to one group (or "personal").',
              },
            },
          },
        },
        {
          'name': 'get_group_balances',
          'description':
              'Net balance per member of a group (+ve = they are owed money, '
                  '-ve = they owe), after recorded payments. Omit group_name '
                  'for all groups.',
          'parameters': {
            'type': 'object',
            'properties': {
              'group_name': {
                'type': 'string',
                'description': 'A group name. Omit for all groups.',
              },
            },
          },
        },
        {
          'name': 'get_pending_settlements',
          'description':
              'The minimal set of payments that would clear all debts '
                  '(optionally for one group). Omit group_name for all groups.',
          'parameters': {
            'type': 'object',
            'properties': {
              'group_name': {
                'type': 'string',
                'description': 'A group name. Omit for all groups.',
              },
            },
          },
        },
        {
          'name': 'record_expense',
          'description':
              'Record an expense or payment when the user asks to log/add/'
                  'record one. Never call this for questions about their '
                  'data, summaries, or chat.',
          'parameters': {
            'type': 'object',
            'properties': {
              'title': {
                'type': 'string',
                'description': '1-4 words describing the expense, e.g. '
                    '"Dinner", "Petrol".',
              },
              'amount': {
                'type': 'number',
                'description': 'Total as a plain number in the user\'s '
                    'currency. "1,240", "₹1240" and "1240 rupees" all become '
                    '1240.',
              },
              'category': {
                'type': 'string',
                'enum': categories,
                'description': 'Best fit from the allowed values ("dinner" → '
                    '"Food & Drink", "uber" → "Transport").',
              },
              'payer': {
                'type': 'string',
                'description': '"me" unless another named person paid. "me" '
                    'when unspecified.',
              },
              'participants': {
                'type': 'array',
                'items': {'type': 'string'},
                'description': 'Everyone sharing it, INCLUDING the payer. '
                    '["me"] for a solo expense. Use "me" for the user.',
              },
              'split': {
                'type': 'string',
                'enum': ['equal', 'custom'],
                'description': '"custom" only when exact per-person amounts '
                    'are given (put them in custom_amounts). Percentages: '
                    'convert to amounts of the total when possible.',
              },
              'custom_amounts': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'name': {'type': 'string'},
                    'amount': {'type': 'number'},
                  },
                  'required': ['name', 'amount'],
                },
                'description': 'Per-person amounts when split is custom.',
              },
              'date': {
                'type': 'string',
                'description':
                    'Expense date as YYYY-MM-DD. Only when the message '
                        'states one.',
              },
              'group_name': {
                'type': 'string',
                'description': 'Only a group the user explicitly named. Empty '
                    'when none was mentioned.',
              },
              'note': {
                'type': 'string',
                'description': 'Anything ambiguous worth surfacing to the '
                    'user. Empty when everything is clear.',
              },
            },
            'required': ['title', 'amount', 'category', 'payer',
              'participants', 'split'],
          },
        },
        {
          'name': 'render_answer',
          'description':
              'Return the final answer as one or more UI components. Always '
                  'finish your response with this call.',
          'parameters': {
            'type': 'object',
            'properties': {
              'components': {
                'type': 'array',
                'description': '1-3 components in reading order that together '
                    'answer the whole message. Use several when the message '
                    'has several parts (e.g. a chart of the data plus a text '
                    'component with the advice).',
                'items': {
                  'type': 'object',
                  'properties': {
                    'component': {
                      'type': 'string',
                      'enum': [
                        'stat_tile',
                        'bar_chart',
                        'donut',
                        'transaction_list',
                        'settle_up_card',
                        'text',
                      ],
                    },
                    'caption': {
                      'type': 'string',
                      'description': 'One short headline line.',
                    },
                    'stats': {
                      'type': 'array',
                      'items': {
                        'type': 'object',
                        'properties': {
                          'label': {'type': 'string'},
                          'value': {
                            'type': 'string',
                            'description':
                                'Display-ready value, e.g. "$symbol 1,240".',
                          },
                          'sublabel': {'type': 'string'},
                        },
                        'required': ['label', 'value'],
                      },
                    },
                    'bars': {
                      'type': 'array',
                      'items': {
                        'type': 'object',
                        'properties': {
                          'label': {'type': 'string'},
                          'value': {
                            'type': 'number',
                            'description': 'Numeric amount in $currency.',
                          },
                        },
                        'required': ['label', 'value'],
                      },
                    },
                    'slices': {
                      'type': 'array',
                      'items': {
                        'type': 'object',
                        'properties': {
                          'label': {'type': 'string'},
                          'value': {
                            'type': 'number',
                            'description': 'Numeric amount in $currency.',
                          },
                        },
                        'required': ['label', 'value'],
                      },
                    },
                    'transactions': {
                      'type': 'array',
                      'items': {
                        'type': 'object',
                        'properties': {
                          'title': {'type': 'string'},
                          'date': {
                            'type': 'string',
                            'description': 'e.g. "3 Sep".',
                          },
                          'amount': {
                            'type': 'string',
                            'description': 'Display-ready, e.g. "$symbol 240".',
                          },
                          'sublabel': {
                            'type': 'string',
                            'description':
                                'e.g. "Food & Drink · paid by You".',
                          },
                        },
                        'required': ['title', 'amount'],
                      },
                    },
                    'transfers': {
                      'type': 'array',
                      'items': {
                        'type': 'object',
                        'properties': {
                          'from': {'type': 'string'},
                          'to': {'type': 'string'},
                          'amount': {
                            'type': 'string',
                            'description': 'Display-ready, e.g. "$symbol 620".',
                          },
                        },
                        'required': ['from', 'to', 'amount'],
                      },
                    },
                    'body': {
                      'type': 'string',
                      'description': 'Prose for the text component.',
                    },
                  },
                  'required': ['component'],
                },
              },
            },
            'required': ['components'],
          },
        },
      ];
  }

  // ------------------------------------------------------------- plumbing

  static String _currencyCode() {
    try {
      return AppSettings.currencyCode;
    } catch (_) {
      return 'INR';
    }
  }

  static String _currencySymbol() {
    try {
      return AppSettings.currencySymbol;
    } catch (_) {
      return 'Rs';
    }
  }

  static String _str(dynamic v) => (v ?? '').toString();

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _weekday(DateTime d) => const [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
        'Sunday'
      ][d.weekday - 1];

  /// POST with exponential backoff on 429 / truncated responses (mirrors the
  /// bill-scan service's retry behaviour). Per-day quota exhaustion rotates
  /// to the next model in the chain instead of failing.
  static Future<Map<String, dynamic>> _postWithRetry(
    Map<String, dynamic> requestBody, {
    int maxAttempts = 3,
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final response = await http.post(
        Uri.parse('${_baseUrlFor(_model)}?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final candidate = (body['candidates'] as List?)?.isNotEmpty == true
            ? body['candidates'][0] as Map<String, dynamic>
            : null;
        final finishReason = candidate?['finishReason']?.toString();

        if ((finishReason == 'MAX_TOKENS' ||
                finishReason == 'MALFORMED_RESPONSE') &&
            attempt < maxAttempts) {
          debugPrint('[Ask] $finishReason on attempt $attempt — retrying');
          await _backoff(attempt);
          continue;
        }
        if (finishReason == 'MAX_TOKENS') {
          debugPrint('[Ask] response still $finishReason after '
              '$maxAttempts attempts');
        }
        return body;
      }

      debugPrint('[Ask] HTTP ${response.statusCode} body=${response.body}');
      if (response.statusCode == 429) {
        // A per-DAY cap can't heal by waiting — but each model has its own
        // bucket, so rotate to the next model in the chain. Per-minute blips
        // self-heal by waiting out the server's RetryInfo hint.
        if (_isDailyQuota(response.body) &&
            _modelIndex < _models.length - 1) {
          _modelIndex++;
          debugPrint('[Ask] daily quota exhausted — switching to $_model');
          attempt--; // a model switch doesn't count as a failed attempt
          continue;
        }
        final daily = _isDailyQuota(response.body);
        final hint = _retryDelaySeconds(response.body);
        if (!daily && attempt < maxAttempts) {
          if (hint != null && hint <= 60) {
            debugPrint('[Ask] 429 — waiting ${hint + 1}s (server hint)');
            await Future.delayed(Duration(seconds: hint + 1));
          } else {
            await _backoff(attempt);
          }
          continue;
        }
        throw Exception('quota_exceeded');
      }
      if (response.statusCode == 400) throw Exception('bad_request');
      if (response.statusCode == 403) throw Exception('auth_error');
      if (response.statusCode == 404) throw Exception('model_not_found');
      if (response.statusCode >= 500 && attempt < maxAttempts) {
        debugPrint('[Ask] HTTP ${response.statusCode} — retrying');
        await _backoff(attempt);
        continue;
      }
      throw Exception('api_error_${response.statusCode}');
    }
    throw Exception('api_failed');
  }

  static Future<void> _backoff(int attempt) async {
    final delayMs = (pow(2, attempt) * 1000).toInt() + Random().nextInt(400);
    await Future.delayed(Duration(milliseconds: delayMs));
  }

  /// Server-suggested wait from a 429's RetryInfo detail ("55s"), or null.
  static int? _retryDelaySeconds(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final details = (json['error']?['details'] as List<dynamic>? ?? const []);
      for (final d in details.whereType<Map<String, dynamic>>()) {
        if (_str(d['@type']).endsWith('RetryInfo')) {
          final m = RegExp(r'(\d+)s').firstMatch(_str(d['retryDelay']));
          if (m != null) return int.parse(m.group(1)!);
        }
      }
    } catch (_) {}
    return null;
  }

  /// True when a 429's QuotaFailure detail names a per-day cap — waiting a
  /// minute won't help, so don't retry.
  static bool _isDailyQuota(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final details = (json['error']?['details'] as List<dynamic>? ?? const []);
      for (final d in details.whereType<Map<String, dynamic>>()) {
        if (!_str(d['@type']).endsWith('QuotaFailure')) continue;
        final violations = (d['violations'] as List<dynamic>? ?? const []);
        for (final v in violations.whereType<Map<String, dynamic>>()) {
          if (_str(v['quotaId']).contains('PerDay')) return true;
        }
      }
    } catch (_) {}
    return false;
  }

  static String _finishReason(Map<String, dynamic> body) {
    final candidate = (body['candidates'] as List?)?.isNotEmpty == true
        ? body['candidates'][0] as Map<String, dynamic>
        : null;
    return _str(candidate?['finishReason']);
  }
}
