import 'package:flutter_test/flutter_test.dart';
import 'package:expensio/data/balances.dart';
import 'package:expensio/models/expense_model.dart';
import 'package:expensio/models/settlement_model.dart';

ExpenseModel _expense({
  required String payerId,
  required List<String> participants,
  required int total,
  Map<String, int>? splitMap,
  bool isPersonal = false,
}) =>
    ExpenseModel(
      id: 'e-${participants.join()}-$total',
      title: 'test',
      totalAmount: total,
      payerId: payerId,
      participantIds: participants,
      groupId: 'g1',
      createdAt: DateTime(2026, 1, 1),
      isPersonal: isPersonal,
      splitMap: splitMap,
    );

SettlementModel _settle(String from, String to, int cents) => SettlementModel(
      id: 's-$from-$to',
      groupId: 'g1',
      fromId: from,
      toId: to,
      amountCents: cents,
      createdAt: DateTime(2026, 1, 2),
    );

/// Net balances must always net to zero across all members.
void _expectZeroSum(Map<String, int> balances) {
  expect(balances.values.fold<int>(0, (s, v) => s + v), 0);
}

void main() {
  group('computeBalancesFrom', () {
    test('empty input yields no balances', () {
      expect(computeBalancesFrom([], []), isEmpty);
    });

    test('equal split credits the payer and debits the others', () {
      final b = computeBalancesFrom(
        [_expense(payerId: 'A', participants: ['A', 'B', 'C'], total: 900)],
        [],
      );
      expect(b['A'], 600);
      expect(b['B'], -300);
      expect(b['C'], -300);
      _expectZeroSum(b);
    });

    test('uneven equal split distributes remainder cents', () {
      final b = computeBalancesFrom(
        [_expense(payerId: 'A', participants: ['A', 'B', 'C'], total: 1000)],
        [],
      );
      // shares [334, 333, 333]; payer keeps own share, collects the other two.
      expect(b['A'], 666);
      expect(b['B'], -333);
      expect(b['C'], -333);
      _expectZeroSum(b);
    });

    test('explicit split map overrides equal split', () {
      final b = computeBalancesFrom(
        [
          _expense(
            payerId: 'A',
            participants: ['A', 'B', 'C'],
            total: 1000,
            splitMap: {'A': 200, 'B': 300, 'C': 500},
          )
        ],
        [],
      );
      expect(b['A'], 800);
      expect(b['B'], -300);
      expect(b['C'], -500);
      _expectZeroSum(b);
    });

    test('personal expenses are ignored', () {
      final b = computeBalancesFrom(
        [
          _expense(
              payerId: 'A',
              participants: ['A'],
              total: 500,
              isPersonal: true)
        ],
        [],
      );
      expect(b, isEmpty);
    });

    test('settlements move both parties toward zero', () {
      final b = computeBalancesFrom(
        [_expense(payerId: 'A', participants: ['A', 'B', 'C'], total: 900)],
        [_settle('B', 'A', 300)],
      );
      // B paid back its full 300; A is still owed 300 by C.
      expect(b['A'], 300);
      expect(b['B'], 0);
      expect(b['C'], -300);
      _expectZeroSum(b);
    });

    test('multiple expenses accumulate', () {
      final b = computeBalancesFrom(
        [
          _expense(payerId: 'A', participants: ['A', 'B'], total: 100),
          _expense(payerId: 'B', participants: ['A', 'B'], total: 100),
        ],
        [],
      );
      // Each fronted 100 split two ways; they cancel out.
      expect(b['A'], 0);
      expect(b['B'], 0);
      _expectZeroSum(b);
    });
  });
}
