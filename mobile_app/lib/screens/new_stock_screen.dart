import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../utils/colors.dart';
import '../utils/formatters.dart';
import '../services/database_helper.dart';
import '../services/supabase_service.dart';
import '../services/audit_service.dart';
import '../models/stock_item.dart';
import '../widgets/common_app_bar_actions.dart';
import '../widgets/transaction_success_dialog.dart';
import '../widgets/processing_loading_dialog.dart';

class NewStockScreen extends StatefulWidget {
  const NewStockScreen({super.key});

  @override
  State<NewStockScreen> createState() => _NewStockScreenState();
}

class _NewStockScreenState extends State<NewStockScreen> {
  // Controllers
  final _supplierController = TextEditingController();
  final _itemController = TextEditingController();
  final _qtyController = TextEditingController(); // Size
  final _unitController = TextEditingController(); // Count
  final _priceController = TextEditingController();

  // State
  final List<StockItem> _items = [];
  List<String> _availableItems = [];
  List<String> _availableSizes = [];
  List<String> _recentSuppliers = [];

  String? _selectedItem;
  String? _selectedSize;

  bool _isNewSize = false;
  bool _isPriceLocked = false;
  String _selectedUnitLabel = "pcs"; // e.g. "Box", "Sack"
  String _totalPiecesSuffix = "pcs"; // e.g. "72 pcs"

  static const String _addNewSizeOption = "__NEW_SIZE__";

  final _formatter = NumberFormat("#,###");

  // Data for Quick Buttons
  final List<String> _qtyQuickButtons = ["None", "g", "kg", "ml", "l", "inch", "50kg", "25kg", "10kg"];
  final List<Map<String, String>> _unitQuickButtons = [
    {"label": "1 pc", "value": "pcs"},
    {"label": "Sack", "value": "Sack"},
    {"label": "6 pcs", "value": "half doz"},
    {"label": "10 pcs", "value": "box*10"},
    {"label": "12 pcs", "value": "box*12"},
    {"label": "20 pcs", "value": "box*20"},
    {"label": "24 pcs", "value": "box*24"},
    {"label": "25 pcs", "value": "crate"},
    {"label": "72 pcs", "value": "box*72"},
  ];

  @override
  void initState() {
    super.initState();
    _loadItems();
    _loadRecentSuppliers();
    _unitController.addListener(_updatePieceCount);
    _itemController.addListener(_onItemChanged);
    _qtyController.addListener(() => setState(() {})); // Trigger rebuild for unit button filtering
  }

  void _onItemChanged() {
    String current = _itemController.text.trim();
    if (_availableItems.contains(current)) {
      if (_selectedItem != current) {
        setState(() {
          _selectedItem = current;
          _loadSizes(current);
        });
      }
    } else {
      if (_selectedItem != null) {
        setState(() {
          _selectedItem = null;
          _availableSizes = [];
          _selectedSize = null;
        });
      }
    }
  }

  void _loadRecentSuppliers() async {
    final suppliers = await DatabaseHelper.instance.getRecentSuppliers();
    setState(() {
      _recentSuppliers = suppliers;
    });
  }

  void _updatePieceCount() {
    String text = _unitController.text;
    double count = DatabaseHelper.instance.extractNumericValue(text);
    double multiplier = DatabaseHelper.instance.getUnitMultiplier(_selectedUnitLabel, _selectedSize ?? "");
    double total = count * multiplier;

    setState(() {
      _totalPiecesSuffix = total % 1 == 0
          ? "${total.toInt()} pcs"
          : "${total.toStringAsFixed(2)} pcs";
    });
  }

