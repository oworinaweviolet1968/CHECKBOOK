import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/history_item.dart';
import '../services/database_helper.dart';
import '../services/supabase_service.dart';
import '../utils/colors.dart';

class DeletedHistoryScreen extends StatefulWidget {
  final String? highlightQuery;
  const DeletedHistoryScreen({super.key, this.highlightQuery});

  @override
  State<DeletedHistoryScreen> createState() => _DeletedHistoryScreenState();
}

class _DeletedHistoryScreenState extends State<DeletedHistoryScreen> {
  List<HistoryItem> _allDeletedItems = [];
  List<HistoryItem> _filteredItems = [];
  bool _isLoading = true;
  final _formatter = NumberFormat("#,###");

  // Filters
  String _searchQuery = "";
  DateTime? _selectedDate;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.highlightQuery != null && widget.highlightQuery!.isNotEmpty) {
      _searchQuery = widget.highlightQuery!;
      _searchController.text = widget.highlightQuery!;
    }
    _loadDeletedHistory();
  }

  Future<void> _loadDeletedHistory() async {
    setState(() => _isLoading = true);
    try {
      final items = await DatabaseHelper.instance.getDeletedHistory();
      if (mounted) {
        setState(() {
          _allDeletedItems = items;
          _applyFilters();
        });
      }
    } catch (e) {
      print("Error loading deleted history: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilters() {
    List<HistoryItem> temp = _allDeletedItems;

    // 1. Search Filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      temp = temp.where((i) {
        return i.item.toLowerCase().contains(q) || i.customer.toLowerCase().contains(q);
      }).toList();
    }

    // 2. Date Filter (by deletion date)
    if (_selectedDate != null) {
      String filterDate = _selectedDate!.toIso8601String().split('T')[0];
      temp = temp.where((i) {
        if (i.deletedAt == null) return false;
        return i.deletedAt!.startsWith(filterDate);
      }).toList();
    }

    setState(() {
      _filteredItems = temp;
    });
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
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _applyFilters();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 120,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Deleted History",
          style: TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: "Search item or name",
                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                        prefixIcon: Icon(Icons.search, color: Colors.grey[400], size: 20),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _pickDate,
                  child: Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: _selectedDate != null ? AppColors.primaryGreen.withOpacity(0.1) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _selectedDate != null ? AppColors.primaryGreen : Colors.grey.shade200,
                      ),
                    ),
                    child: Icon(
                      Icons.calendar_today_outlined,
                      color: _selectedDate != null ? AppColors.primaryGreen : Colors.grey[500],
                      size: 20,
                    ),
                  ),
                ),
                if (_selectedDate != null)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red, size: 20),
                    onPressed: () => setState(() {
                      _selectedDate = null;
                      _applyFilters();
                    }),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredItems.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filteredItems.length,
                  separatorBuilder: (c, i) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    return _buildDeletedCard(_filteredItems[index]);
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.delete_sweep_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text("No deleted history found", style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildDeletedCard(HistoryItem item) {
    Color badgeBg = Colors.grey[100]!;
    Color badgeText = Colors.grey[800]!;
    String typeLabel = item.type.toUpperCase();

    if (typeLabel == 'NEW STOCK') {
      badgeBg = const Color(0xFFFFEDD5);
      badgeText = const Color(0xFF9A3412);
    } else {
      badgeBg = const Color(0xFFF3F4F6);
      badgeText = const Color(0xFF374151);
    }

    bool isStock = (typeLabel == 'NEW STOCK');
    
    // Age check
    bool isOld = false;
    if (item.deletedAt != null) {
      try {
        DateTime deletedTime = DateTime.parse(item.deletedAt!);
        isOld = DateTime.now().difference(deletedTime).inDays >= 4;
      } catch (e) {
        // Ignore parsing errors
      }
    }

    final bool isHighlighted = _searchQuery.isNotEmpty &&
        (item.customer.toLowerCase().contains(_searchQuery.toLowerCase()) ||
         item.item.toLowerCase().contains(_searchQuery.toLowerCase()));

    return Container(
      decoration: BoxDecoration(
          color: isHighlighted
              ? Colors.red.withOpacity(0.08)
              : (isOld ? const Color(0xFFFFF1F2) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isHighlighted ? Colors.red : (isOld ? Colors.red.withOpacity(0.2) : Colors.grey.shade100),
            width: isHighlighted ? 2.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isHighlighted ? Colors.red.withOpacity(0.3) : Colors.black.withOpacity(0.02),
              blurRadius: isHighlighted ? 12 : 4,
              offset: const Offset(0, 2),
            )
          ]),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (isHighlighted)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star, color: Colors.white, size: 12),
                    SizedBox(width: 4),
                    Text(
                      'HIGHLIGHTED DELETED ITEM',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Tx Date: ${item.date}", style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                    if (item.deletedAt != null)
                      Text("Deleted: ${item.deletedAt!.split('.')[0].replaceFirst('T', ' ')}", 
                           style: TextStyle(fontSize: 10, color: isOld ? Colors.red : Colors.grey[500])),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(4)),
                  child: Text(typeLabel,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeText, letterSpacing: 0.5)),
                )
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.item,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF111827))),
                      const SizedBox(height: 4),
                      Text("${item.quantity} ${item.unit}", style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                      const SizedBox(height: 4),
                      Text(isStock ? "Supplier: ${item.customer}" : "Customer: ${item.customer}",
                          style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF9CA3AF))),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("UGX ${_formatter.format(double.tryParse(item.amount.replaceAll(',', '')) ?? 0)}",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isStock ? const Color(0xFFEA580C) : const Color(0xFF10B981))),
                    const SizedBox(height: 4),
                    const Text("DELETED", style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                )
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _confirmRestore(item),
                  icon: const Icon(Icons.restore, size: 16, color: AppColors.primaryGreen),
                  label: const Text("Restore to History", style: TextStyle(fontSize: 12, color: AppColors.primaryGreen)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primaryGreen),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRestore(HistoryItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Restore Transaction"),
        content: Text("Do you want to restore '${item.item}' back to active history and stock?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen),
            child: const Text("Restore", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && item.id != null) {
      try {
        await DatabaseHelper.instance.restoreDeletedHistoryItem(item.id!);
        await SupasService.instance.uploadDatabase();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Transaction restored to active history and stock."),
              backgroundColor: AppColors.primaryGreen,
            ),
          );
          _loadDeletedHistory();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error restoring item: $e"), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}
