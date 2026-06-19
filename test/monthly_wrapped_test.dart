import 'package:flutter_test/flutter_test.dart';
import 'package:expensio/models/expense_model.dart';
import 'package:expensio/screens/monthly_unwrapped.dart';

ExpenseModel _e(String category, int total, DateTime when, {String title = 'x'}) =>
    ExpenseModel(
      id: '$category-$total-${when.toIso8601String()}',
      title: title,
      totalAmount: total,
      payerId: 'A',
      participantIds: const ['A'],
      groupId: 'g1',
      createdAt: when,
      category: category,
    );

void main() {
  group('MonthlyWrapped.forMonth', () {
    final june = DateTime(2026, 6, 15);

    test('is empty when nothing falls in the month', () {
      final w = MonthlyWrapped.forMonth(
          [_e('Food & Drink', 500, DateTime(2026, 5, 30))], june, 'A');
      expect(w.isEmpty, isTrue);
      expect(w.count, 0);
    });

    test('aggregates totals, count, and top category for the month', () {
      final w = MonthlyWrapped.forMonth([
        _e('Food & Drink', 600, DateTime(2026, 6, 2)),
        _e('Food & Drink', 300, DateTime(2026, 6, 10)),
        _e('Transport', 100, DateTime(2026, 6, 12)),
        _e('Entertainment', 200, DateTime(2026, 5, 1)), // previous month
      ], june, 'A');

      expect(w.count, 3);
      expect(w.totalCents, 1000);
      expect(w.topCategory, 'Food & Drink');
      expect(w.topCategoryCents, 900);
      expect(w.topCategoryPct, 90.0);
    });

    test('excludes the very first day of the next month', () {
      final w = MonthlyWrapped.forMonth(
          [_e('Health', 500, DateTime(2026, 7, 1))], june, 'A');
      expect(w.isEmpty, isTrue);
    });

    test('identifies the biggest single expense', () {
      final w = MonthlyWrapped.forMonth([
        _e('Food & Drink', 300, DateTime(2026, 6, 2)),
        _e('Electronics', 5000, DateTime(2026, 6, 4), title: 'Headphones'),
        _e('Transport', 100, DateTime(2026, 6, 6)),
      ], june, 'A');
      expect(w.biggest?.title, 'Headphones');
      expect(w.biggest?.totalAmount, 5000);
    });
  });

  group('personaFor', () {
    test('maps known categories and falls back for unknown ones', () {
      expect(personaFor('Food & Drink').title, 'Certified Foodie');
      expect(personaFor('Transport').emoji, '🚗');
      expect(personaFor('Something Else').title, 'A Bit of Everything');
    });
  });
}
