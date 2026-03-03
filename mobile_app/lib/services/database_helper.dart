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
    String sql = "SELECT id, customer, item, type, quantity, unit, price, cost_price, base_quantity, amount, paid_amount, is_edited, date, is_debt, is_paid FROM sales WHERE 1=1";

    List<dynamic> args = [];
    if (filter.isNotEmpty && filter != "ALL") {
        if (filter == "DEBTS") {
            sql += " AND is_debt = 1 AND is_paid = 0";
        } else {
            sql += " AND type = ?";
            args.add(filter);
        }
    }
    sql += " ORDER BY date DESC, created_at DESC";

    final result = await db.rawQuery(sql, args);
    
    return result.map((rs) {
        double amount = (rs['amount'] as num).toDouble();
        double paidAmount = (rs['paid_amount'] as num? ?? 0).toDouble();
        double cost = (rs['cost_price'] as num).toDouble();
        double baseQty = (rs['base_quantity'] as num).toDouble();
        double profitVal = amount - (cost * baseQty);
        
        return HistoryItem(
            id: rs['id'] as int,
            customer: rs['customer'] as String,
            item: rs['item'] as String,
            type: rs['type'] as String,
            quantity: rs['quantity'] as String,
            unit: rs['unit'] as String,
            price: (rs['price'] as num).toStringAsFixed(0),
            amount: amount.toStringAsFixed(0),
            paidAmount: paidAmount.toStringAsFixed(0),
            profit: profitVal.toStringAsFixed(0),
            date: rs['date'] as String,
            isDebt: (rs['is_debt'] as int? ?? 0) == 1,
            isPaid: (rs['is_paid'] as int? ?? 0) == 1,
            isEdited: (rs['is_edited'] as int? ?? 0) == 1,
        );
    }).toList().cast<HistoryItem>();
  }

  Future<List<HistoryItem>> getTodaysSales() async {
      final db = await instance.database;
      final today = DateTime.now().toIso8601String().split('T')[0];
      
      final result = await db.rawQuery(
          "SELECT id, customer, item, type, quantity, unit, price, amount, paid_amount, cost_price, base_quantity, is_edited, date, is_debt, is_paid FROM sales WHERE date = ? AND type != 'NEW STOCK' ORDER BY created_at DESC",
          [today]
      );

      return result.map((rs) {
          double amount = (rs['amount'] as num).toDouble();
          double cost = (rs['cost_price'] as num).toDouble();
          double baseQty = (rs['base_quantity'] as num).toDouble();
          double profitVal = amount - (cost * baseQty);

          return HistoryItem(
              id: rs['id'] as int,
              customer: rs['customer'] as String,
              item: rs['item'] as String,
              type: rs['type'] as String,
              quantity: rs['quantity'] as String,
              unit: rs['unit'] as String,
              price: (rs['price'] as num).toStringAsFixed(0),
              amount: amount.toStringAsFixed(0),
              paidAmount: (rs['paid_amount'] as num? ?? 0).toStringAsFixed(0),
              profit: profitVal.toStringAsFixed(0),
              date: rs['date'] as String,
              isDebt: (rs['is_debt'] as int? ?? 0) == 1,
              isPaid: (rs['is_paid'] as int? ?? 0) == 1,
              isEdited: (rs['is_edited'] as int? ?? 0) == 1,
          );
      }).toList().cast<HistoryItem>();
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
          await db.execute('''
            CREATE TABLE IF NOT EXISTS settings (
              key TEXT PRIMARY KEY,
              value TEXT
            )
          ''');

          // Migration for Debts & Edits
          try { await db.execute("ALTER TABLE sales ADD COLUMN is_debt INTEGER DEFAULT 0"); } catch (e) { print("Migration error (sales.is_debt): $e"); }
          try { await db.execute("ALTER TABLE sales ADD COLUMN is_paid INTEGER DEFAULT 0"); } catch (e) { print("Migration error (sales.is_paid): $e"); }
          try { await db.execute("ALTER TABLE sales ADD COLUMN paid_amount REAL DEFAULT 0"); } catch (e) { print("Migration error (sales.paid_amount): $e"); }
          try { await db.execute("ALTER TABLE sales ADD COLUMN is_edited INTEGER DEFAULT 0"); } catch (e) { print("Migration error (sales.is_edited): $e"); }
          try { await db.execute("ALTER TABLE stock ADD COLUMN is_edited INTEGER DEFAULT 0"); } catch (e) { print("Migration error (stock.is_edited): $e"); }

          try { await db.execute("ALTER TABLE deleted_history ADD COLUMN is_debt INTEGER DEFAULT 0"); } catch (e) { print("Migration error (deleted_history.is_debt): $e"); }
          try { await db.execute("ALTER TABLE deleted_history ADD COLUMN is_paid INTEGER DEFAULT 0"); } catch (e) { print("Migration error (deleted_history.is_paid): $e"); }
          try { await db.execute("ALTER TABLE deleted_history ADD COLUMN paid_amount REAL DEFAULT 0"); } catch (e) { print("Migration error (deleted_history.paid_amount): $e"); }
          try { await db.execute("ALTER TABLE deleted_history ADD COLUMN is_edited INTEGER DEFAULT 0"); } catch (e) { print("Migration error (deleted_history.is_edited): $e"); }

          // Create deleted_history table if it doesn't exist
          await db.execute('''
            CREATE TABLE IF NOT EXISTS deleted_history (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              customer TEXT,
              item TEXT,
              quantity TEXT,
              unit TEXT,
              price REAL,
              cost_price REAL,
              base_quantity REAL,
              amount REAL,
              type TEXT,
              date TEXT,
              is_debt INTEGER,
              is_paid INTEGER,
              paid_amount REAL DEFAULT 0,
              is_edited INTEGER DEFAULT 0,
              deleted_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
          ''');
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
        is_edited INTEGER DEFAULT 0,
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
        is_debt INTEGER DEFAULT 0,
        is_paid INTEGER DEFAULT 0,
        paid_amount $realDefault0,
        is_edited INTEGER DEFAULT 0,
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

    // Settings Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    // Deleted History Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS deleted_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer TEXT,
        item TEXT,
        quantity TEXT,
        unit TEXT,
        price REAL,
        cost_price REAL,
        base_quantity REAL,
        amount REAL,
        type TEXT,
        date TEXT,
        is_debt INTEGER DEFAULT 0,
        is_paid INTEGER DEFAULT 0,
        is_edited INTEGER DEFAULT 0,
        deleted_at DATETIME DEFAULT CURRENT_TIMESTAMP
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
      'SELECT id, available_pieces, price, unit FROM stock WHERE item = ? AND quantity = ?',
      [itemName, size]
    );

    if (result.isNotEmpty) {
      final row = result.first;
      int id = row['id'] as int;
      double existingPieces = row['available_pieces'] as double;
      double existingCostPerPiece = row['price'] as double;
      String existingUnit = row['unit'] as String;

      double quantityNumber = extractNumericValue(newUnit);
      double multiplier = getUnitMultiplier(newUnit, size);
      double incomingPieces = quantityNumber * multiplier;
      double newCostPerPiece = newPrice / (multiplier > 0 ? multiplier : 1);

      // Logic: Only update the 'unit' label if the new unit has a LARGER multiplier.
      // This ensures we always format stock using the biggest box size (e.g. *72 vs *12).
      double existingMultiplier = getUnitMultiplier(existingUnit, size);
      String unitToKeep = multiplier > existingMultiplier ? cleanUnitLabel(newUnit) : existingUnit;

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
          DateTime.now().toString(), 
          unitToKeep,
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

  Future<void> addSaleWithProfit(String customer, String item, String size, String unit, double sellingPrice, double totalAmount, String type, {bool isDebt = false}) async {
      final db = await instance.database;
      double costPrice = await getLastRecordedPrice(item, size);
      
      double quantityFactor = extractNumericValue(unit);
      double multiplier = getUnitMultiplier(unit, size);
      double baseQty = quantityFactor * multiplier;
      
      // Normalize cost basis for Bulk Items
      double sizeVal = extractNumericValue(size);
      bool isBulk = size.toLowerCase().contains("kg") && sizeVal >= 10.0;
      
      if (isBulk && sizeVal > 0) {
           baseQty = baseQty / sizeVal;
      }

      await db.rawInsert(
          'INSERT INTO sales(customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date, is_debt, is_paid, paid_amount) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
              customer, item, size, unit, sellingPrice, 
              costPrice, baseQty, totalAmount, type, 
              DateTime.now().toIso8601String().split('T')[0],
              isDebt ? 1 : 0, 0, 0
          ]
      );
  }

  Future<void> markSaleAsPaid(int id, double newPayment) async {
      final db = await instance.database;
      
      // Get current totals
      final result = await db.rawQuery('SELECT amount, paid_amount FROM sales WHERE id = ?', [id]);
      if (result.isNotEmpty) {
          double totalAmount = (result.first['amount'] as num).toDouble();
          double currentPaid = (result.first['paid_amount'] as num? ?? 0).toDouble();
          double updatedPaid = currentPaid + newPayment;
          
          if (updatedPaid >= totalAmount) {
              await db.rawUpdate('UPDATE sales SET paid_amount = amount, is_paid = 1 WHERE id = ?', [id]);
          } else {
              await db.rawUpdate('UPDATE sales SET paid_amount = ? WHERE id = ?', [updatedPaid, id]);
          }
      }
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

  // --- DELETE & REVERT STOCK ---

  Future<void> deleteHistoryItem(int id) async {
    final db = await instance.database;

    // 1. Fetch the item to be deleted
    final List<Map<String, dynamic>> result = await db.query(
      'sales',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (result.isEmpty) return;
    final item = result.first;

    // 2. Insert into deleted_history
    await db.insert('deleted_history', {
      'customer': item['customer'],
      'item': item['item'],
      'quantity': item['quantity'],
      'unit': item['unit'],
      'price': item['price'],
      'cost_price': item['cost_price'],
      'base_quantity': item['base_quantity'],
      'amount': item['amount'],
      'type': item['type'],
      'date': item['date'],
      'is_debt': item['is_debt'],
      'is_paid': item['is_paid'],
      'paid_amount': item['paid_amount'],
    });

    // 3. Revert stock
    String itemName = item['item'] as String;
    String size = item['quantity'] as String;
    String unit = item['unit'] as String;
    String type = item['type'] as String;

    double piecesToRevert = extractNumericValue(unit) * getUnitMultiplier(unit, size);

    final stockResult = await db.query(
      'stock',
      where: 'item = ? AND quantity = ?',
      whereArgs: [itemName, size],
    );

    if (stockResult.isNotEmpty) {
      int stockId = stockResult.first['id'] as int;
      double currentPieces = stockResult.first['available_pieces'] as double;
      double newPieces;

      if (type == 'NEW STOCK') {
        // Deleting added stock -> Subtract from available
        newPieces = currentPieces - piecesToRevert;
        if (newPieces < 0) {
            throw Exception('Cannot delete this entry. It would result in negative stock since some of these pieces have already been sold.');
        }
      } else {
        // Deleting a sale -> Add back to available
        newPieces = currentPieces + piecesToRevert;
      }

      await db.update(
        'stock',
        {'available_pieces': newPieces},
        where: 'id = ?',
        whereArgs: [stockId],
      );
    }

    // 4. Delete from sales
    await db.delete('sales', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateNewStockQuantity(int saleId, String newUnitLabel) async {
      final db = await instance.database;

      // 1. Fetch sales entry
      final List<Map<String, dynamic>> salesResult = await db.query(
          'sales',
          where: 'id = ?',
          whereArgs: [saleId],
      );
      if (salesResult.isEmpty) throw Exception('Entry not found');
      final saleRow = salesResult.first;

      String itemName = saleRow['item'] as String;
      String size = saleRow['quantity'] as String;
      String oldUnit = saleRow['unit'] as String;
      double costAtEntry = saleRow['price'] as double; // This is price per unit (e.g. per box)

      // 2. Fetch stock item
      final List<Map<String, dynamic>> stockResult = await db.query(
          'stock',
          where: 'item = ? AND quantity = ?',
          whereArgs: [itemName, size],
      );
      if (stockResult.isEmpty) throw Exception('Stock item not found');
      final stockRow = stockResult.first;
      int stockId = stockRow['id'] as int;
      double availablePieces = stockRow['available_pieces'] as double;
      double avgCostPerPiece = stockRow['price'] as double; // current weighted average cost per base piece

      // 3. Calculate piece difference
      double oldMultiplier = getUnitMultiplier(oldUnit, size);
      double oldPieces = extractNumericValue(oldUnit) * oldMultiplier;
      
      double newMultiplier = getUnitMultiplier(newUnitLabel, size);
      double newPieces = extractNumericValue(newUnitLabel) * newMultiplier;

      double diff = newPieces - oldPieces;

      // 4. Safety Check
      if (availablePieces + diff < 0) {
          throw Exception('Stock below zero error. Current available stock is lower than your requested reduction.');
      }

      // 5. Update Stock Table
      // Note: Recalculating weighted average is tricky if we don't have all historic entries properly.
      // But typically we do: TotalValue = (CurrentAvailable * AvgCost) + DiffInPieces * (EntryCostPerPiece)
      // Actually, since we are EDITING an existing entry, the piece cost from that entry is already in the average.
      // So NewAvg = (CurrentPieces * AvgPrice + DiffPieces * EntryPieceCost) / (CurrentPieces + DiffPieces)
      double entryPieceCost = costAtEntry / (oldMultiplier > 0 ? oldMultiplier : 1);
      double newAvgPrice = avgCostPerPiece;
      if (availablePieces + diff > 0) {
          newAvgPrice = ((availablePieces * avgCostPerPiece) + (diff * entryPieceCost)) / (availablePieces + diff);
      }

      await db.update(
          'stock',
          {
              'available_pieces': availablePieces + diff,
              'price': newAvgPrice,
              'is_edited': 1
          },
          where: 'id = ?',
          whereArgs: [stockId],
      );

      // 6. Update Sales Table
      double newAmount = extractNumericValue(newUnitLabel) * costAtEntry;
      double baseQuantity = newPieces;
      
      // Normalize cost basis for Bulk Items just like addSaleWithProfit
      double sizeVal = extractNumericValue(size);
      bool isBulk = size.toLowerCase().contains("kg") && sizeVal >= 10.0;
      if (isBulk && sizeVal > 0) {
           baseQuantity = baseQuantity / sizeVal;
      }

      await db.update(
          'sales',
          {
              'unit': newUnitLabel,
              'amount': newAmount,
              'base_quantity': baseQuantity,
              'is_edited': 1
          },
          where: 'id = ?',
          whereArgs: [saleId],
      );
  }

  Future<bool> isStockEntryDeletable(int saleId) async {
      final db = await instance.database;

      // 1. Fetch sales entry
      final List<Map<String, dynamic>> salesResult = await db.query(
          'sales',
          where: 'id = ?',
          whereArgs: [saleId],
      );
      if (salesResult.isEmpty) return false;
      final saleRow = salesResult.first;

      String itemName = saleRow['item'] as String;
      String size = saleRow['quantity'] as String;
      String unitText = saleRow['unit'] as String;

      // 2. Fetch stock item
      final List<Map<String, dynamic>> stockResult = await db.query(
          'stock',
          where: 'item = ? AND quantity = ?',
          whereArgs: [itemName, size],
      );
      if (stockResult.isEmpty) return false;
      final stockRow = stockResult.first;
      double availablePieces = stockRow['available_pieces'] as double;

      // 3. Calculate piece reduction
      double piecesInEntry = extractNumericValue(unitText) * getUnitMultiplier(unitText, size);

      return (availablePieces - piecesInEntry) >= 0;
  }

  Future<List<HistoryItem>> getDeletedHistory() async {
    final db = await instance.database;
    final result = await db.rawQuery("SELECT * FROM deleted_history ORDER BY deleted_at DESC");

    return result.map((rs) {
      return HistoryItem(
        id: rs['id'] as int,
        customer: rs['customer'] as String,
        item: rs['item'] as String,
        type: rs['type'] as String,
        quantity: rs['quantity'] as String,
        unit: rs['unit'] as String,
        price: (rs['price'] as num).toStringAsFixed(0),
        amount: (rs['amount'] as num).toDouble().toStringAsFixed(0),
        paidAmount: (rs['paid_amount'] as num? ?? 0).toDouble().toStringAsFixed(0),
        profit: "0", 
        date: rs['date'] as String,
        deletedAt: rs['deleted_at'] as String?,
        isDebt: (rs['is_debt'] as int? ?? 0) == 1,
        isPaid: (rs['is_paid'] as int? ?? 0) == 1,
        isEdited: (rs['is_edited'] as int? ?? 0) == 1,
      );
    }).toList().cast<HistoryItem>();
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
      String normalized = cleaned.replaceAll(' ', '');
      if (normalized.contains("box*12")) return "box*12";
      if (normalized.contains("box*10")) return "box*10";
      if (normalized.contains("box*20")) return "box*20";
      if (normalized.contains("box*24") || normalized.contains("carton")) return "box*24";
      if (normalized.contains("box*72")) return "box*72";
      if (normalized.contains("crate")) return "crate";
      if (normalized.contains("half")) return "half";
      if (normalized.contains("quarter")) return "quarter";
      if (normalized.contains("kg")) return "kg";
      
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

  Future<List<String>> getRecentSuppliers() async {
      final db = await instance.database;
      final result = await db.rawQuery(
          "SELECT DISTINCT supplier FROM stock WHERE supplier IS NOT NULL AND supplier != '' ORDER BY created_at DESC LIMIT 10"
      );
      return result.map((row) => row['supplier'] as String).toList();
  }

  Future<List<String>> getRecentCustomers() async {
      final db = await instance.database;
      final result = await db.rawQuery(
          "SELECT DISTINCT customer FROM sales WHERE customer != '' AND customer IS NOT NULL ORDER BY created_at DESC LIMIT 20"
      );
      return result.map((row) => row['customer'] as String).toList();
  }

  // --- SETTINGS ---
  Future<void> saveSetting(String key, String value) async {
    final db = await instance.database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await instance.database;
    final maps = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (maps.isNotEmpty) {
      return maps.first['value'] as String?;
    }
    return null;
  }
  
  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}

