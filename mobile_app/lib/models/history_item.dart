class HistoryItem {
  final int? id;
  final String customer;
  final String item;
  final String type;
  final String quantity;
  final String unit;
  final String price;
  final String amount;
  final String paidAmount;
  final String profit;
  final String date;
  final String? deletedAt;
  final bool isDebt;
  final bool isPaid;
  final bool isEdited;
  final String deviceSource;
  final String? receiptId;

  HistoryItem({
    this.id,
    required this.customer, 
    required this.item, 
    required this.type, 
    required this.quantity, 
    required this.unit, 
    required this.price, 
    required this.amount, 
    required this.paidAmount,
    required this.profit, 
    required this.date,
    this.deletedAt,
    this.isDebt = false,
    this.isPaid = false,
    this.isEdited = false,
    this.deviceSource = "System",
    this.receiptId,
  });
}
