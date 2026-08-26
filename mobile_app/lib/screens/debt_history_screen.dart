import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/history_item.dart';
import '../services/database_helper.dart';
import '../services/printer_service.dart';
import '../services/supabase_service.dart';
import '../utils/colors.dart';

class DebtHistoryScreen extends StatefulWidget {
  final int initialIndex;
  final String? highlightQuery;
  const DebtHistoryScreen({super.key, this.initialIndex = 0, this.highlightQuery});

  @override
  State<DebtHistoryScreen> createState() => _DebtHistoryScreenState();
}

class _DebtHistoryScreenState extends State<DebtHistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  List<HistoryItem> _allDebts = [];
  List<HistoryItem> _filteredDebts = [];
  bool _isLoading = true;
  final _formatter = NumberFormat("#,###");
  String _searchQuery = "";
  double _totalRemainingDebt = 0.0;
  int _debtorCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialIndex);
    if (widget.highlightQuery != null && widget.highlightQuery!.isNotEmpty) {
      _searchQuery = widget.highlightQuery!;
      _searchController.text = widget.highlightQuery!;
    }
    SupasService.instance.syncStatus.addListener(_onSyncStatusChanged);
    _loadDebts();
  }

  @override
  void dispose() {
    SupasService.instance.syncStatus.removeListener(_onSyncStatusChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSyncStatusChanged() {
    if (SupasService.instance.syncStatus.value == SyncStatus.synced) {
      _loadDebts(showLoading: false);
    }
  }

  Future<void> _loadDebts({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
    final debts = await DatabaseHelper.instance.getHistory("DEBTS");
    final settledDebts = await DatabaseHelper.instance.getSettledDebts();

    final dbCount = await DatabaseHelper.instance.getDebtorCount();
    final dbTotalDebt = await DatabaseHelper.instance.getTotalOutstandingDebt();

    if (mounted) {
      if (_searchQuery.isNotEmpty) {
        final qLower = _searchQuery.toLowerCase();
        bool hasUnsettled = debts.any((d) => d.customer.toLowerCase().contains(qLower) || d.item.toLowerCase().contains(qLower));
        bool hasPaid = settledDebts.any((d) => d.customer.toLowerCase().contains(qLower) || d.item.toLowerCase().contains(qLower));
        if (!hasUnsettled && hasPaid) {
          _tabController.index = 1;
        }
      }

      setState(() {
        _allDebts = [...debts, ...settledDebts];
        _allDebts.removeWhere((item) => item.customer == "Walk-in Customer");
        _debtorCount = dbCount;
        _totalRemainingDebt = dbTotalDebt;
        _applyFilters();
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    setState(() {
      final terms = _searchQuery
          .split(',')
          .map((t) => t.trim().toLowerCase())
          .where((t) => t.isNotEmpty)
          .toList();

      _filteredDebts = _allDebts.where((d) {
        final matchesSearch = terms.isEmpty || terms.any((q) =>
            d.customer.toLowerCase().contains(q) ||
            d.item.toLowerCase().contains(q));

        if (_tabController.index == 0) {
          return matchesSearch && !d.isPaid;
        } else {
          return matchesSearch && d.isPaid;
        }
      }).toList();
    });
  }

  String _formatDisplayDate(String dateStr) {
    try {
      final parsed = DateTime.parse(dateStr);
      return DateFormat('MMM d, yyyy').format(parsed);
    } catch (e) {
      return dateStr;
    }
  }

  String _formatAmountNum(String amtStr) {
    if (amtStr.isEmpty) return "0";
    double val = double.tryParse(amtStr.replaceAll(',', '')) ?? 0;
    return _formatter.format(val);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Debt History', style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primaryGreen,
          unselectedLabelColor: const Color(0xFF64748B),
          indicatorColor: AppColors.primaryGreen,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
          unselectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
          onTap: (_) => _applyFilters(),
          tabs: const [
            Tab(text: 'Unsettled'),
            Tab(text: 'Paid Off'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildSummaryHeader(),
          _buildSearchField(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
                : _filteredDebts.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredDebts.length,
                        itemBuilder: (context, index) => _buildDebtCard(_filteredDebts[index]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
          _buildSummaryCard(
            'Total Debt',
            'UGX ${_formatter.format(_totalRemainingDebt)}',
            Icons.account_balance_wallet,
            const Color(0xFFDC2626),
          ),
          const SizedBox(width: 12),
          _buildSummaryCard(
            'Debtors',
            '$_debtorCount People',
            Icons.people,
            AppColors.primaryGreen,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(title, style: GoogleFonts.outfit(color: color.withValues(alpha: 0.85), fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: GoogleFonts.outfit(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchController,
        onChanged: (val) {
          _searchQuery = val;
          _applyFilters();
        },
        style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF334155)),
        decoration: InputDecoration(
          hintText: 'Search customer or item...',
          hintStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 13),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8), size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _searchQuery = "";
                    _applyFilters();
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.neutralBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.neutralBorder),
          ),
        ),
      ),
    );
  }

  // Parse raw debt item log string into clean structured items
  List<ParsedDebtLine> _parseDebtLogLines(String itemText) {
    final List<ParsedDebtLine> parsedList = [];

    final String normalizedItem = itemText
        .replaceAll('\\n', '\n')
        .replaceAll(r'\n', '\n');

    List<String> rawLines = [];
    if (normalizedItem.contains('\n')) {
      rawLines = normalizedItem.split('\n');
    } else if (normalizedItem.contains('),')) {
      final parts = normalizedItem.split('),');
      rawLines = parts.asMap().entries.map((e) {
        final idx = e.key;
        final val = e.value.trim();
        if (idx < parts.length - 1 && !val.endsWith(')')) {
          return '$val)';
        }
        return val;
      }).toList();
    } else {
      rawLines = [normalizedItem];
    }

    for (var line in rawLines) {
      if (line.trim().isEmpty) continue;

      String dateStr = '';
      String workingLine = line.trim();

      // Extract date string inside parentheses if present (e.g. "(2026-07-29)")
      final dateMatch = RegExp(r'\(([\d\-]+)\)$').firstMatch(workingLine);
      if (dateMatch != null) {
        dateStr = dateMatch.group(1)!;
        workingLine = workingLine.substring(0, dateMatch.start).trim();
      }

      final atSplit = workingLine.split('@');
      if (atSplit.length < 2) {
        parsedList.add(ParsedDebtLine(
          itemName: workingLine,
          rawQtyVal: '',
          rawUnitLabel: '',
          priceStr: '',
          amountStr: '',
          dateStr: dateStr,
        ));
        continue;
      }

      final beforeAt = atSplit[0].trim();
      final afterAt = atSplit[1].trim();

      final equalSplit = afterAt.split('=');
      final priceStr = equalSplit[0].trim();
      final amountStr = equalSplit.length > 1 ? equalSplit[1].trim() : '';

      final words = beforeAt.split(RegExp(r'\s+'));
      String qtyVal = '';
      String unitLabel = '';
      int itemStartIndex = 0;

      if (words.isNotEmpty) {
        final firstWord = words[0];
        final isPureNumeric = RegExp(r'^\d+(\.\d+)?$').hasMatch(firstWord);

        if (isPureNumeric) {
          qtyVal = firstWord;
          itemStartIndex = 1;
        } else {
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
              }
            }
          } else if (nextWord == 'half' && words.length > (itemStartIndex + 1) &&
              (words[itemStartIndex + 1].toLowerCase().startsWith('doz') || words[itemStartIndex + 1].toLowerCase().startsWith('dozen'))) {
            unitLabel = 'half doz';
            itemStartIndex += 2;
          }
        }
      }

      final itemName = words.length > itemStartIndex
          ? words.sublist(itemStartIndex).join(' ')
          : beforeAt;

      parsedList.add(ParsedDebtLine(
        itemName: itemName,
        rawQtyVal: qtyVal,
        rawUnitLabel: unitLabel,
        priceStr: priceStr,
        amountStr: amountStr,
        dateStr: dateStr,
      ));
    }

    return parsedList;
  }

  // Compact Multiplier Packaging Chip Widget (e.g. [ 8 • 📦 box*12 ], [ 8 • 📦 pcs ])
  Widget _buildUnitChipWidget(String qtyVal, String unitLabel) {
    String formattedQty = '';
    if (qtyVal.trim().isNotEmpty) {
      double? val = double.tryParse(qtyVal.trim());
      if (val != null) {
        if (val == val.roundToDouble()) {
          formattedQty = val.toInt().toString();
        } else {
          String s = val.toString();
          if (s.contains('.')) {
            s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
          }
          formattedQty = s;
        }
      } else {
        formattedQty = qtyVal.trim();
      }
    }

    String unitText;
    String u = unitLabel.toLowerCase().replaceAll(' ', '');

    if (u.isEmpty || u == 'pcs' || u == 'pc') {
      unitText = (formattedQty == '1') ? 'pc' : 'pcs';
    } else if (u.contains('halfdoz')) {
      unitText = 'half doz';
    } else if (u.contains('box*')) {
      final match = RegExp(r'box\*\d+').firstMatch(u);
      if (match != null) {
        unitText = match.group(0)!;
      } else {
        unitText = unitLabel.toLowerCase();
      }
    } else {
      unitText = unitLabel.toLowerCase();
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
          if (formattedQty.isNotEmpty) ...[
            Text(
              '$formattedQty • ',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF00A389),
              ),
            ),
          ],
          const Icon(Icons.inventory_2_outlined, size: 13, color: Color(0xFF00A389)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              unitText,
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

  Widget _buildDebtCard(HistoryItem debt) {
    double total = double.tryParse(debt.amount.replaceAll(',', '')) ?? 0;
    double paid = double.tryParse(debt.paidAmount.replaceAll(',', '')) ?? 0;
    double remaining = total - paid;
    bool isPaid = debt.isPaid || remaining <= 0;

    final bool isHighlighted = _searchQuery.isNotEmpty &&
        (debt.customer.toLowerCase().contains(_searchQuery.toLowerCase()) ||
         debt.item.toLowerCase().contains(_searchQuery.toLowerCase()));

    final Color statusColor = isPaid ? AppColors.primaryGreen : const Color(0xFFDC2626);
    final Color statusBgColor = isPaid ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2);
    final Color bgColor = isHighlighted
        ? AppColors.primaryGreen.withValues(alpha: 0.08)
        : (isPaid ? const Color(0xFFF0FDF4) : const Color(0xFFFFF7F7));

    String initial = debt.customer.trim().isNotEmpty ? debt.customer.trim()[0].toUpperCase() : '?';
    final parsedLines = _parseDebtLogLines(debt.item);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isHighlighted ? AppColors.primaryGreen : statusColor.withValues(alpha: 0.25),
          width: isHighlighted ? 2.5 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isHighlighted
                ? AppColors.primaryGreen.withValues(alpha: 0.25)
                : statusColor.withValues(alpha: 0.06),
            blurRadius: isHighlighted ? 14 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left status bar indicator
              Container(
                width: 6,
                color: isHighlighted ? AppColors.primaryGreen : statusColor,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isHighlighted)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
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

                      // Top Row: Avatar + Customer Name + Status Badge + Date & Print
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: statusColor.withValues(alpha: 0.15),
                            child: Text(
                              initial,
                              style: GoogleFonts.outfit(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        debt.customer,
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: AppColors.textPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: statusBgColor,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isPaid ? 'PAID OFF' : 'UNSETTLED',
                                        style: GoogleFonts.outfit(
                                          color: statusColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _formatDisplayDate(debt.date),
                                  style: GoogleFonts.outfit(color: const Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.print_outlined, color: AppColors.primaryGreen, size: 20),
                            onPressed: () => _reprintInvoice(debt),
                            tooltip: 'Print Receipt',
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Clean & Formatted Purchased Items Breakdown
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.neutralBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.shopping_bag_outlined, size: 16, color: Color(0xFF64748B)),
                                const SizedBox(width: 8),
                                Text(
                                  parsedLines.length > 1
                                      ? 'Purchased Items (${parsedLines.length})'
                                      : 'Purchased Item',
                                  style: GoogleFonts.outfit(
                                    color: const Color(0xFF475569),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ...List.generate(parsedLines.length, (index) {
                              final pl = parsedLines[index];
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Line 1: Item Name
                                  Text(
                                    pl.itemName,
                                    style: GoogleFonts.outfit(
                                      color: const Color(0xFF0F172A),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),

                                  // Line 2: [ Badge ] on Left, Unit Price @ UGX X on Right
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      if (pl.rawQtyVal.isNotEmpty || pl.rawUnitLabel.isNotEmpty)
                                        Flexible(
                                          child: _buildUnitChipWidget(pl.rawQtyVal, pl.rawUnitLabel),
                                        )
                                      else
                                        const SizedBox.shrink(),
                                      if (pl.priceStr.isNotEmpty)
                                        Flexible(
                                          child: Text(
                                            "@ UGX ${_formatAmountNum(pl.priceStr)}",
                                            style: GoogleFonts.outfit(
                                              color: const Color(0xFF64748B),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),

                                  // Line 3: Total Line Price = UGX Y
                                  if (pl.amountStr.isNotEmpty)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          "= UGX ${_formatAmountNum(pl.amountStr)}",
                                          style: GoogleFonts.outfit(
                                            color: AppColors.primaryGreen,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),

                                  if (pl.dateStr.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatDisplayDate(pl.dateStr),
                                      style: GoogleFonts.outfit(
                                        color: const Color(0xFF94A3B8),
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                  if (index < parsedLines.length - 1)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                                      child: const Divider(
                                        height: 1,
                                        thickness: 0.6,
                                        color: AppColors.neutralBorder,
                                      ),
                                    ),
                                ],
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Redesigned 3-Column Financial Summary Grid
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.neutralBorder),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildSummaryMetric(
                                label: 'Total',
                                amount: total,
                                labelColor: const Color(0xFF64748B),
                                amountColor: const Color(0xFF475569),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Container(width: 1, height: 32, color: AppColors.neutralBorder),
                            Expanded(
                              child: _buildSummaryMetric(
                                label: 'Paid',
                                amount: paid,
                                labelColor: const Color(0xFF10B981),
                                amountColor: const Color(0xFF10B981),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Container(width: 1, height: 32, color: AppColors.neutralBorder),
                            Expanded(
                              child: _buildSummaryMetric(
                                label: 'Balance',
                                amount: remaining,
                                labelColor: const Color(0xFFDC2626),
                                amountColor: remaining > 0 ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (!isPaid) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _showPayDebtDialog(debt),
                            icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                            label: Text('Record Payment', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryMetric({
    required String label,
    required double amount,
    required Color labelColor,
    required Color amountColor,
    required FontWeight fontWeight,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(color: labelColor, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'UGX ${_formatter.format(amount)}',
              style: GoogleFonts.outfit(color: amountColor, fontWeight: fontWeight, fontSize: 13),
              maxLines: 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_turned_in_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No ${_tabController.index == 0 ? "unsettled" : "settled"} debts found',
            style: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 16),
          ),
        ],
      ),
    );
  }

  void _showPayDebtDialog(HistoryItem debt) {
    final controller = TextEditingController();
    double total = double.tryParse(debt.amount.replaceAll(',', '')) ?? 0;
    double paid = double.tryParse(debt.paidAmount.replaceAll(',', '')) ?? 0;
    double remaining = total - paid;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Record Payment', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Customer: ${debt.customer}', style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Text(
              'Remaining Balance: UGX ${_formatter.format(remaining)}',
              style: GoogleFonts.outfit(color: const Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.outfit(fontSize: 15),
              decoration: InputDecoration(
                labelText: 'Amount Paid (UGX)',
                labelStyle: GoogleFonts.outfit(color: const Color(0xFF64748B)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () async {
              double payment = double.tryParse(controller.text) ?? 0;
              if (payment <= 0) return;

              await DatabaseHelper.instance.markDebtAsPaid(debt.customer, payment);
              SupasService.instance.syncDatabase();
              if (context.mounted) {
                Navigator.pop(context);
                _loadDebts();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Payment recorded successfully', style: GoogleFonts.outfit()), backgroundColor: AppColors.primaryGreen),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Save Payment', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
        ],
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
        throw Exception("Could not find items for this receipt.");
      }

      await PrinterService.instance.printInvoice(
        item.customer,
        itemsList,
        date: item.date,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.accentRed,
            content: Text('Reprint Failed: ${e.toString().replaceAll("Exception: ", "")}', style: GoogleFonts.outfit()),
          ),
        );
      }
    }
  }
}

class ParsedDebtLine {
  final String itemName;
  final String rawQtyVal;
  final String rawUnitLabel;
  final String priceStr;
  final String amountStr;
  final String dateStr;

  ParsedDebtLine({
    required this.itemName,
    required this.rawQtyVal,
    required this.rawUnitLabel,
    required this.priceStr,
    required this.amountStr,
    required this.dateStr,
  });
}
