import 'package:flutter/material.dart';
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
      _filteredDebts = _allDebts.where((d) {
        final matchesSearch = d.customer.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                            d.item.toLowerCase().contains(_searchQuery.toLowerCase());
        
        if (_tabController.index == 0) {
          return matchesSearch && !d.isPaid;
        } else {
          return matchesSearch && d.isPaid;
        }
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('Debt History', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primaryGreen,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.primaryGreen,
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
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        children: [
          _buildSummaryCard(
            'Total Debt',
            'UGX ${_formatter.format(_totalRemainingDebt)}',
            Icons.account_balance_wallet,
            Colors.red,
          ),
          const SizedBox(width: 16),
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: TextField(
        controller: _searchController,
        onChanged: (val) {
          _searchQuery = val;
          _applyFilters();
        },
        decoration: InputDecoration(
          hintText: 'Search customer or item...',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
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
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
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

    final Color statusColor = isPaid ? AppColors.primaryGreen : const Color(0xFFEF4444);
    final Color bgColor = isHighlighted 
        ? AppColors.primaryGreen.withValues(alpha: 0.08) 
        : (isPaid ? const Color(0xFFF0FDF4) : const Color(0xFFFFF7F7));

    String initial = debt.customer.trim().isNotEmpty ? debt.customer.trim()[0].toUpperCase() : '?';

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
              // Left status indicator bar
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
                      // Top Row: Avatar + Customer Name + Status Badge + Date & Print
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: statusColor.withValues(alpha: 0.15),
                            child: Text(
                              initial,
                              style: TextStyle(
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
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: AppColors.textPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isPaid ? 'PAID OFF' : 'UNSETTLED',
                                        style: TextStyle(
                                          color: statusColor,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  debt.date,
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
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

                      // Item Details Card with Spaced Debt Lines
                      Builder(builder: (context) {
                        // Normalize literal '\n' or '\\n' text into actual line breaks
                        final String normalizedItem = debt.item
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

                        final List<String> itemLines = rawLines
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList();
                        final List<String> displayLines = itemLines.isNotEmpty ? itemLines : [normalizedItem];

                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.shopping_bag_outlined, size: 16, color: Colors.grey.shade600),
                                  const SizedBox(width: 8),
                                  Text(
                                    displayLines.length > 1
                                        ? 'Purchased Items (${displayLines.length})'
                                        : 'Purchased Item',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ...List.generate(displayLines.length, (index) {
                                final line = displayLines[index];
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                                      child: Text(
                                        line,
                                        style: const TextStyle(
                                          color: Color(0xFF374151),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          height: 1.45,
                                        ),
                                      ),
                                    ),
                                    if (index < displayLines.length - 1)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                                        child: Divider(
                                          height: 1,
                                          thickness: 0.6,
                                          color: Colors.grey.withValues(alpha: 0.2),
                                        ),
                                      ),
                                  ],
                                );
                              }),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 14),

                      // Metrics Row (Total, Paid, Balance)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                        ),
                        child: Row(
                          children: [
                            Expanded(child: _buildAmountInfo('Total Debt', total, Colors.black87)),
                            Container(width: 1, height: 28, color: Colors.grey.shade200),
                            Expanded(child: _buildAmountInfo('Amount Paid', paid, AppColors.primaryGreen)),
                            Container(width: 1, height: 28, color: Colors.grey.shade200),
                            Expanded(child: _buildAmountInfo('Balance', remaining, remaining > 0 ? const Color(0xFFEF4444) : Colors.grey)),
                          ],
                        ),
                      ),

                      if (!isPaid) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _showPayDebtDialog(debt),
                            icon: const Icon(Icons.payments_outlined, size: 18),
                            label: const Text('Record Payment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
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

  Widget _buildAmountInfo(String label, double amount, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w500)),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'UGX ${_formatter.format(amount)}',
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
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
          Text('No ${_tabController.index == 0 ? "unsettled" : "settled"} debts found', 
            style: const TextStyle(color: Colors.grey, fontSize: 16)),
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
        title: const Text('Record Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Customer: ${debt.customer}'),
            const SizedBox(height: 8),
            Text('Remaining Balance: UGX ${_formatter.format(remaining)}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Amount Paid (UGX)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              double payment = double.tryParse(controller.text) ?? 0;
              if (payment <= 0) return;
              
              await DatabaseHelper.instance.markDebtAsPaid(debt.customer, payment);
              // Trigger cloud sync to immediately upload the payment
              SupasService.instance.syncDatabase();
              if (mounted) {
                Navigator.pop(context);
                _loadDebts();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Payment recorded successfully'), backgroundColor: AppColors.primaryGreen),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen, foregroundColor: Colors.white),
            child: const Text('Save Payment'),
          ),
        ],
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
        itemsList,
        date: item.date
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
}
