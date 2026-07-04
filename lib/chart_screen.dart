import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'models.dart';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class ChartScreen extends StatefulWidget {
  final List<SpendingItem> spendings;

  const ChartScreen({super.key, required this.spendings});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, String>> _chatMessages = []; 
  bool _isAiThinking = false;

  final List<String> _suggestedPrompts = [
    "Analyze my spending behavior",
    "Give me 3 quick savings tips",
    "Show categories with highest spikes",
    "Where can I cut costs?",
  ];

  @override
  void initState() {
    super.initState();
  }

  Future<void> _handleSendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _chatMessages.add({'role': 'user', 'text': text});
      _isAiThinking = true;
    });
    _chatController.clear();

    try {
      final StringBuffer historyContext = StringBuffer();
      historyContext.writeln(
        "You are Gemini Financial Copilot. "
        "CRITICAL: Keep your response extremely concise (under 100 words total). "
        "Do not use introductory phrases or conversational fluff. Get straight to the analysis.\n"
        "Transaction history context:"
      );
      
      for (var item in widget.spendings) {
        historyContext.writeln(
          "- Date: ${item.date.toIso8601String().substring(0, 10)}, Category: ${item.category}, Amount: \$${item.amount}"
        );
      }
      
      historyContext.writeln("\nUser Question: $text");

      final gemini = Gemini.instance;
      final response = await gemini.text(historyContext.toString());

      setState(() {
        _chatMessages.add({
          'role': 'model',
          'text': response?.output ?? "I reviewed your metrics but couldn't formulate a breakdown. Let's try again!"
        });
      });
    } catch (e) {
      setState(() {
        _chatMessages.add({
          'role': 'model',
          'text': "Connection error with financial systems: $e"
        });
      });
    } finally {
      setState(() {
        _isAiThinking = false;
      });
    }
  }

  Widget _buildGeminiAssistantPanel() {
    final systemBottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF161616), 
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(top: BorderSide(color: Colors.white10, width: 1)),
      ),
      padding: EdgeInsets.only(
        top: 12, 
        left: 16, 
        right: 16, 
        bottom: MediaQuery.of(context).viewInsets.bottom > 0 
            ? 190 
            : (systemBottomPadding > 0 ? systemBottomPadding : 12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, 
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Color(0xFF03DAC6), size: 16),
              const SizedBox(width: 8),
              const Text('Gemini Financial Copilot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              if (_isAiThinking)
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF03DAC6))),
            ],
          ),
          
          const Divider(height: 12, color: Colors.white10),
          
          if (_chatMessages.isNotEmpty) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: 0,
                maxHeight: 220,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: _chatMessages.length,
                itemBuilder: (context, index) {
                  final msg = _chatMessages[index];
                  final isUser = msg['role'] == 'user';
                  return Container(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isUser ? const Color(0xFF03DAC6) : const Color(0xFF222222),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: isUser
                          ? Text(
                              msg['text']!,
                              style: const TextStyle(color: Colors.black, fontSize: 13),
                            )
                          : MarkdownBody(
                              data: msg['text']!,
                              styleSheet: MarkdownStyleSheet(
                                p: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                                listBullet: const TextStyle(color: Color(0xFF03DAC6)),
                              ),
                            ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],

          const SizedBox(height: 8),

          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _suggestedPrompts.length,
              itemBuilder: (context, index) {
                final promptText = _suggestedPrompts[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ActionChip(
                    label: Text(
                      promptText,
                      style: const TextStyle(color: Color(0xFF03DAC6), fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                    backgroundColor: const Color(0xFF1E1E1E),
                    side: const BorderSide(color: Colors.white10, width: 1),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    onPressed: _isAiThinking 
                        ? null
                        : () {
                            _chatController.text = promptText;
                            _handleSendMessage();
                          },
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),
          
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  onSubmitted: (_) => _handleSendMessage(), 
                  decoration: InputDecoration(
                    hintText: 'Ask about your spending...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    fillColor: const Color(0xFF222222), 
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.send, color: Color(0xFF03DAC6), size: 20),
                onPressed: _handleSendMessage, 
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFF161616), 
      appBar: AppBar(
        title: const Text('Analytics & Insights'),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildCardWrapper(
                  title: 'Category Breakdown (This Month)',
                  child: _buildDonutChart(), 
                ),
                const SizedBox(height: 16),
                _buildCardWrapper(
                  title: 'Monthly Spending Trajectory',
                  child: SizedBox(
                    height: 220,
                    child: _buildBarChart(), 
                  ),
                ),
              ],
            ),
          ),

          _buildGeminiAssistantPanel(),
        ],
      ),
    );
  }

  Widget _buildCardWrapper({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildDonutChart() {
    final now = DateTime.now();
    
    final thisMonthSpendings = widget.spendings.where((item) {
      return item.date.year == now.year && item.date.month == now.month;
    }).toList();

    if (thisMonthSpendings.isEmpty) {
      return const Center(
        child: Text('No transactions recorded this month.', style: TextStyle(color: Colors.white38)),
      );
    }

    final Map<String, double> categoryMap = {};
    double totalSum = 0;

    for (var item in thisMonthSpendings) {
      final amountVal = double.tryParse(item.amount) ?? 0.0;
      categoryMap[item.category] = (categoryMap[item.category] ?? 0.0) + amountVal;
      totalSum += amountVal;
    }

    final List<Color> palette = [
      const Color(0xFF03DAC6),
      Colors.purpleAccent,
      Colors.orangeAccent,
      Colors.blueAccent,
      Colors.pinkAccent,
      Colors.amberAccent,
    ];

    int colorIndex = 0;
    final List<PieChartSectionData> sections = [];
    final List<Map<String, dynamic>> legendData = [];

    categoryMap.forEach((category, value) {
      final color = palette[colorIndex % palette.length];
      colorIndex++;
      final percentage = (value / totalSum) * 100;

      sections.add(
        PieChartSectionData(
          color: color,
          value: value,
          title: '${percentage.toStringAsFixed(1)}%',
          radius: 22,
          showTitle: true,
          titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black),
        ),
      );

      legendData.add({
        'category': category,
        'color': color,
        'amount': value,
      });
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 3,
                  centerSpaceRadius: 45,
                  sections: sections,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('TOTAL', style: TextStyle(fontSize: 10, color: Colors.white38, fontWeight: FontWeight.bold)),
                  Text(
                    totalSum.toStringAsFixed(0).replaceAllMapped(
                      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},'
                    ),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: legendData.map((data) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: data['color'] as Color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  data['category'].toString(),
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 4),
                Text(
                  '(${(data['amount'] as double).toStringAsFixed(0).replaceAllMapped(
                      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},'
                    )})',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBarChart() {
    final now = DateTime.now();
    final List<BarChartGroupData> barGroups = [];
    double maxMonthlyValue = 100000;

    const int totalMonthsToShow = 12;

    for (int i = totalMonthsToShow - 1; i >= 0; i--) {
      int targetMonthVal = now.month - i;
      int targetYearVal = now.year;
      while (targetMonthVal <= 0) {
        targetMonthVal += 12;
        targetYearVal -= 1;
      }

      double monthlyTotal = 0;
      for (var item in widget.spendings) {
        if (item.date.year == targetYearVal && item.date.month == targetMonthVal) {
          final parsedAmount = double.tryParse(item.amount) ?? 0.0;
          monthlyTotal += parsedAmount;
        }
      }

      if (monthlyTotal > maxMonthlyValue) {
        maxMonthlyValue = monthlyTotal;
      }

      barGroups.add(
        BarChartGroupData(
          x: (totalMonthsToShow - 1) - i,
          showingTooltipIndicators: monthlyTotal > 0 ? [0] : [],
          barRods: [
            BarChartRodData(
              toY: monthlyTotal,
              color: i == 0 ? const Color(0xFF03DAC6) : const Color(0xFF444444),
              width: 16,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: maxMonthlyValue > 0 ? maxMonthlyValue * 1.1 : 100000,
                color: Colors.white10,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        SizedBox(
          width: 45,
          height: 220,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(4, (index) {
              if (index == 3) return const SizedBox(height: 12); 
              final val = (maxMonthlyValue * 1.1) * (3 - index) / 3;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text('${(val / 1000).toStringAsFixed(0)}k', 
                  style: const TextStyle(color: Colors.white24, fontSize: 10)),
              );
            }),
          ),
        ),
        
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true, 
            child: SizedBox(
              width: totalMonthsToShow * 60.0, 
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxMonthlyValue * 1.25, 
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxMonthlyValue > 0 ? (maxMonthlyValue * 1.1) / 3 : 50000,
                    getDrawingHorizontalLine: (value) => const FlLine(
                      color: Colors.white10,
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ),
                  
                  barTouchData: BarTouchData(
                    enabled: false,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => Colors.transparent,
                      tooltipPadding: EdgeInsets.zero,
                      tooltipMargin: 6,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final String formattedVal = rod.toY.toInt().toString().replaceAllMapped(
                          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},'
                        );
                        return BarTooltipItem(
                          formattedVal,
                          TextStyle(
                            color: groupIndex == (totalMonthsToShow - 1) 
                                ? const Color(0xFF03DAC6)
                                : Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ),
                  
                  barGroups: barGroups,
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= totalMonthsToShow) return const SizedBox.shrink();
                          
                          final monthLabels = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                          
                          int targetMonthVal = now.month - ((totalMonthsToShow - 1) - index);
                          while (targetMonthVal <= 0) {
                            targetMonthVal += 12;
                          }
                          
                          final isCurrentMonth = index == (totalMonthsToShow - 1);
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              monthLabels[targetMonthVal - 1],
                              style: TextStyle(
                                color: isCurrentMonth ? const Color(0xFF03DAC6) : Colors.white38,
                                fontSize: 11,
                                fontWeight: isCurrentMonth ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}