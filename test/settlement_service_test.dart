import 'package:flutter_test/flutter_test.dart';
import 'package:expensio/services/settlement_service.dart';

/// Apply the computed settlements back onto the balances; everyone should
/// land on exactly zero if the settlements truly clear the debts.
void _expectClears(Map<String, int> balances, List<Settlement> settlements) {
  final residual = Map<String, int>.from(balances);
  for (final s in settlements) {
    residual[s.fromId] = (residual[s.fromId] ?? 0) + s.amount;
    residual[s.toId] = (residual[s.toId] ?? 0) - s.amount;
  }
  for (final entry in residual.entries) {
    expect(entry.value, 0, reason: '${entry.key} should be settled to zero');
  }
}

void main() {
  group('SettlementService.computeSettlements', () {
    test('returns nothing when there is nothing to settle', () {
      expect(SettlementService.computeSettlements({}, {}), isEmpty);
      expect(
          SettlementService.computeSettlements({'A': 0, 'B': 0}, {}), isEmpty);
    });

    test('produces a single transfer for a two-person debt', () {
      final s = SettlementService.computeSettlements(
          {'A': 300, 'B': -300}, {'A': 'Ann', 'B': 'Bob'});
      expect(s.length, 1);
      expect(s.first.fromId, 'B');
      expect(s.first.toId, 'A');
      expect(s.first.amount, 300);
      expect(s.first.fromName, 'Bob');
      expect(s.first.toName, 'Ann');
    });

    test('falls back to the id when no name is supplied', () {
      final s = SettlementService.computeSettlements({'A': 100, 'B': -100}, {});
      expect(s.first.fromName, 'B');
      expect(s.first.toName, 'A');
    });

    test('clears a multi-debtor group within n-1 transfers', () {
      final balances = {'A': 1000, 'B': -400, 'C': -600};
      final s =
          SettlementService.computeSettlements(balances, const {});
      expect(s.length, lessThanOrEqualTo(balances.length - 1));
      _expectClears(balances, s);
    });

    test('every transfer is a positive amount', () {
      final balances = {'A': 500, 'B': 500, 'C': -500, 'D': -500};
      final s = SettlementService.computeSettlements(balances, const {});
      expect(s.every((x) => x.amount > 0), isTrue);
      _expectClears(balances, s);
    });

    test('finds the optimal (fewer than greedy) solution for small groups', () {
      // Greedy yields 4 transfers here; the optimal grouping needs only 3:
      // D->E (4) clears the +4/-4 pair, then A->C (5) and B->C (2).
      final balances = {'A': -5, 'B': -2, 'C': 7, 'D': -4, 'E': 4};
      final s = SettlementService.computeSettlements(balances, const {});
      expect(s.length, 3);
      _expectClears(balances, s);
    });

    test('handles a larger balanced group correctly', () {
      final balances = {
        'A': 1500,
        'B': -500,
        'C': -250,
        'D': -750,
        'E': 300,
        'F': -300,
      };
      final s = SettlementService.computeSettlements(balances, const {});
      _expectClears(balances, s);
      expect(s.length, lessThanOrEqualTo(balances.length - 1));
    });
  });
}
