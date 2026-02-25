class SaleItem {
  final String item;
  final String quantity; // Size (e.g. 50kg)
  final String unit;     // Count/Weight (e.g. 2 1/4 kg)
  final String price;    // Unit Price
  final String amount;   // Total Amount
  final bool isDebt;

  SaleItem({
    required this.item, 
    required this.quantity, 
    required this.unit, 
    required this.price, 
    required this.amount,
    this.isDebt = false,
  });
}
