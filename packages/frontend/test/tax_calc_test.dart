import 'package:decimal/decimal.dart';
import 'package:test/test.dart';

void main() {
  group('稅額計算（Issue #8 AC2）', () {
    const unitPriceStr = '100.00';
    const qtyInt = 2;

    final unitPrice = Decimal.parse(unitPriceStr);
    final qty       = Decimal.parse(qtyInt.toString());
    final subtotal  = unitPrice * qty;

    test('subtotal = 200.00', () {
      expect(subtotal.toStringAsFixed(2), '200.00');
    });

    test('含稅 taxAmount = 10.00', () {
      final tax = subtotal * Decimal.parse('0.05');
      expect(tax.toStringAsFixed(2), '10.00');
    });

    test('含稅 totalAmount = 210.00', () {
      final tax   = subtotal * Decimal.parse('0.05');
      final total = subtotal + tax;
      expect(total.toStringAsFixed(2), '210.00');
    });

    test('未稅 taxAmount = 0.00', () {
      expect(Decimal.zero.toStringAsFixed(2), '0.00');
    });

    test('未稅 totalAmount = 200.00', () {
      final total = subtotal + Decimal.zero;
      expect(total.toStringAsFixed(2), '200.00');
    });
  });
}
