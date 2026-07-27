import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/colors.dart';

enum TransactionType { sale, newStock }

class SuccessItemSummary {
  final String name;
  final String quantity;
  final String unit;
  final double price;
  final double amount;
  final bool isDebt;

  SuccessItemSummary({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.price,
    required this.amount,
    this.isDebt = false,
  });
}

class TransactionSuccessDialog extends StatefulWidget {
  final TransactionType type;
  final String receiptId;
  final String partyName;
  final double totalAmount;
  final int totalItemsCount;
  final List<SuccessItemSummary> items;
  final Future<void> Function()? onPrint;
  final VoidCallback? onDone;
  final VoidCallback? onViewHistory;

  const TransactionSuccessDialog({
    super.key,
    required this.type,
    required this.receiptId,
    required this.partyName,
    required this.totalAmount,
    required this.totalItemsCount,
    required this.items,
    this.onPrint,
    this.onDone,
    this.onViewHistory,
  });

  static Future<void> show(
    BuildContext context, {
    required TransactionType type,
    required String receiptId,
    required String partyName,
    required double totalAmount,
    required int totalItemsCount,
    required List<SuccessItemSummary> items,
    Future<void> Function()? onPrint,
    VoidCallback? onDone,
    VoidCallback? onViewHistory,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => TransactionSuccessDialog(
        type: type,
        receiptId: receiptId,
        partyName: partyName,
        totalAmount: totalAmount,
        totalItemsCount: totalItemsCount,
        items: items,
        onPrint: onPrint,
        onDone: onDone,
        onViewHistory: onViewHistory,
      ),
    );
  }

  @override
  State<TransactionSuccessDialog> createState() => _TransactionSuccessDialogState();
}

class _TransactionSuccessDialogState extends State<TransactionSuccessDialog> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  final NumberFormat _formatter = NumberFormat("#,###");
  bool _isPrinting = false;
  bool _printedSuccess = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  bool get _isSale => widget.type == TransactionType.sale;

  Future<void> _handlePrint() async {
    if (widget.onPrint == null || _isPrinting) return;
    setState(() {
      _isPrinting = true;
    });
    try {
      await widget.onPrint!();
      if (mounted) {
        setState(() {
          _printedSuccess = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Printing failed: ${e.toString().replaceAll('Exception: ', '')}"),
            backgroundColor: AppColors.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPrinting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = _isSale ? AppColors.primaryGreen : AppColors.accentBlue;
    final formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());
    final displayReceiptId = widget.receiptId.length > 8
        ? widget.receiptId.substring(0, 8).toUpperCase()
        : widget.receiptId.toUpperCase();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 12,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: themeColor.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Gradient Section with Icon
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 28, bottom: 20, left: 20, right: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      themeColor.withValues(alpha: 0.08),
                      themeColor.withValues(alpha: 0.02),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    // Animated Badge Circle
                    ScaleTransition(
                      scale: _scaleAnim,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: _isSale
                                ? [AppColors.primaryGreen, AppColors.darkGreen]
                                : [AppColors.accentBlue, const Color(0xFF1E40AF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: themeColor.withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Title
                    Text(
                      _isSale ? 'Sale Completed!' : 'Stock Saved Successfully!',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    // Subtitle & Ref ID Pill
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: themeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.tag, size: 12, color: themeColor),
                              const SizedBox(width: 2),
                              Text(
                                displayReceiptId,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: themeColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formattedDate,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Content Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    children: [
                      // Total Amount Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _isSale ? 'TOTAL AMOUNT PAID' : 'TOTAL STOCK VALUE',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textSecondary,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'UGX ${_formatter.format(widget.totalAmount)}',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: themeColor,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Divider(height: 1),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildDetailChip(
                                  icon: _isSale ? Icons.person_outline : Icons.local_shipping_outlined,
                                  label: _isSale ? 'Customer' : 'Supplier',
                                  value: widget.partyName.isEmpty
                                      ? (_isSale ? 'Walk-in Customer' : 'General Supplier')
                                      : widget.partyName,
                                ),
                                _buildDetailChip(
                                  icon: Icons.inventory_2_outlined,
                                  label: 'Items',
                                  value: '${widget.totalItemsCount} ${widget.totalItemsCount == 1 ? 'Item' : 'Items'}',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Items Breakdown List
                      if (widget.items.isNotEmpty) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Item Summary (${widget.items.length})',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: widget.items.length,
                            separatorBuilder: (context, index) => const Divider(height: 1, indent: 12, endIndent: 12),
                            itemBuilder: (context, index) {
                              final item = widget.items[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: themeColor.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        _isSale ? Icons.shopping_bag_outlined : Icons.add_box_outlined,
                                        size: 16,
                                        color: themeColor,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item.name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                    color: AppColors.textPrimary,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (item.isDebt) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.accentAmber.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Text(
                                                    'DEBT',
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.bold,
                                                      color: AppColors.accentAmber,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${item.quantity} ${item.unit} • @ UGX ${_formatter.format(item.price)}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'UGX ${_formatter.format(item.amount)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Action Buttons Section
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    if (widget.onPrint != null) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isPrinting ? null : _handlePrint,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _printedSuccess ? Colors.blueGrey.shade800 : AppColors.textPrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          icon: _isPrinting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Icon(
                                  _printedSuccess ? Icons.check_circle_outlined : Icons.print_rounded,
                                  size: 20,
                                ),
                          label: Text(
                            _isPrinting
                                ? 'Printing Receipt...'
                                : (_printedSuccess ? 'Printed Successfully' : 'Print Thermal Receipt'),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    Row(
                      children: [
                        if (widget.onViewHistory != null)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                widget.onViewHistory?.call();
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                              icon: const Icon(Icons.history, size: 18, color: AppColors.textSecondary),
                              label: const Text(
                                "History",
                                style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        if (widget.onViewHistory != null) const SizedBox(width: 10),
                        Expanded(
                          flex: widget.onViewHistory != null ? 1 : 2,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onDone?.call();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: themeColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 2,
                            ),
                            icon: const Icon(Icons.add_circle_outline, size: 18),
                            label: Text(
                              _isSale ? "New Sale" : "Add More Stock",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailChip({required IconData icon, required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
