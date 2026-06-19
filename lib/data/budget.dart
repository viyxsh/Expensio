import '../models/expense_model.dart';
import 'balances.dart';

/// Pure budget maths, shared by the Budget screen and the home card (and easy
/// to unit-test). "Spend" is the user's own amount per expense (their share, or
/// the full total on expenses they paid), summed over the calendar month.
class BudgetMath {
  BudgetMath._();

  /// The user's spend per category for the calendar month containing [month].
  static Map<String, int> spendByCategory(
      List<ExpenseModel> all, String uid, DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final out = <String, int>{};
    for (final e in all) {
      if (e.createdAt.isBefore(start) || !e.createdAt.isBefore(end)) continue;
      final amt = userAmountOf(e, uid);
      if (amt <= 0) continue;
      out[e.category] = (out[e.category] ?? 0) + amt;
    }
    return out;
  }

  static int total(Map<String, int> byCategory) =>
      byCategory.values.fold(0, (a, b) => a + b);

  /// Fraction (0..1) of the current month that has elapsed, for pacing.
  static double monthElapsed(DateTime now) {
    final days = DateTime(now.year, now.month + 1, 0).day;
    return (now.day / days).clamp(0.0, 1.0);
  }
}

/// How one budget line (overall or a single category) is tracking this month.
class BudgetLine {
  final int limit; // cents; 0 means no budget set
  final int spent; // cents
  final double monthElapsed; // 0..1

  const BudgetLine({
    required this.limit,
    required this.spent,
    required this.monthElapsed,
  });

  bool get hasLimit => limit > 0;
  int get remaining => limit - spent;

  /// Spent / limit, may exceed 1.0 when over budget. 0 when no limit.
  double get fraction => limit <= 0 ? 0 : spent / limit;

  bool get isOver => hasLimit && spent > limit;
  bool get isNear => hasLimit && !isOver && fraction >= 0.8;

  /// True when spending is running ahead of the month's pace (e.g. 60% spent
  /// only 30% through the month) — an early warning before you're over.
  bool get aheadOfPace =>
      hasLimit && !isOver && fraction > monthElapsed + 0.1;

  BudgetState get state {
    if (!hasLimit) return BudgetState.none;
    if (isOver) return BudgetState.over;
    if (isNear || aheadOfPace) return BudgetState.warning;
    return BudgetState.ok;
  }
}

enum BudgetState { none, ok, warning, over }
