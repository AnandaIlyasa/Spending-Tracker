class SpendingItem {
  final String id;
  final String category;
  final String amount;
  final DateTime date;
  bool isSynced;

  SpendingItem({
    required this.id,
    required this.category,
    required this.amount,
    required this.date,
    this.isSynced = false,
  });
}