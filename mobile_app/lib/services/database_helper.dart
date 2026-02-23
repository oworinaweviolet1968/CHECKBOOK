import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/history_item.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  String _dbName = 'inventory.db';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(_dbName);
    return _database!;
  }

  // --- DATABASE MANAGEMENT ---

  Future<void> switchDatabase(String userId) async {
    // Sanitize userId (match JavaFX logic)
    String cleanId = userId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    String newDbName = "inventory_$cleanId.db";

    if (_dbName == newDbName && _database != null) return;

    // Close current
    if (_database != null) {
      await _database!.close();
      _database = null;
    }

    _dbName = newDbName;
    // Database will be re-initialized on next 'get database' call
  }

  Future<bool> hasData() async {
    final db = await instance.database;
    final stock = await db.rawQuery('SELECT COUNT(*) as count FROM stock');
    final sales = await db.rawQuery('SELECT COUNT(*) as count FROM sales');

    int stockCount = Sqflite.firstIntValue(stock) ?? 0;
    int salesCount = Sqflite.firstIntValue(sales) ?? 0;

    return stockCount > 0 || salesCount > 0;
  }

  // --- HISTORY & SALES ---

  Future<List<HistoryItem>> getHistory(String filter) async {
    final db = await instance.database;
    String sql = "SELECT customer, item, type, quantity, unit, price, cost_price, base_quantity, amount, date FROM sales WHERE 1=1";

    List<dynamic> args = [];
    if (filter.isNotEmpty && filter != "ALL") {
        sql += " AND type = ?";
        args.add(filter);
    }
    sql += " ORDER BY date DESC, created_at DESC";

    final result = await db.rawQuery(sql, args);
    
    return result.map((rs) {
        double amount = (rs['amount'] as num).toDouble();
        double cost = (rs['cost_price'] as num).toDouble();
        double baseQty = (rs['base_quantity'] as num).toDouble();
        double profitVal = amount - (cost * baseQty);
        
        return HistoryItem(
            customer: rs['customer'] as String,
            item: rs['item'] as String,
            type: rs['type'] as String,
            quantity: rs['quantity'] as String,
            unit: rs['unit'] as String,
            price: (rs['price'] as num).toStringAsFixed(0),
            amount: amount.toStringAsFixed(0),
            profit: profitVal.toStringAsFixed(0),
            date: rs['date'] as String
        );
    }).toList();
  }

  Future<List<HistoryItem>> getTodaysSales() async {
      final db = await instance.database;
      final today = DateTime.now().toIso8601String().split('T')[0];
      
      final result = await db.rawQuery(
          "SELECT customer, item, type, quantity, unit, price, amount, cost_price, base_quantity, date FROM sales WHERE date = ? AND type != 'NEW STOCK' ORDER BY created_at DESC",
          [today]
      );

      return result.map((rs) {
          double amount = (rs['amount'] as num).toDouble();
          double cost = (rs['cost_price'] as num).toDouble();
          double baseQty = (rs['base_quantity'] as num).toDouble();
          double profitVal = amount - (cost * baseQty);

          return HistoryItem(
              customer: rs['customer'] as String,
              item: rs['item'] as String,
              type: rs['type'] as String,
              quantity: rs['quantity'] as String,
              unit: rs['unit'] as String,
              price: (rs['price'] as num).toStringAsFixed(0),
              amount: amount.toStringAsFixed(0),
              profit: profitVal.toStringAsFixed(0),
              date: rs['date'] as String
          );
      }).toList();
  }


  Future<Database> _initDB(String filePath) async {
    String path;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // Mirror JavaFX logic: ~/METO_IMS_DATA
      final userHome = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
      // Simplified: JavaFX uses METO_IMS_DATA in home
      final dir = Directory(join(userHome, 'METO_IMS_DATA'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      path = join(dir.path, filePath);
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, filePath);
    }

    print('Database Path: $path');

    return await openDatabase(
      path, 
      version: 1, 
      onCreate: _createDB,
      onOpen: (db) async {
         // Ensure schemas if opening existing DB
         // In real sync scenario, we might be overwriting this file entirely,
         // so onOpen might need to re-check if we replaced the file.
      }
    );
  }
  
  // Helper to get the full path for sync operations
  Future<String> getDbPath() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
       final userHome = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
       return join(userHome, 'METO_IMS_DATA', _dbName);
    }
    final dbPath = await getDatabasesPath();
    return join(dbPath, _dbName);
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const realType = 'REAL NOT NULL';
    const realDefault0 = 'REAL DEFAULT 0';
    const dateType = 'TEXT NOT NULL'; // SQLite doesn't have Date type, usually TEXT
    const dateTimeDefault = 'DATETIME DEFAULT CURRENT_TIMESTAMP';

    // Stock Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock (
        id $idType,
        supplier $textType,
        item $textType,
        quantity $textType,
        unit $textType,
        price $realType,
        available_pieces $realDefault0,
        date $dateType,
        created_at $dateTimeDefault
      )
    ''');

    // Sales Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales (
        id $idType,
        customer $textType,
        item $textType,
        quantity $textType,
        unit $textType,
        price $realType,
        cost_price $realDefault0,
        base_quantity $realDefault0,
        amount $realType,
        type $textType,
        date $dateType,
        created_at $dateTimeDefault
      )
    ''');

    // Summary Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS yearly_summaries (
        year INTEGER PRIMARY KEY,
        total_profit REAL,
        total_sales REAL,
        closed_at $dateTimeDefault
      )
    ''');
  }

  // --- Queries matching Java backend ---

  // Dashboard: Total Stock Value
  Future<double> getTotalStockValue() async {
    final db = await instance.database;
    // Calculation: sum(available_pieces * (price / multiplier?))
    // Wait, the Java code stores price per piece in `price` column?
    // Checking Java addStock: 
    // double pricePerSinglePiece = (double) p / multiplier; 
    // pstmt.setDouble(5, pricePerSinglePiece);
    // So 'price' in DB is cost per single piece (base unit).
    // So Value = available_pieces * price.
    
    final result = await db.rawQuery('SELECT SUM(available_pieces * price) as total FROM stock');
    if (result.isNotEmpty && result.first['total'] != null) {
      return (result.first['total'] as num).toDouble();
    }
    return 0.0;
  }

  // Dashboard: Today's Profit
  Future<Map<String, double>> getTodaysStats() async {
     final db = await instance.database;
     final today = DateTime.now().toIso8601String().split('T')[0]; // YYYY-MM-DD
     
     // Profit = amount - (cost_price * base_quantity)
     // Filter: date = today AND type != 'NEW STOCK'
     final result = await db.rawQuery('''
       SELECT 
         SUM(amount) as total_sales,
         SUM(amount - (cost_price * base_quantity)) as total_profit
       FROM sales 
       WHERE date = ? AND type != 'NEW STOCK'
     ''', [today]);
     
     if (result.isNotEmpty) {
       return {
         'sales': (result.first['total_sales'] as num?)?.toDouble() ?? 0.0,
         'profit': (result.first['total_profit'] as num?)?.toDouble() ?? 0.0,
       };
     }
     return {'sales': 0.0, 'profit': 0.0};
  }

  // Dashboard: Yesterday's Profit (for % calc)
  Future<double> getYesterdaysProfit() async {
     final db = await instance.database;
     final yesterday = DateTime.now().subtract(const Duration(days: 1)).toIso8601String().split('T')[0];
     
     final result = await db.rawQuery('''
       SELECT SUM(amount - (cost_price * base_quantity)) as total_profit
       FROM sales 
       WHERE date = ? AND type != 'NEW STOCK'
     ''', [yesterday]);
     
     if (result.isNotEmpty && result.first['total_profit'] != null) {
       return (result.first['total_profit'] as num).toDouble();
     }
     return 0.0;
  }

  // Dashboard: Yearly Profit
  Future<double> getYearlyProfit() async {
    final db = await instance.database;
    final yearPrefix = '${DateTime.now().year}-%';
    
    // Profit = amount - (cost_price * base_quantity)
    // Filter: date LIKE '2024-%' AND type != 'NEW STOCK'
    final result = await db.rawQuery('''
      SELECT SUM(amount - (cost_price * base_quantity)) as total_profit
      FROM sales 
      WHERE date LIKE ? AND type != 'NEW STOCK'
    ''', [yearPrefix]);

    if (result.isNotEmpty && result.first['total_profit'] != null) {
      return (result.first['total_profit'] as num).toDouble();
    }
    return 0.0;
  }

  // Dashboard: Previous Year Profit (Placeholder for % calc)
  Future<double> getPrevYearProfit() async {
      // In a real app with historical data, query for (Year - 1)
      // For now, return a mock small number to show increase, or 0.
      return 1.0; 
  }
  
  // Dashboard: Available Stock List
  Future<List<Map<String, dynamic>>> getAvailableStock() async {
    final db = await instance.database;
    // Java: SELECT item, quantity, available_pieces, price, supplier, date FROM stock ORDER BY item
    return await db.rawQuery('SELECT * FROM stock WHERE available_pieces > 0 ORDER BY item');
  }
  
  // Dashboard: Today's Sales List
  Future<List<Map<String, dynamic>>> getTodaysSalesList() async {
    final db = await instance.database;
    final today = DateTime.now().toIso8601String().split('T')[0];
    return await db.rawQuery(
      "SELECT * FROM sales WHERE date = ? AND type != 'NEW STOCK' ORDER BY created_at DESC", 
      [today]
    );
  }
  
  // --- STOCK OPERATIONS ---

  Future<bool> itemExists(String itemName, String size) async {
    final db = await instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM stock WHERE item = ? AND quantity = ?',
      [itemName, size]
    );
    if (result.isNotEmpty) {
      return (result.first['count'] as num) > 0;
    }
    return false;
  }

  Future<bool> mergeStock(String itemName, String size, String newUnit, double newPrice, String supplier, {bool forceSave = false}) async {
    final db = await instance.database;
    final result = await db.rawQuery(
      'SELECT id, available_pieces, price FROM stock WHERE item = ? AND quantity = ?',
      [itemName, size]
    );

    if (result.isNotEmpty) {
      final row = result.first;
      int id = row['id'] as int;
      double existingPieces = row['available_pieces'] as double;
      double existingCostPerPiece = row['price'] as double;

      double quantityNumber = extractNumericValue(newUnit);
      double multiplier = getUnitMultiplier(newUnit, size);
      double incomingPieces = quantityNumber * multiplier;
      double newCostPerPiece = newPrice / (multiplier > 0 ? multiplier : 1);

      // --- VALIDATION GATE ---
      if (!forceSave && existingCostPerPiece > 0) {
        double diff = (newCostPerPiece - existingCostPerPiece).abs();
        if ((diff / existingCostPerPiece) > 0.20) {
          return false; // Tell the controller to show an alert
        }
      }

      // UPDATE
      await db.rawUpdate(
        'UPDATE stock SET available_pieces = ?, price = ?, supplier = ?, date = ?, unit = ? WHERE id = ?',
        [
          existingPieces + incomingPieces,
          ((existingPieces * existingCostPerPiece) + (incomingPieces * newCostPerPiece)) / (existingPieces + incomingPieces),
          supplier,
          DateTime.now().toString(), // Using full timestamp or just date part? Java uses LocalDate.now()
          cleanUnitLabel(newUnit),
          id
        ]
      );
      return true;
    }
    return false;
  }

  Future<void> addStock(String s, String i, String q, String u, double p, String d) async {
    final db = await instance.database;
    double unitCount = extractNumericValue(u);
    double multiplier = getUnitMultiplier(u, q);
    double totalPieces = unitCount * multiplier;
    
    // Price per single piece (base unit)
    double pricePerSinglePiece = p / (multiplier > 0 ? multiplier : 1); 

    await db.rawInsert(
      'INSERT INTO stock(supplier, item, quantity, unit, price, available_pieces, date) VALUES(?, ?, ?, ?, ?, ?, ?)',
      [s, i, q, cleanUnitLabel(u), pricePerSinglePiece, totalPieces, d]
    );
  }

  Future<void> updateStockQuantity(String itemName, String soldSize, String soldUnit) async {
      final db = await instance.database;
      final result = await db.rawQuery(
        'SELECT id, available_pieces FROM stock WHERE item = ? AND quantity = ?',
        [itemName, soldSize]
      );

      if (result.isNotEmpty) {
          int id = result.first['id'] as int;
          double currentPieces = result.first['available_pieces'] as double;
          double soldPieces = extractNumericValue(soldUnit) * getUnitMultiplier(soldUnit, soldSize);
          double remaining = currentPieces - soldPieces;

          if (remaining >= 0) {
              await db.rawUpdate(
                  'UPDATE stock SET available_pieces = ? WHERE id = ?',
                  [remaining, id]
              );
          }
      }
  }

  Future<bool> hasEnoughStock(String itemName, String size, String soldUnit) async {
      final db = await instance.database;
      final result = await db.rawQuery(
          "SELECT available_pieces FROM stock WHERE item = ? AND quantity = ?",
          [itemName, size]
      );
      if (result.isNotEmpty) {
          double stockAvailable = result.first['available_pieces'] as double;
          // Note: In SalesController, 'soldUnit' passed here acts as the 'Count Unit'
          // Java code calls: extractNumericValue(soldUnit) * getUnitMultiplier(soldUnit, size)
          // BUT wait, SalesController Java logic passes 'weightStr' to 'updateStockQuantity'
          // but passes 'item.getUnit()' (e.g. "2 1/4 kg") to 'hasEnoughStock'.
          double amountTryingToSell = extractNumericValue(soldUnit) * getUnitMultiplier(soldUnit, size);
          return stockAvailable >= amountTryingToSell;
      }
      return false;
  }
  
  Future<String> getAvailableStockString(String itemName, String size) async {
      final db = await instance.database;
      final result = await db.rawQuery(
          "SELECT unit, quantity, available_pieces FROM stock WHERE item = ? AND quantity = ?",
          [itemName, size]
      );
      if (result.isNotEmpty) {
           final row = result.first;
           return formatStockForDisplay(
               (row['available_pieces'] as num).toDouble(), 
               row['unit'] as String, 
               row['quantity'] as String
           );
      }
      return "0";
  }

  String formatStockForDisplay(double availablePieces, String unitLabel, String size) {
      if (availablePieces <= 0) return "0";

      double multiplier = getUnitMultiplier(unitLabel, size);
      String sizeLower = size.toLowerCase();
      String unitLower = unitLabel.toLowerCase();
      
      // If multiplier is 1 or it's a direct unit comparison, just return standard
      if (multiplier <= 1) {
          if (sizeLower.contains("kg")) return "${availablePieces.toStringAsFixed(1)} kg";
          return "${availablePieces.toInt()} pcs";
      }

      int mainUnits = (availablePieces / multiplier).floor();
      double remainder = availablePieces % multiplier;

      // Extract a clean label for the main unit (e.g. "Sack", "Box")
      String cleanMainLabel = "units";
      if (unitLower.contains("sack")) cleanMainLabel = "sack";
      else if (unitLower.contains("box")) cleanMainLabel = "box";
      else if (unitLower.contains("crate")) cleanMainLabel = "crate";
      else if (unitLower.contains("doz") || unitLower.contains("dozen")) cleanMainLabel = "box";
      else if (unitLower.contains("carton")) cleanMainLabel = "carton";

      double sizeVal = extractNumericValue(sizeLower);
      bool isBulkSack = sizeLower.contains("kg") && sizeVal > 9.0;
      String baseUnit = isBulkSack ? "kg" : "pcs";
      
      if (mainUnits > 0) {
          String mainStr = "$mainUnits $cleanMainLabel${mainUnits > 1 ? 's' : ''}";
          if (remainder > 0) {
              String remStr = remainder == remainder.toInt() ? remainder.toInt().toString() : remainder.toStringAsFixed(2);
              return "$mainStr $remStr $baseUnit";
          }
          return mainStr;
      } else {
          String remStr = remainder == remainder.toInt() ? remainder.toInt().toString() : remainder.toStringAsFixed(2);
          return "$remStr $baseUnit";
      }
  }

  // --- SALES OPERATIONS ---

  Future<void> addSaleWithProfit(String customer, String item, String size, String unit, double sellingPrice, double totalAmount, String type) async {
      final db = await instance.database;
      double costPrice = await getLastRecordedPrice(item, size);
      
      double quantityFactor = extractNumericValue(unit);
      double multiplier = getUnitMultiplier(unit, size);
      double baseQty = quantityFactor * multiplier;
      
      // Normalize cost basis for Bulk Items
      // If Cost Price is per Sack (e.g. 50kg), but we sold fractions (e.g. 1kg),
      // baseQty (which is in KG) must be divided by Sack Size to get "Fraction of Sack".
      double sizeVal = extractNumericValue(size);
      bool isBulk = size.toLowerCase().contains("kg") && sizeVal >= 10.0;
      
      if (isBulk && sizeVal > 0) {
           baseQty = baseQty / sizeVal;
      }

      await db.rawInsert(
          'INSERT INTO sales(customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
              customer, item, size, unit, sellingPrice, 
              costPrice, baseQty, totalAmount, type, 
              DateTime.now().toIso8601String().split('T')[0]
          ]
      );
  }

  Future<double> getLastRecordedPrice(String item, String size) async {
      final db = await instance.database;
      final result = await db.rawQuery(
          "SELECT price FROM stock WHERE item = ? AND quantity = ? ORDER BY id DESC LIMIT 1",
          [item, size]
      );
      if (result.isNotEmpty) {
          return result.first['price'] as double;
      }
      return 0.0;
  }

  // --- DATA HELPERS ---

  /// Ported from Java extractNumericValue
  double extractNumericValue(String text) {
    if (text.isEmpty) return 0.0;
    String lowercaseText = text.toLowerCase().trim();
    double fractionValue = 0.0;

    // Handle common fractions at the beginning
    if (lowercaseText.startsWith("1/4")) fractionValue = 0.25;
    else if (lowercaseText.startsWith("1/2")) fractionValue = 0.5;

    // Regex to find the FIRST numeric part (whole number or decimal) at the START of the string
    // This ignores internal numbers like the "72" in "2 box*72"
    final cleaned = lowercaseText
        .replaceAll("1/4", "")
        .replaceAll("1/2", "")
        .replaceAll(",", "")
        .trim();
    final match = RegExp(r'^(\d+(\.\d+)?)').firstMatch(cleaned);
    
    if (match != null) {
        try {
            double wholeNumber = double.parse(match.group(1)!);
            return wholeNumber + fractionValue;
        } catch (e) {
            return fractionValue;
        }
    }
    
    // If no leading number, check if there's just a fraction
    return fractionValue;
  }

  /// Ported from Java getUnitMultiplier
  double getUnitMultiplier(String unitText, String size) {
      String type = unitText.toLowerCase().replaceAll(' ', '');
      String sizeLower = size.toLowerCase().replaceAll(' ', '');

      double sizeNum = extractNumericValue(sizeLower);
      bool isBulkSack = sizeLower.contains("kg") && sizeNum >= 10.0;

      if (type.contains("sack") || (isBulkSack && type.contains("pc"))) {
          return sizeNum;
      }
      if (type.contains("halfdoz")) return 6.0;
      if (type.contains("half")) return 0.5;
      if (type.contains("quarter")) return 0.25;

      if (type.contains("dozen") || type.contains("doz") || type.contains("box*12")) return 12.0;
      if (type.contains("carton") || type.contains("box*24")) return 24.0;
      if (type.contains("crate") || type.contains("crate*25")) return 25.0;
      if (type.contains("box*10")) return 10.0;
      if (type.contains("box*72")) return 72.0;
      if (type.contains("box*20") || type == "box") return 20.0;
      if (type.contains("box")) return 20.0; // Default for other boxes if unspecified 

      return 1.0;
  }

  /// Strips leading numbers/spaces to get a clean unit label for UI/DB
  String cleanUnitLabel(String text) {
      if (text.isEmpty) return "pcs";
      String lower = text.toLowerCase().trim();
      
      // Remove leading numeric part and spaces (e.g., "5 Box * 24" -> "box * 24")
      String cleaned = lower.replaceFirst(RegExp(r'^[\d\s\./]+'), '').trim();
      
      // Map back to standard internal values if possible
      if (cleaned.contains("sack")) return "Sack";
      if (cleaned.contains("halfdoz") || cleaned.contains("half doz")) return "half doz";
      if (cleaned.contains("box*12")) return "box*12";
      if (cleaned.contains("box*10")) return "box*10";
      if (cleaned.contains("box*20")) return "box*20";
      if (cleaned.contains("box*24") || cleaned.contains("carton")) return "box*24";
      if (cleaned.contains("box*72")) return "box*72";
      if (cleaned.contains("crate")) return "crate";
      if (cleaned.contains("half")) return "half";
      if (cleaned.contains("quarter")) return "quarter";
      if (cleaned.contains("kg")) return "kg";
      
      return cleaned.isEmpty ? "pcs" : cleaned;
  }
  
  // Need to fix 'boolean' to 'bool' in Dart above
  
  Future<List<String>> getAvailableItems() async {
      final db = await instance.database;
      final result = await db.rawQuery("SELECT DISTINCT item FROM stock ORDER BY item");
      return result.map((row) => row['item'] as String).toList();
  }

  Future<List<String>> getItemSizes(String itemName) async {
      final db = await instance.database;
      final result = await db.rawQuery("SELECT DISTINCT quantity FROM stock WHERE item = ?", [itemName]);
      return result.map((row) => row['quantity'] as String).toList();
  }
  
  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}

