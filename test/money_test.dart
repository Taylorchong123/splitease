import 'package:flutter_test/flutter_test.dart';
import 'package:splitease/core/money.dart';

void main() {
  group('Money.allocate', () {
    test('splits 100 into three parts that sum to 100', () {
      final parts = Money.splitEqually(100, 3);
      expect(parts, [34, 33, 33]);
      expect(parts.reduce((a, b) => a + b), 100);
    });

    test('respects weights', () {
      final parts = Money.allocate(1000, [1, 3]);
      expect(parts, [250, 750]);
    });

    test('always sums to the total', () {
      for (var total = 0; total < 500; total += 7) {
        for (var n = 1; n <= 9; n++) {
          expect(Money.splitEqually(total, n).reduce((a, b) => a + b), total);
        }
      }
    });
  });

  group('Money.parse / format', () {
    test('parses common formats', () {
      expect(Money.parse('12.50', 'SGD'), 1250);
      expect(Money.parse('12,50', 'EUR'), 1250);
      expect(Money.parse('1,234.56', 'USD'), 123456);
      expect(Money.parse('1.234,56', 'EUR'), 123456);
    });

    test('handles zero-decimal currencies', () {
      expect(Money.parse('1,500', 'JPY'), 1500);
      expect(Money.format(1500, 'JPY'), 'JPY 1,500');
    });

    test('returns null for garbage', () {
      expect(Money.parse('abc', 'USD'), isNull);
    });
  });

  group('Money.convert', () {
    test('converts via USD rates', () {
      final rates = {'USD': 1.0, 'SGD': 1.35, 'JPY': 150.0};
      expect(Money.convert(10000, from: 'USD', to: 'SGD', rates: rates), 13500);
      expect(Money.convert(13500, from: 'SGD', to: 'USD', rates: rates), 10000);
      expect(Money.convert(10000, from: 'USD', to: 'JPY', rates: rates), 15000);
    });
  });
}
