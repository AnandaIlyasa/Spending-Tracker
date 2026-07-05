import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models.dart';
import 'home_screen.dart';
import 'chart_screen.dart';
import 'google_sheets_service.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logging/logging.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_gemini/flutter_gemini.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Warning: Could not load .env file: $e");
  }

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord record) {
    debugPrint('${record.time} [${record.level.name}] ${record.loggerName}: ${record.message}');
    if (record.error != null) {
      debugPrint('Error Details: ${record.error}');
      debugPrint('Stack Trace:\n${record.stackTrace}');
    }
  });

  await Hive.initFlutter();
  await Hive.openBox('spendings_box');
  
  final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
  if (apiKey.isNotEmpty) {
    Gemini.init(apiKey: apiKey);
  }

  runApp(const SpendingTrackerApp());
}

class SpendingTrackerApp extends StatelessWidget {
  const SpendingTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spending Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: const Color(0xFF03DAC6),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  static final Logger _log = Logger('MainNavigationScreen');

  int _currentTabIndex = 0;
  final _myBox = Hive.box('spendings_box');

  final GoogleSheetsService _sheetsService = GoogleSheetsService();
  
  List<SpendingItem> _dynamicSpendings = [];
  List<Map<String, dynamic>> _categories = [];
  
  DateTime _selectedMonthFocus = DateTime(DateTime.now().year, DateTime.now().month);

  final List<IconData> _iconPool = [
    Icons.shopping_basket_outlined, Icons.restaurant, Icons.phone_android,
    Icons.music_note, Icons.menu_book, Icons.face, Icons.pool,
    Icons.card_giftcard, Icons.directions_bus_filled_outlined,
    Icons.checkroom, Icons.fastfood, Icons.flight,
    Icons.pets, Icons.medical_services, 
    Icons.fastfood, Icons.local_cafe, Icons.local_gas_station, 
    Icons.local_movies, Icons.computer, Icons.bar_chart,
  ];

  @override
  void initState() {
    super.initState();
    _loadStoredData();
    // _loadSpendingsFromHive();
    _initConnectivityListener();
  }

  // void _loadSpendingsFromHive() {
  //   final box = Hive.box('spendings_box');
  //   setState(() {
  //     _dynamicSpendings = box.values.map((item) {
  //       final Map<dynamic, dynamic> map = item as Map<dynamic, dynamic>;
  //       return SpendingItem(
  //         id: map['id'],
  //         category: map['category'],
  //         amount: map['amount'],
  //         date: DateTime.parse(map['date']),
  //         isSynced: map['isSynced'] ?? false,
  //       );
  //     }).toList();

  //     // Keep newest items on top
  //     _dynamicSpendings.sort((a, b) => b.date.compareTo(a.date));
  //   });
  // }

  void _loadStoredData() async {
    final rawSpendings = _myBox.get('DAILY_LIST', defaultValue: []);
    _dynamicSpendings = List<SpendingItem>.from(rawSpendings.map((item) {
      return SpendingItem(
        id: item['id'] ?? md5.convert(utf8.encode(DateTime.now().toString())).toString(),
        category: item['category'], 
        amount: item['amount'], 
        date: DateTime.parse(item['date']),
        isSynced: item['isSynced'] ?? false,
      );
    }));

    if (_dynamicSpendings.isEmpty) {
      _log.info('Local database is empty. Attempting cloud data recovery...');
      final cloudItems = await _sheetsService.fetchSpendingsFromSheets();
      
      if (cloudItems.isNotEmpty) {
        setState(() {
          _dynamicSpendings = cloudItems;
          _dynamicSpendings.sort((a, b) => b.date.compareTo(a.date)); 
          _saveSpendingsToDisk(); // Cache them locally in Hive
        });
      }

      _log.info('=== CURRENT DYNAMIC SPENDINGS MAP (${_dynamicSpendings.length} items) ===');
      for (var item in _dynamicSpendings) {
        _log.info('ID: ${item.id} | Date: ${item.date.year}-${item.date.month}-${item.date.day} | Category: ${item.category} | Amount: ${item.amount} | Synced: ${item.isSynced}');
      }
      _log.info('=======================================================');
    }

    final rawCategories = _myBox.get('CATEGORIES_LIST', defaultValue: null);
    if (rawCategories == null) {
      _categories = [
        {'label': 'Shopping', 'iconCode': Icons.shopping_basket_outlined.codePoint},
        {'label': 'Food', 'iconCode': Icons.restaurant.codePoint},
        {'label': 'Phone', 'iconCode': Icons.phone_android.codePoint},
        {'label': 'Home', 'iconCode': Icons.home.codePoint},
        {'label': 'Entertainment', 'iconCode': Icons.music_note.codePoint},
        {'label': 'Education', 'iconCode': Icons.menu_book.codePoint},
        {'label': 'Beauty', 'iconCode': Icons.face.codePoint},
        {'label': 'Sports', 'iconCode': Icons.pool.codePoint},
        {'label': 'Gifts', 'iconCode': Icons.card_giftcard.codePoint},
        {'label': 'Transportation', 'iconCode': Icons.directions_bus_filled_outlined.codePoint},
        {'label': 'Clothing', 'iconCode': Icons.checkroom.codePoint},
        {'label': 'Snacks', 'iconCode': Icons.fastfood.codePoint},
        {'label': 'Settings', 'iconCode': Icons.settings.codePoint},
      ];
      _saveCategoriesToDisk();
    } else {
      _categories = List<Map<String, dynamic>>.from(
        (rawCategories as List).map((item) => Map<String, dynamic>.from(item))
      );
    }
    setState(() {});
  }

