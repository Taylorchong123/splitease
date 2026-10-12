import 'dart:math' as math;

import 'package:intl/intl.dart';

/// Money helpers. All amounts are integers in **minor units** (e.g. cents),
/// which avoids floating-point rounding errors.
class Money {
  Money._();

  static const _zeroDecimal = {'JPY', 'KRW', 'VND', 'CLP', 'ISK', 'UGX'};
  static const _threeDecimal = {'KWD', 'BHD', 'OMR', 'JOD', 'TND'};

  static int decimals(String currency) {
    final c = currency.toUpperCase();
    if (_zeroDecimal.contains(c)) return 0;
    if (_threeDecimal.contains(c)) return 3;
    return 2;
  }

  /// Normalises "1,234.56", "1.234,56" and "12,50" into a parseable string.
  static String _normalise(String s) {
    s = s.replaceAll(RegExp(r'[^\d.,-]'), '');
    final dot = s.lastIndexOf('.');
    final comma = s.lastIndexOf(',');
    if (dot >= 0 && comma >= 0) {
      return dot > comma
          ? s.replaceAll(',', '')
          : s.replaceAll('.', '').replaceAll(',', '.');
    }
    if (comma >= 0) {
      // "12,50" -> decimal comma; "1,000" -> thousands separator
      return (s.length - comma - 1) <= 2 ? s.replaceAll(',', '.') : s.replaceAll(',', '');
    }
    return s;
  }

  /// Parses user/OCR text to minor units. Returns null if it is not a number.
  static int? parse(String input, String currency) {
    final value = double.tryParse(_normalise(input.trim()));
    if (value == null) return null;
    return (value * math.pow(10, decimals(currency))).round();
  }

  static String format(int minor, String currency) {
    final d = decimals(currency);
    final value = minor / math.pow(10, d);
    final text = NumberFormat.decimalPatternDigits(decimalDigits: d).format(value);
    return '${currency.toUpperCase()} $text';
  }

  /// Splits [total] proportionally to [weights] so the parts always add up to
  /// exactly [total] (largest-remainder method).
  static List<int> allocate(int total, List<int> weights) {
    if (weights.isEmpty) return const [];
    final sum = weights.fold<int>(0, (a, b) => a + b);
    if (sum <= 0) throw ArgumentError('weights must sum to a positive number');

    final parts = [for (final w in weights) (total * w) ~/ sum];
    var remainder = total - parts.fold<int>(0, (a, b) => a + b);

    final order = List<int>.generate(weights.length, (i) => i)
      ..sort((a, b) {
        final ra = (total * weights[a]) % sum;
        final rb = (total * weights[b]) % sum;
        final cmp = rb.compareTo(ra);
        return cmp != 0 ? cmp : a.compareTo(b);
      });

    for (var i = 0; remainder > 0; i++, remainder--) {
      parts[order[i]]++;
    }
    return parts;
  }

  static List<int> splitEqually(int total, int parts) =>
      allocate(total, List.filled(parts, 1));

  /// Converts using [rates] expressed as "units of currency per 1 USD".
  static int convert(
    int minor, {
    required String from,
    required String to,
    required Map<String, double> rates,
  }) {
    if (from == to) return minor;
    final rf = rates[from];
    final rt = rates[to];
    if (rf == null || rt == null) {
      throw StateError('Missing exchange rate for $from or $to');
    }
    final major = minor / math.pow(10, decimals(from));
    final converted = major / rf * rt;
    return (converted * math.pow(10, decimals(to))).round();
  }
}
