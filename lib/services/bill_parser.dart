import '../core/money.dart';
import '../models/ticket.dart';

class ParsedBill {
  const ParsedBill({
    required this.items,
    this.total,
    this.subtotal,
    this.tax = 0,
    this.serviceCharge = 0,
    this.discount = 0,
    this.rounding = 0,
    this.currency = 'MYR',
    this.country = 'MY',
    this.taxType = 'SST',
    this.taxRate = 6.0,
    this.serviceChargeRate = 10.0,
    this.merchant,
    this.receiptNumber,
    this.transactionDate,
    this.tableNumber,
    this.reconciliationDiscrepancy = 0,
    this.requiresReview = false,
  });

  final List<TicketItem> items;
  final int? total;
  final int? subtotal;

  /// SST/GST/VAT in minor units.
  final int tax;

  /// Service Charge in minor units.
  final int serviceCharge;

  /// Total discount in minor units.
  final int discount;

  /// Rounding adjustment in minor units.
  final int rounding;

  final String currency;
  final String country; // "MY" or "SG"
  final String taxType; // "SST" or "GST"
  final double taxRate;
  final double serviceChargeRate;
  final String? merchant;
  final String? receiptNumber;
  final String? transactionDate;
  final String? tableNumber;

  /// Unexplained difference between printed total vs sum of line items + charges.
  final int reconciliationDiscrepancy;

  /// True if there is a discrepancy or low confidence parsing.
  final bool requiresReview;
}

/// Robust parser for Singapore and Malaysian F&B receipts.
class BillParser {
  static final _priceAtEnd = RegExp(
    r'^(.*\S)\s+(?:(?:RM|SGD|USD|EUR|GBP|MYR|IDR|THB|AUD|CAD|CNY|HKD|KRW|INR|PHP|VND|\$|€|£|¥)\s*)?(-?\d+(?:[.,]\d{3})*[.,]\d{2})\s*(?:[A-Za-z0-9/]{1,6}(?:\s*[-/]\s*\d{0,2})?)?\s*$',
  );
  static final _qtyPrefix = RegExp(r'^(\d+)\s*[xX]?\s+(.*)$');
  static final _qtyTrailing = RegExp(
    r'^(.*\S)\s+(?:[xX]\s*|\(\s*)?(\d{1,2})\s*(?:[xX]|\))?$',
  );
  static final _currencyCode =
      RegExp(r'\b(SGD|USD|EUR|GBP|JPY|MYR|IDR|THB|AUD|CAD|CNY|HKD|KRW|INR|PHP|VND)\b');
  static final _bulletLine = RegExp('^[\u00B7\u2022\u2219\\-]\\s*');

  static const _skip = [
    'subtotal', 'sub total', 'change', 'cash', 'visa', 'mastercard',
    'tendered', 'debit', 'qty', 'pax', 'table', 'cashier', 'document no',
    'card no', 'invoice', 'tax invoice', 'thank you', 'powered by', 'scan this',
  ];
  static const _taxWords = ['tax', 'gst', 'vat', 'sst'];
  static const _serviceWords = ['service charge', 'serv charge', 'svc charge'];
  static const _discountWords = ['discount', 'less'];
  static const _roundingWords = ['rounding', 'round adj', 'rnd adj'];
  static const _totalWords = ['total', 'amount due', 'rounded total'];
  static const _subtotalWords = ['subtotal', 'sub total'];
  static const _voidWords = ['void', 'cancelled', 'complimentary', 'comp'];

  static ParsedBill parse(String text, {String defaultCurrency = 'USD'}) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final countryInfo = _detectCountryAndTax(text, defaultCurrency);
    final items = <TicketItem>[];
    var tax = 0;
    var serviceCharge = 0;
    var discount = 0;
    var rounding = 0;
    int? printedSubtotal;
    int? printedTotal;
    String? merchant;
    String? receiptNumber;
    String? transactionDate;
    String? tableNumber;

