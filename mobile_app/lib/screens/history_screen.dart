import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart'; 
import '../models/history_item.dart';
import '../services/database_helper.dart';
import '../services/passcode_service.dart';
import '../services/supabase_service.dart';
import '../widgets/common_app_bar_actions.dart';
import '../screens/passcode_setup_screen.dart';
import '../services/printer_service.dart';
import '../utils/colors.dart';

class HistoryScreen extends StatefulWidget {
  final int initialTab;
  final String? highlightQuery;
  final String? highlightReceiptId;
  const HistoryScreen({super.key, this.initialTab = 0, this.highlightQuery, this.highlightReceiptId});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey _targetItemKey = GlobalKey();
  
  // Data
  List<HistoryItem> _allItems = [];
  List<HistoryItem> _filteredItems = [];
  
  // Filters
  String _currentTabFilter = "ALL"; // ALL, NEW STOCK, SALES
  String _searchQuery = "";
  DateTime? _selectedDate;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  final _formatter = NumberFormat("#,###");

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: widget.initialTab);
    _tabController.addListener(_handleTabSelection);

    switch (widget.initialTab) {
      case 1: _currentTabFilter = "NEW STOCK"; break;
      case 2: _currentTabFilter = "SALES"; break;
      case 3: _currentTabFilter = "DEBTS"; break;
      default: _currentTabFilter = "ALL"; break;
    }

    if (widget.highlightQuery != null && widget.highlightQuery!.isNotEmpty) {
      _searchQuery = widget.highlightQuery!;
      _searchController.text = widget.highlightQuery!;
    }

    _loadHistory();
    SupasService.instance.syncStatus.addListener(_onSyncStatusChanged);
  }

  void _onSyncStatusChanged() {
    if (SupasService.instance.syncStatus.value == SyncStatus.synced) {
        if (mounted) {
            _loadHistory(showLoading: false);
        }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    SupasService.instance.syncStatus.removeListener(_onSyncStatusChanged);
    super.dispose();
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) {
      // Intentionally empty or simple update if needed triggers on animation end usually
      // But setState in `onTap` or ensuring logic runs is safest.
    }
    // We bind the tab index to a filter string
    setState(() {
        switch (_tabController.index) {
          case 0: _currentTabFilter = "ALL"; break;
          case 1: _currentTabFilter = "NEW STOCK"; break;
          case 2: _currentTabFilter = "SALES"; break;
          case 3: _currentTabFilter = "DEBTS"; break;
        }
        _applyFilters();
    });
  }

  Future<void> _loadHistory({bool showLoading = true}) async {
      if (showLoading) setState(() => _isLoading = true);
      final items = await DatabaseHelper.instance.getHistory("ALL");
      if (mounted) {
          setState(() {
              _allItems = items;
              _applyFilters();
              _isLoading = false;
          });

          if (widget.highlightReceiptId != null && widget.highlightReceiptId!.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_targetItemKey.currentContext != null) {
                Scrollable.ensureVisible(
                  _targetItemKey.currentContext!,
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeInOut,
                  alignment: 0.2,
                );
              }
            });
          }
      }
  }

  void _applyFilters() {
      List<HistoryItem> temp = _allItems;

      // 1. Tab Filter
      if (_currentTabFilter == "NEW STOCK") {
          temp = temp.where((i) => i.type == "NEW STOCK").toList();
      } else if (_currentTabFilter == "SALES") {
          temp = temp.where((i) => i.type != "NEW STOCK" && !i.isDebt).toList();
      } else if (_currentTabFilter == "DEBTS") {
          temp = temp.where((i) => i.isDebt && !i.isPaid).toList();
      }

      // 2. Search Filter (Supports multi-term OR search)
      if (_searchQuery.isNotEmpty) {
          final terms = _searchQuery
              .split(',')
              .map((t) => t.trim().toLowerCase())
              .where((t) => t.isNotEmpty)
              .toList();

          temp = temp.where((i) {
             final itemLower = i.item.toLowerCase();
             final customerLower = i.customer.toLowerCase();
             return terms.any((q) => itemLower.contains(q) || customerLower.contains(q));
          }).toList();
      }

      // 3. Date Filter
      if (_selectedDate != null) {
          String filterDate = _selectedDate!.toIso8601String().split('T')[0];
          temp = temp.where((i) => i.date == filterDate).toList();
      }

      _filteredItems = temp;
  }

  void _onSearchChanged(String value) {
      setState(() {
          _searchQuery = value;
          _applyFilters();
      });
  }

  Future<void> _pickDate() async {
      final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 1)),
      );
      if (picked != null && picked != _selectedDate) {
          setState(() {
              _selectedDate = picked;
              _applyFilters();
          });
      } else if (picked == null && _selectedDate != null) {
          // Optional: clear date if they cancel? No, standard behavior is keep.
          // If user wants to clear, maybe add a "Clear" button or tap active date icon again?
          // For now, let's allow re-tapping to clear if same date picked? No that's confusing.
          // Let's add a clear mechanism in the UI if date is selected.
      }
  }



  bool _canDelete(String dateString) {
      try {
          DateTime itemDate = DateTime.parse(dateString);
          DateTime now = DateTime.now();
          // Compare dates by reset to midnight
          DateTime today = DateTime(now.year, now.month, now.day);
          DateTime itemDay = DateTime(itemDate.year, itemDate.month, itemDate.day);
          
          return today.difference(itemDay).inDays <= 4;
      } catch (e) {
          return false;
      }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB), // background-light
      appBar: AppBar(
         backgroundColor: Colors.white,
         elevation: 0,
         titleSpacing: 0,
         toolbarHeight: 140, // Expanded height for Header + Tabs
         title: Container(
             padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
             child: Column(
                 crossAxisAlignment: CrossAxisAlignment.stretch,
                 children: [
                     Row(
                       children: [
                         Container(
                           padding: const EdgeInsets.all(8),
                           decoration: BoxDecoration(
                             color: AppColors.primaryGreen.withValues(alpha: 0.1),
                             borderRadius: BorderRadius.circular(8),
                           ),
                           child: Image.asset('assets/images/app_icon.png', width: 20, height: 20),
                         ),
                         const SizedBox(width: 12),
                         const Expanded(
                           child: Text("Transaction History", style: TextStyle(
                               color: Color(0xFF111827), // text-primary-light
                               fontSize: 20, 
                               fontWeight: FontWeight.bold
                           )),
                         ),
                          StandardAppBarActions(onRefresh: _loadHistory),
                       ],
                     ),

                     const SizedBox(height: 12),
                     Row(
                         children: [
                             // Search Bar
                             Expanded(
                                 child: Container(
                                     height: 40,
                                     decoration: BoxDecoration(
                                         color: Colors.white,
                                         borderRadius: BorderRadius.circular(8),
                                         border: Border.all(color: Colors.grey.shade300),
                                     ),
                                     child: TextField(
                                         controller: _searchController,
                                         onChanged: _onSearchChanged,
                                         textAlignVertical: TextAlignVertical.center,
                                         decoration: InputDecoration(
                                            isDense: true,
                                            hintText: "Product or Customer",
                                            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                                            prefixIcon: Icon(Icons.search, color: Colors.grey[400], size: 20),
                                            border: InputBorder.none,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            suffixIcon: _searchQuery.isNotEmpty 
                                                ? IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () {
                                                    _searchController.clear();
                                                    _onSearchChanged("");
                                                  }) 
                                                : null
                                         ),
                                     ),
                                 ),
                             ),
                             const SizedBox(width: 8),
                             // Date Button
                             InkWell(
                                 onTap: _pickDate,
                                 child: Container(
                                     height: 40,
                                     width: 40,
                                     decoration: BoxDecoration(
                                         color: _selectedDate != null ? AppColors.primaryGreen.withValues(alpha: 0.1) : Colors.white,
                                         borderRadius: BorderRadius.circular(8),
                                         border: Border.all(
                                             color: _selectedDate != null ? AppColors.primaryGreen : Colors.grey.shade300
                                         ),
                                     ),
                                     child: Icon(
                                         Icons.calendar_today_outlined, 
                                         color: _selectedDate != null ? AppColors.primaryGreen : Colors.grey[500],
                                         size: 20
                                     ),
                                 ),
                             ),
                             if (_selectedDate != null)
                                 Padding(
                                   padding: const EdgeInsets.only(left: 4),
                                   child: IconButton(
                                      icon: const Icon(Icons.close, color: Colors.red, size: 20),
                                      onPressed: () => setState(() {
                                          _selectedDate = null;
                                          _applyFilters();
                                      }),
                                      tooltip: "Clear Date Filter",
                                   ),
                                 )
                         ],
                     ),
                 ],
             ),
         ),
         bottom: PreferredSize(
             preferredSize: const Size.fromHeight(48),
             child: Container(
                 decoration: BoxDecoration(
                     border: Border(bottom: BorderSide(color: Colors.grey.shade200))
                 ),
                 child: TabBar(
                     controller: _tabController,
                     labelColor: AppColors.primaryGreen,
                     unselectedLabelColor: const Color(0xFF6B7280), // text-secondary
                     indicatorColor: AppColors.primaryGreen,
                     indicatorWeight: 3,
                     labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                     tabs: const [
                         Tab(text: "ALL"),
                         Tab(text: "NEW STOCK"),
                         Tab(text: "SALES"),
                         Tab(text: "DEBTS"),
                     ],
                 ),
             ),
         ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _filteredItems.isEmpty 
            ? _buildEmptyState()
            : _buildGroupedHistoryList(),
    );
  }
  
  Widget _buildGroupedHistoryList() {
    final grouped = _groupItemsByPeriod(_filteredItems);
    final List<Widget> children = [];

    grouped.forEach((period, items) {
      if (items.isNotEmpty) {
        children.add(_buildSectionHeader(period, items.length));
        for (var item in items) {
          children.add(_buildHistoryCard(item));
          children.add(const SizedBox(height: 12));
        }
        children.add(const SizedBox(height: 8));
      }
    });

    return ListView(
      padding: const EdgeInsets.all(16),
      children: children,
    );
  }

  Map<String, List<HistoryItem>> _groupItemsByPeriod(List<HistoryItem> items) {
    final Map<String, List<HistoryItem>> groups = {
      'Today': [],
      'Yesterday': [],
      'Earlier': [],
    };

    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final yesterdayStr = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));

    for (var item in items) {
      if (item.date == todayStr) {
        groups['Today']!.add(item);
      } else if (item.date == yesterdayStr) {
        groups['Yesterday']!.add(item);
      } else {
        groups['Earlier']!.add(item);
      }
    }

    return groups;
  }

  Widget _buildSectionHeader(String period, int count) {
    IconData icon;
    Color iconColor;
    if (period == 'Today') {
      icon = Icons.today;
      iconColor = AppColors.primaryGreen;
    } else if (period == 'Yesterday') {
      icon = Icons.history;
      iconColor = Colors.orange;
    } else {
      icon = Icons.calendar_today_outlined;
      iconColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Text(
            period,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count ${count == 1 ? "transaction" : "transactions"}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: iconColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
      return Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                  Icon(Icons.history_toggle_off, size: 48, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                      _searchQuery.isNotEmpty 
                          ? "No matches found for '$_searchQuery'"
                          : "No transactions found",
                      style: TextStyle(color: Colors.grey[500])
                  ),
              ],
          ),
      );
  }

  List<TransactionItem> _parseHistoryItemText(String itemText) {
    final List<TransactionItem> parsedItems = [];
    final lines = itemText.split('\n');

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      final atSplit = line.split('@');
      if (atSplit.length < 2) {
        parsedItems.add(TransactionItem(
          size: '',
          itemName: line.trim(),
          quantityStr: '',
          priceStr: '',
          amountStr: '',
        ));
        continue;
      }

      final beforeAt = atSplit[0].trim();
      final afterAt = atSplit[1].trim();

      final equalSplit = afterAt.split('=');
      final priceStr = equalSplit[0].trim();
      final amountStr = equalSplit.length > 1 ? equalSplit[1].trim() : '';

      final words = beforeAt.split(RegExp(r'\s+'));
      if (words.isEmpty) continue;

      String size = '';
      String qtyVal = '';
      String unitLabel = '';
      int itemStartIndex = 0;

      final firstWord = words[0];
      final isPureNumeric = RegExp(r'^\d+(\.\d+)?$').hasMatch(firstWord);
      
      if (isPureNumeric) {
        size = '';
        qtyVal = firstWord;
        itemStartIndex = 1;
      } else {
        size = firstWord.toLowerCase() == 'none' ? '' : firstWord;
        qtyVal = words.length > 1 ? words[1] : '';
        itemStartIndex = 2;
      }

      if (words.length > itemStartIndex) {
        final nextWord = words[itemStartIndex].toLowerCase();
        if (nextWord == 'pcs' || nextWord == 'doz' || nextWord == 'dozen' || nextWord == 'crate' || nextWord == 'sack' || nextWord == 'kg' || nextWord.contains('box') || nextWord.contains('bx')) {
          unitLabel = words[itemStartIndex];
          itemStartIndex += 1;

          // Capture and merge explicit multiplier suffixes that were split by spaces (e.g. "* 20", "*20", "20*")
          if (itemStartIndex < words.length) {
            final follow1 = words[itemStartIndex].toLowerCase();
            if (follow1 == '*' && (itemStartIndex + 1) < words.length && RegExp(r'^\d+$').hasMatch(words[itemStartIndex + 1])) {
              unitLabel += '*${words[itemStartIndex + 1]}';
              itemStartIndex += 2;
            } else if (follow1.startsWith('*') && RegExp(r'^\*\d+$').hasMatch(follow1)) {
              unitLabel += '*${follow1.substring(1)}';
              itemStartIndex += 1;
            } else if (follow1.endsWith('*') && RegExp(r'^\d+\*$').hasMatch(follow1)) {
              unitLabel += '*${follow1.substring(0, follow1.length - 1)}';
              itemStartIndex += 1;
            } else if (RegExp(r'^\d+$').hasMatch(follow1) && (itemStartIndex + 1) < words.length && words[itemStartIndex + 1] == '*') {
              unitLabel += '*$follow1';
              itemStartIndex += 2;
            }
          }
        } else if (nextWord == 'half' && words.length > (itemStartIndex + 1) && 
                   (words[itemStartIndex + 1].toLowerCase().startsWith('doz') || words[itemStartIndex + 1].toLowerCase().startsWith('dozen'))) {
          final dozWord = words[itemStartIndex + 1];
          unitLabel = 'half $dozWord';
          itemStartIndex += 2;

          // Capture and merge explicit multiplier suffixes for 'half doz' that were split by spaces (e.g. "* 6", "*6", "6*")
          if (!dozWord.contains('*') && itemStartIndex < words.length) {
            final follow1 = words[itemStartIndex].toLowerCase();
            if (follow1 == '*' && (itemStartIndex + 1) < words.length && RegExp(r'^\d+$').hasMatch(words[itemStartIndex + 1])) {
              unitLabel += '*${words[itemStartIndex + 1]}';
              itemStartIndex += 2;
            } else if (follow1.startsWith('*') && RegExp(r'^\*\d+$').hasMatch(follow1)) {
              unitLabel += '*${follow1.substring(1)}';
              itemStartIndex += 1;
            } else if (follow1.endsWith('*') && RegExp(r'^\d+\*$').hasMatch(follow1)) {
              unitLabel += '*${follow1.substring(0, follow1.length - 1)}';
              itemStartIndex += 1;
            } else if (RegExp(r'^\d+$').hasMatch(follow1) && (itemStartIndex + 1) < words.length && words[itemStartIndex + 1] == '*') {
              unitLabel += '*$follow1';
              itemStartIndex += 2;
            }
          }
        }
      }

      final itemName = words.length > itemStartIndex 
          ? words.sublist(itemStartIndex).join(' ') 
          : beforeAt;

      String formattedQty = '';
      if (qtyVal.isNotEmpty) {
        if (unitLabel.toLowerCase() == 'pcs' || unitLabel.isEmpty) {
          formattedQty = '(x$qtyVal pc)';
        } else {
          formattedQty = '(x$qtyVal $unitLabel)';
        }
      }

      parsedItems.add(TransactionItem(
        size: size,
        itemName: itemName,
        quantityStr: formattedQty,
        priceStr: priceStr,
        amountStr: amountStr,
      ));
    }

    return parsedItems;
  }

  String _formatAmount(String amtStr) {
    if (amtStr.isEmpty) return "";
    double val = double.tryParse(amtStr.replaceAll(',', '')) ?? 0;
    return _formatter.format(val);
  }

  Widget _buildHistoryCard(HistoryItem item) {
      Color badgeBg = Colors.grey[100]!;
      Color badgeText = Colors.grey[800]!;
      String typeLabel = item.type.toUpperCase();
      
      if (typeLabel == 'NEW STOCK') {
          badgeBg = const Color(0xFFFFEDD5); // orange-100
          badgeText = const Color(0xFF9A3412); // orange-800
      } else if (typeLabel == 'RETAIL' || typeLabel == 'SALE') {
           badgeBg = const Color(0xFFDCFCE7); // green-100
           badgeText = const Color(0xFF166534); // green-800
      } else if (typeLabel == 'WHOLESALE') {
           badgeBg = const Color(0xFFF3E8FF); // purple-100
           badgeText = const Color(0xFF6B21A8); // purple-800
      } else {
           badgeBg = const Color(0xFFF3F4F6);
           badgeText = const Color(0xFF374151);
      }
      
      bool isStock = (typeLabel == 'NEW STOCK');

      // Premium styling for Device badge
      Color deviceBg;
      Color deviceText;
      if (item.deviceSource.toLowerCase() == "mobile") {
          deviceBg = const Color(0xFFEFF6FF); // blue-50
          deviceText = const Color(0xFF1E40AF); // blue-800
      } else {
          deviceBg = const Color(0xFFF3F4F6); // gray-100
          deviceText = const Color(0xFF374151); // gray-700
      }

      final parsedLines = _parseHistoryItemText(item.item);

      double amountVal = double.tryParse(item.amount.replaceAll(',', '')) ?? 0;
      double paidAmountVal = double.tryParse(item.paidAmount.replaceAll(',', '')) ?? 0;
      double remainingVal = amountVal - paidAmountVal;

      double displayAmount = amountVal;
      if (item.isDebt && !item.isPaid) {
          displayAmount = remainingVal;
      }

      final bool isTargetReceipt = widget.highlightReceiptId != null &&
          widget.highlightReceiptId!.isNotEmpty &&
          item.receiptId == widget.highlightReceiptId;

      final bool isSearchMatch = _searchQuery.isNotEmpty &&
          _searchQuery.split(',').any((t) {
            final term = t.trim().toLowerCase();
            return term.isNotEmpty &&
                (item.customer.toLowerCase().contains(term) ||
                 item.item.toLowerCase().contains(term));
          });

      final bool isHighlighted = isTargetReceipt || isSearchMatch;

      return Container(
          key: isTargetReceipt ? _targetItemKey : null,
          decoration: BoxDecoration(
              color: isHighlighted ? AppColors.primaryGreen.withValues(alpha: 0.08) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isHighlighted ? AppColors.primaryGreen : const Color(0xFFE5E7EB),
                width: isHighlighted ? 2.5 : 1,
              ),
              boxShadow: [
                  BoxShadow(
                    color: isHighlighted ? AppColors.primaryGreen.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.015),
                    blurRadius: isHighlighted ? 12 : 8,
                    offset: const Offset(0, 4),
                  )
              ]
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (item.isDebt && !item.isPaid) {
                    _showPaymentModal(item);
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                        if (isHighlighted)
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primaryGreen,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, color: Colors.white, size: 12),
                                SizedBox(width: 4),
                                Text(
                                  'HIGHLIGHTED ALERT ITEM',
                                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        // Top Row: Date & Badges
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                                Text(
                                    item.date, 
                                    style: const TextStyle(
                                        fontSize: 14, 
                                        fontWeight: FontWeight.w600, 
                                        color: Color(0xFF9CA3AF) // medium gray
                                    )
                                ),
                                Row(
                                  children: [
                                    Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                            color: deviceBg,
                                            borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                            item.deviceSource.toUpperCase(), 
                                            style: TextStyle(
                                                fontSize: 10, 
                                                fontWeight: FontWeight.bold, 
                                                color: deviceText, 
                                                letterSpacing: 0.5
                                            )
                                        ),
                                    ),
                                    Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                            color: badgeBg,
                                            borderRadius: BorderRadius.circular(6)
                                        ),
                                        child: Text(
                                            typeLabel, 
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeText, letterSpacing: 0.5)
                                        ),
                                    ),
                                  ],
                                )
                            ],
                        ),
                        const SizedBox(height: 16),
                        
                        // Middle Row: Items and details
                        ...parsedLines.map((pi) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                    Expanded(
                                        child: Text(
                                            "${pi.size.isNotEmpty ? '${pi.size} ' : ''}${pi.itemName} ${pi.quantityStr}",
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600, 
                                                fontSize: 13, 
                                                color: Color(0xFF374151) // text-secondary-dark
                                            )
                                        ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                        _formatAmount(pi.amountStr),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold, 
                                            fontSize: 13,
                                            color: Color(0xFF111827)
                                        )
                                    ),
                                ],
                            ),
                        )).toList(),
                        
                        const SizedBox(height: 4),
                        Text(
                            isStock ? "Supplier: ${item.customer}" : "Customer: ${item.customer}",
                            style: const TextStyle(
                                fontSize: 13, 
                                fontStyle: FontStyle.italic, 
                                color: Color(0xFF9CA3AF)
                            )
                        ),

                        const SizedBox(height: 12),
                        const Divider(height: 1, color: Color(0xFFF3F4F6)),
                        const SizedBox(height: 12),

                        // Bottom Row: Actions (left) & UGX grand totals (right)
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                                // Action Icons (Delete & Reprint)
                                Row(
                                    children: [
                                        if (_canDelete(item.date))
                                            IconButton(
                                                icon: const Icon(
                                                    Icons.delete_outline,
                                                    color: Colors.red,
                                                    size: 20
                                                ),
                                                onPressed: () => _confirmDeletion(item),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                visualDensity: VisualDensity.compact,
                                            ),
                                        if (_canDelete(item.date) && !isStock)
                                            const SizedBox(width: 12),
                                        if (!isStock)
                                            IconButton(
                                                icon: const Icon(Icons.print, color: AppColors.primaryGreen, size: 20),
                                                onPressed: () => _reprintInvoice(item),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                visualDensity: VisualDensity.compact,
                                            ),
                                    ],
                                ),

                                // Totals Column
                                Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                         Text(
                                             "UGX ${_formatter.format(displayAmount)}", 
                                             style: TextStyle(
                                                 fontWeight: FontWeight.bold, 
                                                 fontSize: 16,
                                                 color: isStock ? const Color(0xFFEA580C) : const Color(0xFF0F766E) 
                                             )
                                         ),
                                         if (!isStock) ...[
                                             const SizedBox(height: 2),
                                             ValueListenableBuilder<bool>(
                                               valueListenable: PasscodeService.instance.isLocked,
                                               builder: (context, isLocked, child) {
                                                 if (isLocked) return const SizedBox.shrink();
                                                 double profitVal = double.tryParse(item.profit.replaceAll(',', '')) ?? 0;
                                                 return Text(
                                                     "Profit: ${_formatter.format(profitVal)}", 
                                                     style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))
                                                 );
                                               },
                                             ),
                                         ]
                                    ],
                                )
                            ],
                        )
                    ],
                ),
              ),
            ),
          ),
      );
  }

  void _reprintInvoice(HistoryItem item) async {
      try {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Searching for MPT-II printer...'), duration: Duration(seconds: 2))
          );
          
          final itemsList = await DatabaseHelper.instance.getReceiptItems(item.id!);
          
          if (itemsList.isEmpty) {
              throw Exception("Could not find items for this receipt.");
          }

          await PrinterService.instance.printInvoice(
              item.customer, 
              itemsList
          );
      } catch (e) {
          if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      backgroundColor: Colors.red,
                      content: Text('Reprint Failed: ${e.toString().replaceAll("Exception: ", "")}'),
                  )
              );
          }
      }
  }

  void _confirmDeletion(HistoryItem item) {
    final passcodeController = TextEditingController();
    String? errorMessage;
    bool hasPasscode = PasscodeService.instance.hasPasscode;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text(hasPasscode ? "Confirm Deletion" : "Security Passcode Required"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasPasscode) ...[
                Text("Are you sure you want to delete this transaction for '${item.item}'?"),
                const SizedBox(height: 8),
                const Text("This will revert the stock quantity.", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 16),
                const Text("Enter 6-digit Admin Passcode to Confirm:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: passcodeController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    hintText: "6-digit Passcode",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    counterText: "",
                  ),
                  onChanged: (_) {
                    if (errorMessage != null) setModalState(() => errorMessage = null);
                  },
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ] else ...[
                const Text("A security passcode is required to delete transactions and revert stock."),
                const SizedBox(height: 8),
                const Text("Please create a passcode in the Account section first.", style: TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            if (hasPasscode)
              ElevatedButton(
                onPressed: () async {
                  final pc = passcodeController.text;
                  final isValid = await PasscodeService.instance.verifyPasscode(pc);
                  
                  if (isValid && pc.isNotEmpty) {
                    if (item.id != null) {
                      try {
                        await DatabaseHelper.instance.deleteHistoryItem(item.id!);
                        await SupasService.instance.uploadDatabase();
                        
                        if (mounted) {
                          Navigator.pop(context); // Close dialog
                          _loadHistory(); // Refresh list
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Transaction deleted and stock reverted."), backgroundColor: AppColors.primaryGreen)
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red)
                          );
                        }
                      }
                    }
                  } else {
                    setModalState(() => errorMessage = "Incorrect Passcode!");
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                child: const Text("Delete"),
              )
            else
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PasscodeSetupScreen()));
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen, foregroundColor: Colors.white),
                child: const Text("Create Passcode"),
              ),
          ],
        ),
      ),
    );
  }

  void _showPaymentModal(HistoryItem item) {
      final amountController = TextEditingController();
      final passcodeController = TextEditingController();
      bool isVerifyingPasscode = false;
      String? errorMessage;

      showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (context) => StatefulBuilder(
              builder: (context, setModalState) => Padding(
                  padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom,
                      left: 24, right: 24, top: 24
                  ),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                          Row(
                              children: [
                                  Icon(Icons.payment, color: Colors.orange.shade700),
                                  const SizedBox(width: 12),
                                  const Text("Settle Debt", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              ],
                          ),
                          const SizedBox(height: 8),
                          Text("Settling debt for ${item.customer}", style: const TextStyle(color: Colors.grey)),
                          const Divider(height: 32),
                          Text("Original Total: UGX ${_formatter.format(double.tryParse(item.amount.replaceAll(',', '')) ?? 0)}", 
                              style: const TextStyle(fontSize: 14, color: Colors.grey)),
                          Text("Paid So Far: UGX ${_formatter.format(double.tryParse(item.paidAmount.replaceAll(',', '')) ?? 0)}", 
                              style: const TextStyle(fontSize: 14, color: Colors.grey)),
                          const SizedBox(height: 8),
                          Text("Remaining Debt: UGX ${_formatter.format((double.tryParse(item.amount.replaceAll(',', '')) ?? 0) - (double.tryParse(item.paidAmount.replaceAll(',', '')) ?? 0))}", 
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primaryGreen)),
                          const SizedBox(height: 16),
                          
                          if (!isVerifyingPasscode) ...[
                              TextField(
                                  controller: amountController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                      labelText: "Enter Amount Paid",
                                      prefixText: "UGX ",
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                  onPressed: () {
                                      double entered = double.tryParse(amountController.text) ?? 0;
                                      double total = double.tryParse(item.amount.replaceAll(',', '')) ?? 0;
                                      double alreadyPaid = double.tryParse(item.paidAmount.replaceAll(',', '')) ?? 0;
                                      double remaining = total - alreadyPaid;
                                      
                                      if (entered > 0 && entered <= remaining) {
                                          setModalState(() => isVerifyingPasscode = true);
                                      } else {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text(entered > remaining ? "Amount exceeds the remaining debt." : "Please enter a valid amount."))
                                          );
                                      }
                                  },
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primaryGreen,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text("Verify Amount", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                          ] else ...[
                              if (PasscodeService.instance.hasPasscode) ...[
                                  const Text("Enter 6-digit Passcode to Confirm Payment", style: TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 12),
                                  TextField(
                                      controller: passcodeController,
                                      obscureText: true,
                                      keyboardType: TextInputType.number,
                                      maxLength: 6,
                                      decoration: InputDecoration(
                                          labelText: "6-digit Passcode",
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                          counterText: "",
                                      ),
                                      onChanged: (_) {
                                           if (errorMessage != null) setModalState(() => errorMessage = null);
                                      },
                                  ),
                                  if (errorMessage != null) ...[
                                      const SizedBox(height: 8),
                                      Center(child: Text(errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold))),
                                  ],
                                  const SizedBox(height: 24),
                                  ElevatedButton(
                                      onPressed: () async {
                                          final pc = passcodeController.text;
                                          bool isValid = await PasscodeService.instance.verifyPasscode(pc) && pc.isNotEmpty;
                                          
                                          if (isValid) {
                                              if (item.id != null) {
                                                  double entered = double.tryParse(amountController.text) ?? 0;
                                                  double total = double.tryParse(item.amount.replaceAll(',', '')) ?? 0;
                                                  double alreadyPaid = double.tryParse(item.paidAmount.replaceAll(',', '')) ?? 0;
                                                  double currentRemaining = total - alreadyPaid;
                                                  double finalRemaining = currentRemaining - entered;
                                                  
                                                  await DatabaseHelper.instance.markDebtAsPaid(item.customer, entered);
                                                  // Trigger background upload
                                                  SupasService.instance.uploadDatabase();
                                                  
                                                  if (mounted) {
                                                      Navigator.pop(context); // Close modal
                                                      _loadHistory(); // Refresh list
                                                      String msg = finalRemaining <= 0 
                                                        ? "Payment Confirmed! Debt settled." 
                                                        : "Partial Payment Received! Remaining: UGX ${_formatter.format(finalRemaining)}";
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                          SnackBar(content: Text(msg))
                                                      );
                                                  }
                                              }
                                          } else {
                                               setModalState(() => errorMessage = "Incorrect Passcode!");
                                          }
                                      },
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange.shade700,
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      child: const Text("Confirm Payment", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ),
                              ] else ...[
                                  const Text("Security Passcode Required", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                                  const SizedBox(height: 8),
                                  const Text("Please create a passcode to settle debts.", style: TextStyle(fontSize: 13, color: Colors.grey)),
                                  const SizedBox(height: 24),
                                  ElevatedButton(
                                      onPressed: () {
                                          Navigator.pop(context); // Close modal
                                          Navigator.push(context, MaterialPageRoute(builder: (_) => const PasscodeSetupScreen()));
                                      },
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primaryGreen,
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      child: const Text("Create Passcode", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ),
                              ],
                              TextButton(
                                  onPressed: () => setModalState(() => isVerifyingPasscode = false),
                                  child: const Text("Back"),
                              ),
                          ],
                           const SizedBox(height: 32),
                      ],
                  ),
              )
          ),
      );
  }
}

class TransactionItem {
  final String size;
  final String itemName;
  final String quantityStr;
  final String priceStr;
  final String amountStr;

  TransactionItem({
    required this.size,
    required this.itemName,
    required this.quantityStr,
    required this.priceStr,
    required this.amountStr,
  });
}
