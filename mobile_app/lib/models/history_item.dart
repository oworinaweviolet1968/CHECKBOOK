class HistoryItem {
  final String customer;
  final String item;
  final String type;
  final String quantity;
  final String unit;
  final String price;
  final String amount;
  final String profit;
  final String date;

  HistoryItem({
    required this.customer, 
    required this.item, 
    required this.type, 
    required this.quantity, 
    required this.unit, 
    required this.price, 
    required this.amount, 
    required this.profit, 
    required this.date
  });
}
