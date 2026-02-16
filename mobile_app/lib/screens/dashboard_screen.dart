import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/colors.dart';
import '../widgets/stat_card.dart';
import '../widgets/stock_tile_redesigned.dart';
import '../widgets/sale_tile_redesigned.dart';
import '../screens/login_screen.dart';
import '../services/database_helper.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<double> _totalStockValue;
  late Future<double> _yearlyProfit;
  late Future<Map<String, double>> _todaysStats;
  late Future<List<Map<String, dynamic>>> _availableStock;
  late Future<List<Map<String, dynamic>>> _todaysSales;
  
  // New Futures for % change
  late Future<double> _yesterdaysProfit;
  late Future<double> _prevYearProfit;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  void _refreshData() {
    setState(() {
      _totalStockValue = DatabaseHelper.instance.getTotalStockValue();
      _yearlyProfit = DatabaseHelper.instance.getYearlyProfit();
      _todaysStats = DatabaseHelper.instance.getTodaysStats();
      _availableStock = DatabaseHelper.instance.getAvailableStock();
      _todaysSales = DatabaseHelper.instance.getTodaysSalesList();
      
      _yesterdaysProfit = DatabaseHelper.instance.getYesterdaysProfit();
      _prevYearProfit = DatabaseHelper.instance.getPrevYearProfit();
    });
  }

  void _logout() async {
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
      }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // Custom Header imitating the HTML one
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.inventory_2, color: AppColors.primaryGreen, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'StockFlow',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white.withValues(alpha: 0.8), // Backdrop blur simulated
        elevation: 0,
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(color: AppColors.primaryGreen.withValues(alpha: 0.1), height: 1)
        ),
        actions: [
            // Notifications Icon
            Stack(
                alignment: Alignment.center,
                children: [
                    IconButton(
                        icon: const Icon(Icons.notifications_outlined, color: AppColors.textSecondary),
                        onPressed: () {},
                    ),
                    Positioned(
                        top: 12,
                        right: 12,
                        child: Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white, width: 1.5))),
                    )
                ],
            ),
            const SizedBox(width: 8),
            // Profile Pic
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'logout') _logout();
              },
              itemBuilder: (BuildContext context) {
                return [
                  const PopupMenuItem<String>(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Text('Logout'),
                      ],
                    ),
                  ),
                ];
              },
              child: Container(
                  margin: const EdgeInsets.only(right: 16),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.person, size: 20, color: AppColors.primaryGreen), 
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
            _refreshData();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 80), // for bottom nav space
          child: Column(
             crossAxisAlignment: CrossAxisAlignment.stretch,
             children: [
                 // Summary Cards Section
                 Padding(
                     padding: const EdgeInsets.all(16),
                     child: LayoutBuilder(
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
                                future: _yearlyProfit,
                                builder: (ctx, snap) {
                                    final current = snap.data ?? 0.0;
                                    return FutureBuilder<double>(
                                        future: _prevYearProfit,
                                        builder: (ctx2, snap2) {
                                            final prev = snap2.data ?? 0.0;
                                            return _buildSummaryCard(
                                                "Yearly Profit", 
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
                     ),
                 ),
                 
                 // In Stock Inventory Section
                 Padding(
                     padding: const EdgeInsets.symmetric(horizontal: 16),
                     child: Row(
                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
                         children: [
                             const Text("In Stock Inventory", style: TextStyle(
                                 fontSize: 18, 
                                 fontWeight: FontWeight.bold, 
                                 color: AppColors.textPrimary
                             )),
                             TextButton(
                                 onPressed: () {
                                     // Navigate to View All logic
                                 },
                                 child: const Text("View All", style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w600)),
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
                             
                             final displayList = list.take(5).toList();
                             
                             return Column(
                                 children: displayList.map((item) {
                                     String size = item['quantity'];
                                     double avail = (item['available_pieces'] as num).toDouble();
                                     double price = (item['price'] as num).toDouble();
                                     
                                     bool isLow = avail < 12;
                                     
                                     String displayAvail = "${avail.toInt()} pcs";
                                      if (size.toLowerCase().contains("kg")) {
                                            double sizeVal = DatabaseHelper.instance.extractNumericValue(size);
                                            if (sizeVal > 0) {
                                                displayAvail = "${avail.toStringAsFixed(1)} kg";
                                            }
                                      }

                                     return StockTileRedesigned(
                                         itemName: item['item'], 
                                         itemSize: "Size: $size", 
                                         price: "UGX ${price.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}", 
                                         quantity: displayAvail,
                                         isLowStock: isLow,
                                     );
                                 }).toList(),
                             );
                         }
                     ),
                   ),
                 ),
                 
                 const SizedBox(height: 24),
                 
                 // Today's Sales Log Section
                 Padding(
                     padding: const EdgeInsets.symmetric(horizontal: 16),
                     child: Row(
                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
                         children: [
                             const Text("Today's Sales Log", style: TextStyle(
                                 fontSize: 18, 
                                 fontWeight: FontWeight.bold, 
                                 color: AppColors.textPrimary
                             )),
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
                                     final time = sale['created_at'].toString().split(' ')[1].substring(0, 5); 
                                     
                                     // Use 'unit' (e.g. 2 pcs) instead of 'quantity' (e.g. Size M)
                                     final unitSold = sale['unit']; 
                                     
                                     return SaleTileRedesigned(
                                         customer: "$unitSold x ${sale['item']}", 
                                         orderInfo: "Order #$orderId • $time",
                                         amount: "UGX ${amount.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}",
                                         profit: "Profit: UGX ${profit.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}",
                                         isPositiveProfit: profit >= 0,
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

  // Helper to build Summary Card with % calc
  Widget _buildSummaryCard(String title, double current, double previous, bool isPositiveTrendGood) {
      double diff = current - previous;
      double percent = 0.0;
      if (previous > 0) {
          percent = (diff / previous) * 100;
      } else if (current > 0) {
          percent = 100.0; // New income
      }
      
      String sign = percent >= 0 ? "+" : "";
      
      return StatCard(
          title: title, 
          value: "UGX ${current.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}", 
          percentage: "$sign${percent.toStringAsFixed(1)}%", 
          isPositive: percent >= 0
      );
  }
}
