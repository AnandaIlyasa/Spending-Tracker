import 'package:flutter/material.dart';
import 'models.dart';

class HomeScreen extends StatelessWidget {
  final List<SpendingItem> spendings;
  final List<Map<String, dynamic>> categories;
  final DateTime selectedMonth;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onMonthPickerTap;

  final Function(SpendingItem) onEditItem;
  final Function(SpendingItem) onDeleteItem;
  
  const HomeScreen({
    super.key, 
    required this.spendings,
    required this.categories,
    required this.selectedMonth,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onMonthPickerTap,
    required this.onEditItem,
    required this.onDeleteItem,
  });

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  IconData _getIconForCategory(String categoryName) {
    try {
      final match = categories.firstWhere(
        (cat) => cat['label'].toString().toLowerCase() == categoryName.toLowerCase()
      );
      return IconData(match['iconCode'], fontFamily: 'MaterialIcons');
    } catch (_) {
      return Icons.help_outline; // Fallback icon if category missing
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredSpendings = spendings.where((item) {
      return item.date.month == selectedMonth.month && 
             item.date.year == selectedMonth.year;
    }).toList();

    filteredSpendings.sort((a, b) => b.date.compareTo(a.date));

    int totalSpending = 0;
    for (var item in filteredSpendings) {
      final cleanAmount = item.amount.replaceAll(RegExp(r'[^\d]'), '');
      totalSpending += int.tryParse(cleanAmount) ?? 0;
    }

    String formatNumber(String value) {
      return value.replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), 
        (Match m) => '${m[1]},'
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildDarkBox(
                padding: EdgeInsets.zero,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 20, color: Color(0xFF03DAC6)),
                      onPressed: onPreviousMonth,
                    ),
                    GestureDetector(
                      onTap: onMonthPickerTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: Text(
                          ' ${_months[selectedMonth.month - 1]} ${selectedMonth.year} ',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 20, color: Color(0xFF03DAC6)),
                      onPressed: onNextMonth,
                    ),
                  ],
                ),
              ),
              _buildDarkBox(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Text(
                  'Total Spending: ${formatNumber(totalSpending.toString())}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF03DAC6)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          Expanded(
            child: filteredSpendings.isEmpty
                ? const Center(child: Icon(Icons.receipt_long, size: 64, color: Colors.white10))
                : ListView.builder(
                    itemCount: filteredSpendings.length,
                    itemBuilder: (context, index) {
                      final item = filteredSpendings[index];
                      
                      bool showDateHeader = false;
                      if (index == 0) {
                        showDateHeader = true;
                      } else {
                        final previousItem = filteredSpendings[index - 1];
                        if (previousItem.date.day != item.date.day || 
                            previousItem.date.month != item.date.month || 
                            previousItem.date.year != item.date.year) {
                          showDateHeader = true;
                        }
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showDateHeader) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Expanded(child: Divider(color: Colors.white10, thickness: 1)),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                                  child: Text(
                                    '${item.date.day} ${_months[item.date.month - 1]} ${item.date.year}',
                                    style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                  ),
                                ),
                                const Expanded(child: Divider(color: Colors.white10, thickness: 1)),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],

                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E1E),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(color: Color(0xFF2D2D2D), shape: BoxShape.circle),
                                    child: Icon(_getIconForCategory(item.category), color: const Color(0xFF03DAC6), size: 20),
                                  ),
                                  const SizedBox(width: 14),
                                  
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item.category, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                        if (!item.isSynced)
                                          const Text('Cloud Sync Pending', style: TextStyle(color: Colors.orangeAccent, fontSize: 10)),
                                      ],
                                    ),
                                  ),
                                  
                                  Text(
                                    formatNumber(item.amount),
                                    style: const TextStyle(color: Color(0xFF03DAC6), fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, color: Colors.white38, size: 20),
                                    color: const Color(0xFF2D2D2D),
                                    onSelected: (action) {
                                      if (action == 'edit') onEditItem(item);
                                      if (action == 'delete') onDeleteItem(item);
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(children: [Icon(Icons.edit, size: 16), SizedBox(width: 8), Text('Edit')]),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(children: [Icon(Icons.delete, color: Colors.redAccent, size: 16), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.redAccent))]),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDarkBox({required Widget child, double? width, EdgeInsetsGeometry? padding}) {
    return Container(
      width: width,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: child,
    );
  }
}