  @override
  void dispose() {
    _unitController.removeListener(_updatePieceCount);
    _itemController.removeListener(_onItemChanged);
    _unitController.dispose();
    _supplierController.dispose();
    _itemController.dispose();
    _qtyController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  bool get _shouldAllowDecimal {
    final u = _selectedUnitLabel.toLowerCase();
    return u.contains('kg') || u.contains('g') || u.contains('ml') || u.contains('l') || u.contains('sack');
  }

  void _loadItems() async {
    final items = await DatabaseHelper.instance.getAvailableItems();
    setState(() {
      _availableItems = items;
    });
  }

  void _loadSizes(String item) async {
    final sizes = await DatabaseHelper.instance.getItemSizes(item);
    setState(() {
      _availableSizes = sizes;
      _selectedSize = null;
      _isNewSize = false;
      _isPriceLocked = false;
    });
  }

  void _checkExistingPrice() async {
    if (_selectedItem != null &&
        _selectedSize != null && _selectedSize != _addNewSizeOption) {
      double basePrice = await DatabaseHelper.instance.getLastRecordedPrice(_selectedItem!, _selectedSize!);
      if (basePrice > 0) {
        String unitText = "${_unitController.text} $_selectedUnitLabel";
        double multiplier = DatabaseHelper.instance.getUnitMultiplier(unitText, _selectedSize!);

        setState(() {
          double unitPrice = basePrice * (multiplier > 0 ? multiplier : 1);
          _priceController.text = unitPrice.toStringAsFixed(0);
          _isPriceLocked = true;
        });
      } else {
        setState(() {
          _isPriceLocked = false;
        });
      }
    } else {
      setState(() {
        _isPriceLocked = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = AppColors.background;
    final surfaceColor = Colors.white;
    final borderColor = AppColors.neutralBorder;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: surfaceColor,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          },
          tooltip: 'Back to Home',
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.lightCyan,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Image.asset('assets/images/app_icon.png', width: 20, height: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'New Stock Entry',
                style: GoogleFonts.outfit(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: -0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          StandardAppBarActions(onRefresh: _loadItems),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: borderColor, height: 1),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 900;

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Form
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _buildFormSection(),
                  ),
                ),
                // Right: Items List
                Expanded(
                  flex: 5,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: borderColor)),
                      color: surfaceColor,
                    ),
                    child: Column(
                      children: [
                        _buildListHeader(),
                        Expanded(child: _buildItemsList(isMobile: false)),
                        _buildFooter(),
                      ],
                    ),
                  ),
                ),
              ],
            );
          } else {
            // Mobile: Column
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildFormSection(),
                  const SizedBox(height: 24),
                  Container(
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildListHeader(),
                        _buildItemsList(isMobile: true),
                        _buildFooter(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }

  // Modern Card Module Header and Form Section
  Widget _buildFormSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.neutralBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title: "New Stock Entry" with subtle cyan circle badge
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: AppColors.lightCyan, // #E0F7FA
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryGreen, // #00D09C
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                "New Stock Entry",
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary, // #000000
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Supplier Name Field Trigger
          _buildLabel("Supplier Name"),
          _buildPickerTrigger(
            value: _supplierController.text,
            placeholder: "Select or Enter Supplier Name",
            onTap: () {
              _showSearchablePicker(
                title: "Select Supplier",
                items: _recentSuppliers,
                selectedValue: _supplierController.text,
                addNewLabel: "+ Add New Supplier",
                onSelected: (val) {
                  setState(() {
                    _supplierController.text = val;
                  });
                },
                onAddNew: () {
                  _promptCustomInput(
                    title: "Add New Supplier",
                    hint: "Enter Supplier Name",
                    onSubmitted: (val) {
                      setState(() {
                        _supplierController.text = val;
                      });
                    },
                  );
                },
              );
            },
            onClear: _supplierController.text.isNotEmpty ? () {
              setState(() {
                _supplierController.clear();
              });
            } : null,
          ),
          const SizedBox(height: 20),

          // Item Name Field Trigger
          _buildLabel("Item Name"),
          _buildPickerTrigger(
            value: _itemController.text,
            placeholder: "Select or Enter Item Name",
            onTap: () {
              _showSearchablePicker(
                title: "Select Item Name",
                items: _availableItems,
                selectedValue: _itemController.text,
                addNewLabel: "+ Add New Item",
                onSelected: (val) {
                  setState(() {
                    _itemController.text = val;
                    _selectedItem = val;
                    _loadSizes(val);
                  });
                },
                onAddNew: () {
                  _promptCustomInput(
                    title: "Add New Item",
                    hint: "Enter Item Name",
                    onSubmitted: (val) {
                      setState(() {
                        _itemController.text = val;
                        _selectedItem = val;
                        _loadSizes(val);
                      });
                    },
                  );
                },
              );
            },
            onClear: _itemController.text.isNotEmpty ? () {
              setState(() {
                _itemController.clear();
                _selectedItem = null;
                _availableSizes = [];
                _selectedSize = null;
              });
            } : null,
          ),
          const SizedBox(height: 20),

          // Item Size / Variant Field Trigger
          _buildLabel("Item Size / Variant"),
          _buildPickerTrigger(
            value: _isNewSize ? _qtyController.text : (_selectedSize ?? ""),
            placeholder: _selectedItem != null ? "Select Size / Variant" : "Select Item First",
            onTap: () {
              if (_selectedItem == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Please select an item first', style: GoogleFonts.outfit())),
                );
                return;
              }
              _showSearchablePicker(
                title: "Select Size / Variant",
                items: _availableSizes,
                selectedValue: _selectedSize,
                addNewLabel: "+ Add New Size...",
                onSelected: (val) {
                  setState(() {
                    _isNewSize = false;
                    _selectedSize = val;
                    _qtyController.text = val;
                    _checkExistingPrice();
                    _updatePieceCount();
                  });
                },
                onAddNew: () {
                  setState(() {
                    _isNewSize = true;
                    _selectedSize = _addNewSizeOption;
                    _qtyController.clear();
                    _priceController.clear();
                    _isPriceLocked = false;
                  });
                },
              );
            },
            onClear: (_selectedSize != null || _isNewSize) ? () {
              setState(() {
                _selectedSize = null;
                _isNewSize = false;
                _qtyController.clear();
                _priceController.clear();
                _isPriceLocked = false;
              });
            } : null,
          ),
          if (_isNewSize || _selectedItem == null) ...[
            if (_selectedItem != null) const SizedBox(height: 8),
            _buildTextField(_qtyController, "Enter Size (e.g. 50kg)", isNumber: true),
          ],

          // Status Banner Cleanup: Light Cyan #E0F7FA Fill, subtle rounded corners, Outfit Medium #00838F text
          if (_isPriceLocked) ...[
            const SizedBox(height: 12),
            _buildNotice("Existing item detected. Price is locked."),
          ],
          const SizedBox(height: 16),

          // ADHD De-cluttered Unit Size Chips (Dynamic Disclosure: Scrollable Row)
          _buildLabel("Unit Size Variant"),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: _qtyQuickButtons.map((label) {
                final isSelected = label == "None"
                    ? _qtyController.text == "None"
                    : _qtyController.text.endsWith(label);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildUnitSizeChip(label, () => _appendQty(label), isSelected: isSelected),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),

          // Unit Price Input
          _buildLabel("Unit Price"),
          Stack(
            children: [
              _buildTextField(_priceController, "0.00", isCurrency: true, paddingLeft: 60, isReadOnly: _isPriceLocked),
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Text(
                    "UGX",
                    style: GoogleFonts.outfit(color: AppColors.neutralMutedText, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              )
            ],
          ),
          const SizedBox(height: 20),

          // Horizontal Icon + Piece Count Chip Selector Layout for Quantity Multipliers
          _buildLabel("Quantity Multipliers"),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Row(
              children: _getFilteredUnitButtons().map((u) {
                final isSelected = _isUnitSelected(u['value']);
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: _buildMultiplierIconChip(
                    label: u['label']!,
                    onTap: () => _appendUnit(u['value']!),
                    isSelected: isSelected,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Big Numeric Counter Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.neutralInactive, // #F4F6F8
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.neutralBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _unitController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      if (!_shouldAllowDecimal) FilteringTextInputFormatter.digitsOnly
                      else FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      if (_shouldAllowDecimal) TextInputFormatter.withFunction((oldValue, newValue) {
                        if (newValue.text.startsWith('.')) return oldValue;
                        if (newValue.text.contains('.') && newValue.text.indexOf('.') != newValue.text.lastIndexOf('.')) return oldValue;
                        return newValue;
                      }),
                    ],
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w800, // ExtraBold (32pt)
                      fontSize: 32,
                      color: const Color(0xFF000000),
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: "0",
                      hintStyle: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800,
                        fontSize: 32,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Styled Pill Badge with Box Icon + Multiplier
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryGreen.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        size: 15,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _getPillBadgeText(),
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Primary Action Button: Full-width elevated Cyan-Green button (#00D09C)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add, color: Colors.white, size: 22),
              label: Text(
                "Add Stock to List",
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen, // #00D09C
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 2,
                shadowColor: AppColors.primaryGreen.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // De-cluttered Unit Size Chip (Dynamic disclosure)
  Widget _buildUnitSizeChip(String label, VoidCallback onTap, {required bool isSelected}) {
    final activeBg = AppColors.primaryGreen;
    final inactiveBg = AppColors.neutralInactive;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : inactiveBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeBg : AppColors.neutralBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 13,
            color: isSelected ? Colors.white : AppColors.neutralMutedText,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // Compact Box Icon + Piece Count Chip (Horizontal Scroll Row)
  Widget _buildMultiplierIconChip({
    required String label,
    required VoidCallback onTap,
    required bool isSelected,
  }) {
    final activeColor = AppColors.primaryGreen; // #00D09C
    final inactiveBg = const Color(0xFFF4F6F8);
    final inactiveText = const Color(0xFF333333);
    final inactiveIcon = const Color(0xFF555555);
    final inactiveBorder = const Color(0xFFE0E0E0);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : inactiveBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : inactiveBorder,
            width: 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.30), // Color(0x3300D09C)
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 18,
              color: isSelected ? Colors.white : inactiveIcon,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: isSelected ? Colors.white : inactiveText,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Clean Status Banner Cleanup
  Widget _buildNotice(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.lightCyan, // #E0F7FA Fill
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkCyan.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.darkCyan), // #00838F
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.outfit(
                color: AppColors.darkCyan,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.neutralBorder)),
        color: Color(0xFFF8FAFC),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.save_alt, color: AppColors.primaryGreen, size: 20),
              const SizedBox(width: 8),
              Text(
                "Items to Save",
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.lightCyan,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.3)),
            ),
            child: Text(
              "${_items.length} ITEMS",
              style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.darkCyan),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildItemsList({required bool isMobile}) {
    if (_items.isEmpty) {
      return SizedBox(
        height: 150,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inventory_2_outlined, size: 40, color: Colors.grey.withValues(alpha: 0.5)),
              const SizedBox(height: 8),
              Text("No items added yet", style: GoogleFonts.outfit(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    final listView = ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: isMobile,
      physics: isMobile ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
      itemCount: _items.length,
      separatorBuilder: (c, i) => const Divider(height: 1, color: AppColors.neutralBorder),
      itemBuilder: (context, index) {
        final item = _items[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.item, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 14)),
                    if (item.quantity.isNotEmpty && item.quantity != "None")
                      Text("Size: ${item.quantity}", style: GoogleFonts.outfit(color: AppColors.neutralMutedText, fontSize: 12)),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.lightCyan,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.unit,
                      style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.darkCyan),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "UGX ${_formatter.format(double.tryParse(item.price) ?? 0)}",
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 13),
                    ),
                    Text(
                      "Total: ${_formatter.format(double.tryParse(item.amount.replaceAll(',', '')) ?? 0)}",
                      style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.accentRed, size: 20),
                    onPressed: () => setState(() => _items.removeAt(index)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    return Column(
      children: [
        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(bottom: BorderSide(color: AppColors.neutralBorder)),
          ),
          child: Row(
            children: [
              Expanded(flex: 5, child: Text("ITEM", style: _tableHeaderStyle())),
              Expanded(flex: 2, child: Text("QTY", style: _tableHeaderStyle(), textAlign: TextAlign.center)),
              Expanded(flex: 3, child: Text("PRICE", style: _tableHeaderStyle(), textAlign: TextAlign.right)),
              Expanded(flex: 2, child: Text("ACTION", style: _tableHeaderStyle(), textAlign: TextAlign.right)),
            ],
          ),
        ),
        isMobile ? listView : Expanded(child: listView),
      ],
    );
  }

  Widget _buildFooter() {
    double totalVal = 0;
    for (var i in _items) {
      totalVal += double.tryParse(i.amount.replaceAll(',', '')) ?? 0;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: AppColors.neutralBorder)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Total Value", style: GoogleFonts.outfit(color: AppColors.neutralMutedText, fontSize: 14, fontWeight: FontWeight.w500)),
              Text("UGX ${_formatter.format(totalVal)}", style: GoogleFonts.outfit(color: AppColors.primaryGreen, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _items.isNotEmpty ? _saveStock : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.textPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text("Save Stock", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.arrow_back, size: 16, color: Colors.grey),
            label: Text("Cancel / Back to In Stock", style: GoogleFonts.outfit(color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // Styles & Helper Components
  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.outfit(
          color: const Color(0xFF64748B),
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  TextStyle _tableHeaderStyle() {
    return GoogleFonts.outfit(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: const Color(0xFF64748B),
      letterSpacing: 0.5,
    );
  }

  InputDecoration _inputDecoration({double paddingLeft = 16}) {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: EdgeInsets.fromLTRB(paddingLeft, 16, 16, 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.neutralBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.neutralBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
      ),
      hintStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint, {
    bool isNumber = false,
    bool isCurrency = false,
    double paddingLeft = 16,
    bool isReadOnly = false,
    String? suffixText,
    Widget? prefixIcon,
    Widget? suffixIconButton,
  }) {
    return TextField(
      controller: controller,
      readOnly: isReadOnly,
      keyboardType: (isNumber || isCurrency) ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      inputFormatters: isCurrency
          ? [ThousandsFormatter()]
          : (isNumber
              ? [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    if (newValue.text.startsWith('.')) return oldValue;
                    if (newValue.text.contains('.') && newValue.text.indexOf('.') != newValue.text.lastIndexOf('.')) return oldValue;
                    return newValue;
                  }),
                ]
              : null),
      style: GoogleFonts.outfit(
        color: isReadOnly ? Colors.grey : const Color(0xFF334155),
        fontWeight: FontWeight.w500,
        fontSize: 15,
      ),
      decoration: _inputDecoration(paddingLeft: paddingLeft).copyWith(
        hintText: hint,
        fillColor: isReadOnly ? AppColors.neutralInactive : const Color(0xFFF8FAFC),
        suffixText: suffixText,
        suffixIcon: suffixIconButton,
        suffixStyle: GoogleFonts.outfit(fontSize: 12, color: Colors.grey),
        prefixIcon: prefixIcon,
      ),
    );
  }

  bool _isUnitSelected(String? btnValue) {
    if (btnValue == null) return false;
    String selected = _selectedUnitLabel.toLowerCase().replaceAll(' ', '');
    String button = btnValue.toLowerCase().replaceAll(' ', '');

    if (selected == button) return true;
    if (selected.contains(button)) return true;
    if (button == "pcs" && (selected == "pcs" || selected.endsWith("pcs"))) return true;

    return false;
  }

  // Logic Helpers
  void _appendQty(String val) {
    if (val == "None") {
      _qtyController.text = "None";
      return;
    }

    if (RegExp(r'^\d').hasMatch(val)) {
      _qtyController.text = val;
      return;
    }

    String current = _qtyController.text;
    if (current == "None") current = "";

    final match = RegExp(r'^(\d+(\.\d+)?)').firstMatch(current);
    if (match != null) {
      String numPart = match.group(1)!;
      _qtyController.text = numPart + val;
    } else {
      _qtyController.text = val;
    }
  }

  List<Map<String, String>> _getFilteredUnitButtons() {
    final sizeText = _qtyController.text;
    final sizeVal = DatabaseHelper.instance.extractNumericValue(sizeText);
    final isKg = sizeText.toLowerCase().contains("kg");

    if (isKg && sizeVal > 9.0) {
      return _unitQuickButtons.where((u) => u['value'] == 'Sack').toList();
    } else {
      return _unitQuickButtons.where((u) => u['value'] != 'Sack').toList();
    }
  }

  void _appendUnit(String val) {
    String cleanVal = DatabaseHelper.instance.cleanUnitLabel(val);

    String currentText = _unitController.text;
    double currentNum = DatabaseHelper.instance.extractNumericValue(currentText);

    setState(() {
      _selectedUnitLabel = cleanVal;
      if (currentNum > 0) {
        _unitController.text = currentNum.toStringAsFixed(0);
      }
      _updatePieceCount();
    });
    _checkExistingPrice();
  }

  void _addItem() {
    if (_supplierController.text.isEmpty || _itemController.text.isEmpty ||
        _qtyController.text.isEmpty || _unitController.text.isEmpty || _priceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please fill all fields', style: GoogleFonts.outfit())),
      );
      return;
    }

    String supplier = _supplierController.text;
    String item = _itemController.text;
    String quantity = _qtyController.text;
    final hasUnit = RegExp(r'(kg|g|ml|l|inch)$', caseSensitive: false).hasMatch(quantity) || quantity == "None";
    if (!hasUnit) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please specify a unit (e.g. kg, g, ml, l) for size', style: GoogleFonts.outfit())),
      );
      return;
    }
    String unitText = "${_unitController.text} $_selectedUnitLabel";
    double price = DatabaseHelper.instance.extractNumericValue(_priceController.text);

    double count = DatabaseHelper.instance.extractNumericValue(unitText);
    double total = count * price;

    setState(() {
      _items.add(StockItem(
        supplier: supplier,
        item: item,
        quantity: quantity,
        unit: unitText,
        price: price.toStringAsFixed(0),
        amount: total.toStringAsFixed(0),
      ));

      _qtyController.clear();
      _unitController.clear();
      _priceController.clear();
      _selectedSize = null;
      _isNewSize = false;
      _isPriceLocked = false;
      _selectedUnitLabel = "pcs";
      _totalPiecesSuffix = "pcs";

      if (_selectedItem != null) {
        _loadSizes(_selectedItem!);
      }
    });
  }

  void _saveStock() async {
    if (_items.isEmpty) return;

    ProcessingLoadingDialog.show(
      context,
      title: 'Saving New Stock...',
      message: 'Updating inventory counts and syncing data. Please wait...',
      themeColor: AppColors.accentBlue,
    );

    final itemsCopy = List<StockItem>.from(_items);
    final supplierCopy = _supplierController.text.isNotEmpty
        ? _supplierController.text
        : (itemsCopy.isNotEmpty ? itemsCopy.first.supplier : 'General Supplier');
    final double totalStockValue = itemsCopy.fold<double>(0, (sum, i) => sum + (double.tryParse(i.amount) ?? 0));
    final int totalItemsCount = itemsCopy.length;
    final String receiptId = DatabaseHelper.generateUUID();

    try {
      for (var item in itemsCopy) {
        double price = double.parse(item.price);

        bool exists = await DatabaseHelper.instance.itemExists(item.item, item.quantity);
        if (exists) {
          await DatabaseHelper.instance.mergeStock(
            item.item, item.quantity, item.unit, price, item.supplier
          );
        } else {
          await DatabaseHelper.instance.addStock(
            item.supplier, item.item, item.quantity, item.unit, price, DateTime.now().toIso8601String().split('T')[0]
          );
        }

        double amount = double.parse(item.amount);
        await DatabaseHelper.instance.addSaleWithProfit(
          item.supplier, item.item, item.quantity, item.unit, price, amount, "NEW STOCK", receiptId: receiptId
        );
      }

      if (itemsCopy.isNotEmpty) {
        String itemsStr = itemsCopy.map((e) => e.item).join(", ");
        String supplier = itemsCopy.first.supplier;
        await DatabaseHelper.instance.addNotification("Added $itemsStr from $supplier", "Mobile", targetType: 'stock', targetId: itemsStr);
        try {
          await AuditService.instance.logAction(
            action: 'STOCK_UPDATE',
            details: {
              'items': itemsCopy.map((e) => {'item': e.item, 'quantity': e.unit, 'size': e.quantity, 'price': e.price, 'amount': e.amount}).toList(),
              'supplier': supplier,
            },
          );
        } catch (e) {
          debugPrint('Error logging stock update audit: $e');
        }
      }

      await SupasService.instance.uploadDatabase();

      if (mounted) {
        ProcessingLoadingDialog.hide(context);

        setState(() {
          _items.clear();
          _supplierController.clear();
          _itemController.clear();
          _selectedItem = null;
          _selectedSize = null;
          _availableSizes = [];
          _isNewSize = false;
          _selectedUnitLabel = "pcs";
          _totalPiecesSuffix = "pcs";
        });
        _loadItems();
        _loadRecentSuppliers();

        TransactionSuccessDialog.show(
          context,
          type: TransactionType.newStock,
          receiptId: receiptId,
          partyName: supplierCopy,
          totalAmount: totalStockValue,
          totalItemsCount: totalItemsCount,
          items: itemsCopy.map((item) => SuccessItemSummary(
            name: item.item,
            quantity: item.quantity,
            unit: item.unit,
            price: double.tryParse(item.price) ?? 0,
            amount: double.tryParse(item.amount) ?? 0,
          )).toList(),
          onDone: () {},
        );
      }
    } catch (e) {
      if (mounted) {
        ProcessingLoadingDialog.hide(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e', style: GoogleFonts.outfit())),
        );
      }
    }
  }

  // Tap-to-Select Field Container Trigger
  Widget _buildPickerTrigger({
    required String value,
    required String placeholder,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final hasValue = value.isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.neutralBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                hasValue ? value : placeholder,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                  color: hasValue ? const Color(0xFF334155) : const Color(0xFF94A3B8),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasValue && onClear != null)
              GestureDetector(
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.only(left: 4, right: 4),
                  child: Icon(Icons.close, size: 16, color: Colors.grey),
                ),
              ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF64748B),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  String _formatUnitDisplayLabel(String unit) {
    String u = unit.toLowerCase().replaceAll(' ', '');
    if (u == 'pcs' || u == '1pc' || u == 'pc') return '1 pc';
    if (u == 'halfdoz') return '6 pcs';
    if (u.contains('box*10')) return '10 pcs';
    if (u.contains('box*12')) return '12 pcs';
    if (u.contains('box*20')) return '20 pcs';
    if (u.contains('box*24')) return '24 pcs';
    if (u == 'crate' || u.contains('crate*25')) return '25 pcs';
    if (u.contains('box*72')) return '72 pcs';
    if (u == 'sack') return 'Sack';
    return unit.toUpperCase();
  }

  String _getPillBadgeText() {
    String formattedUnit = _formatUnitDisplayLabel(_selectedUnitLabel);
    double count = DatabaseHelper.instance.extractNumericValue(_unitController.text);
    if (count <= 0) {
      return formattedUnit;
    } else {
      return "$formattedUnit • $_totalPiecesSuffix";
    }
  }

  // Open Searchable Modal Bottom Sheet Picker
  void _showSearchablePicker({
    required String title,
    required List<String> items,
    required String? selectedValue,
    required String addNewLabel,
    required ValueChanged<String> onSelected,
    required VoidCallback onAddNew,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return _SearchablePickerBottomSheet(
          title: title,
          items: items,
          selectedValue: selectedValue,
          addNewLabel: addNewLabel,
          onSelected: onSelected,
          onAddNew: onAddNew,
        );
      },
    );
  }

  // Prompt Custom Input Dialog for "Add New"
  void _promptCustomInput({
    required String title,
    required String hint,
    required ValueChanged<String> onSubmitted,
  }) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(
            title,
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: GoogleFonts.outfit(fontSize: 15, color: const Color(0xFF334155)),
            decoration: _inputDecoration().copyWith(hintText: hint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel", style: GoogleFonts.outfit(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  onSubmitted(text);
                }
                Navigator.pop(context);
              },
              child: Text("Add", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}

// Searchable Modal Bottom Sheet Picker Widget
class _SearchablePickerBottomSheet extends StatefulWidget {
  final String title;
  final List<String> items;
  final String? selectedValue;
  final String addNewLabel;
  final ValueChanged<String> onSelected;
  final VoidCallback onAddNew;

  const _SearchablePickerBottomSheet({
    required this.title,
    required this.items,
    required this.selectedValue,
    required this.addNewLabel,
    required this.onSelected,
    required this.onAddNew,
  });

  @override
  State<_SearchablePickerBottomSheet> createState() => _SearchablePickerBottomSheetState();
}

class _SearchablePickerBottomSheetState extends State<_SearchablePickerBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  late List<String> _filteredItems;

  @override
  void initState() {
    super.initState();
    _filteredItems = List.from(widget.items);
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredItems = widget.items
          .where((item) => item.toLowerCase().contains(query))
          .toList();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // Handle Bar
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Header Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.title,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF000000),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF334155)),
              decoration: InputDecoration(
                hintText: "Search...",
                hintStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8), size: 20),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // "Add New" Quick Action Button Row
          InkWell(
            onTap: () {
              Navigator.pop(context);
              widget.onAddNew();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              color: AppColors.lightCyan.withValues(alpha: 0.5),
              child: Row(
                children: [
                  const Icon(Icons.add_circle_outline, color: AppColors.primaryGreen, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    widget.addNewLabel,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkCyan,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // List Items
          Flexible(
            child: _filteredItems.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(
                      "No matching items found",
                      style: GoogleFonts.outfit(color: Colors.grey, fontSize: 14),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _filteredItems.length,
                    separatorBuilder: (c, i) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    itemBuilder: (context, index) {
                      final item = _filteredItems[index];
                      final isSelected = item == widget.selectedValue;

                      return InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          widget.onSelected(item);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item,
                                  style: GoogleFonts.outfit(
                                    fontSize: 15,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected ? AppColors.textPrimary : const Color(0xFF334155),
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.primaryGreen,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
