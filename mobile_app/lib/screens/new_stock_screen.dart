import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/colors.dart';
import '../utils/formatters.dart';
import '../services/database_helper.dart';
import '../services/supabase_service.dart';
import '../models/stock_item.dart';
import '../widgets/common_app_bar_actions.dart';
import '../widgets/transaction_success_dialog.dart';
import '../widgets/processing_loading_dialog.dart';
import 'package:intl/intl.dart';

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

  // Data from Mockup
  final List<String> _qtyQuickButtons = ["None", "g", "kg", "ml", "l", "inch", "50kg", "25kg", "10kg"];
  final List<Map<String, String>> _unitQuickButtons = [
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
              // Get current unit multiplier
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
    // Theme Colors
    final bgColor = AppColors.background;
    final surfaceColor = Colors.white;
    final borderColor = const Color(0xFFE2E8F0);
    final textDark = const Color(0xFF334155);
    final textGray = const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: surfaceColor,
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
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
                'New Stock Entry',
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
                  flex: 4, 
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _buildFormSection(surfaceColor, borderColor, textDark, textGray),
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
                         _buildListHeader(borderColor, textDark, textGray),
                         Expanded(child: _buildItemsList(borderColor, textDark, textGray, isMobile: false)),
                         _buildFooter(surfaceColor, borderColor, textDark, textGray),
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
                   _buildFormSection(surfaceColor, borderColor, textDark, textGray),
                   const SizedBox(height: 24),
                   // Create a container for the list that mimics the right side of desktop but fits in column
                   Container(
                     decoration: BoxDecoration(
                       color: surfaceColor,
                       borderRadius: BorderRadius.circular(12),
                       border: Border.all(color: borderColor),
                       boxShadow: [
                         BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
                       ]
                     ),
                     child: Column(
                       children: [
                         _buildListHeader(borderColor, textDark, textGray),
                         _buildItemsList(borderColor, textDark, textGray, isMobile: true),
                         _buildFooter(surfaceColor, borderColor, textDark, textGray),
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

  Widget _buildFormSection(Color surface, Color border, Color textDark, Color textGray) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note, color: AppColors.primaryGreen, size: 28),
              const SizedBox(width: 8),
              Text(
                "Entry Details",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          _buildLabel("Supplier Name"),
          TextFormField(
            controller: _supplierController,
            style: TextStyle(color: textDark, fontSize: 15),
            decoration: _inputDecoration().copyWith(
              hintText: "Enter Supplier Name",
              suffixIcon: PopupMenuButton<String>(
                icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                onSelected: (String value) {
                  setState(() {
                    _supplierController.text = value;
                  });
                },
                itemBuilder: (BuildContext context) {
                  return _recentSuppliers.map((supplier) => PopupMenuItem<String>(
                    value: supplier,
                    child: Text(supplier),
                  )).toList();
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
          
          _buildLabel("Item Name"),
          TextFormField(
            controller: _itemController,
            style: TextStyle(color: textDark, fontSize: 15),
            decoration: _inputDecoration().copyWith(
              hintText: "Enter or Select Item",
              suffixIcon: PopupMenuButton<String>(
                icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                onSelected: (String value) {
                  setState(() {
                    _itemController.text = value;
                    _selectedItem = value;
                    _loadSizes(value);
                  });
                },
                itemBuilder: (BuildContext context) {
                  return _availableItems.map((item) => PopupMenuItem<String>(
                    value: item,
                    child: Text(item),
                  )).toList();
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
          
          _buildLabel("Item Size / Variant"),
          if (_selectedItem != null)
            DropdownButtonFormField<String>(
                value: _selectedSize,
                hint: const Text("Select Size"),
                isExpanded: true,
                style: TextStyle(color: textDark, fontSize: 15),
                decoration: _inputDecoration(),
                items: [
                    ..._availableSizes.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                    const DropdownMenuItem(value: _addNewSizeOption, child: Text("➕ Add New Size...", style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold))),
                ],
                onChanged: (val) {
                    setState(() {
                        if (val == _addNewSizeOption) {
                            _isNewSize = true;
                            _selectedSize = _addNewSizeOption;
                            _qtyController.clear();
                            _priceController.clear();
                            _isPriceLocked = false;
                        } else {
                            _isNewSize = false;
                            _selectedSize = val;
                            _qtyController.text = val!;
                            _checkExistingPrice();
                            _updatePieceCount(); // Update piece count when size changes
                        }
                    });
                },
            ),
          if (_isNewSize || _selectedItem == null) ...[
              if (_selectedItem != null) const SizedBox(height: 8),
              _buildTextField(_qtyController, "Enter Size (e.g. 50kg)", isNumber: true),
          ],
          if (_isPriceLocked) ...[
              const SizedBox(height: 8),
              _buildNotice("Existing item detected. Price is locked.", AppColors.primaryGreen),
          ],
          const SizedBox(height: 12),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _qtyQuickButtons.map((label) {
                final isSelected = label == "None" 
                    ? _qtyController.text == "None" 
                    : _qtyController.text.endsWith(label);
                return _buildQuickButton(label, () => _appendQty(label), isSelected: isSelected);
              }).toList(),
          ),
          const SizedBox(height: 20),
          
          _buildLabel("Unit Price"),
          Stack(
             children: [
               _buildTextField(_priceController, "0.00", isCurrency: true, paddingLeft: 60, isReadOnly: _isPriceLocked),
               Positioned(
                 left: 16,
                 top: 0,
                 bottom: 0,
                 child: Center(child: Text("UGX", style: TextStyle(color: textGray, fontWeight: FontWeight.bold, fontSize: 12))),
               )
             ],
          ),
          const SizedBox(height: 20),
          
          _buildLabel("Quantity / Count"),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _getFilteredUnitButtons().map((u) {
                final isSelected = _isUnitSelected(u['value']);
                final isSack = u['value'] == 'Sack';
                return _buildQuickButton(
                  u['label']!, 
                  () => _appendUnit(u['value']!), 
                  isBlue: !isSack && isSelected,
                  isSelected: isSelected,
                  customColor: isSack ? Colors.orange : null,
                );
              }).toList(),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9), // slate-100
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
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
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 32, color: textDark),
                            decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                hintText: "0",
                            ),
                        ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text(
                                _selectedUnitLabel.toUpperCase(), 
                                style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w900, fontSize: 13)
                            ),
                            Text(
                                _totalPiecesSuffix, 
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textGray)
                            ),
                        ],
                    ),
                ],
            ),
          ),
          
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add_circle, color: Colors.white),
              label: const Text("ADD TO LIST", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildListHeader(Color border, Color textDark, Color textGray) {
      return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border)),
              color: const Color(0xFFF8FAFC).withOpacity(0.5),
          ),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                  Row(
                      children: [
                          Icon(Icons.save_alt, color: AppColors.primaryGreen),
                          const SizedBox(width: 8),
                          Text("Items to Save", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: textDark)),
                      ],
                  ),
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: AppColors.primaryGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.primaryGreen.withOpacity(0.2)),
                      ),
                      child: Text("${_items.length} ITEMS", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryGreen)),
                  )
              ],
          ),
      );
  }
   Widget _buildItemsList(Color border, Color textDark, Color textGray, {required bool isMobile}) {
     if (_items.isEmpty) {
        return SizedBox(
          height: 150,
          child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 40, color: Colors.grey.withOpacity(0.5)),
                  const SizedBox(height: 8),
                  const Text("No items added yet", style: TextStyle(color: Colors.grey)),
                ],
              )
          ),
        );
     }
     
     final listView = ListView.separated(
       padding: EdgeInsets.zero,
       shrinkWrap: isMobile,
       physics: isMobile ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
       itemCount: _items.length,
       separatorBuilder: (c, i) => Divider(height: 1, color: border),
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
                                 Text(item.item, style: TextStyle(fontWeight: FontWeight.w500, color: textDark, fontSize: 14)),
                                 if (item.quantity.isNotEmpty && item.quantity != "None")
                                    Text("Size: ${item.quantity}", style: TextStyle(color: textGray, fontSize: 12)),
                             ],
                         ),
                     ),
                     Expanded(
                         flex: 2,
                         child: Center(
                             child: Container(
                                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                 decoration: BoxDecoration(
                                     color: Colors.blue.withOpacity(0.1),
                                     borderRadius: BorderRadius.circular(4),
                                 ),
                                 child: Text(item.unit, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue)),
                             ),
                         ),
                     ),
                     Expanded(
                         flex: 3,
                         child: Column(
                             crossAxisAlignment: CrossAxisAlignment.end,
                             children: [
                                 Text("UGX ${_formatter.format(double.tryParse(item.price) ?? 0)}", style: TextStyle(fontWeight: FontWeight.w600, color: textDark, fontSize: 13)),
                                 Text("Total: ${_formatter.format(double.tryParse(item.amount.replaceAll(',', '')) ?? 0)}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                             ],
                         ),
                     ),
                     Expanded(
                         flex: 2,
                         child: Align(
                             alignment: Alignment.centerRight,
                             child: IconButton(
                                 icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
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
            decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC).withOpacity(0.8),
                border: Border(bottom: BorderSide(color: border)),
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
         // List
         isMobile ? listView : Expanded(child: listView),
       ],
     );
  }
  
  Widget _buildFooter(Color surface, Color border, Color textDark, Color textGray) {
     double totalVal = 0;
     for (var i in _items) {
         totalVal += double.tryParse(i.amount.replaceAll(',', '')) ?? 0;
     }
     
     return Container(
         padding: const EdgeInsets.all(20),
         decoration: BoxDecoration(
             color: const Color(0xFFF8FAFC),
             border: Border(top: BorderSide(color: border)),
         ),
         child: Column(
             children: [
                 Row(
                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                     children: [
                         Text("Total Value", style: TextStyle(color: textGray, fontSize: 14, fontWeight: FontWeight.w500)),
                         Text("UGX ${_formatter.format(totalVal)}", style: const TextStyle(color: AppColors.primaryGreen, fontSize: 18, fontWeight: FontWeight.bold)),
                     ],
                 ),
                 const SizedBox(height: 16),
                 SizedBox(
                     width: double.infinity,
                     child: ElevatedButton(
                         onPressed: _items.isNotEmpty ? _saveStock : null,
                         style: ElevatedButton.styleFrom(
                             backgroundColor: textDark, // "gray-800"
                             foregroundColor: Colors.white,
                             padding: const EdgeInsets.symmetric(vertical: 16),
                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                         ),
                         child: const Text("Save Stock", style: TextStyle(fontWeight: FontWeight.w600)),
                     ),
                 ),
             ],
         ),
     );
  }

  // Styles & Components
  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF64748B), // text-gray-500
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
  
  TextStyle _tableHeaderStyle() {
      return const TextStyle(
          fontSize: 10, 
          fontWeight: FontWeight.bold, 
          color: Color(0xFF64748B), 
          letterSpacing: 0.5
      );
  }
  
  InputDecoration _inputDecoration({double paddingLeft = 16}) {
      return InputDecoration(
          filled: true,
          fillColor: const Color(0xFFF8FAFC), // gray-50
          contentPadding: EdgeInsets.fromLTRB(paddingLeft, 20, 16, 20),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: const Color(0xFFE2E8F0)), // border-light
          ),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
          ),
          hintStyle: const TextStyle(color: Color(0xFF94A3B8)), // placeholder-gray-400
      );
  }
  
  Widget _buildTextField(TextEditingController controller, String hint, {bool isNumber = false, bool isCurrency = false, double paddingLeft = 16, bool isReadOnly = false, String? suffixText, Widget? prefixIcon, Widget? suffixIconButton}) {
      return TextField(
          controller: controller,
          readOnly: isReadOnly,
          keyboardType: (isNumber || isCurrency) ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          inputFormatters: isCurrency 
            ? [ThousandsFormatter()] 
            : (isNumber ? [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                TextInputFormatter.withFunction((oldValue, newValue) {
                    if (newValue.text.startsWith('.')) return oldValue;
                    if (newValue.text.contains('.') && newValue.text.indexOf('.') != newValue.text.lastIndexOf('.')) return oldValue;
                    return newValue;
                }),
              ] : null),
          style: TextStyle(color: isReadOnly ? Colors.grey : const Color(0xFF334155), fontWeight: FontWeight.w500),
          decoration: _inputDecoration(paddingLeft: paddingLeft).copyWith(
              hintText: hint,
              fillColor: isReadOnly ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
              suffixText: suffixText,
              suffixIcon: suffixIconButton,
              suffixStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.grey),
              prefixIcon: prefixIcon,
          ),
      );
  }
  
  Widget _buildQuickButton(String label, VoidCallback onTap, {bool isBlue = false, bool isSelected = false, Color? customColor}) {
      // If isSelected, use Light Blue. Otherwise use Green (or customColor).
      final color = isSelected 
          ? (customColor != null ? customColor : Colors.blue) 
          : (customColor != null ? customColor : AppColors.primaryGreen);
      
      return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1), 
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Text(
                  label, 
                  style: TextStyle(
                      fontSize: 13, 
                      color: color, 
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600
                  ),
              ),
          ),
      );
  }
  
  bool _isUnitSelected(String? btnValue) {
      if (btnValue == null) return false;
      String selected = _selectedUnitLabel.toLowerCase().replaceAll(' ', '');
      String button = btnValue.toLowerCase().replaceAll(' ', '');
      
      // Case 1: Exact match
      if (selected == button) return true;
      
      // Case 2: Selected contains the button value
      if (selected.contains(button)) return true;
      
      // Case 3: Handle "pcs"
      if (button == "pcs" && (selected == "pcs" || selected.endsWith("pcs"))) return true;
      
      return false;
  }
  
  Widget _buildNotice(String message, Color color) {
       return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4)
          ),
          child: Row(
              children: [
                  Icon(Icons.info_outline, size: 16, color: color),
                  const SizedBox(width: 8),
                  Expanded(child: Text(message, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12))),
              ],
          ),
      );
  }

  // Logic Helpers
  void _appendQty(String val) {
    if (val == "None") {
        _qtyController.text = "None";
        return;
    }
    
    // If val starts with a number (e.g. "50kg"), replace everything
    if (RegExp(r'^\d').hasMatch(val)) {
        _qtyController.text = val;
        return;
    }

    String current = _qtyController.text;
    if (current == "None") current = "";

    // Extract numeric part from current text
    final match = RegExp(r'^(\d+(\.\d+)?)').firstMatch(current);
    if (match != null) {
        String numPart = match.group(1)!;
        _qtyController.text = numPart + val;
    } else {
        // No numeric part, just replace or append if empty
        _qtyController.text = val;
    }
  }

  List<Map<String, String>> _getFilteredUnitButtons() {
      final sizeText = _qtyController.text;
      final sizeVal = DatabaseHelper.instance.extractNumericValue(sizeText);
      final isKg = sizeText.toLowerCase().contains("kg");
      
      if (isKg && sizeVal > 9.0) {
          // ONLY Sack for bulk > 9kg
          return _unitQuickButtons.where((u) => u['value'] == 'Sack').toList();
      } else {
          // Hide Sack for non-bulk
          return _unitQuickButtons.where((u) => u['value'] != 'Sack').toList();
      }
  }

  void _appendUnit(String val) {
     String cleanVal = DatabaseHelper.instance.cleanUnitLabel(val);
     String unitLabel = cleanVal;
     
     // Extract multiplier label for display
     if (cleanVal == "half doz") unitLabel = "H.Doz";
     else if (cleanVal == "dozen") unitLabel = "Doz";
     else if (cleanVal.contains("box*")) unitLabel = "Box";
     else if (cleanVal == "crate") unitLabel = "Crate";
     else if (cleanVal == "pcs") unitLabel = "pcs";

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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
          return;
      }

      String supplier = _supplierController.text;
      String item = _itemController.text;
      String quantity = _qtyController.text;
      // Unit Validation: ensure it has kg, g, ml, l or is "None"
      final hasUnit = RegExp(r'(kg|g|ml|l|inch)$', caseSensitive: false).hasMatch(quantity) || quantity == "None";
      if (!hasUnit) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please specify a unit (e.g. kg, g, ml, l) for size')));
          return;
      }
      String unitText = "${_unitController.text} $_selectedUnitLabel";
      // Use robust parsing to allow things like "1,000 pkg"
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
              amount: total.toStringAsFixed(0)
          ));
          
          // Only clear size/unit/price — keep supplier and item name
          // so the user can quickly add more sizes of the same item.
          _qtyController.clear();
          _unitController.clear();
          _priceController.clear();
          _selectedSize = null;
          _isNewSize = false;
          _isPriceLocked = false;
          _selectedUnitLabel = "pcs";
          _totalPiecesSuffix = "pcs";
          
          // Reload sizes for the same item so the dropdown is ready
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
              await DatabaseHelper.instance.addNotification("Added $itemsStr from $supplier", "Mobile");
          }

          // Trigger background upload
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
                onDone: () {
                  // Form is ready for more stock input
                },
              );
          }
      } catch (e) {
         if (mounted) {
           ProcessingLoadingDialog.hide(context);
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
         }
      }
  }
}


