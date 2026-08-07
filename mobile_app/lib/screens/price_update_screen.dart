import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';
import '../services/supabase_service.dart';
import '../services/audit_service.dart';
import '../services/notification_service.dart';
import '../utils/colors.dart';

class PriceUpdateScreen extends StatefulWidget {
  final String? highlightQuery;
  const PriceUpdateScreen({super.key, this.highlightQuery});

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
    if (widget.highlightQuery != null && widget.highlightQuery!.isNotEmpty) {
      _searchController.text = widget.highlightQuery!;
    }
    _loadStock();
  }

  Future<void> _loadStock() async {
    final data = await DatabaseHelper.instance.getAvailableStock();
    if (mounted) {
      setState(() {
        _allStock = data;
        _isLoading = false;
      });
      if (_searchController.text.isNotEmpty) {
        _filterStock(_searchController.text);
      } else {
        setState(() {
          _filteredStock = data;
        });
      }
    }
  }

  void _filterStock(String query) {
    setState(() {
      final terms = query
          .split(',')
          .map((t) => t.trim().toLowerCase())
          .where((t) => t.isNotEmpty)
          .toList();

      _filteredStock = _allStock.where((item) {
        final name = item['item']?.toString().toLowerCase() ?? "";
        final size = item['quantity']?.toString().toLowerCase() ?? "";
        return terms.isEmpty || terms.any((q) => name.contains(q) || size.contains(q));
      }).toList();
    });
  }

  // Modern Security Verification & Edit Price Dialog
  void _showEditPriceDialog(Map<String, dynamic> item) {
    final String unitLabel = item['unit'] ?? "pcs";
    final String size = item['quantity'] ?? "";
    final double multiplier = DatabaseHelper.instance.getUnitMultiplier(unitLabel, size);
    final double currentPiecePrice = (item['price'] as num).toDouble();
    final double currentUnitPrice = currentPiecePrice * multiplier;

    final priceController = TextEditingController(text: currentUnitPrice.toInt().toString());

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top centered security badge
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: AppColors.lightCyan,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    color: AppColors.primaryGreen,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  "Security Verification",
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  "${item['item'] ?? 'Update Price'} (${unitLabel.toUpperCase()})",
                  style: GoogleFonts.outfit(
                    color: AppColors.neutralMutedText,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                autofocus: true,
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Price for 1 $unitLabel (UGX)',
                  labelStyle: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF64748B)),
                  prefixText: 'UGX ',
                  prefixStyle: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.neutralBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.outfit(color: const Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final newUnitPrice = double.tryParse(priceController.text);
                        if (newUnitPrice != null) {
                          final newPiecePrice = newUnitPrice / (multiplier > 0 ? multiplier : 1);
                          await DatabaseHelper.instance.updateItemPrice(item['id'], newPiecePrice);
                          try {
                            await AuditService.instance.logAction(
                              action: 'REPRICING',
                              details: {
                                'item': item['item'],
                                'unit': unitLabel,
                                'old_price': item['price'],
                                'new_unit_price': newUnitPrice,
                                'new_piece_price': newPiecePrice,
                              },
                            );
                            await NotificationService.instance.notify(
                              title: 'Repricing Alert',
                              body: 'Updated price for ${item['item']} to UGX ${newUnitPrice.toStringAsFixed(0)} ($unitLabel)',
                              type: 'REPRICING',
                            );
                          } catch (e) {
                            debugPrint('Error logging repricing audit/notification: $e');
                          }
                          SupasService.instance.uploadDatabase();

                          if (context.mounted) {
                            Navigator.pop(dialogContext);
                            _loadStock();
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Price updated successfully', style: GoogleFonts.outfit()),
                                backgroundColor: AppColors.primaryGreen,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('Update Price', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Compact Multiplier Packaging Chip Widget
  Widget _buildUnitChipWidget(String unitLabel) {
    String text = unitLabel.toLowerCase();

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
          Text(
            text,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF00A389),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Price Update / Repricing',
          style: GoogleFonts.outfit(
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
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: TextField(
              controller: _searchController,
              onChanged: _filterStock,
              style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF334155)),
              decoration: InputDecoration(
                hintText: 'Search items or sizes...',
                hintStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8), size: 20),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.neutralBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.neutralBorder),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
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
                            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              _allStock.isEmpty ? 'No stock items found' : 'No items match your search',
                              style: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 15),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
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

                          final String itemName = item['item']?.toString() ?? "Unknown Item";
                          final bool isHighlighted = _searchController.text.isNotEmpty &&
                              itemName.toLowerCase().contains(_searchController.text.toLowerCase());

                          return Container(
                            decoration: BoxDecoration(
                              color: isHighlighted ? AppColors.primaryGreen.withValues(alpha: 0.08) : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: isHighlighted ? AppColors.primaryGreen.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.03),
                                  blurRadius: isHighlighted ? 12 : 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                              border: Border.all(
                                color: isHighlighted ? AppColors.primaryGreen : AppColors.neutralBorder,
                                width: isHighlighted ? 2.5 : 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                            'HIGHLIGHTED ITEM',
                                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),

                                  // Header Row: Item Name (left) & Device Badge (right)
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          itemName,
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: AppColors.textPrimary,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: (source.toLowerCase() == 'mobile' ? const Color(0xFFEFF6FF) : const Color(0xFFF3F4F6)),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          source.toUpperCase(),
                                          style: GoogleFonts.outfit(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: (source.toLowerCase() == 'mobile' ? const Color(0xFF1E40AF) : const Color(0xFF374151)),
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  // Price & Packaging Row (left) & Edit Button (right)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Wrap(
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          spacing: 8,
                                          runSpacing: 6,
                                          children: [
                                            if (size.isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF1F5F9),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  size,
                                                  style: GoogleFonts.outfit(color: const Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.w600),
                                                ),
                                              ),
                                            _buildUnitChipWidget(unitLabel),
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                'UGX ${_formatter.format(currentUnitPrice)}',
                                                style: GoogleFonts.outfit(
                                                  color: AppColors.primaryGreen,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      InkWell(
                                        onTap: () => _showEditPriceDialog(item),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: AppColors.lightCyan,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Icon(Icons.edit_outlined, color: AppColors.primaryGreen, size: 20),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
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
