import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/history_item.dart';
import '../services/database_helper.dart';
import '../utils/colors.dart';

class DebtHistoryScreen extends StatefulWidget {
  const DebtHistoryScreen({super.key});

  @override
  State<DebtHistoryScreen> createState() => _DebtHistoryScreenState();
}

class _DebtHistoryScreenState extends State<DebtHistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<HistoryItem> _allDebts = [];
  List<HistoryItem> _filteredDebts = [];
  bool _isLoading = true;
  final _formatter = NumberFormat("#,###");
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDebts();
  }

  Future<void> _loadDebts() async {
    setState(() => _isLoading = true);
    final debts = await DatabaseHelper.instance.getHistory("DEBTS");
    // We also want settled debts, so we might need a different filter or fetch all and filter locally
    final allHistory = await DatabaseHelper.instance.getHistory("ALL");
    final settledDebts = allHistory.where((i) => i.isDebt && i.isPaid).toList();
    
    if (mounted) {
      setState(() {
        _allDebts = [...debts, ...settledDebts];
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

  double get _totalRemainingDebt {
    return _allDebts.where((d) => !d.isPaid).fold(0, (sum, d) {
      double total = double.tryParse(d.amount.replaceAll(',', '')) ?? 0;
      double paid = double.tryParse(d.paidAmount.replaceAll(',', '')) ?? 0;
      return sum + (total - paid);
    });
  }

  int get _debtorCount {
    return _allDebts.where((d) => !d.isPaid).map((d) => d.customer).toSet().length;
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
        onChanged: (val) {
          _searchQuery = val;
          _applyFilters();
        },
        decoration: InputDecoration(
          hintText: 'Search customer or item...',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(debt.customer, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(debt.date, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            Text(debt.item, style: const TextStyle(color: Color(0xFF374151), fontSize: 13)),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildAmountInfo('Total', total, Colors.black),
                _buildAmountInfo('Paid', paid, AppColors.primaryGreen),
                _buildAmountInfo('Balance', remaining, remaining > 0 ? Colors.red : Colors.grey),
              ],
            ),
            if (!debt.isPaid) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _showPayDebtDialog(debt),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('Record Payment'),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildAmountInfo(String label, double amount, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 2),
        Text('UGX ${_formatter.format(amount)}', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
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
              
              await DatabaseHelper.instance.markSaleAsPaid(debt.id!, payment);
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
}
