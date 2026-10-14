import 'package:flutter_test/flutter_test.dart';
import 'package:splitease/services/bill_parser.dart';

void main() {
  const sample = '''
Sunrise Cafe
Chilli Crab 68.00
2x Fried Rice 36.00
Subtotal 104.00
GST 9% 9.36
Total SGD 113.36
''';

  test('extracts merchant, items, tax, total and currency', () {
    final bill = BillParser.parse(sample);

    expect(bill.merchant, 'Sunrise Cafe');
    expect(bill.currency, 'SGD');
    expect(bill.items.length, 2);
    expect(bill.items[0].name, 'Chilli Crab');
    expect(bill.items[0].amount, 6800);
    expect(bill.items[1].name, 'Fried Rice');
    expect(bill.items[1].quantity, 2);
    expect(bill.items[1].amount, 1800);
    expect(bill.tax, 936);
    expect(bill.total, 11336);
  });

  // Based on a real Malaysian F&B receipt: amounts are followed by an
  // "SV-" SST tax-code suffix, and there's a separate discount line.
  group('receipt with trailing tax-code suffix and a discount', () {
    const receipt = '''
Manzanita Patisserie
Signature Big Breakfast 1 32.90 SV-
Honey Milk 1 8.80 SV-
Cheesy Wedges 1 15.90 SV-
Sub Total (Exclusive Tax) : 149.90
Total Discount : 1.30
SST : 8.99
Service Charge 10% : 14.99
Rounding Adjustment : 0.02
Rounded Total (RM): 173.90
''';

    test('detects RM as MYR and strips the SV- suffix from amounts', () {
      final bill = BillParser.parse(receipt);
      expect(bill.currency, 'MYR');
      expect(bill.items.length, 3);
      expect(bill.items[0].name, 'Signature Big Breakfast');
      expect(bill.items[0].amount, 3290);
    });

    test('separates SST tax and service charge into separate fields', () {
      final bill = BillParser.parse(receipt);
      expect(bill.tax, 899);
      expect(bill.serviceCharge, 1499);
      expect(bill.discount, 130);
    });

    test('uses the final "Rounded Total" line as the grand total', () {
      final bill = BillParser.parse(receipt);
      expect(bill.total, 17390);
    });
  });

  // Based on a real receipt where each set-menu item has its components
  // itemised underneath it (prefixed with a bullet). Those must not be
  // double-counted as separate line items.
  group('receipt with nested set-menu components', () {
    const receipt = '''
Shabu Place
Duck Blood Jelly 1 7.90
Chicken Shabu Set 1 52.70
-Chicken Shabu Set 1 36.90 SV-1
-Arashi Sukiyaki 1 5.90 SV-1
Tai Fish Shabu Set 1 49.80
-Tai Fish Shabu Set 1 39.90 SV-1
Sub Total (Exclusive Tax) : 0.00
Total Discount : 14.74
SST : 24.57
Service Charge 10% : 0.00
Rounded Total (RM): 285.00
''';

    test('only counts the parent set-menu line, not its nested components', () {
      final bill = BillParser.parse(receipt);
      final names = bill.items.map((i) => i.name).toList();
      expect(names, ['Duck Blood Jelly', 'Chicken Shabu Set', 'Tai Fish Shabu Set']);
    });
  });

  group('receipt with multi-quantity items like Teh Tarik 2 7.00 SV-', () {
    const receipt = '''
SAMPLE CAFE
Jalan Contoh 1, Johor Bahru

Document No. : SC1-000123
Table : 5 Pax : 3
Date : 07/10/2026 12:30:00 PM

Description Qty Amount RM
Nasi Lemak Ayam 1 14.90 SV-
Teh Tarik 2 7.00 SV-
Chicken Chop 1 21.90 SV-
Iced Lemon Tea 1 6.50 SV-
Cheesy Fries 1 12.90 SV-

Sub Total (Exclusive Tax) : 63.20
Total Discount : 3.20
SST : 3.60
Service Charge 10% : 6.00
Rounding Adjustment : 0.00
Rounded Total (RM) : 69.60
''';

    test('correctly parses all items including Teh Tarik with qty 2 and unit price', () {
      final bill = BillParser.parse(receipt);
      expect(bill.items.length, 5);
      expect(bill.items[0].name, 'Nasi Lemak Ayam');
      expect(bill.items[0].quantity, 1);
      expect(bill.items[0].amount, 1490);

      expect(bill.items[1].name, 'Teh Tarik');
      expect(bill.items[1].quantity, 2);
      expect(bill.items[1].amount, 350); // 7.00 / 2 = 3.50 unit price

      expect(bill.items[2].name, 'Chicken Chop');
      expect(bill.items[3].name, 'Iced Lemon Tea');
      expect(bill.items[4].name, 'Cheesy Fries');

      expect(bill.discount, 320);
      expect(bill.tax, 360);
      expect(bill.serviceCharge, 600);
      expect(bill.total, 6960);
    });
  });
}

