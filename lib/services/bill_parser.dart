import '../core/money.dart';
import '../models/ticket.dart';

class ParsedBill {
  const ParsedBill({
    required this.items,
    this.total,
    this.tax = 0,
    this.discount = 0,
    this.rounding = 0,
    this.currency,
    this.merchant,
  });

  final List<TicketItem> items;
  final int? total;

  /// Combined SST/GST/VAT + service charge, in minor units.
  /// (The create-ticket screen has a single "Tax / service charge" field,
  /// so the two are folded together here rather than tracked separately.)
  final int tax;

  /// Total discount found on the receipt, in minor units (positive number).
  final int discount;
  /// Rounding adjustment in minor units. Signed: can be negative (e.g. -2).
  final int rounding;

  final String? currency;
  final String? merchant;
}

/// Heuristic parser that turns raw OCR text into line items, tax and total.
///
/// This is intentionally a best-effort parser, not a full receipt-layout
/// engine: OCR text loses column alignment, so a line like
///   "Signature Big Breakfast      1      32.90  SV-"
/// arrives as a single string with no reliable way to know where the "1"
/// (quantity) column ends and the "32.90" (amount) column begins. The UI
/// always shows a review screen after parsing so the user can fix anything
/// this gets wrong -- treat this as "get most of it right, fast" rather
/// than "parse perfectly".
class BillParser {
  // Name, then an amount (optionally negative, for discounts/rounding),
  // then an optional short trailing tax code such as "SV-1", "SR", "ZR"
  // that Malaysian/Singaporean POS receipts often print after the amount.
  static final _priceAtEnd = RegExp(
    r'^(.*\S)\s+(?:(?:RM|SGD|USD|EUR|GBP|MYR|IDR|THB|AUD|CAD|CNY|HKD|KRW|INR|PHP|VND|\$|€|£|¥)\s*)?(-?\d+(?:[.,]\d{3})*[.,]\d{2})\s*(?:[A-Za-z0-9/]{1,6}(?:\s*[-/]\s*\d{0,2})?)?\s*$',
  );
  static final _qtyPrefix = RegExp(r'^(\d+)\s*[xX]?\s+(.*)$');
  // A lone trailing small integer or "2x", "x2", "(2)", e.g. "Teh Tarik 2"
  static final _qtyTrailing = RegExp(
    r'^(.*\S)\s+(?:[xX]\s*|\(\s*)?(\d{1,2})\s*(?:[xX]|\))?$',
  );
  static final _currencyCode =
      RegExp(r'\b(SGD|USD|EUR|GBP|JPY|MYR|IDR|THB|AUD|CAD|CNY|HKD|KRW|INR|PHP|VND)\b');
  static final _ringgit = RegExp(r'\bRM\b');
  // Bullet prefix on set-menu component lines (e.g. "-Chicken Shabu Set 1 36.90")
  static final _bulletLine = RegExp('^[\u00B7\u2022\u2219\\-]\\s*');

  static const _skip = [
    'subtotal', 'sub total', 'change', 'cash', 'visa', 'mastercard',
    'tendered', 'debit', 'qty', 'pax', 'table', 'cashier', 'document no',
    'card no', 'invoice', 'tax invoice', 'thank you', 'powered by', 'scan this',
  ];
  static const _taxWords = ['tax', 'gst', 'vat', 'sst'];
  static const _serviceWords = ['service charge', 'serv charge', 'svc charge'];
  static const _discountWords = ['discount'];
  static const _roundingWords = ['rounding', 'round adj', 'rnd adj'];
  static const _totalWords = ['total', 'amount due'];

  static ParsedBill parse(String text, {String defaultCurrency = 'USD'}) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final currency = _detectCurrency(text) ?? defaultCurrency;
    final items = <TicketItem>[];
    var tax = 0;
    var discount = 0;
    var rounding = 0;
    int? total;
    String? merchant;

    for (final rawLine in lines) {
      final isBulleted = _bulletLine.hasMatch(rawLine);
      final line = rawLine.replaceFirst(_bulletLine, '').trim();
      if (line.isEmpty) continue;

      final m = _priceAtEnd.firstMatch(line);
      if (m == null) {
        if (!isBulleted) merchant ??= line;
        continue;
      }
      var name = m.group(1)!.trim();
      final amount = Money.parse(m.group(2)!, currency);
      if (amount == null) continue;

      // Strip currency tags from name if left over (e.g. "Teh Tarik 2 RM")
      name = name
          .replaceAll(
            RegExp(r'\s+\b(RM|SGD|USD|EUR|GBP|MYR|IDR|THB|AUD|CAD|CNY|HKD|KRW|INR|PHP|VND|\$|€|£|¥)\b$', caseSensitive: false),
            '',
          )
          .trim();

      // Skip set-menu component lines if they start with a bullet/hyphen and
      // share the same name as a parent item already added.
      if (isBulleted && items.any((i) => i.name.toLowerCase() == name.toLowerCase())) {
        continue;
      }

      final lower = name.toLowerCase();

      if (_discountWords.any(lower.contains)) {
        discount += amount.abs();
        continue;
      }
      if (_roundingWords.any(lower.contains)) {
        final negative = amount < 0 || name.trimRight().endsWith('-');
        rounding += negative ? -amount.abs() : amount.abs();
        continue;
      }
      if (_skip.any(lower.contains)) continue;
      if (_totalWords.any(lower.contains)) {
        total = amount;
        continue;
      }
      if (_serviceWords.any(lower.contains)) {
        tax += amount;
        continue;
      }
      if (_taxWords.any(lower.contains)) {
        tax += amount;
        continue;
      }

      var qty = 1;
      final q = _qtyPrefix.firstMatch(name);
      if (q != null) {
        qty = int.parse(q.group(1)!);
        name = q.group(2)!.trim();
      } else {
        final qt = _qtyTrailing.firstMatch(name);
        if (qt != null) {
          final maybeQty = int.tryParse(qt.group(2)!);
          if (maybeQty != null && maybeQty > 0 && maybeQty < 100) {
            name = qt.group(1)!.trim();
            qty = maybeQty;
          }
        }
      }

      final unit = (qty > 1 && amount % qty == 0) ? amount ~/ qty : amount;
      final quantity = (qty > 1 && amount % qty == 0) ? qty : 1;
      if (name.isEmpty) continue;
      items.add(TicketItem(name: name, amount: unit, quantity: quantity));
    }

    return ParsedBill(
      items: items,
      total: total,
      tax: tax,
      discount: discount,
      rounding: rounding,
      currency: currency,
      merchant: merchant,
    );
  }

  static String? _detectCurrency(String text) {
    final code = _currencyCode.firstMatch(text)?.group(1);
    if (code != null) return code;
    if (_ringgit.hasMatch(text)) return 'MYR';
    if (text.contains('\u20AC')) return 'EUR'; // €
    if (text.contains('\u00A3')) return 'GBP'; // £
    if (text.contains('\u00A5')) return 'JPY'; // ¥
    return null;
  }
}
