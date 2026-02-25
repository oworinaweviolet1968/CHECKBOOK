import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; 
import '../models/history_item.dart';
import '../services/database_helper.dart';
import '../services/passcode_service.dart';
import '../utils/colors.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
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
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabSelection);
    _loadHistory();
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

  Future<void> _loadHistory() async {
      setState(() => _isLoading = true);
      // Fetch ALL filtered items from DB initially? Or just fetch everything and filter locally?
      // "ALL" fetches everything.
      final items = await DatabaseHelper.instance.getHistory("ALL");
      if (mounted) {
          setState(() {
              _allItems = items;
              _applyFilters();
              _isLoading = false;
          });
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
          final q = _searchQuery.toLowerCase();
          temp = temp.where((i) {
             return i.item.toLowerCase().contains(q) || 
                    i.customer.toLowerCase().contains(q);
          }).toList();
      }

      // 3. Date Filter
      if (_selectedDate != null) {
          // item.date is String YYYY-MM-DD
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

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
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
                     const Text("Transaction History", style: TextStyle(
                         color: Color(0xFF111827), // text-primary-light
                         fontSize: 20, 
                         fontWeight: FontWeight.bold
                     )),
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
                                         color: _selectedDate != null ? AppColors.primaryGreen.withOpacity(0.1) : Colors.white,
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
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _filteredItems.length,
                separatorBuilder: (c, i) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                    return _buildHistoryCard(_filteredItems[index]);
                },
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

  Widget _buildHistoryCard(HistoryItem item) {
      // Determine Type style
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
           // Fallback/Default
           badgeBg = const Color(0xFFF3F4F6);
           badgeText = const Color(0xFF374151);
      }
      
      bool isStock = (typeLabel == 'NEW STOCK');

      return Container(
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade100),
              boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))
              ]
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (item.isDebt && !item.isPaid) {
                    _showPaymentModal(item);
                }
              }, // Detail view?
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    children: [
                        // Top Row: Date & Badge
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                                Text(item.date, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))), // text-secondary
                                Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: badgeBg,
                                        borderRadius: BorderRadius.circular(4)
                                    ),
                                    child: Text(
                                        typeLabel, 
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeText, letterSpacing: 0.5)
                                    ),
                                )
                            ],
                        ),
                        const SizedBox(height: 12),
                        
                        // Middle Row: Item & Amount
                        Row(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                                 Expanded(
                                     child: Column(
                                         crossAxisAlignment: CrossAxisAlignment.start,
                                         children: [
                                             Text(
                                                 item.item, 
                                                 style: const TextStyle(
                                                     fontWeight: FontWeight.bold, 
                                                     fontSize: 16, 
                                                     color: Color(0xFF111827) // text-primary
                                                 )
                                             ),
                                             const SizedBox(height: 4),
                                             Text(
                                                 "${item.quantity} ${item.unit}", 
                                                 style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))
                                             ),
                                              const SizedBox(height: 4),
                                             Text(
                                                 isStock ? "Supplier: ${item.customer}" : "Customer: ${item.customer}",
                                                 style: const TextStyle(
                                                     fontSize: 12, 
                                                     fontStyle: FontStyle.italic, 
                                                     color: Color(0xFF9CA3AF)
                                                 )
                                             ),
                                         ],
                                     ),
                                 ),
                                 Column(
                                     crossAxisAlignment: CrossAxisAlignment.end,
                                     children: [
                                          Text(
                                              "UGX ${_formatter.format(double.tryParse(item.amount.replaceAll(',', '')) ?? 0)}", 
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold, 
                                                  fontSize: 16,
                                                  color: isStock ? const Color(0xFFEA580C) : const Color(0xFF10B981) 
                                              )
                                          ),
                                           if (!isStock) ...[
                                               const SizedBox(height: 4),
                                               ValueListenableBuilder<bool>(
                                                 valueListenable: PasscodeService.instance.isLocked,
                                                 builder: (context, isLocked, child) {
                                                   if (isLocked) return const SizedBox.shrink();
                                                   return Text(
                                                       "Profit: ${_formatter.format(double.tryParse(item.profit.replaceAll(',', '')) ?? 0)}", 
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

  void _showPaymentModal(HistoryItem item) {
      final amountController = TextEditingController();
      final passcodeController = TextEditingController();
      bool isVerifyingPasscode = false;

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
                          
                          Text("Total Debt: UGX ${_formatter.format(double.tryParse(item.amount) ?? 0)}", 
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
                                      double total = double.tryParse(item.amount) ?? 0;
                                      if (entered == total) {
                                          setModalState(() => isVerifyingPasscode = true);
                                      } else {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text("Amount must equal the total debt amount."))
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
                              const Text("Enter Passcode to Confirm Payment", style: TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 12),
                              TextField(
                                  controller: passcodeController,
                                  obscureText: true,
                                  keyboardType: TextInputType.number,
                                  maxLength: 4,
                                  decoration: InputDecoration(
                                      labelText: "Passcode",
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      counterText: "",
                                  ),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                  onPressed: () async {
                                      final pc = passcodeController.text;
                                      final isValid = await PasscodeService.instance.verifyPasscode(pc);
                                      
                                      if (isValid && pc.isNotEmpty) {
                                          if (item.id != null) {
                                              await DatabaseHelper.instance.markSaleAsPaid(item.id!);
                                              Navigator.pop(context); // Close modal
                                              _loadHistory(); // Refresh list
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text("Payment Confirmed! Debt settled."))
                                              );
                                          }
                                      } else {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text("Incorrect Passcode!"), backgroundColor: Colors.red)
                                          );
                                      }
                                  },
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange.shade700,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text("Confirm Payment", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
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
