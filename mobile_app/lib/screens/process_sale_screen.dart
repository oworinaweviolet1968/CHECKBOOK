import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/colors.dart';
import '../utils/formatters.dart';
import '../services/database_helper.dart';
import '../services/supabase_service.dart';
import '../models/sale_item.dart';
import 'package:intl/intl.dart';

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
  
  String? _selectedItem;
  String? _selectedSize;
  String _currentStock = "";
  String _selectedUnitLabel = "pcs"; // e.g. "Box", "Sack"
  String _totalPiecesSuffix = "pcs"; // e.g. "72 pcs"

  // Quick Buttons
  final List<String> _weightButtons = ["Quarter", "Half", "Sack"];
  final List<Map<String, String>> _unitOptions = [
    {"label": "pcs * 1", "value": "pcs"},
    {"label": "Sack", "value": "Sack"},
    {"label": "Half Doz * 6", "value": "half doz"},
    {"label": "Box * 12", "value": "box*12"},
    {"label": "Box * 10", "value": "box*10"},
    {"label": "Box * 20", "value": "box*20"},
    {"label": "Box * 24", "value": "box*24"},
    {"label": "Crate * 25", "value": "crate"},
    {"label": "Box * 72", "value": "box*72"},
  ];

  bool _isBulkItem = false; 
  final _formatter = NumberFormat("#,###");

  @override
  void initState() {
    super.initState();
    _loadItems();
    _unitController.addListener(_updatePieceCount);
  }

  void _updatePieceCount() {
    String text = _unitController.text;
    double count = DatabaseHelper.instance.extractNumericValue(text);
    double multiplier = DatabaseHelper.instance.getUnitMultiplier(_selectedUnitLabel, _selectedSize ?? "");
    double total = count * multiplier;
    
    setState(() {
       _totalPiecesSuffix = "${total.toStringAsFixed(0)} pcs";
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

  void _updateStockDisplay() async {
      if (_selectedItem != null && _selectedSize != null) {
          // Filter in memory for simplicity or add specific query
          // Using existing query for now to match logic
          // Or better, use specific query if available?
          // Let's use getAvailableStockString if possible, checking logic.
          // Since getAvailableStockString returns "quantity (Check...)" which is not great,
          // let's query raw to get exact number.
          
           final db = await DatabaseHelper.instance.database;
           final result = await db.rawQuery(
               "SELECT quantity, unit, available_pieces FROM stock WHERE item = ? AND quantity = ?",
               [_selectedItem, _selectedSize]
           );
           
           if (result.isNotEmpty && mounted) {
               double avail = (result.first['available_pieces'] as num).toDouble();
               String unit = result.first['quantity'].toString();
                String display = DatabaseHelper.instance.formatStockForDisplay(avail, result.first['unit'] as String, unit);

               
               setState(() {
                   _currentStock = "Stock: $display";
                    
                    // Auto-select unit from stocking if none selected
                    String rawUnit = result.first['unit'] as String;
                    if (_unitController.text.isEmpty) {
                        _selectedUnitLabel = rawUnit; 
                        _appendUnit(rawUnit);
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Process Sale', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(color: Colors.grey.shade200, height: 1)
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isWide = constraints.maxWidth > 800;
          
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Form Section (Scrollable)
                Expanded(
                  flex: 7,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _buildFormSection(),
                  ),
                ),
                // Separator
                Container(width: 1, color: Colors.grey.shade200),
                // Cart Section (Fixed/Sticky-ish)
                Expanded(
                  flex: 5,
                  child: Container(
                      color: Colors.white,
                      height: constraints.maxHeight, // Fill height
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
                   const SizedBox(height: 80), // Bottom padding for Fab/NavBar if needed
                ],
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildFormSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Customer Name
        _buildLabel("Customer Name"),
        const SizedBox(height: 6),
        TextFormField(
            controller: _customerController,
            decoration: _inputDecoration("Search or enter customer name", Icons.person),
        ),
        const SizedBox(height: 16),
        
        // Item
        _buildLabel("Select Item"),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
            value: _selectedItem,
            hint: const Text("Select Item"),
            decoration: _inputDecoration("Search item by name", Icons.inventory_2),
            isExpanded: true,
            items: _availableItems.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
            onChanged: (val) {
                if (val != null) {
                    setState(() {
                        _selectedItem = val;
                        _unitController.clear();
                        _selectedUnitLabel = "pcs";
                        _loadSizes(val);
                    });
                }
            },
        ),
        const SizedBox(height: 16),

        Row(
            children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            _buildLabel("Size"),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                                value: _selectedSize,
                                hint: const Text("Select size"),
                                decoration: _inputDecoration("Select size", null), // No icon for size
                                isExpanded: true,
                                items: _availableSizes.map((size) => DropdownMenuItem(value: size, child: Text(size))).toList(),
                                onChanged: (val) {
                                    if (val != null) {
                                        setState(() {
                                            _selectedSize = val;
                                            _unitController.clear();
                                            _selectedUnitLabel = "pcs";
                                            _checkBulkStatus(val);
                                            _updateStockDisplay();
                                        });
                                    }
                                },
                            ),
                        ],
                    ),
                ),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            _buildLabel("Unit Price"),
                            const SizedBox(height: 6),
                            TextFormField(
                                controller: _priceController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [ThousandsFormatter()],
                                decoration: _inputDecoration("Enter Price", null, prefixText: "UGX "),
                            ),
                        ],
                    ),
                ),
            ],
        ),
        const SizedBox(height: 16),
        
        // Quantity / Unit
        Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
                _buildLabel("Quantity / Unit"),
                if (_currentStock.isNotEmpty)
                    Text(_currentStock, style: const TextStyle(fontSize: 12, color: AppColors.primaryGreen, fontWeight: FontWeight.bold)),
            ],
        ),
        const SizedBox(height: 6),
        Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                SizedBox(
                    width: 100,
                    child: TextFormField(
                        controller: _unitController,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        decoration: _inputDecoration("", null).copyWith(
                            suffixText: " $_totalPiecesSuffix",
                            suffixStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.grey)
                        ),
                    ),
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Wrap(
                        spacing: 8.0,
                        runSpacing: 8.0,
                        children: _isBulkItem 
                        ? _weightButtons.map((u) {
                             final isSelected = u.toLowerCase().replaceAll(' ', '') == _selectedUnitLabel.toLowerCase().replaceAll(' ', '');
                             return _buildQuickBtn(u, isSelected ? Colors.blue.shade50 : Colors.orange.shade50, isSelected ? Colors.blue.shade700 : Colors.orange.shade700, isSelected: isSelected);
                        }).toList()
                        : _unitOptions.map((u) {
                             final isSelected = u['value']!.toLowerCase().replaceAll(' ', '') == _selectedUnitLabel.toLowerCase().replaceAll(' ', '');
                             return _buildQuickBtn(u['label']!, isSelected ? Colors.blue.shade50 : AppColors.primaryGreen.withValues(alpha: 0.1), isSelected ? Colors.blue.shade700 : AppColors.primaryGreen, value: u['value'], isSelected: isSelected);
                        }).toList(),
                    ),
                ),
            ],
        ),
        
        const SizedBox(height: 32),
        
        // Add to Cart Button
        ElevatedButton(
            onPressed: _addToCart,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 4,
                shadowColor: AppColors.primaryGreen.withValues(alpha: 0.4),
            ),
            child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                    Icon(Icons.add_shopping_cart),
                    SizedBox(width: 8),
                    Text("Add to Cart", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
            ),
        ),
      ],
    );
  }

  Widget _buildCartSection({required bool isWide}) {
      return Container(
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: isWideScreen(context) ? [] : [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))
              ],
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                  // Header
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                              Row(
                                  children: [
                                      const Icon(Icons.shopping_basket, color: AppColors.primaryGreen, size: 20),
                                      const SizedBox(width: 8),
                                      Text("Current Cart (${_cart.length})", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                                  ],
                              ),
                              if (_cart.isNotEmpty)
                                  TextButton(
                                      onPressed: () => setState(() => _cart.clear()),
                                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                      child: const Text("Clear All", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accentRed)),
                                  )
                          ],
                      ),
                  ),
                  
                  // List
                  isWide
                      ? Expanded(
                          child: _buildCartList(isWide),
                        )
                      : _buildCartList(isWide),

                  // Footer Total
                  Container(
                     padding: const EdgeInsets.all(16), 
                     decoration: BoxDecoration(
                         color: AppColors.primaryGreen.withValues(alpha: 0.05),
                         border: Border(top: BorderSide(color: AppColors.primaryGreen.withValues(alpha: 0.1))),
                     ),
                     child: Column(
                         children: [
                             Row(
                                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                 children: [
                                     const Text("Total Amount", style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                                     Text("UGX ${_formatter.format(_calculateTotalNum())}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: AppColors.primaryGreen)),
                                 ],
                             ),
                             const SizedBox(height: 16),
                             SizedBox(
                                 width: double.infinity,
                                 child: ElevatedButton.icon(
                                     onPressed: _cart.isEmpty ? null : _checkout,
                                     icon: const Icon(Icons.receipt_long, size: 20),
                                     label: const Text("Complete Sale"),
                                     style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.textPrimary, // dark bg
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
  
  // Helpers
  Widget _buildLabel(String text) {
      return Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary));
  }
  
  InputDecoration _inputDecoration(String hint, IconData? icon, {String? prefixText}) {
      return InputDecoration(
          hintText: hint,
          prefixIcon: icon != null ? Icon(icon, color: Colors.grey.shade400, size: 20) : null,
          prefixText: prefixText,
          prefixStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
          filled: true,
          fillColor: Colors.white, // dark:bg-slate-900 logic would go here
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2)),
      );
  }
  
  Widget _buildQuickBtn(String label, Color bg, Color text, {String? value, bool isSelected = false}) {
      final color = isSelected ? Colors.blue.shade800 : text;
      final bgColor = isSelected ? Colors.blue.shade50 : bg;

      return Material(
          color: Colors.transparent,
          child: InkWell(
              onTap: () => _appendUnit(value ?? label),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: bgColor,
                      border: Border.all(color: color.withValues(alpha: 0.2)),
                      borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600, color: color)),
              ),
          ),
      );
  }
  
  bool isWideScreen(BuildContext context) => MediaQuery.of(context).size.width > 800;

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

  void _checkBulkStatus(String size) {
      double val = DatabaseHelper.instance.extractNumericValue(size);
      bool isBulk = size.toLowerCase().contains("kg") && val >= 10.0;
      setState(() {
          _isBulkItem = isBulk;
      });
  }

  void _appendUnit(String val) async {
     String unitLabel = val;
     String vNorm = val.toLowerCase().replaceAll(' ', '');
     
     // Extract multiplier label for display
     if (vNorm == "halfdoz") unitLabel = "H.Doz";
     else if (vNorm == "dozen" || vNorm == "doz") unitLabel = "Doz";
     else if (vNorm.contains("box*")) unitLabel = "Box";
     else if (vNorm == "crate") unitLabel = "Crate";
     else if (vNorm == "pcs") unitLabel = "pcs";
     else if (vNorm == "half") unitLabel = "Half";
     else if (vNorm == "quarter") unitLabel = "Quarter";
     else if (vNorm == "sack") unitLabel = "Sack";

     String currentText = _unitController.text;
     double currentNum = DatabaseHelper.instance.extractNumericValue(currentText);
     if (currentNum <= 0) currentNum = 1;

     setState(() {
         _selectedUnitLabel = val;
         // Display format: "3 Box"
         if (unitLabel.toLowerCase() == "pcs") {
            _unitController.text = currentNum.toStringAsFixed(0);
         } else {
            _unitController.text = "${currentNum.toStringAsFixed(0)} $unitLabel";
         }
     });
  }

  void _addToCart() async {
      if (_customerController.text.isEmpty || _selectedItem == null || _selectedSize == null ||
          _unitController.text.isEmpty || _priceController.text.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
          return;
      }
      
      String item = _selectedItem!;
      String size = _selectedSize!;
      String unitText = "${_unitController.text} $_selectedUnitLabel";
      // Use robust parsing to allow things like "1,000 negotiated"
      double price = DatabaseHelper.instance.extractNumericValue(_priceController.text);
      
      // Stock Check
      bool hasStock = await DatabaseHelper.instance.hasEnoughStock(item, size, unitText);
      if (!mounted) return;
      if (!hasStock) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.red, content: Text('Not enough stock!')));
          return;
      }
      
      // Calculate Total Amount
      double count = _getMoneyMultiplier(unitText);
      double total = count * price;

      // LOSS CHECK
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
                       title: const Text("Warning: Loss Sale", style: TextStyle(color: Colors.red)),
                       content: Text("You are selling below cost price!\n\nUnit Cost: ${_formatter.format(unitCost)}\nSelling Price: ${_formatter.format(price)}\n\nAre you sure you want to proceed?"),
                       actions: [
                           TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                           TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Confirm Loss Sale", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                       ],
                   )
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
              amount: total.toStringAsFixed(0)
          ));
          _unitController.clear();
          _selectedUnitLabel = "pcs";
          _totalPiecesSuffix = "pcs";
          // Price clear? Mockup clears? Usually keep price for speed if same item?
          // Let's clear for safety.
          _priceController.clear();
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

  Widget _buildCartList(bool isWide) {
      if (_cart.isEmpty) {
        return const SizedBox(
            height: 150,
            child: Center(child: Padding(padding: EdgeInsets.all(32), child: Text("Cart is empty", style: TextStyle(color: AppColors.textSecondary))))
        );
      }
      
      return ListView.separated(
          padding: EdgeInsets.zero,
          shrinkWrap: !isWide, // True on mobile to allow scroll inside parent
          physics: isWide ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics(),
          itemCount: _cart.length,
          separatorBuilder: (c, i) => Divider(height: 1, color: Colors.grey.shade100),
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
                                      Text(item.item, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                      const SizedBox(height: 2),
                                      Text("Size: ${item.quantity} • Qty: ${item.unit}", style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                  ],
                              ),
                          ),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                  Text("UGX ${_formatter.format(double.tryParse(item.amount) ?? 0)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primaryGreen)),
                                  const SizedBox(height: 4),
                                  InkWell(
                                      onTap: () => setState(() => _cart.removeAt(index)),
                                      child: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                                  )
                              ],
                          )
                      ],
                  ),
              );
          },
      );
  }

  void _checkout() async {
      try {
          String customer = _customerController.text;
          for (var item in _cart) {
              double price = double.parse(item.price);
              double amount = double.parse(item.amount);
              String type = "RETAIL";
              String u = item.unit.toLowerCase();
              if (u.contains("half doz") || u.contains("carton") || u.contains("dozen") || u.contains("box") || u.contains("crate")) {
                  type = "WHOLESALE";
              }
              await DatabaseHelper.instance.addSaleWithProfit(
                  customer, item.item, item.quantity, item.unit, price, amount, type
              );
              await DatabaseHelper.instance.updateStockQuantity(
                  item.item, item.quantity, item.unit
              );
          }

          // Trigger background upload
          SupasService.instance.uploadDatabase();
           if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sale Completed Successfully!')));
              setState(() {
                  _cart.clear();
                  _customerController.clear();
                  _selectedItem = null;
                  _selectedSize = null;
                  _availableSizes = [];
                  _currentStock = "";
                  _selectedUnitLabel = "pcs";
              });
          }
      } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
