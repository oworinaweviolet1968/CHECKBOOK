import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/supabase_service.dart';
import '../utils/colors.dart';
import 'package:intl/intl.dart';

class PriceUpdateScreen extends StatefulWidget {
  const PriceUpdateScreen({super.key});

  @override
  State<PriceUpdateScreen> createState() => _PriceUpdateScreenState();
}

class _PriceUpdateScreenState extends State<PriceUpdateScreen> {
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _formatter = NumberFormat("#,###");
  List<Map<String, dynamic>> _allStock = [];
  List<Map<String, dynamic>> _filteredStock = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStock();
  }

  Future<void> _loadStock() async {
    final data = await DatabaseHelper.instance.getAvailableStock();
    if (mounted) {
      setState(() {
        _allStock = data;
        _filteredStock = data;
        _isLoading = false;
      });
    }
  }

  void _filterStock(String query) {
    setState(() {
      _filteredStock = _allStock.where((item) {
        final name = item['item']?.toString().toLowerCase() ?? "";
        final size = item['quantity']?.toString().toLowerCase() ?? "";
        return name.contains(query.toLowerCase()) || size.contains(query.toLowerCase());
      }).toList();
    });
  }

  void _showEditPriceDialog(Map<String, dynamic> item) {
    final String unitLabel = item['unit'] ?? "pcs";
    final String size = item['quantity'] ?? "";
    final double multiplier = DatabaseHelper.instance.getUnitMultiplier(unitLabel, size);
    final double currentPiecePrice = (item['price'] as num).toDouble();
    final double currentUnitPrice = currentPiecePrice * multiplier;

    final priceController = TextEditingController(text: currentUnitPrice.toInt().toString());
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item['item'] ?? "Update Price", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 4),
            Text('Editing price for: $unitLabel', style: const TextStyle(color: AppColors.primaryGreen, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        content: TextField(
          controller: priceController,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          autofocus: true,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            labelText: 'Total Price for 1 $unitLabel (UGX)',
            labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixText: 'UGX ',
            floatingLabelBehavior: FloatingLabelBehavior.always,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newUnitPrice = double.tryParse(priceController.text);
              if (newUnitPrice != null) {
                // Calculate new per-piece price
                final newPiecePrice = newUnitPrice / (multiplier > 0 ? multiplier : 1);
                await DatabaseHelper.instance.updateItemPrice(item['id'], newPiecePrice);
                // Trigger background upload
                SupasService.instance.uploadDatabase();
                
                if (mounted) {
                  Navigator.pop(context);
                  _loadStock();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Price updated successfully'),
                      backgroundColor: AppColors.primaryGreen,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text('Update Price', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Price Update / Repricing',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: TextField(
              controller: _searchController,
              onChanged: _filterStock,
              decoration: InputDecoration(
                hintText: 'Search items or sizes...',
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                prefixIcon: const Icon(Icons.search, color: AppColors.primaryGreen, size: 20),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
                : _filteredStock.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade200),
                            const SizedBox(height: 16),
                            Text(
                              _allStock.isEmpty ? 'No stock items found' : 'No items match your search',
                              style: const TextStyle(color: Colors.grey, fontSize: 15),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: _filteredStock.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = _filteredStock[index];
                          final String unitLabel = item['unit'] ?? "pcs";
                          final String size = item['quantity'] ?? "";
                          final double multiplier = DatabaseHelper.instance.getUnitMultiplier(unitLabel, size);
                          final double currentPiecePrice = (item['price'] as num).toDouble();
                          final double currentUnitPrice = currentPiecePrice * multiplier;
                          final String source = item['device_source'] as String? ?? 'System';

                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                              border: Border.all(color: Colors.grey.shade100),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                              title: Row(
                                children: [
                                  Text(
                                    item['item'] ?? "Unknown Item",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: AppColors.textPrimary,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  if (true) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: (source.toLowerCase() == 'mobile' ? Colors.blue : Colors.grey).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: (source.toLowerCase() == 'mobile' ? Colors.blue : Colors.grey).withValues(alpha: 0.2)),
                                      ),
                                      child: Text(
                                        source.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                          color: (source.toLowerCase() == 'mobile' ? Colors.blue : Colors.grey),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          item['quantity'] ?? "-",
                                          style: TextStyle(color: Colors.grey.shade700, fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'UGX ${_formatter.format(currentUnitPrice)} / $unitLabel',
                                        style: const TextStyle(
                                          color: AppColors.primaryGreen,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: Material(
                                color: AppColors.primaryGreen.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  onTap: () => _showEditPriceDialog(item),
                                  borderRadius: BorderRadius.circular(12),
                                  child: const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: Icon(Icons.edit_rounded, color: AppColors.primaryGreen, size: 20),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
