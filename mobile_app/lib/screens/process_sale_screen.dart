import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../utils/colors.dart';
import '../utils/formatters.dart';
import '../services/database_helper.dart';
import '../services/supabase_service.dart';
import '../services/audit_service.dart';
import '../services/printer_service.dart';
import '../models/sale_item.dart';
import '../widgets/common_app_bar_actions.dart';
import '../widgets/transaction_success_dialog.dart';
import '../widgets/processing_loading_dialog.dart';

class ProcessSaleScreen extends StatefulWidget {
  const ProcessSaleScreen({super.key});

  @override
  State<ProcessSaleScreen> createState() => _ProcessSaleScreenState();
}

class _ProcessSaleScreenState extends State<ProcessSaleScreen> {
  final _customerController = TextEditingController();
  final _unitController = TextEditingController(); // Count/Weight input
  final _priceController = TextEditingController();
  final List<SaleItem> _cart = [];
  List<String> _availableItems = [];
  List<String> _availableSizes = [];
  List<String> _recentCustomers = [];

  String? _selectedItem;
  String? _selectedSize;
  String _currentStock = "";
  String _selectedUnitLabel = "pcs"; // e.g. "Box", "Sack"
  String _totalPiecesSuffix = "pcs"; // e.g. "72 pcs"
  bool _isDebt = false;

  // Quick Buttons
  final List<String> _weightButtons = ["kg", "Quarter", "Half"];
  final List<Map<String, String>> _unitOptions = [
    {"label": "1 pc", "value": "pcs"},
    {"label": "6 pcs", "value": "half doz"},
    {"label": "10 pcs", "value": "box*10"},
    {"label": "12 pcs", "value": "box*12"},
    {"label": "24 pcs", "value": "box*24"},
    {"label": "36 pcs", "value": "box*36"},
    {"label": "48 pcs", "value": "box*48"},
    {"label": "96 pcs", "value": "box*96"},
    {"label": "100 pcs", "value": "box*100"},
  ];

  bool _isBulkItem = false;
  bool _isCheckingOut = false;
  final _formatter = NumberFormat("#,###");

  @override
  void initState() {
    super.initState();
    _loadItems();
    _loadRecentCustomers();
    _unitController.addListener(_updatePieceCount);
  }

  void _loadRecentCustomers() async {
    final customers = await DatabaseHelper.instance.getRecentCustomers();
    setState(() {
      _recentCustomers = customers;
    });
  }

  void _updatePieceCount() {
    String text = _unitController.text;
    double count = DatabaseHelper.instance.extractNumericValue(text);
    double multiplier = DatabaseHelper.instance.getUnitMultiplier(_selectedUnitLabel, _selectedSize ?? "");
    double total = count * multiplier;
    setState(() {
      final double totalPieces = total;
      if (_isBulkItem) {
        _totalPiecesSuffix = "${totalPieces.toStringAsFixed(2)} kg";
      } else {
        _totalPiecesSuffix = totalPieces % 1 == 0
            ? "${totalPieces.toInt()} pcs"
            : "${totalPieces.toStringAsFixed(2)} pcs";
      }
    });
  }

  void _loadItems() async {
    final items = await DatabaseHelper.instance.getAvailableItems();
    setState(() {
      _availableItems = items;
      if (_selectedItem != null && !items.contains(_selectedItem)) {
        _selectedItem = null;
        _availableSizes = [];
        _selectedSize = null;
        _currentStock = "";
      }
    });
  }

  void _loadSizes(String item) async {
    final sizes = await DatabaseHelper.instance.getItemSizes(item);
    setState(() {
      _availableSizes = sizes;
      _selectedSize = null;
      _currentStock = "";

      if (sizes.length == 1) {
        _selectedSize = sizes[0];
        _checkBulkStatus(sizes[0]);
        _updateStockDisplay();
      }
    });
  }

