import 'package:flutter_test/flutter_test.dart';
// Helper function that simulates your price calculation logic
int calculateTotal(double price, int quantity, String priceType) {
  const double TAX_RATE = 0.08;
  final int priceInSen = (price * 100).round();
  final int calculationQuantity = (priceType == 'Hourly') ? quantity : 1;
  final int subtotalInSen = priceInSen * calculationQuantity;
  final int taxInSen = (subtotalInSen * TAX_RATE).round();
  return subtotalInSen + taxInSen;
}
void main() {
  group('Booking Price Calculation', () {
    test('UT-01: Correctly calculates total for hourly service', () {
      final total = calculateTotal(50.00, 2, 'Hourly');
      expect(total, 10800); // 50*2 = 100 -> 10000 sen. Tax = 800. Total = 10800.
    });
    test('UT-02: Correctly calculates total for fixed price service', () {
      final total = calculateTotal(150.00, 1, 'Fixed');
      expect(total, 16200); // 150*1 = 150 -> 15000 sen. Tax = 1200. Total = 16200.
    });
    test('Correctly calculates for zero price', () {
      final total = calculateTotal(0.0, 5, 'Hourly');
      expect(total, 0);
    });
  });
}