    for (final rawLine in lines) {
      // Metadata extractions
      receiptNumber ??= _extractReceiptNumber(rawLine);
      transactionDate ??= _extractDate(rawLine);
      tableNumber ??= _extractTableNumber(rawLine);

      final isBulleted = _bulletLine.hasMatch(rawLine);
      if (isBulleted) continue; // Skip indented set-menu subcomponents
      final line = rawLine.replaceFirst(_bulletLine, '').trim();
      if (line.isEmpty) continue;

      final m = _priceAtEnd.firstMatch(line);
      if (m == null) {
        if (!isBulleted && merchant == null && !line.toLowerCase().contains('table') && !line.toLowerCase().contains('date')) {
          merchant = line;
        }
        continue;
      }
      var name = m.group(1)!.trim();
      final amount = Money.parse(m.group(2)!, countryInfo.currency);
      if (amount == null) continue;

      name = name
          .replaceAll(
            RegExp(r'\s+\b(RM|SGD|USD|EUR|GBP|MYR|IDR|THB|AUD|CAD|CNY|HKD|KRW|INR|PHP|VND|\$|€|£|¥)\b$', caseSensitive: false),
            '',
          )
          .trim();

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
      if (_subtotalWords.any(lower.contains)) {
        printedSubtotal = amount;
        continue;
      }
      if (_totalWords.any(lower.contains)) {
        printedTotal = amount;
        continue;
      }
      if (_serviceWords.any(lower.contains)) {
        serviceCharge += amount;
        continue;
      }
      if (_taxWords.any(lower.contains)) {
        tax += amount;
        continue;
      }
      if (_skip.any(lower.contains)) continue;

      final isVoid = _voidWords.any(lower.contains);

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

      items.add(TicketItem(
        name: name,
        amount: unit,
        quantity: quantity,
        isVoidOrComplimentary: isVoid,
      ));
    }

    // Deterministic arithmetic validation
    final itemsSubtotal = items.fold(0, (sum, i) => sum + i.total);
    final computedTotal = itemsSubtotal + tax + serviceCharge + rounding - discount;

    final discrepancy = (printedTotal != null) ? (printedTotal - computedTotal) : 0;
    final requiresReview = discrepancy != 0 || items.isEmpty;

    return ParsedBill(
      items: items,
      subtotal: printedSubtotal ?? itemsSubtotal,
      total: printedTotal ?? computedTotal,
      tax: tax,
      serviceCharge: serviceCharge,
      discount: discount,
      rounding: rounding,
      currency: countryInfo.currency,
      country: countryInfo.country,
      taxType: countryInfo.taxType,
      taxRate: countryInfo.taxRate,
      serviceChargeRate: countryInfo.serviceChargeRate,
      merchant: merchant,
      receiptNumber: receiptNumber,
      transactionDate: transactionDate,
      tableNumber: tableNumber,
      reconciliationDiscrepancy: discrepancy,
      requiresReview: requiresReview,
    );
  }

  static _CountryInfo _detectCountryAndTax(String text, String defaultCurrency) {
    final lower = text.toLowerCase();
    if (lower.contains('sgd') || lower.contains('singapore') || lower.contains('gst')) {
      return const _CountryInfo(
        country: 'SG',
        currency: 'SGD',
        taxType: 'GST',
        taxRate: 9.0, // Standard Singapore GST rate as of 2026
        serviceChargeRate: 10.0,
      );
    }
    if (lower.contains('rm') || lower.contains('myr') || lower.contains('malaysia') || lower.contains('sst')) {
      return const _CountryInfo(
        country: 'MY',
        currency: 'MYR',
        taxType: 'SST',
        taxRate: 6.0, // Standard Malaysian F&B service tax rate
        serviceChargeRate: 10.0,
      );
    }

    final code = _currencyCode.firstMatch(text)?.group(1);
    if (code == 'SGD') {
      return const _CountryInfo(country: 'SG', currency: 'SGD', taxType: 'GST', taxRate: 9.0, serviceChargeRate: 10.0);
    }
    return const _CountryInfo(country: 'MY', currency: 'MYR', taxType: 'SST', taxRate: 6.0, serviceChargeRate: 10.0);
  }

  static String? _extractReceiptNumber(String line) {
    final m = RegExp(r'\b(?:SC|INV|DOC|INVOICE|REC|BILL)\d*[-:]\s*([A-Za-z0-9-]+)\b', caseSensitive: false).firstMatch(line);
    return m?.group(1);
  }

  static String? _extractDate(String line) {
    final m = RegExp(r'\b(\d{2}/\d{2}/\d{4}|\d{4}-\d{2}-\d{2})\b').firstMatch(line);
    return m?.group(1);
  }

  static String? _extractTableNumber(String line) {
    final m = RegExp(r'\bTable\s*:\s*(\w+)', caseSensitive: false).firstMatch(line);
    return m?.group(1);
  }
}

class _CountryInfo {
  const _CountryInfo({
    required this.country,
    required this.currency,
    required this.taxType,
    required this.taxRate,
    required this.serviceChargeRate,
  });

  final String country;
  final String currency;
  final String taxType;
  final double taxRate;
  final double serviceChargeRate;
}
