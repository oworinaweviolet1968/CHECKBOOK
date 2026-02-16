class StockItem {
  final String supplier;
  final String item;
  final String quantity; // Size (e.g. 50kg)
  final String unit;     // Count (e.g. 10 sacks)
  final String price;    // Unit Price
  final String amount;   // Total Amount

  StockItem({
    required this.supplier, 
    required this.item, 
    required this.quantity, 
    required this.unit, 
    required this.price, 
    required this.amount
  });
}