  void _initConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.isNotEmpty && !results.contains(ConnectivityResult.none)) {
        _triggerBackgroundSync();
      }
    });
  }

  void _triggerBackgroundSync() async {
    final pendingItems = _dynamicSpendings.where((item) => !item.isSynced).toList();
    if (pendingItems.isEmpty) return;

    _log.info('Found ${pendingItems.length} pending items. Triggering sync...');

    final success = await _sheetsService.syncSpendingsToSheets(pendingItems);

    if (success) {
      _log.info('Cloud sync batch upload succeeded!');
      
      setState(() {
        for (var pending in pendingItems) {
          final idx = _dynamicSpendings.indexWhere((element) => element.id == pending.id);
          if (idx != -1) {
            _dynamicSpendings[idx].isSynced = true;
          }
        }
        _saveSpendingsToDisk();
      });
    } else {
      _log.warning('Cloud sync batch upload failed or timed out.');
    }
  }

  void _saveSpendingsToDisk() {
    final mapList = _dynamicSpendings.map((item) => {
      'id': item.id,
      'category': item.category, 
      'amount': item.amount, 
      'date': item.date.toIso8601String(),
      'isSynced': item.isSynced,
    }).toList();
    _myBox.put('DAILY_LIST', mapList);
  }

  void _saveCategoriesToDisk() {
    _myBox.put('CATEGORIES_LIST', _categories);
  }

  void _openMonthYearPickerPopup(BuildContext context) {
    int workingYear = _selectedMonthFocus.year;
    final List<String> shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setPopupState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_left, color: Color(0xFF03DAC6)),
                    onPressed: () => setPopupState(() => workingYear--),
                  ),
                  Text('$workingYear', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  IconButton(
                    icon: const Icon(Icons.arrow_right, color: Color(0xFF03DAC6)),
                    onPressed: () => setPopupState(() => workingYear++),
                  ),
                ],
              ),
              content: SizedBox(
                width: 300,
                height: 200,
                child: GridView.builder(
                  itemCount: 12,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.2
                  ),
                  itemBuilder: (context, idx) {
                    final isCurrentMonthFocus = (_selectedMonthFocus.month == idx + 1 && _selectedMonthFocus.year == workingYear);
                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isCurrentMonthFocus ? const Color(0xFF03DAC6) : const Color(0xFF2D2D2D),
                        foregroundColor: isCurrentMonthFocus ? Colors.black : Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedMonthFocus = DateTime(workingYear, idx + 1);
                        });
                        Navigator.pop(context);
                      },
                      child: Text(shortMonths[idx], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddEditCategoryDrawer(BuildContext context, {int? editIndex, VoidCallback? onComplete}) {
    final nameController = TextEditingController(text: editIndex != null ? _categories[editIndex]['label'] : '');
    IconData selectedIcon = editIndex != null ? IconData(_categories[editIndex]['iconCode'], fontFamily: 'MaterialIcons') : _iconPool.first;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDrawerState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.92,
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(editIndex != null ? 'Edit Category' : 'Add New Category', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(hintText: 'Category Name', filled: true, fillColor: Color(0xFF2D2D2D), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  const Text('Select Icon', style: TextStyle(color: Colors.white54)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, mainAxisSpacing: 8, crossAxisSpacing: 8),
                      itemCount: _iconPool.length,
                      itemBuilder: (context, idx) {
                        final icon = _iconPool[idx];
                        final isSelected = selectedIcon == icon;
                        return GestureDetector(
                          onTap: () => setDrawerState(() => selectedIcon = icon),
                          child: Container(
                            decoration: BoxDecoration(color: isSelected ? const Color(0xFF03DAC6) : const Color(0xFF2D2D2D), shape: BoxShape.circle),
                            child: Icon(icon, color: isSelected ? Colors.black : Colors.white),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF03DAC6), foregroundColor: Colors.black, minimumSize: const Size.fromHeight(48)),
                    onPressed: () {
                      if (nameController.text.trim().isEmpty) return;
                      setState(() {
                        if (editIndex != null) {
                          _categories[editIndex]['label'] = nameController.text.trim();
                          _categories[editIndex]['iconCode'] = selectedIcon.codePoint;
                        } else {
                          _categories.insert(_categories.length - 1, {'label': nameController.text.trim(), 'iconCode': selectedIcon.codePoint});
                        }
                        _saveCategoriesToDisk();
                      });
                      Navigator.pop(context);
                      if (onComplete != null) onComplete();
                    },
                    child: const Text('Save Category', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 60), 
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showManageCategoriesDrawer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setManagerDataState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.92,
              child: Column(
                children: [
                  const Padding(padding: EdgeInsets.all(16.0), child: Text('Manage Categories', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  Expanded(
                    child: ReorderableListView.builder(
                      itemCount: _categories.length,
                      onReorder: (oldIdx, newIdx) {
                        if (newIdx > _categories.length) newIdx = _categories.length;
                        if (oldIdx == _categories.length - 1 || newIdx >= _categories.length) return;
                        setState(() {
                          if (newIdx > oldIdx) newIdx -= 1;
                          final item = _categories.removeAt(oldIdx);
                          _categories.insert(newIdx, item);
                          _saveCategoriesToDisk();
                        });
                        setManagerDataState(() {});
                      },
                      itemBuilder: (context, index) {
                        final cat = _categories[index];
                        final isSettingsKey = cat['label'] == 'Settings';
                        return ListTile(
                          key: ValueKey(cat['label'] + index.toString()),
                          leading: Icon(IconData(cat['iconCode'], fontFamily: 'MaterialIcons'), color: const Color(0xFF03DAC6)),
                          title: Text(cat['label']),
                          trailing: isSettingsKey ? const SizedBox(width: 20) : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.edit, size: 20, color: Colors.white70), onPressed: () => _showAddEditCategoryDrawer(context, editIndex: index, onComplete: () => setManagerDataState(() {}))),
                              IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.redAccent), onPressed: () { setState(() { _categories.removeAt(index); _saveCategoriesToDisk(); }); setManagerDataState(() {}); }),
                              const Icon(Icons.drag_handle, color: Colors.white30),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, bottom: 60, top: 8),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D2D2D), foregroundColor: const Color(0xFF03DAC6), minimumSize: const Size.fromHeight(48), side: const BorderSide(color: Color(0xFF03DAC6), width: 1)),
                      onPressed: () => _showAddEditCategoryDrawer(context, onComplete: () => setManagerDataState(() {})),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Category', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAddSpendingModal(BuildContext context) {
    if (_categories.isEmpty) return;
    String selectedCategory = _categories.first['label'];
    String runningAmount = '0';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {

            return Container(
              height: MediaQuery.of(context).size.height * 0.92,
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  const Text('Add Spending', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 16, crossAxisSpacing: 8, childAspectRatio: 0.95),
                      itemCount: _categories.length,
                      itemBuilder: (context, index) {
                        final cat = _categories[index];
                        final isSelected = selectedCategory == cat['label'];
                        final isSettings = cat['label'] == 'Settings';

                        return GestureDetector(
                          onTap: () {
                            if (isSettings) {
                              Navigator.pop(context); 
                              _showManageCategoriesDrawer(context); 
                            } else {
                              setModalState(() => selectedCategory = cat['label']);
                            }
                          },
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: isSelected ? const Color(0xFF03DAC6) : const Color(0xFF2D2D2D), shape: BoxShape.circle),
                                child: Icon(IconData(cat['iconCode'], fontFamily: 'MaterialIcons'), color: isSelected ? Colors.black : (isSettings ? const Color(0xFF03DAC6) : Colors.white70), size: 24),
                              ),
                              const SizedBox(height: 6),
                              Text(cat['label'], style: TextStyle(fontSize: 11, color: isSelected ? const Color(0xFF03DAC6) : Colors.white70)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  _CalculatorKeypad(
                    initialAmount: '0',
                    initialDate: DateTime.now(),
                    onSavePressed: (finalAmount, finalDate) {
                      setState(() {
                        _dynamicSpendings.insert(
                          0, 
                          SpendingItem(
                            id: md5.convert(utf8.encode(DateTime.now().toIso8601String() + finalAmount)).toString(),
                            category: selectedCategory, 
                            amount: finalAmount, 
                            date: finalDate,
                          ),
                        );
                        _dynamicSpendings.sort((a, b) => b.date.compareTo(a.date));
                        _saveSpendingsToDisk();
                      });
                      
                      Navigator.pop(context);
                      _triggerBackgroundSync();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _deleteSpending(SpendingItem item) async {
    setState(() {
      _dynamicSpendings.removeWhere((element) => element.id == item.id);
      _saveSpendingsToDisk();
    });
    
    await _sheetsService.deleteSpendingFromSheets(item.id);
  }

  void _editSpending(SpendingItem item) {
    String selectedCategory = item.category;
    String runningAmount = item.amount;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.92,
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  const Text('Modify Entry Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4, 
                        mainAxisSpacing: 16, 
                        crossAxisSpacing: 8, 
                        childAspectRatio: 0.95
                      ),
                      itemCount: _categories.length,
                      itemBuilder: (context, index) {
                        final cat = _categories[index];
                        final isSelected = selectedCategory == cat['label'];
                        if (cat['label'] == 'Settings') return const SizedBox.shrink(); 

                        return GestureDetector(
                          onTap: () {
                            setModalState(() {
                              selectedCategory = cat['label'];
                            });
                          },
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF03DAC6) : const Color(0xFF2D2D2D), 
                                  shape: BoxShape.circle
                                ),
                                child: Icon(
                                  IconData(cat['iconCode'], fontFamily: 'MaterialIcons'), 
                                  color: isSelected ? Colors.black : Colors.white70, 
                                  size: 24
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(cat['label'], style: TextStyle(fontSize: 11, color: isSelected ? const Color(0xFF03DAC6) : Colors.white70)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  
                  _CalculatorKeypad(
                    initialAmount: runningAmount,
                    initialDate: item.date,
                    onSavePressed: (finalAmount, finalDate) {
                      final updatedItem = SpendingItem(
                        id: item.id,
                        category: selectedCategory,
                        amount: finalAmount,
                        date: finalDate,
                        isSynced: false, 
                      );

                      setState(() {
                        final idx = _dynamicSpendings.indexWhere((element) => element.id == item.id);
                        if (idx != -1) {
                          _dynamicSpendings[idx] = updatedItem;
                          _dynamicSpendings.sort((a, b) => b.date.compareTo(a.date));
                          _saveSpendingsToDisk();
                        }
                      });

                      Navigator.pop(context);

                      _sheetsService.updateSpendingInSheets(updatedItem).then((rewriteSuccess) {
                        if (!rewriteSuccess) {
                          _triggerBackgroundSync();
                        } else {
                          if (mounted) {
                            setState(() {
                              updatedItem.isSynced = true;
                              _saveSpendingsToDisk();
                            });
                          }
                        }
                      });
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false, 
      body: SafeArea(
        child: IndexedStack(
          index: _currentTabIndex,
          children: [
            HomeScreen(
              spendings: _dynamicSpendings,
              categories: _categories,
              selectedMonth: _selectedMonthFocus,
              onPreviousMonth: () {
                setState(() {
                  _selectedMonthFocus = DateTime(_selectedMonthFocus.year, _selectedMonthFocus.month - 1);
                });
              },
              onNextMonth: () {
                setState(() {
                  _selectedMonthFocus = DateTime(_selectedMonthFocus.year, _selectedMonthFocus.month + 1);
                });
              },
              onMonthPickerTap: () => _openMonthYearPickerPopup(context),
              onEditItem: _editSpending,
              onDeleteItem: _deleteSpending,
            ),
            ChartScreen(spendings: _dynamicSpendings),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSpendingModal(context),
        backgroundColor: const Color(0xFF03DAC6),
        foregroundColor: Colors.black,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        color: const Color(0xFF1E1E1E),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: Icon(Icons.home, color: _currentTabIndex == 0 ? const Color(0xFF03DAC6) : Colors.white38, size: 26),
                onPressed: () => setState(() => _currentTabIndex = 0),
              ),
              const SizedBox(width: 40),
              IconButton(
                icon: Icon(Icons.bar_chart, color: _currentTabIndex == 1 ? const Color(0xFF03DAC6) : Colors.white38, size: 26),
                onPressed: () => setState(() => _currentTabIndex = 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _CalculatorKeypad extends StatefulWidget {
  final String initialAmount;
  final DateTime initialDate;
  final Function(String finalAmount, DateTime finalDate) onSavePressed;

  const _CalculatorKeypad({
    required this.initialAmount,
    required this.initialDate,
    required this.onSavePressed,
  });

  @override
  State<_CalculatorKeypad> createState() => _CalculatorKeypadState();
}

class _CalculatorKeypadState extends State<_CalculatorKeypad> {
  late String runningAmount;
  late DateTime selectedDate;

  @override
  void initState() {
    super.initState();
    runningAmount = widget.initialAmount;
    selectedDate = widget.initialDate;
  }

  String _getDateButtonLabel() {
    final now = DateTime.now();
    if (selectedDate.year == now.year &&
        selectedDate.month == now.month &&
        selectedDate.day == now.day) {
      return 'Today';
    }
    return '${selectedDate.day}/${selectedDate.month}';
  }

  void _selectCustomDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF03DAC6),
              onPrimary: Colors.black,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  void handleKeyPress(String key) {
    setState(() {
      if (key == '⌫') {
        if (runningAmount.length > 1) {
          runningAmount = runningAmount.substring(0, runningAmount.length - 1);
        } else {
          runningAmount = '0';
        }
      } else if (key == '✓') {
        if (runningAmount != '0' && runningAmount.isNotEmpty) {
          widget.onSavePressed(runningAmount, selectedDate);
        }
      } else if (key == 'C') {
        runningAmount = '0';
      } else if (key == '000') {
        if (runningAmount == '0') return;
        runningAmount += '000';
      } else {        
        if (runningAmount == '0') {
          runningAmount = key;
        } else {
          runningAmount += key;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: const Color(0xFF161616),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                runningAmount.replaceAllMapped(
                  RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), 
                  (Match m) => '${m[1]},'
                ),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w400, color: Colors.white),
              ),
            ],
          ),
        ),
        Container(
          color: const Color(0xFF121212),
          padding: const EdgeInsets.only(top: 4, left: 4, right: 4, bottom: 40),
          child: Table(
            children: [
              _buildKeyRow(['7', '8', '9', _getDateButtonLabel()]),
              _buildKeyRow(['4', '5', '6', '⌫']),
              _buildKeyRow(['1', '2', '3', 'C']),
              _buildKeyRow(['', '0', '000', '✓']),
            ],
          ),
        ),
      ],
    );
  }

  TableRow _buildKeyRow(List<String> keys) {
    return TableRow(
      children: keys.map((key) {
        if (key.isEmpty) return const TableCell(child: SizedBox.shrink());

        final isCheckmark = key == '✓';
        final isBackspace = key == '⌫';
        final isClear = key == 'C';
        final isDateAction = key == 'Today' || key.contains('/');

        return TableCell(
          child: InkWell(
            onTap: isDateAction ? _selectCustomDate : () => handleKeyPress(key),
            child: Container(
              height: 54,
              alignment: Alignment.center,
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isCheckmark 
                    ? const Color(0xFF03DAC6) 
                    : (isDateAction || isBackspace ? const Color(0xFF222222) : const Color(0xFF1E1E1E)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: isBackspace 
                  ? const Icon(Icons.backspace_outlined, size: 18, color: Color(0xFF03DAC6))
                  : Text(
                      key,
                      style: TextStyle(
                        fontSize: isDateAction ? 15 : 20, 
                        fontWeight: FontWeight.bold,
                        color: isCheckmark 
                            ? Colors.black 
                            : (isDateAction || isBackspace || isClear? const Color(0xFF03DAC6) : Colors.white)
                      ),
                    ),
            ),
          ),
        );
      }).toList(),
    );
  }
}