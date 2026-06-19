import 'package:flutter_test/flutter_test.dart';
import 'package:expensio/data/budget.dart';
import 'package:expensio/models/expense_model.dart';

ExpenseModel _e(String category, int total, DateTime when,
        {String payer = 'A', List<String>? participants}) =>
    ExpenseModel(
      id: '$category-$total-${when.toIso8601String()}',
      title: 'x',
      totalAmount: total,
      payerId: payer,
      participantIds: participants ?? const ['A'],
      groupId: 'g1',
      createdAt: when,
      category: category,
    );

void main() {
  final june = DateTime(2026, 6, 15);

  group('BudgetMath.spendByCategory', () {
    test('sums the user amount per category within the month', () {
      final byCat = BudgetMath.spendByCategory([
        _e('Food & Drink', 600, DateTime(2026, 6, 2)),
        _e('Food & Drink', 300, DateTime(2026, 6, 9)),
        _e('Transport', 200, DateTime(2026, 6, 9)),
        _e('Food & Drink', 999, DateTime(2026, 5, 31)), // previous month
      ], 'A', june);
      expect(byCat['Food & Drink'], 900);
      expect(byCat['Transport'], 200);
      expect(BudgetMath.total(byCat), 1100);
    });

    test('uses the share when someone else paid', () {
      // B paid 900 split 3 ways; from A's view only the 300 share counts.
      final byCat = BudgetMath.spendByCategory([
        _e('Food & Drink', 900, june,
            payer: 'B', participants: ['A', 'B', 'C']),
      ], 'A', june);
      expect(byCat['Food & Drink'], 300);
    });
  });

  group('BudgetLine', () {
    BudgetLine line(int limit, int spent, {double elapsed = 0.5}) =>
        BudgetLine(limit: limit, spent: spent, monthElapsed: elapsed);

    test('no limit set', () {
      final l = line(0, 500);
      expect(l.hasLimit, isFalse);
      expect(l.state, BudgetState.none);
      expect(l.fraction, 0);
    });

    test('under budget and on pace is OK', () {
      final l = line(1000, 400, elapsed: 0.5);
      expect(l.state, BudgetState.ok);
      expect(l.remaining, 600);
      expect(l.isOver, isFalse);
    });

    test('near 80% warns', () {
      final l = line(1000, 850, elapsed: 0.9);
      expect(l.isNear, isTrue);
      expect(l.state, BudgetState.warning);
    });

    test('ahead of pace warns even when not near the cap', () {
      // 60% spent only 30% through the month.
      final l = line(1000, 600, elapsed: 0.3);
      expect(l.aheadOfPace, isTrue);
      expect(l.state, BudgetState.warning);
    });

    test('over budget', () {
      final l = line(1000, 1200, elapsed: 0.5);
      expect(l.isOver, isTrue);
      expect(l.state, BudgetState.over);
      expect(l.remaining, -200);
      expect(l.fraction, 1.2);
    });
  });
}
