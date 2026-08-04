import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/history_item.dart';
import '../services/database_helper.dart';
import '../services/passcode_service.dart';
import '../services/supabase_service.dart';
import '../widgets/common_app_bar_actions.dart';
import '../screens/passcode_setup_screen.dart';
import '../services/printer_service.dart';
import '../utils/colors.dart';
import '../widgets/passcode_dialog.dart';

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
  String _currentTabFilter = "ALL"; // ALL, NEW STOCK, SALES, DEBTS
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
      case 1:
        _currentTabFilter = "NEW STOCK";
        break;
      case 2:
        _currentTabFilter = "SALES";
        break;
      case 3:
        _currentTabFilter = "DEBTS";
        break;
      default:
        _currentTabFilter = "ALL";
        break;
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
    setState(() {
      switch (_tabController.index) {
        case 0:
          _currentTabFilter = "ALL";
          break;
        case 1:
          _currentTabFilter = "NEW STOCK";
          break;
        case 2:
          _currentTabFilter = "SALES";
          break;
        case 3:
          _currentTabFilter = "DEBTS";
          break;
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

    // 2. Search Filter
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
    }
  }

  bool _canDelete(String dateString) {
    try {
      DateTime itemDate = DateTime.parse(dateString);
      DateTime now = DateTime.now();
      DateTime today = DateTime(now.year, now.month, now.day);
      DateTime itemDay = DateTime(itemDate.year, itemDate.month, itemDate.day);

      return today.difference(itemDay).inDays <= 4;
    } catch (e) {
      return false;
    }
  }

  String _formatDisplayDate(String dateStr) {
    try {
      final parsed = DateTime.parse(dateStr);
      return DateFormat('MMM d, yyyy').format(parsed);
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        toolbarHeight: 145,
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
                      color: AppColors.lightCyan,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Image.asset('assets/images/app_icon.png', width: 20, height: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Transaction History",
                      style: GoogleFonts.outfit(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
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
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.neutralBorder),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        textAlignVertical: TextAlignVertical.center,
                        style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF334155)),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: "Search Product or Customer",
                          hintStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 13),
                          prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8), size: 20),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    _onSearchChanged("");
                                  },
                                )
                              : null,
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
                        color: _selectedDate != null ? AppColors.lightCyan : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _selectedDate != null ? AppColors.primaryGreen : AppColors.neutralBorder,
                        ),
                      ),
                      child: Icon(
                        Icons.calendar_today_outlined,
                        color: _selectedDate != null ? AppColors.primaryGreen : const Color(0xFF64748B),
                        size: 18,
                      ),
                    ),
                  ),
                  if (_selectedDate != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: IconButton(
                        icon: const Icon(Icons.close, color: AppColors.accentRed, size: 20),
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
          child: _buildPillTabBar(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredItems.isEmpty
              ? _buildEmptyState()
              : _buildGroupedHistoryList(),
    );
  }

  // Horizontally Scrollable Category Pill Tab Bar
  Widget _buildPillTabBar() {
    final tabs = [
      {"label": "ALL", "filter": "ALL"},
      {"label": "NEW STOCK", "filter": "NEW STOCK"},
      {"label": "SALES", "filter": "SALES"},
      {"label": "DEBTS", "filter": "DEBTS"},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.neutralBorder)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: tabs.asMap().entries.map((entry) {
            final idx = entry.key;
            final tab = entry.value;
            final isSelected = _currentTabFilter == tab['filter'];

            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: InkWell(
                onTap: () {
                  _tabController.animateTo(idx);
                  setState(() {
                    _currentTabFilter = tab['filter']!;
                    _applyFilters();
                  });
                },
                borderRadius: BorderRadius.circular(20),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primaryGreen : AppColors.neutralInactive,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.primaryGreen.withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : [],
                  ),
                  child: Text(
                    tab['label']!,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? Colors.white : AppColors.neutralMutedText,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
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
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Text(
                period.toUpperCase(),
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: AppColors.textPrimary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.lightCyan,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "$count ITEMS",
              style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.darkCyan),
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
            style: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 15),
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
        rawQtyVal: qtyVal,
        rawUnitLabel: unitLabel,
      ));
    }

    return parsedItems;
  }

  String _formatAmount(String amtStr) {
    if (amtStr.isEmpty) return "";
    double val = double.tryParse(amtStr.replaceAll(',', '')) ?? 0;
    return _formatter.format(val);
  }

  // Compact Multiplier Packaging Badge Widget (e.g. [ 📦 box*12 ], [ 📦 half doz ], [ 📦 1 pc ])
  Widget _buildUnitChipWidget(String qtyVal, String unitLabel) {
    String text;
    String u = unitLabel.toLowerCase().replaceAll(' ', '');

    if (u.isEmpty || u == 'pcs' || u == 'pc') {
      text = (qtyVal == '1' || qtyVal.isEmpty) ? '1 pc' : '$qtyVal pcs';
    } else if (u.contains('halfdoz')) {
      text = 'half doz';
    } else if (u.contains('box*')) {
      final match = RegExp(r'box\*\d+').firstMatch(u);
      if (match != null) {
        text = match.group(0)!;
      } else {
        text = unitLabel.toLowerCase();
      }
    } else {
      text = unitLabel.toLowerCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.lightCyan,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00A389).withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined, size: 13, color: Color(0xFF00A389)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF00A389),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // Modernized History Item Card
  Widget _buildHistoryCard(HistoryItem item) {
    Color badgeBg = AppColors.neutralInactive;
    Color badgeText = AppColors.textPrimary;
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

    Color deviceBg;
    Color deviceText;
    if (item.deviceSource.toLowerCase() == "mobile") {
      deviceBg = const Color(0xFFEFF6FF); // blue-50
      deviceText = const Color(0xFF1E40AF); // blue-800
    } else {
      deviceBg = const Color(0xFFF3F4F6);
      deviceText = const Color(0xFF374151);
    }

    // Color coding grand total: Sale green #00D09C, Debt amber #D97706, New Stock red #E11D48
    Color amountColor;
    if (isStock) {
      amountColor = const Color(0xFFE11D48); // Expense Red
    } else if (item.isDebt && !item.isPaid) {
      amountColor = const Color(0xFFD97706); // Debt Amber
    } else {
      amountColor = AppColors.primaryGreen; // Sale Cyan-Green
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isHighlighted ? AppColors.primaryGreen : AppColors.neutralBorder,
          width: isHighlighted ? 2.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isHighlighted ? AppColors.primaryGreen.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.03),
            blurRadius: isHighlighted ? 12 : 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (item.isDebt && !item.isPaid) {
              _showPaymentModal(item);
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(18),
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, color: Colors.white, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          'HIGHLIGHTED ALERT ITEM',
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),

                // Top Row: Date & Badges (Responsive / Overflow-safe)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        _formatDisplayDate(item.date),
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: deviceBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.deviceSource.toUpperCase(),
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: deviceText,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              typeLabel,
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: badgeText,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Middle Section: Multi-row Item Name & Packaging Chip / Price Row
                ...parsedLines.map((pi) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Line 1: Full Item Name (Zero Truncation)
                      Text(
                        "${pi.size.isNotEmpty ? '${pi.size} ' : ''}${pi.itemName}",
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Line 2: [ Packaging Chip ] on Left, Price on Right
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (pi.rawQtyVal.isNotEmpty)
                            Flexible(
                              child: _buildUnitChipWidget(pi.rawQtyVal, pi.rawUnitLabel),
                            )
                          else
                            const SizedBox.shrink(),
                          const SizedBox(width: 8),
                          Text(
                            "UGX ${_formatAmount(pi.amountStr)}",
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )),

                const SizedBox(height: 6),

                // Customer / Supplier Line
                Row(
                  children: [
                    Icon(
                      isStock ? Icons.storefront_outlined : Icons.person_outline,
                      size: 16,
                      color: const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isStock ? "Supplier: ${item.customer}" : "Customer: ${item.customer}",
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                const Divider(height: 1, color: AppColors.neutralBorder),
                const SizedBox(height: 12),

                // Bottom Row: Actions (left) & Total Amount (right)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Action Icons with Touch Padding
                    Row(
                      children: [
                        if (_canDelete(item.date))
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppColors.accentRed, size: 20),
                            onPressed: () => _confirmDeletion(item),
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            tooltip: "Delete Entry",
                          ),
                        if (_canDelete(item.date) && !isStock)
                          const SizedBox(width: 8),
                        if (!isStock)
                          IconButton(
                            icon: const Icon(Icons.print_outlined, color: AppColors.primaryGreen, size: 20),
                            onPressed: () => _reprintInvoice(item),
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            tooltip: "Reprint Receipt",
                          ),
                      ],
                    ),

                    // Totals Column
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          "UGX ${_formatter.format(displayAmount)}",
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: amountColor,
                          ),
                        ),
                        if (!isStock) ...[
                          const SizedBox(height: 2),
                          ValueListenableBuilder<bool>(
                            valueListenable: PasscodeService.instance.isLocked,
                            builder: (context, isLocked, child) {
                              if (isLocked) return const SizedBox.shrink();
                              double profitVal = double.tryParse(item.profit.replaceAll(',', '')) ?? 0;
                              return Text(
                                "Profit: UGX ${_formatter.format(profitVal)}",
                                style: GoogleFonts.outfit(fontSize: 11, color: AppColors.neutralMutedText, fontWeight: FontWeight.w500),
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
        SnackBar(content: Text('Searching for MPT-II printer...', style: GoogleFonts.outfit()), duration: const Duration(seconds: 2)),
      );

      final itemsList = await DatabaseHelper.instance.getReceiptItems(item.id!);

      if (itemsList.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Receipt details not found', style: GoogleFonts.outfit())),
          );
        }
        return;
      }

      await PrinterService.instance.printInvoice(item.customer, itemsList);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.accentRed,
            content: Text('Printing Failed: ${e.toString().replaceAll("Exception: ", "")}', style: GoogleFonts.outfit()),
            action: SnackBarAction(label: 'Retry', textColor: Colors.white, onPressed: () => _reprintInvoice(item)),
          ),
        );
      }
    }
  }

  void _confirmDeletion(HistoryItem item) async {
    if (!PasscodeService.instance.hasPasscode) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const PasscodeSetupScreen()),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final bool verified = await PasscodeDialog.show(
      context,
      reason: "Confirm authorization to delete transaction",
    );

    if (verified) {
      await DatabaseHelper.instance.deleteHistoryItem(item.id!);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Transaction deleted successfully', style: GoogleFonts.outfit()),
            backgroundColor: AppColors.primaryGreen,
          ),
        );
        _loadHistory();
      }
    } else {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: AppColors.accentRed,
            content: Text('Verification failed or canceled. Deletion aborted.', style: GoogleFonts.outfit()),
          ),
        );
      }
    }
  }

  void _showPaymentModal(HistoryItem item) {
    double amountVal = double.tryParse(item.amount.replaceAll(',', '')) ?? 0;
    double paidAmountVal = double.tryParse(item.paidAmount.replaceAll(',', '')) ?? 0;
    double remainingAmount = amountVal - paidAmountVal;

    final payController = TextEditingController(text: remainingAmount.toStringAsFixed(0));
    final passcodeController = TextEditingController();
    bool isVerifyingPasscode = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 24,
                left: 24,
                right: 24,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Record Debt Payment",
                    style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Customer: ${item.customer}",
                    style: GoogleFonts.outfit(color: AppColors.neutralMutedText, fontSize: 13),
                  ),
                  const SizedBox(height: 16),

                  if (!isVerifyingPasscode) ...[
                    Text(
                      "Remaining Debt: UGX ${_formatter.format(remainingAmount)}",
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFFD97706), fontSize: 15),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: payController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: "Payment Amount (UGX)",
                        labelStyle: GoogleFonts.outfit(color: const Color(0xFF64748B)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          double pVal = DatabaseHelper.instance.extractNumericValue(payController.text);
                          if (pVal <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Enter a valid payment amount", style: GoogleFonts.outfit())),
                            );
                            return;
                          }
                          if (pVal > remainingAmount) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Payment exceeds remaining debt", style: GoogleFonts.outfit())),
                            );
                            return;
                          }
                          setModalState(() {
                            isVerifyingPasscode = true;
                          });
                        },
                        child: Text("Proceed to Verify Passcode", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                      ),
                    ),
                  ] else ...[
                    Text(
                      "Security Verification",
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: passcodeController,
                      obscureText: true,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.outfit(fontSize: 15),
                      decoration: InputDecoration(
                        labelText: "Enter Passcode to Confirm Payment",
                        labelStyle: GoogleFonts.outfit(color: const Color(0xFF64748B)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => setModalState(() => isVerifyingPasscode = false),
                            child: Text("Back", style: GoogleFonts.outfit(color: Colors.grey, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryGreen,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () async {
                              String enteredPass = passcodeController.text.trim();
                              bool isValid = await PasscodeService.instance.verifyPasscode(enteredPass);

                              if (isValid) {
                                double pVal = DatabaseHelper.instance.extractNumericValue(payController.text);

                                await DatabaseHelper.instance.markDebtAsPaid(
                                  item.customer,
                                  pVal,
                                );

                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Payment recorded successfully', style: GoogleFonts.outfit())),
                                  );
                                  _loadHistory();
                                }
                              } else {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: AppColors.accentRed,
                                      content: Text('Incorrect passcode. Payment aborted.', style: GoogleFonts.outfit()),
                                    ),
                                  );
                                }
                              }
                            },
                            child: Text("Confirm Payment", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class TransactionItem {
  final String size;
  final String itemName;
  final String quantityStr;
  final String priceStr;
  final String amountStr;
  final String rawQtyVal;
  final String rawUnitLabel;

  TransactionItem({
    required this.size,
    required this.itemName,
    required this.quantityStr,
    required this.priceStr,
    required this.amountStr,
    this.rawQtyVal = '',
    this.rawUnitLabel = '',
  });
}
