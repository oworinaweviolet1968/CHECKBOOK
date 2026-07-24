import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/colors.dart';
import '../widgets/stat_card.dart';
import '../widgets/stock_tile_redesigned.dart';
import '../widgets/sale_tile_redesigned.dart';
import '../widgets/common_app_bar_actions.dart';
import '../screens/login_screen.dart';
import '../services/database_helper.dart';
import '../services/supabase_service.dart';
import '../services/passcode_service.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  late Future<double> _totalStockValue;
  late Future<double> _weeklyProfit;
  late Future<Map<String, double>> _todaysStats;
  late Future<List<Map<String, dynamic>>> _availableStock;
  late Future<List<Map<String, dynamic>>> _todaysSales;
  
  // New Futures for % change
  late Future<double> _yesterdaysProfit;
  late Future<double> _prevWeeklyProfit;

  bool _showAllStock = false;

  final _formatter = NumberFormat("#,###");

  @override
  void initState() {
    super.initState();
    refreshData();
  }

  void refreshData() {
    PasscodeService.instance.lock();
    setState(() {
      _totalStockValue = DatabaseHelper.instance.getTotalStockValue();
      _weeklyProfit = DatabaseHelper.instance.getWeeklyProfit();
      _todaysStats = DatabaseHelper.instance.getTodaysStats();
      _availableStock = DatabaseHelper.instance.cleanupZombieStock().then((_) => DatabaseHelper.instance.getAvailableStock());
      _todaysSales = DatabaseHelper.instance.getTodaysSalesList();
      
      _yesterdaysProfit = DatabaseHelper.instance.getYesterdaysProfit();
      _prevWeeklyProfit = DatabaseHelper.instance.getPrevWeeklyProfit();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
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
              child: Text(
                'Checkbook',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: -0.5,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white.withValues(alpha: 0.8),
        elevation: 0,
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(color: AppColors.primaryGreen.withValues(alpha: 0.1), height: 1)
        ),
        actions: [
          StandardAppBarActions(onRefresh: refreshData),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
            refreshData();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 80),
          child: Column(
             crossAxisAlignment: CrossAxisAlignment.stretch,
             children: [
                 Padding(
                     padding: const EdgeInsets.all(16),
                     child: ValueListenableBuilder<bool>(
                       valueListenable: PasscodeService.instance.isLocked,
                       builder: (context, isLocked, child) {
                         if (isLocked) {
                           return _buildLockedPlaceholder();
                         }
                         
                         return LayoutBuilder(
                             builder: (context, constraints) {
                                 bool isWide = constraints.maxWidth > 800;
                                 
                                 final card1 = FutureBuilder<double>(
                                    future: _totalStockValue,
                                    builder: (ctx, snap) => _buildSummaryCard(
                                        "Total Stock Value", 
                                        snap.data ?? 0.0, 
                                        0, 
                                        true
                                    ),
                                 );
                                 
                                 final card2 = FutureBuilder<double>(
                                    future: _weeklyProfit,
                                    builder: (ctx, snap) {
                                        final current = snap.data ?? 0.0;
                                        return FutureBuilder<double>(
                                            future: _prevWeeklyProfit,
                                            builder: (ctx2, snap2) {
                                                final prev = snap2.data ?? 0.0;
                                                return _buildSummaryCard(
                                                    "Weekly Profit", 
                                                    current, 
                                                    prev, 
                                                    true
                                                );
                                            }
                                        );
                                    }
                                 );
                                 
                                 final card3 = FutureBuilder<Map<String, double>>(
                                    future: _todaysStats,
                                    builder: (ctx, snap) {
                                        final profit = snap.data?['profit'] ?? 0.0;
                                        return FutureBuilder<double>(
                                            future: _yesterdaysProfit,
                                            builder: (ctx2, snap2) {
                                                final yesterday = snap2.data ?? 0.0;
                                                return _buildSummaryCard(
                                                    "Today's Profit", 
                                                    profit, 
                                                    yesterday, 
                                                    true
                                                );
                                            }
                                        );
                                    }
                                 );

                                 if (isWide) {
                                     return Row(
                                         children: [
                                             Expanded(child: card1),
                                             const SizedBox(width: 16),
                                             Expanded(child: card2),
                                             const SizedBox(width: 16),
                                             Expanded(child: card3),
                                         ],
                                     );
                                 } else {
                                     return Column(
                                         children: [
                                             card1,
                                             const SizedBox(height: 12),
                                             card2,
                                             const SizedBox(height: 12),
                                             card3,
                                         ],
                                     );
                                 }
                             }
                         );
                       },
                     ),
                 ),
                 
                 Padding(
                     padding: const EdgeInsets.symmetric(horizontal: 16),
                     child: Row(
                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
                         children: [
                             Flexible(
                               child: Row(
                                 mainAxisSize: MainAxisSize.min,
                               children: [
                                 const Flexible(
                                   child: Text(
                                     "In Stock Inventory", 
                                     overflow: TextOverflow.ellipsis,
                                     style: TextStyle(
                                         fontSize: 18, 
                                         fontWeight: FontWeight.bold, 
                                         color: AppColors.textPrimary
                                     ),
                                   ),
                                 ),
                                 const SizedBox(width: 8),
                                 ValueListenableBuilder<SyncStatus>(
                                   valueListenable: SupasService.instance.syncStatus,
                                   builder: (context, status, child) {
                                     Color color = Colors.grey;
                                     IconData icon = Icons.cloud_off;
                                     String label = "Offline";

                                     switch (status) {
                                       case SyncStatus.syncing:
                                         color = Colors.blue;
                                         icon = Icons.sync;
                                         label = "Syncing...";
                                         break;
                                       case SyncStatus.synced:
                                         color = AppColors.primaryGreen;
                                         icon = Icons.cloud_done;
                                         label = "Synced";
                                         break;
                                       case SyncStatus.error:
                                         color = Colors.orange;
                                         icon = Icons.cloud_off;
                                         label = "Offline";
                                         break;
                                       case SyncStatus.offline:
                                         color = Colors.orange;
                                         icon = Icons.cloud_off;
                                         label = "Not Backed Up";
                                         break;
                                       case SyncStatus.idle:
                                         color = Colors.grey;
                                         icon = Icons.cloud_queue;
                                         label = "Idle";
                                         break;
                                     }

                                     return Container(
                                       padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                       decoration: BoxDecoration(
                                         color: color.withValues(alpha: 0.1),
                                         borderRadius: BorderRadius.circular(4),
                                         border: Border.all(color: color.withValues(alpha: 0.2)),
                                       ),
                                       child: Row(
                                         mainAxisSize: MainAxisSize.min,
                                         children: [
                                           Icon(icon, size: 10, color: color),
                                           const SizedBox(width: 4),
                                           Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color)),
                                         ],
                                       ),
                                     );
                                   },
                                  ),
                                ],
                              ),
                            ),
                             IconButton(
                                 onPressed: () {
                                     setState(() {
                                         _showAllStock = !_showAllStock;
                                     });
                                 },
                                 icon: Icon(
                                   _showAllStock ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, 
                                   color: AppColors.primaryGreen,
                                   size: 20,
                                 ),
                                 tooltip: _showAllStock ? "Show Less" : "View All",
                                 padding: EdgeInsets.zero,
                                 constraints: const BoxConstraints(),
                             )



                         ],
                     ),
                 ),
                 
                 Padding(
                   padding: const EdgeInsets.symmetric(horizontal: 16),
                   child: Container(
                     decoration: BoxDecoration(
                         color: Colors.white,
                         borderRadius: BorderRadius.circular(12),
                         border: Border.all(color: Colors.grey.shade100),
                         boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5)],
                     ),
                     child: FutureBuilder<List<Map<String, dynamic>>>(
                         future: _availableStock,
                         builder: (context, snapshot) {
                             if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                             final list = snapshot.data!;
                             if (list.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text("No stock available"));
                             
                             final displayList = _showAllStock ? list : list.take(5).toList();
                             
                             return Column(
                                 children: displayList.map((item) {
                                     String size = item['quantity'];
                                     double avail = (item['available_pieces'] as num).toDouble();
                                     double price = (item['price'] as num).toDouble();
                                     
                                     bool isLow = avail < 12;
                                     double multiplier = DatabaseHelper.instance.getUnitMultiplier(item['unit'] ?? "pcs", size);
                                     double unitPrice = price * multiplier;
                                     
                                     String displayAvail = DatabaseHelper.instance.formatStockForDisplay(
                                         avail, 
                                         item['unit'] ?? "pcs", 
                                         size
                                     );

                                     return StockTileRedesigned(
                                         itemName: item['item'], 
                                         itemSize: "Size: $size", 
                                         price: "UGX ${_formatter.format(unitPrice)} / ${item['unit'] ?? 'pc'}", 
                                         quantity: displayAvail,
                                         isLowStock: isLow,
                                         isEdited: (item['is_edited'] as int? ?? 0) == 1,
                                         source: item['device_source'] as String? ?? "System",
                                     );
                                 }).toList(),
                             );
                         }
                     ),
                   ),
                 ),
                 
                 const SizedBox(height: 24),
                 
                 Padding(
                     padding: const EdgeInsets.symmetric(horizontal: 16),
                     child: Row(
                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
                         children: [
                             Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                 const Text("Today's Sales Log", style: TextStyle(
                                     fontSize: 18, 
                                     fontWeight: FontWeight.bold, 
                                     color: AppColors.textPrimary
                                 )),
                                  FutureBuilder<Map<String, double>>(
                                   future: _todaysStats,
                                   builder: (context, snap) {
                                     final total = snap.data?['sales'] ?? 0.0;
                                     final debt = snap.data?['debt'] ?? 0.0;
                                     return Column(
                                       crossAxisAlignment: CrossAxisAlignment.start,
                                       children: [
                                         Text(
                                           "Total: UGX ${_formatter.format(total)}",
                                           style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryGreen),
                                         ),
                                         if (debt > 0)
                                           Text(
                                             "Debt: UGX ${_formatter.format(debt)}",
                                             style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red),
                                           ),
                                       ],
                                     );
                                   },
                                 ),
                               ],
                             ),
                             Container(
                                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                 decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                                 child: Text(DateTime.now().toIso8601String().split('T')[0], style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                             )
                         ],
                     ),
                 ),
                 const SizedBox(height: 12),
                 
                 Padding(
                     padding: const EdgeInsets.symmetric(horizontal: 16),
                     child: FutureBuilder<List<Map<String, dynamic>>>(
                         future: _todaysSales,
                         builder: (context, snapshot) {
                             if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                             final list = snapshot.data!;
                             if (list.isEmpty) return const Text("No sales today", style: TextStyle(color: AppColors.textSecondary));
                             
                             return Column(
                                 children: list.map((sale) {
                                     final profit = (sale['amount'] as num) - ((sale['cost_price'] as num) * (sale['base_quantity'] as num));
                                     final amount = (sale['amount'] as num).toDouble();
                                     
                                     final orderId = sale['id'];
                                     
                                     String timeStr = "";
                                     try {
                                         String rawDate = sale['created_at'].toString();
                                         if (rawDate.contains(' ')) {
                                             timeStr = rawDate.split(' ')[1];
                                         } else if (rawDate.contains('T')) {
                                             timeStr = rawDate.split('T')[1];
                                         } else {
                                             timeStr = rawDate;
                                         }
                                         if (timeStr.length > 5 && (timeStr.contains(':'))) {
                                             timeStr = timeStr.substring(0, 5);
                                         }
                                     } catch (e) {
                                         timeStr = "";
                                     }
                                     final time = timeStr;
                                     
                                     final unitSold = sale['unit']; 
                                     final isDebt = (sale['is_debt'] as int? ?? 0) == 1;
                                                                          return ValueListenableBuilder<bool>(
                                         valueListenable: PasscodeService.instance.isLocked,
                                         builder: (context, isLocked, child) {
                                             return SaleTileRedesigned(
                                                 customer: "$unitSold x ${sale['item']}", 
                                                 orderInfo: "Order #$orderId • $time",
                                                 amount: "UGX ${_formatter.format(amount)}",
                                                 profit: isLocked ? "" : "Profit: UGX ${_formatter.format(profit)}",
                                                 source: sale['device_source'] as String? ?? "System",
                                                 isPositiveProfit: profit >= 0,
                                                 isDebt: isDebt,
                                             );
                                         },
                                      );
                                 }).toList(),
                             );
                         }
                     ),
                 ),
             ], 
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, double current, double previous, bool isPositiveTrendGood) {
      double diff = current - previous;
      double percent = 0.0;
      if (previous > 0) {
          percent = (diff / previous) * 100;
      } else if (current > 0) {
          percent = 100.0;
      }
      
      String sign = percent >= 0 ? "+" : "";
      
      return StatCard(
          title: title, 
          value: "UGX ${_formatter.format(current)}", 
          percentage: "$sign${percent.toStringAsFixed(1)}%", 
          isPositive: percent >= 0
      );
  }

  Widget _buildLockedPlaceholder() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
            child: Icon(Icons.visibility_off_outlined, color: Colors.grey.shade400, size: 32),
          ),
          const SizedBox(height: 16),
          const Text(
            'Passcode required',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          const Text(
            'Metrics are hidden for security',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _showPasscodeDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: const Text('Unlock View', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showPasscodeDialog() {
    final controller = TextEditingController();
    String? errorMessage;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Enter Passcode'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: true,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 10),
                decoration: const InputDecoration(border: OutlineInputBorder(), counterText: ""),
                onChanged: (_) {
                  if (errorMessage != null) setModalState(() => errorMessage = null);
                },
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                bool success = await PasscodeService.instance.verifyPasscode(controller.text);
                if (mounted) {
                  if (success) {
                    Navigator.pop(context);
                  } else {
                    setModalState(() => errorMessage = "Incorrect Passcode!");
                  }
                }
              },
              child: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }
}
