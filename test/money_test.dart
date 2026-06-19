import 'package:flutter_test/flutter_test.dart';
import 'package:expensio/utils/money.dart';

void main() {
  group('Money.tryParseToCents', () {
    test('parses plain and decimal values', () {
      expect(Money.tryParseToCents('12'), 1200);
      expect(Money.tryParseToCents('12.50'), 1250);
      expect(Money.tryParseToCents('0'), 0);
      expect(Money.tryParseToCents('0.01'), 1);
    });

    test('trims whitespace and handles negatives', () {
      expect(Money.tryParseToCents('  5.5 '), 550);
      expect(Money.tryParseToCents('-3.25'), -325);
    });

    test('rounds to the nearest cent', () {
      expect(Money.tryParseToCents('12.505'), 1251);
      expect(Money.tryParseToCents('0.004'), 0);
    });

    test('returns null for non-numeric input', () {
      expect(Money.tryParseToCents('abc'), isNull);
      expect(Money.tryParseToCents(''), isNull);
    });
  });

  group('Money.fromMajor / toMajor', () {
    test('fromMajor converts and rounds', () {
      expect(Money.fromMajor(12.5), 1250);
      expect(Money.fromMajor(19.99), 1999);
      expect(Money.fromMajor(0.1), 10);
    });

    test('toMajor is the inverse for whole cents', () {
      expect(Money.toMajor(1250), 12.5);
      expect(Money.toMajor(1), 0.01);
      expect(Money.toMajor(0), 0.0);
    });
  });

  group('Money.format', () {
    test('formats with the requested decimals', () {
      expect(Money.format(123450), '1234.50');
      expect(Money.format(1200), '12.00');
      expect(Money.format(1234, decimals: 0), '12');
    });
  });

  group('Money.splitEqual', () {
    test('splits evenly when divisible', () {
      expect(Money.splitEqual(1000, 4), [250, 250, 250, 250]);
    });

    test('distributes the remainder to the first parts', () {
      expect(Money.splitEqual(1000, 3), [334, 333, 333]);
      expect(Money.splitEqual(101, 3), [34, 34, 33]);
    });

    test('handles edge counts', () {
      expect(Money.splitEqual(10, 0), isEmpty);
      expect(Money.splitEqual(0, 3), [0, 0, 0]);
    });

    test('always sums exactly to the total and differs by at most one cent', () {
      for (final total in [1, 7, 100, 999, 12345]) {
        for (final n in [1, 2, 3, 4, 7]) {
          final parts = Money.splitEqual(total, n);
          expect(parts.length, n);
          expect(parts.fold<int>(0, (s, p) => s + p), total,
              reason: 'split($total, $n) must sum to total');
          expect(parts.reduce((a, b) => a > b ? a : b) -
              parts.reduce((a, b) => a < b ? a : b),
              lessThanOrEqualTo(1));
        }
      }
    });
  });
}