  void _updateStockDisplay() async {
    if (_selectedItem != null && _selectedSize != null) {
      final db = await DatabaseHelper.instance.database;
      final result = await db.rawQuery(
        "SELECT quantity, unit, available_pieces FROM stock WHERE item = ? AND quantity = ?",
        [_selectedItem, _selectedSize],
      );

      if (result.isNotEmpty && mounted) {
        double avail = (result.first['available_pieces'] as num).toDouble();
        String display = DatabaseHelper.instance.formatStockForDisplay(avail, result.first['unit'] as String, result.first['quantity'].toString());

        setState(() {
          _currentStock = "Stock: $display";

          String rawUnit = result.first['unit'] as String;
          if (_unitController.text.isEmpty) {
            String cleanUnit = DatabaseHelper.instance.cleanUnitLabel(rawUnit);
            _selectedUnitLabel = cleanUnit;
            _appendUnit(cleanUnit);
          }
        });
      }
    } else {
      setState(() {
        _currentStock = "";
      });
    }
  }

  @override
  void dispose() {
    _unitController.removeListener(_updatePieceCount);
    _customerController.dispose();
    _unitController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
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
                'Process Sale',
                style: GoogleFonts.outfit(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: -0.4,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          StandardAppBarActions(onRefresh: _loadItems),
        ],
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.neutralBorder, height: 1),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isWide = constraints.maxWidth > 800;

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 7,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _buildFormSection(),
                  ),
                ),
                Container(width: 1, color: AppColors.neutralBorder),
                Expanded(
                  flex: 5,
                  child: Container(
                    color: Colors.white,
                    height: constraints.maxHeight,
                    child: _buildCartSection(isWide: true),
                  ),
                ),
              ],
            );
          } else {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildFormSection(),
                  const SizedBox(height: 24),
                  _buildCartSection(isWide: false),
                  const SizedBox(height: 40),
                ],
              ),
            );
          }
        },
      ),
    );
  }

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
          // Section Title Badge
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: AppColors.lightCyan,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                "New Sale Transaction",
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Customer Name (Searchable Bottom Sheet Picker)
          _buildLabel("Customer Name"),
          _buildPickerTrigger(
            value: _customerController.text,
            placeholder: "Select or Enter Customer Name",
            onTap: () {
              final customers = ["Walk-in Customer", ..._recentCustomers.where((c) => c != "Walk-in Customer")];
              _showSearchablePicker(
                title: "Select Customer",
                items: customers,
                selectedValue: _customerController.text,
                addNewLabel: "+ Add New Customer",
                onSelected: (val) {
                  setState(() {
                    _customerController.text = val;
                  });
                },
                onAddNew: () {
                  _promptCustomInput(
                    title: "Add New Customer",
                    hint: "Enter Customer Name",
                    onSubmitted: (val) {
                      setState(() {
                        _customerController.text = val;
                      });
                    },
                  );
                },
              );
            },
            onClear: _customerController.text.isNotEmpty ? () {
              setState(() {
                _customerController.clear();
              });
            } : null,
          ),
          const SizedBox(height: 20),

          // Select Item (Searchable Bottom Sheet Picker)
          _buildLabel("Select Item"),
          _buildPickerTrigger(
            value: _selectedItem ?? "",
            placeholder: "Search & Select Item by Name",
            onTap: () {
              _showSearchablePicker(
                title: "Select Item",
                items: _availableItems,
                selectedValue: _selectedItem,
                addNewLabel: "+ Custom Item Entry",
                onSelected: (val) {
                  setState(() {
                    _selectedItem = val;
                    _unitController.clear();
                    _selectedUnitLabel = "pcs";
                    _loadSizes(val);
                  });
                },
                onAddNew: () {
                  _promptCustomInput(
                    title: "Add Custom Item",
                    hint: "Enter Item Name",
                    onSubmitted: (val) {
                      setState(() {
                        _selectedItem = val;
                        _unitController.clear();
                        _selectedUnitLabel = "pcs";
                        _loadSizes(val);
                      });
                    },
                  );
                },
              );
            },
            onClear: _selectedItem != null ? () {
              setState(() {
                _selectedItem = null;
                _availableSizes = [];
                _selectedSize = null;
                _currentStock = "";
              });
            } : null,
          ),
          const SizedBox(height: 20),

          // Size & Price Layout (Responsive & Multi-Row Fallback)
          Builder(
            builder: (context) {
              final isSmallScreen = MediaQuery.of(context).size.width < 360;

              final sizeWidget = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel("Size / Variant"),
                  const SizedBox(height: 6),
                  _buildPickerTrigger(
                    value: _selectedSize ?? "",
                    placeholder: _selectedItem != null ? "Select Size" : "Item First",
                    onTap: () {
                      if (_selectedItem == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Please select an item first', style: GoogleFonts.outfit())),
                        );
                        return;
                      }
                      _showSearchablePicker(
                        title: "Select Size",
                        items: _availableSizes,
                        selectedValue: _selectedSize,
                        addNewLabel: "+ Custom Size",
                        onSelected: (val) {
                          setState(() {
                            _selectedSize = val;
                            _unitController.clear();
                            _selectedUnitLabel = "pcs";
                            _checkBulkStatus(val);
                            _updateStockDisplay();
                            _updatePieceCount();
                          });
                          _checkExistingPrice();
                        },
                        onAddNew: () {
                          _promptCustomInput(
                            title: "Enter Custom Size",
                            hint: "e.g. 50kg",
                            onSubmitted: (val) {
                              setState(() {
                                _selectedSize = val;
                                _unitController.clear();
                                _selectedUnitLabel = "pcs";
                                _checkBulkStatus(val);
                                _updateStockDisplay();
                                _updatePieceCount();
                              });
                              _checkExistingPrice();
                            },
                          );
                        },
                      );
                    },
                    onClear: _selectedSize != null ? () {
                      setState(() {
                        _selectedSize = null;
                        _currentStock = "";
                      });
                    } : null,
                  ),
                ],
              );

              final priceWidget = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel("Unit Price"),
                  const SizedBox(height: 6),
                  _buildTextField(_priceController, "0.00", isCurrency: true),
                ],
              );

              if (isSmallScreen) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sizeWidget,
                    const SizedBox(height: 12),
                    priceWidget,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Size / Variant (Flex 2)
                  Expanded(
                    flex: 2,
                    child: sizeWidget,
                  ),
                  const SizedBox(width: 12),

                  // Unit Price Input (Flex 3)
                  Expanded(
                    flex: 3,
                    child: priceWidget,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),

          // DEBT Badge Toggle Button
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: () => setState(() => _isDebt = !_isDebt),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _isDebt ? Colors.orange.shade600 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _isDebt ? Colors.orange.shade700 : Colors.orange.shade200),
                  boxShadow: _isDebt ? [
                    BoxShadow(
                      color: Colors.orange.shade600.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ] : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isDebt ? Icons.check_circle : Icons.money_off_rounded,
                      size: 16,
                      color: _isDebt ? Colors.white : Colors.orange.shade800,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "DEBT SALE",
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _isDebt ? Colors.white : Colors.orange.shade800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Quantity / Unit Label & Stock Display (Prevent Overflow)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: _buildLabel("Quantity Multipliers"),
              ),
              if (_currentStock.isNotEmpty)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.lightCyan,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _currentStock,
                      style: GoogleFonts.outfit(fontSize: 12, color: AppColors.darkCyan, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Horizontal Box-Icon Multiplier Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: Row(
              children: (_isBulkItem ? _weightButtons.map((u) => {"label": u, "value": u}).toList() : _unitOptions).map((u) {
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

          // Big Numeric Quantity Entry Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.neutralInactive,
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
                      if (!_isBulkItem) FilteringTextInputFormatter.digitsOnly
                      else FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      if (_isBulkItem) TextInputFormatter.withFunction((oldValue, newValue) {
                        if (newValue.text.startsWith('.')) return oldValue;
                        if (newValue.text.contains('.') && newValue.text.indexOf('.') != newValue.text.lastIndexOf('.')) return oldValue;
                        return newValue;
                      }),
                    ],
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w800,
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

          // Add to Cart Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _addToCart,
              icon: const Icon(Icons.add_shopping_cart, color: Colors.white, size: 22),
              label: Text(
                "Add to Cart",
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
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

  // Cart Summary Section Polish
  Widget _buildCartSection({required bool isWide}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.neutralBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: AppColors.neutralBorder)),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shopping_basket, color: AppColors.primaryGreen, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      "Current Cart",
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.lightCyan,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "${_cart.length}",
                        style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.darkCyan),
                      ),
                    ),
                  ],
                ),
                if (_cart.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _cart.clear()),
                    child: Text(
                      "Clear All",
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.accentRed),
                    ),
                  )
              ],
            ),
          ),

          // List
          isWide
              ? Expanded(child: _buildCartList(isWide))
              : _buildCartList(isWide),

          // Footer Total
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(top: BorderSide(color: AppColors.neutralBorder)),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Total Amount", style: GoogleFonts.outfit(fontWeight: FontWeight.w500, color: AppColors.neutralMutedText, fontSize: 14)),
                    Text(
                      "UGX ${_formatter.format(_calculateTotalNum())}",
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 20, color: AppColors.primaryGreen),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _cart.isEmpty ? null : _checkout,
                    icon: const Icon(Icons.check_circle_outline, size: 20, color: Colors.white),
                    label: Text("Complete Sale", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.textPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartList(bool isWide) {
    if (_cart.isEmpty) {
      return SizedBox(
        height: 150,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_cart_outlined, size: 36, color: Colors.grey.withValues(alpha: 0.5)),
                const SizedBox(height: 8),
                Text("Cart is empty", style: GoogleFonts.outfit(color: Colors.grey, fontSize: 14)),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: !isWide,
      physics: isWide ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics(),
      itemCount: _cart.length,
      separatorBuilder: (c, i) => const Divider(height: 1, color: AppColors.neutralBorder),
      itemBuilder: (context, index) {
        final item = _cart[index];
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.item, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          "Size: ${item.quantity} • Qty: ${item.unit}",
                          style: GoogleFonts.outfit(fontSize: 12, color: AppColors.neutralMutedText),
                        ),
                        if (item.isDebt) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              "DEBT",
                              style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "UGX ${_formatter.format(double.tryParse(item.amount) ?? 0)}",
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primaryGreen),
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => setState(() => _cart.removeAt(index)),
                    child: const Icon(Icons.delete_outline, size: 18, color: AppColors.accentRed),
                  )
                ],
              )
            ],
          ),
        );
      },
    );
  }

  // Helper Styling Widgets
  Widget _buildLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.outfit(
        color: const Color(0xFF64748B),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.6,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData? icon, {String? prefixText}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, color: const Color(0xFF94A3B8), size: 20) : null,
      prefixText: prefixText,
      prefixStyle: GoogleFonts.outfit(color: AppColors.neutralMutedText, fontWeight: FontWeight.bold),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.neutralBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.neutralBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2)),
      hintStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint, {
    bool isCurrency = false,
    double? paddingLeft,
  }) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final textLength = value.text.length;
        final double fontSize = textLength > 10 ? 12.0 : (textLength > 7 ? 14.0 : 15.0);

        return TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: isCurrency ? [ThousandsFormatter()] : null,
          style: GoogleFonts.outfit(
            color: const Color(0xFF334155),
            fontWeight: FontWeight.w500,
            fontSize: fontSize,
          ),
          decoration: _inputDecoration(hint, null).copyWith(
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: isCurrency
                ? const EdgeInsets.symmetric(horizontal: 10.0, vertical: 12.0)
                : EdgeInsets.fromLTRB(paddingLeft ?? 16, 14, 16, 14),
            prefixIcon: isCurrency
                ? Padding(
                    padding: const EdgeInsets.only(left: 10.0, right: 6.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "UGX",
                          style: GoogleFonts.outfit(
                            color: AppColors.neutralMutedText,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : null,
            prefixIconConstraints: isCurrency ? const BoxConstraints(minWidth: 0, minHeight: 0) : null,
          ),
        );
      },
    );
  }

  // Compact Box Icon + Piece Count Chip for Multipliers
  Widget _buildMultiplierIconChip({
    required String label,
    required VoidCallback onTap,
    required bool isSelected,
  }) {
    final activeColor = AppColors.primaryGreen; // #00D09C
    final inactiveBg = const Color(0xFFF8FAFC);
    final inactiveText = const Color(0xFF475569);
    final inactiveIcon = const Color(0xFF64748B);
    final inactiveBorder = const Color(0xFFE2E8F0);

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
                    color: activeColor.withValues(alpha: 0.30),
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
    final match = RegExp(r'box\*(\d+)').firstMatch(u);
    if (match != null) {
      return '${match.group(1)} pcs';
    }
    if (u.contains('box*10')) return '10 pcs';
    if (u.contains('box*12')) return '12 pcs';
    if (u.contains('box*20')) return '20 pcs';
    if (u.contains('box*24')) return '24 pcs';
    if (u.contains('box*36')) return '36 pcs';
    if (u.contains('box*48')) return '48 pcs';
    if (u.contains('box*96')) return '96 pcs';
    if (u.contains('box*100')) return '100 pcs';
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
            decoration: _inputDecoration(hint, null),
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

  bool _isUnitSelected(String? btnValue) {
    if (btnValue == null) return false;
    String selected = _selectedUnitLabel.toLowerCase().replaceAll(' ', '');
    String button = btnValue.toLowerCase().replaceAll(' ', '');

    if (selected == button) return true;
    if (button == "pcs" && (selected == "pcs" || selected == "pc" || selected == "1pc")) return true;

    if (selected.contains('*') && button.contains('*')) {
      String selectedNum = selected.split('*').last;
      String buttonNum = button.split('*').last;
      return selectedNum == buttonNum;
    }

    return false;
  }

  void _checkBulkStatus(String size) {
    double val = DatabaseHelper.instance.extractNumericValue(size);
    bool isBulk = size.toLowerCase().contains("kg") && val >= 10.0;
    setState(() {
      _isBulkItem = isBulk;
      _totalPiecesSuffix = isBulk ? "kg" : "pcs";
    });
  }

  void _checkExistingPrice() async {
    if (_selectedItem != null && _selectedSize != null) {
      double basePrice = await DatabaseHelper.instance.getLastRecordedPrice(_selectedItem!, _selectedSize!);
      if (basePrice > 0) {
        double multiplier = DatabaseHelper.instance.getUnitMultiplier(_selectedUnitLabel, _selectedSize!);
        if (multiplier <= 0) multiplier = 1.0;
        double unitPrice = basePrice * multiplier;

        if (mounted) {
          setState(() {
            _priceController.text = unitPrice.toStringAsFixed(0);
          });
        }
      }
    }
  }

  void _appendUnit(String val) async {
    String cleanVal = DatabaseHelper.instance.cleanUnitLabel(val);

    String currentText = _unitController.text;
    double currentNum = DatabaseHelper.instance.extractNumericValue(currentText);

    setState(() {
      _selectedUnitLabel = cleanVal;
      if (currentNum <= 0) {
        _unitController.text = "1";
        currentNum = 1.0;
      } else {
        _unitController.text = currentNum.toStringAsFixed(0);
      }

      double multiplier = DatabaseHelper.instance.getUnitMultiplier(val, _selectedSize ?? "");
      double total = currentNum * multiplier;
      _totalPiecesSuffix = _isBulkItem ? "${total.toStringAsFixed(2)} kg" : "${total.toStringAsFixed(0)} pcs";
    });
    _checkExistingPrice();
  }

  void _addToCart() async {
    if (_customerController.text.isEmpty || _selectedItem == null || _selectedSize == null ||
        _unitController.text.isEmpty || _priceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please fill all fields', style: GoogleFonts.outfit())),
      );
      return;
    }

    String item = _selectedItem!;
    String size = _selectedSize!;

    double unitCountVal = DatabaseHelper.instance.extractNumericValue(_unitController.text);
    String unitText = "${unitCountVal.toStringAsFixed(0)} $_selectedUnitLabel";
    double price = DatabaseHelper.instance.extractNumericValue(_priceController.text);

    bool hasStock = await DatabaseHelper.instance.hasEnoughStock(item, size, unitText);
    if (!mounted) return;
    if (!hasStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.accentRed, content: Text('Not enough stock!', style: GoogleFonts.outfit())),
      );
      return;
    }

    double count = _getMoneyMultiplier(unitText);
    double total = count * price;

    // Loss check
    {
      double baseCost = await DatabaseHelper.instance.getLastRecordedPrice(item, size);
      double multiplier = DatabaseHelper.instance.getUnitMultiplier(unitText, size);
      double sizeVal = DatabaseHelper.instance.extractNumericValue(size);
      bool isBulk = size.toLowerCase().contains("kg") && sizeVal >= 10.0;
      double priceFactor = multiplier;
      if (isBulk && sizeVal > 0) {
        priceFactor = multiplier / sizeVal;
      }
      double fraction = 1.0;
      String uLower = unitText.toLowerCase();
      if (uLower.contains("1/4")) {
        fraction = 0.25;
      } else if (uLower.contains("1/2")) {
        fraction = 0.5;
      }

      double unitCost = baseCost * priceFactor * fraction;

      if (price < unitCost) {
        if (!mounted) return;
        bool? confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text("Warning: Loss Sale", style: GoogleFonts.outfit(color: AppColors.accentRed, fontWeight: FontWeight.bold)),
            content: Text(
              "You are selling below cost price!\n\nUnit Cost: ${_formatter.format(unitCost)}\nSelling Price: ${_formatter.format(price)}\n\nAre you sure you want to proceed?",
              style: GoogleFonts.outfit(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel", style: GoogleFonts.outfit(color: Colors.grey))),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text("Confirm Loss Sale", style: GoogleFonts.outfit(color: AppColors.accentRed, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        if (confirm != true) return;
      }
    }

    setState(() {
      _cart.add(SaleItem(
        item: item,
        quantity: size,
        unit: unitText,
        price: price.toStringAsFixed(0),
        amount: total.toStringAsFixed(0),
        isDebt: _isDebt,
      ));
      _unitController.clear();
      _selectedUnitLabel = "pcs";
      _totalPiecesSuffix = _isBulkItem ? "kg" : "pcs";
      _priceController.clear();
      _isDebt = false;
    });
  }

  double _getMoneyMultiplier(String text) {
    if (text.isEmpty) return 1.0;
    String lower = text.toLowerCase().trim();
    final match = RegExp(r'^(\d+(\.\d+)?)').firstMatch(lower);
    if (match != null) {
      return double.tryParse(match.group(1)!) ?? 1.0;
    }
    return 1.0;
  }

  void _checkout() async {
    if (_isCheckingOut) return;
    setState(() {
      _isCheckingOut = true;
    });

    ProcessingLoadingDialog.show(
      context,
      title: 'Processing Sale...',
      message: 'Recording items and syncing data. Please wait...',
      themeColor: AppColors.primaryGreen,
    );

    final cartCopy = List<SaleItem>.from(_cart);
    final customerCopy = _customerController.text.isEmpty ? 'Walk-in Customer' : _customerController.text;
    final totalAmountCopy = _calculateTotalNum();
    final itemsCountCopy = cartCopy.length;
    final String receiptId = DatabaseHelper.generateUUID();

    try {
      for (var item in cartCopy) {
        double price = double.parse(item.price);
        double amount = double.parse(item.amount);
        String type = "RETAIL";
        String u = item.unit.toLowerCase();
        if (u.contains("half doz") || u.contains("carton") || u.contains("dozen") || u.contains("box") || u.contains("crate")) {
          type = "WHOLESALE";
        }
        await DatabaseHelper.instance.addSaleWithProfit(
          customerCopy, item.item, item.quantity, item.unit, price, amount, type, isDebt: item.isDebt, receiptId: receiptId
        );
        await DatabaseHelper.instance.updateStockQuantity(
          item.item, item.quantity, item.unit
        );
      }

      if (cartCopy.isNotEmpty) {
        String itemsStr = cartCopy.map((e) => e.item).join(", ");
        bool hasDebt = cartCopy.any((e) => e.isDebt);
        String action = hasDebt ? "Debt recorded" : "Sale made";
        await DatabaseHelper.instance.addNotification(
          "$action for $customerCopy: $itemsStr",
          "Mobile",
          targetType: hasDebt ? 'debt' : 'sale',
          targetId: receiptId,
        );
        try {
          await AuditService.instance.logAction(
            action: hasDebt ? 'DEBT_RECORDED' : 'SALE_COMPLETED',
            details: {
              'customer': customerCopy,
              'receipt_id': receiptId,
              'total_amount': totalAmountCopy,
              'items': cartCopy.map((e) => {'item': e.item, 'quantity': e.quantity, 'amount': e.amount, 'is_debt': e.isDebt}).toList(),
            },
          );
        } catch (e) {
          debugPrint('Error logging sale audit: $e');
        }
      }

      await SupasService.instance.uploadDatabase();

      if (mounted) {
        ProcessingLoadingDialog.hide(context);

        setState(() {
          _cart.clear();
          _customerController.clear();
          _selectedItem = null;
          _selectedSize = null;
          _availableSizes = [];
          _currentStock = "";
          _selectedUnitLabel = "pcs";
        });

        TransactionSuccessDialog.show(
          context,
          type: TransactionType.sale,
          receiptId: receiptId,
          partyName: customerCopy,
          totalAmount: totalAmountCopy,
          totalItemsCount: itemsCountCopy,
          items: cartCopy.map((item) => SuccessItemSummary(
            name: item.item,
            quantity: item.quantity,
            unit: item.unit,
            price: double.tryParse(item.price) ?? 0,
            amount: double.tryParse(item.amount) ?? 0,
            isDebt: item.isDebt,
          )).toList(),
          onPrint: () async {
            _printInvoice(customerCopy, cartCopy);
          },
          onDone: () {},
        );
      }
    } catch (e) {
      if (mounted) {
        ProcessingLoadingDialog.hide(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e', style: GoogleFonts.outfit())),
        );
      }
    } finally {
      setState(() {
        _isCheckingOut = false;
      });
    }
  }

  void _printInvoice(String customer, List<SaleItem> cart) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Searching for MPT-II printer...', style: GoogleFonts.outfit()), duration: const Duration(seconds: 2)),
      );

      await PrinterService.instance.printInvoice(
        customer,
        cart,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.accentRed,
            content: Text('Printing Failed: ${e.toString().replaceAll("Exception: ", "")}', style: GoogleFonts.outfit()),
            action: SnackBarAction(label: 'Retry', textColor: Colors.white, onPressed: () => _printInvoice(customer, cart)),
          ),
        );
      }
    }
  }

  double _calculateTotalNum() {
    double total = 0;
    for (var item in _cart) {
      total += double.tryParse(item.amount) ?? 0;
    }
    return total;
  }
}

// Searchable Modal Bottom Sheet Picker Widget for ProcessSaleScreen
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

          // "Add New" Quick Action Row
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
