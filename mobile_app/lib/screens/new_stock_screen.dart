import 'package:flutter/material.dart';
import '../utils/colors.dart';
import '../services/database_helper.dart';
import '../models/stock_item.dart';

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
  
  String? _selectedItem;
  String? _selectedSize;
  
  bool _isNewItem = false;
  bool _isNewSize = false;
  
  static const String _addNewItemOption = "__NEW_ITEM__";
  static const String _addNewSizeOption = "__NEW_SIZE__";

  // Data from Mockup
  final List<String> _qtyQuickButtons = ["None", "g", "kg", "ml", "l", "50kg", "25kg", "10kg"];
  final List<Map<String, String>> _unitQuickButtons = [
    {"label": "pcs * 1", "value": "pcs"},
    {"label": "Sack", "value": "Sack"},
    {"label": "Half Doz * 6", "value": "half doz"},
    {"label": "Dozen * 12", "value": "dozen"},
    {"label": "Box * 20", "value": "box"},
    {"label": "Carton * 24", "value": "carton"},
  ];

  @override
  void initState() {
    super.initState();
    _loadItems();
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
    });
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
        title: Text(
          'New Stock Entry',
          style: TextStyle(
            color: textDark, 
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),

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
                         Expanded(child: _buildItemsList(borderColor, textDark, textGray)),
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
                     height: 600, // Fixed height for list area on mobile to allow scrolling inside it, or minimal height
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
                         Expanded(child: _buildItemsList(borderColor, textDark, textGray)),
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
          _buildTextField(_supplierController, "Enter Supplier Name"),
          const SizedBox(height: 20),
          
          _buildLabel("Item Name"),
          Container(
             decoration: BoxDecoration(
                 color: const Color(0xFFF8FAFC), // gray-50
                 borderRadius: BorderRadius.circular(8),
                 border: Border.all(color: Colors.transparent), // Manage border via decoration or InputDecorator?
             ),
             child: DropdownButtonFormField<String>(
                value: _selectedItem,
                hint: const Text("Select Item"),
                isExpanded: true,
                style: TextStyle(color: textDark, fontSize: 15),
                decoration: _inputDecoration(),
                items: [
                   ..._availableItems.map((item) => DropdownMenuItem(value: item, child: Text(item))),
                   const DropdownMenuItem(value: _addNewItemOption, child: Text("➕ Add New Item...", style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold))),
                ],
                onChanged: (val) {
                   setState(() {
                      if (val == _addNewItemOption) {
                          _isNewItem = true;
                          _selectedItem = _addNewItemOption;
                          _itemController.clear();
                          _availableSizes = [];
                          _selectedSize = null;
                      } else {
                          _isNewItem = false;
                          _selectedItem = val;
                          _itemController.text = val!;
                          _loadSizes(val);
                      }
                   });
                },
             ),
          ),
          if (_isNewItem) ...[
             const SizedBox(height: 8),
             _buildTextField(_itemController, "Enter New Item Name"),
             const SizedBox(height: 4),
             _buildNotice("Adding a NEW Product", Colors.blue),
          ],
          const SizedBox(height: 20),
          
          _buildLabel("Item Size / Variant"),
          DropdownButtonFormField<String>(
              value: _selectedSize,
              hint: const Text("Select Size"),
              isExpanded: true,
              style: TextStyle(color: textDark, fontSize: 15),
              decoration: _inputDecoration(),
              items: _isNewItem 
                  ? [const DropdownMenuItem(value: _addNewSizeOption, child: Text("➕ Add New Size...", style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold)))]
                  : [
                      ..._availableSizes.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                      const DropdownMenuItem(value: _addNewSizeOption, child: Text("➕ Add New Size...", style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold))),
                  ],
              onChanged: (val) {
                  setState(() {
                      if (val == _addNewSizeOption) {
                          _isNewSize = true;
                          _selectedSize = _addNewSizeOption;
                          _qtyController.clear();
                      } else {
                          _isNewSize = false;
                          _selectedSize = val;
                          _qtyController.text = val!;
                      }
                  });
              },
          ),
          if (_isNewSize || _isNewItem) ...[
              const SizedBox(height: 8),
              _buildTextField(_qtyController, "Enter Size (e.g. 50kg)"),
          ],
          const SizedBox(height: 12),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _qtyQuickButtons.map((label) => _buildQuickButton(label, () => _appendQty(label))).toList(),
          ),
          const SizedBox(height: 20),
          
          _buildLabel("Quantity / Count"),
          _buildTextField(_unitController, "Enter Count", isNumber: false), // Needs text for units like "10 sacks"
          const SizedBox(height: 12),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _unitQuickButtons.map((u) => _buildQuickButton(
                  u['label']!, 
                  () => _appendUnit(u['value']!), 
                  isBlue: u['value'] == 'Sack'
              )).toList(),
          ),
          const SizedBox(height: 20),
          
          _buildLabel("Unit Price"),
          Stack(
             children: [
               _buildTextField(_priceController, "0.00", isNumber: true, paddingLeft: 60),
               Positioned(
                 left: 16,
                 top: 0,
                 bottom: 0,
                 child: Center(child: Text("UGX", style: TextStyle(color: textGray, fontWeight: FontWeight.bold, fontSize: 12))),
               )
             ],
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
  
  Widget _buildItemsList(Color border, Color textDark, Color textGray) {
     if (_items.isEmpty) {
        return const Center(child: Text("No items added yet", style: TextStyle(color: Colors.grey)));
     }
     
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
         Expanded(
           child: ListView.separated(
             padding: EdgeInsets.zero,
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
                                       Text("UGX ${item.price}", style: TextStyle(fontWeight: FontWeight.w600, color: textDark, fontSize: 13)),
                                       Text("Total: ${item.amount}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
           ),
         ),
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
                         Text("UGX ${totalVal.toStringAsFixed(0)}", style: const TextStyle(color: AppColors.primaryGreen, fontSize: 18, fontWeight: FontWeight.bold)),
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
          contentPadding: EdgeInsets.fromLTRB(paddingLeft, 16, 16, 16),
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
  
  Widget _buildTextField(TextEditingController controller, String hint, {bool isNumber = false, double paddingLeft = 16}) {
      return TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          style: const TextStyle(color: Color(0xFF334155), fontWeight: FontWeight.w500),
          decoration: _inputDecoration(paddingLeft: paddingLeft).copyWith(hintText: hint),
      );
  }
  
  Widget _buildQuickButton(String label, VoidCallback onTap, {bool isBlue = false}) {
      // User requested all buttons to look like the "Sack" button (which was blue) but in Green.
      // So we ignore isBlue and apply Green style to all.
      const color = AppColors.primaryGreen;
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
                      fontWeight: FontWeight.w600 // Slightly bolder to match "Sack" look
                  ),
              ),
          ),
      );
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
                  Text(message, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
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
    String current = _qtyController.text;
    if (current.isEmpty) {
        _qtyController.text = val;
    } else {
        _qtyController.text = current + val;
    }
  }

  void _appendUnit(String val) {
     String current = _unitController.text;
     String number = current.replaceAll(RegExp(r'[^0-9.]'), '').trim();
     if (number.isEmpty) number = "1";

     String unitToUse = val;
     if (val == "half doz") unitToUse = "1/2 doz"; // mapping logic
     
     _unitController.text = "$number $unitToUse";
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
      String unitText = _unitController.text;
      double price = double.tryParse(_priceController.text.replaceAll(',', '')) ?? 0.0;
      
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
          
          _qtyController.clear();
          _unitController.clear();
          _priceController.clear();
          // Keep item logic?
          _itemController.clear(); 
          _selectedItem = null;
          _selectedSize = null;
          _availableSizes = [];
          _isNewItem = false;
          _isNewSize = false;
      });
  }

  void _saveStock() async {
      try {
          for (var item in _items) {
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
                   item.supplier, item.item, item.quantity, item.unit, price, amount, "NEW STOCK"
               );
          }

          if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock Saved Successfully!')));
              setState(() {
                  _items.clear();
                  _supplierController.clear();
                  _itemController.clear();
                  _selectedItem = null;
                  _selectedSize = null;
                  _availableSizes = [];
                  _isNewItem = false;
                  _isNewSize = false;
              });
              _loadItems();
          }
      } catch (e) {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
  }
}
