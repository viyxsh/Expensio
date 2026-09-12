import '../data/balances.dart';
import '../models/expense_model.dart';
import '../utils/money.dart';
import 'services.dart';
import 'settlement_service.dart';

/// Executes the data tools the "Ask Expensio" query loop can call. Everything
/// reads from the [Services.state] cache — which is a reactive view over the
/// provider-agnostic repository — so the exact same tools answer questions in
/// local Hive mode and cloud Firestore mode.
class AskTools {
  AskTools._();

  static Future<Object?> execute(String name, Map<String, dynamic> args) async {
    switch (name) {
      case 'list_transactions':
        return _listTransactions(args);
      case 'get_spending_summary':
        return _spendingSummary(args);
      case 'get_group_balances':
        return _groupBalances(args);
      case 'get_pending_settlements':
        return _pendingSettlements(args);
      default:
        return {'error': 'unknown_tool'};
    }
  }

  // -------------------------------------------------------------- filters

  static DateTime? _date(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  /// True when the expense's category matches the requested one, tolerating
  /// loose input like "food" for "Food & Drink".
  static bool _categoryMatch(ExpenseModel e, String? raw) {
    final q = (raw ?? '').trim().toLowerCase();
    if (q.isEmpty) return true;
    final c = e.category.toLowerCase();
    return c == q || c.contains(q) || q.contains(c);
  }

  /// True when the expense belongs to a group (or personal ledger) whose name
  /// loosely matches the request.
  static bool _groupMatch(ExpenseModel e, String? raw) {
    final q = (raw ?? '').trim().toLowerCase();
    if (q.isEmpty) return true;
    if (e.isPersonal || q.contains('personal')) return e.isPersonal;
    final group = Services.state.getGroupById(e.groupId);
    return group != null && group.name.toLowerCase().contains(q);
  }

  /// Filter to expenses in an inclusive [start, end] date window.
  static bool _inRange(ExpenseModel e, DateTime? start, DateTime? end) {
    if (start != null && e.createdAt.isBefore(start)) return false;
    if (end != null) {
      // A date-only end (midnight) counts the whole day.
      final endEx = (end.hour == 0 && end.minute == 0 && end.second == 0)
          ? end.add(const Duration(days: 1))
          : end;
      if (!e.createdAt.isBefore(endEx)) return false;
    }
    return true;
  }

  /// Filtered, newest-first list. Names are resolved; amounts are converted
  /// into the reporting currency (major units).
  static List<ExpenseModel> _filtered(Map<String, dynamic> args) {
    final start = _date(args['start_date']);
    final end = _date(args['end_date']);
    final category = (args['category'] ?? '').toString();
    final group = (args['group_name'] ?? '').toString();

    return Services.state
        .getAllExpenses()
        .where((e) => _inRange(e, start, end))
        .where((e) => _categoryMatch(e, category))
        .where((e) => _groupMatch(e, group))
        .toList();
  }

  static String _name(String id) =>
      Services.state.getUserById(id)?.name ?? id;

  static String _groupName(ExpenseModel e) {
    if (e.isPersonal) return 'Personal';
    return Services.state.getGroupById(e.groupId)?.name ?? 'Unknown';
  }

  static Map<String, dynamic> _toJson(ExpenseModel e, String uid) {
    final payer = Services.state.getUserById(e.payerId);
    return {
      'date': _fmtDate(e.createdAt),
      'title': e.title,
      'amount': _major(Money.convert(e.totalAmount, e.currencyCode)),
      'category': e.category,
      'payer': payer?.name ?? 'Unknown',
      'group': _groupName(e),
      'participants': e.participantIds.map(_name).toList(),
      'your_share':
          _major(Money.convert(userShareOf(e, uid), e.currencyCode)),
    };
  }

  // ---------------------------------------------------------------- tools

  static Object _listTransactions(Map<String, dynamic> args) {
    final uid = Services.currentUserId;
    var limit = (args['limit'] as num?)?.toInt() ?? 10;
    if (limit <= 0) limit = 10;
    if (limit > 30) limit = 30;

    return _filtered(args).take(limit).map((e) => _toJson(e, uid)).toList();
  }

  static Object _spendingSummary(Map<String, dynamic> args) {
    final uid = Services.currentUserId;
    final expenses = _filtered(args);

    var total = 0;
    var yourTotal = 0;
    final byCategory = <String, int>{};
    for (final e in expenses) {
      final amt = Money.convert(e.totalAmount, e.currencyCode);
      total += amt;
      yourTotal += Money.convert(userAmountOf(e, uid), e.currencyCode);
      byCategory[e.category] = (byCategory[e.category] ?? 0) + amt;
    }

    final top = expenses.take(5).map((e) {
      final j = _toJson(e, uid);
      return {
        'title': j['title'],
        'date': j['date'],
        'amount': j['amount'],
      };
    }).toList();

    return {
      'total': _major(total),
      'your_total': _major(yourTotal),
      'count': expenses.length,
      'by_category': {
        for (final e in byCategory.entries) e.key: _major(e.value),
      },
      'top_expenses': top,
    };
  }

  static Object _groupBalances(Map<String, dynamic> args) {
    final q = (args['group_name'] ?? '').toString().trim().toLowerCase();
    final groups = Services.state.getAllGroups().where((g) {
      if (q.isEmpty) return true;
      return g.name.toLowerCase().contains(q);
    }).toList();

    final out = <Map<String, dynamic>>[];
    for (final g in groups) {
      final balances = Services.state.computeBalances(g.id);
      for (final entry in balances.entries) {
        if (entry.value == 0) continue;
        out.add({
          'group': g.name,
          'member': _name(entry.key),
          'net': _major(entry.value),
          'position':
              entry.value > 0 ? 'is owed money' : 'owes money',
        });
      }
    }
    return out;
  }

  static Object _pendingSettlements(Map<String, dynamic> args) {
    final q = (args['group_name'] ?? '').toString().trim().toLowerCase();
    final groups = Services.state.getAllGroups().where((g) {
      if (q.isEmpty) return true;
      return g.name.toLowerCase().contains(q);
    }).toList();

    final out = <Map<String, dynamic>>[];
    for (final g in groups) {
      final balances = Services.state.computeBalances(g.id);
      final names = {
        for (final id in balances.keys) id: _name(id),
      };
      for (final s in SettlementService.computeSettlements(balances, names)) {
        out.add({
          'group': g.name,
          'from': s.fromName,
          'to': s.toName,
          'amount': _major(s.amount),
        });
      }
    }
    return out;
  }

  // -------------------------------------------------------------- helpers

  static double _major(int cents) => Money.toMajor(cents);

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
