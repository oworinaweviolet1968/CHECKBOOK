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

  Future<void> close() async {
    if (_database != null) {
      print('DATABASE: Explicitly closing connection.');
      await _database!.close();
      _database = null;
    }
  }

  Future<void> reopen() async {
    await close();
    await database; // This triggers _initDB via 'get database'
  }

  Future<bool> hasData() async {
    final db = await instance.database;
    final stock = await db.rawQuery('SELECT COUNT(*) as count FROM stock');
    final sales = await db.rawQuery('SELECT COUNT(*) as count FROM sales');
    final delStock = await db.rawQuery('SELECT COUNT(*) as count FROM deleted_stock');
    final delSales = await db.rawQuery('SELECT COUNT(*) as count FROM deleted_history');

    int stockCount = Sqflite.firstIntValue(stock) ?? 0;
    int salesCount = Sqflite.firstIntValue(sales) ?? 0;
    int delStockCount = Sqflite.firstIntValue(delStock) ?? 0;
    int delSalesCount = Sqflite.firstIntValue(delSales) ?? 0;

    return stockCount > 0 || salesCount > 0 || delStockCount > 0 || delSalesCount > 0;
  }

  // --- HISTORY & SALES ---

  Future<List<HistoryItem>> getHistory(String filter) async {
    final db = await instance.database;
    final String sql;
    if (filter == "DEBTS") {
      sql = "SELECT MIN(id) as id, customer, GROUP_CONCAT(quantity || ' ' || unit || ' ' || item || ' @ ' || price || ' = ' || amount, '\n') as item, type, SUM(amount) as amount, SUM(paid_amount) as paid_amount, SUM(amount - (cost_price * base_quantity)) as profit, date, is_debt, is_paid, is_edited, device_source FROM sales WHERE is_debt = 1 AND is_paid = 0 GROUP BY COALESCE(receipt_id, created_at || customer) ORDER BY date DESC, created_at DESC";
    } else if (filter != "ALL") {
      sql = "SELECT MIN(id) as id, customer, GROUP_CONCAT(quantity || ' ' || unit || ' ' || item || ' @ ' || price || ' = ' || amount, '\n') as item, type, SUM(amount) as amount, SUM(paid_amount) as paid_amount, SUM(amount - (cost_price * base_quantity)) as profit, date, is_debt, is_paid, is_edited, device_source FROM sales WHERE type = ? GROUP BY COALESCE(receipt_id, created_at || customer) ORDER BY date DESC, created_at DESC";
    } else {
      sql = "SELECT MIN(id) as id, customer, GROUP_CONCAT(quantity || ' ' || unit || ' ' || item || ' @ ' || price || ' = ' || amount, '\n') as item, type, SUM(amount) as amount, SUM(paid_amount) as paid_amount, SUM(amount - (cost_price * base_quantity)) as profit, date, is_debt, is_paid, is_edited, device_source FROM sales GROUP BY COALESCE(receipt_id, created_at || customer) ORDER BY date DESC, created_at DESC";
    }

    final List<Map<String, dynamic>> result = await db.rawQuery(
        sql, filter != "ALL" && filter != "DEBTS" ? [filter] : []);

    return result.map((rs) {
      double amount = (rs['amount'] as num).toDouble();
      double profitVal = (rs['profit'] as num).toDouble();

      return HistoryItem(
        id: rs['id'] as int,
        customer: rs['customer'] as String,
        item: rs['item'] as String,
        type: rs['type'] as String,
        quantity: "-",
        unit: "-",
        price: "-",
        amount: amount.toStringAsFixed(0),
        paidAmount: (rs['paid_amount'] as num? ?? 0).toStringAsFixed(0),
        profit: profitVal.toStringAsFixed(0),
        date: rs['date'] as String,
        isDebt: (rs['is_debt'] as int? ?? 0) == 1,
        isPaid: (rs['is_paid'] as int? ?? 0) == 1,
        isEdited: (rs['is_edited'] as int? ?? 0) == 1,
        deviceSource: rs['device_source'] as String? ?? "System",
      );
    }).toList().cast<HistoryItem>();
  }

  Future<List<HistoryItem>> getTodaysSales() async {
    final db = await instance.database;
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    final String sql = "SELECT MIN(id) as id, customer, GROUP_CONCAT(quantity || ' ' || unit || ' ' || item || ' @ ' || price || ' = ' || amount, '\n') as item, type, SUM(amount) as amount, SUM(paid_amount) as paid_amount, SUM(amount - (cost_price * base_quantity)) as profit, date, is_debt, is_paid, is_edited, device_source FROM sales WHERE date = ? AND type != 'NEW STOCK' GROUP BY COALESCE(receipt_id, created_at || customer) ORDER BY created_at DESC";

    final List<Map<String, dynamic>> result = await db.rawQuery(sql, [today]);

    return result.map((rs) {
      double amount = (rs['amount'] as num).toDouble();
      double profitVal = (rs['profit'] as num).toDouble();

      return HistoryItem(
        id: rs['id'] as int,
        customer: rs['customer'] as String,
        item: rs['item'] as String,
        type: rs['type'] as String,
        quantity: "-",
        unit: "-",
        price: "-",
        amount: amount.toStringAsFixed(0),
        paidAmount: (rs['paid_amount'] as num? ?? 0).toStringAsFixed(0),
        profit: profitVal.toStringAsFixed(0),
        date: rs['date'] as String,
        isDebt: (rs['is_debt'] as int? ?? 0) == 1,
        isPaid: (rs['is_paid'] as int? ?? 0) == 1,
        isEdited: (rs['is_edited'] as int? ?? 0) == 1,
        deviceSource: rs['device_source'] as String? ?? "System",
      );
    }).toList().cast<HistoryItem>();
  }

  Future<List<SaleItem>> getReceiptItems(int saleId) async {
    final db = await instance.database;
    final info = await db.query("sales", columns: ["customer", "created_at", "receipt_id"], where: "id = ?", whereArgs: [saleId]);
    
    if (info.isEmpty) return [];
    
    final customer = info[0]['customer'];
    final createdAt = info[0]['created_at'];
    final receiptId = info[0]['receipt_id'];

    final List<Map<String, dynamic>> items;
    if (receiptId != null && receiptId.toString().isNotEmpty) {
      items = await db.query("sales", columns: ["item", "quantity", "unit", "price", "amount"], where: "receipt_id = ?", whereArgs: [receiptId]);
    } else {
      items = await db.query("sales", columns: ["item", "quantity", "unit", "price", "amount"], where: "customer = ? AND created_at = ?", whereArgs: [customer, createdAt]);
    }

    return items.map((rs) {
      return SaleItem(
        items: rs['item'] as String,
        qty: rs['quantity'] as String,
        unit: rs['unit'] as String,
        price: (rs['price'] as num).toStringAsFixed(0),
        amount: (rs['amount'] as num).toStringAsFixed(0),
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
          await db.execute('''
            CREATE TABLE IF NOT EXISTS settings (
              key TEXT PRIMARY KEY,
              value TEXT
            )
          ''');

          // Migration Helper (Clean)
          Future<void> addCol(String tbl, String col, String type) async {
              var columns = await db.rawQuery("PRAGMA table_info($tbl)");
              bool exists = columns.any((c) => c['name'] == col);
              if (!exists) {
                  await db.execute("ALTER TABLE $tbl ADD COLUMN $col $type");
              }
          }
          
          await addCol("sales", "is_debt", "INTEGER DEFAULT 0");
          await addCol("sales", "is_paid", "INTEGER DEFAULT 0");
          await addCol("sales", "paid_amount", "REAL DEFAULT 0");
          await addCol("sales", "is_edited", "INTEGER DEFAULT 0");
          await addCol("stock", "is_edited", "INTEGER DEFAULT 0");
          await addCol("sales", "device_source", "TEXT DEFAULT 'Desktop'");
          await addCol("stock", "device_source", "TEXT DEFAULT 'Desktop'");
          await addCol("deleted_history", "is_debt", "INTEGER DEFAULT 0");
          await addCol("deleted_history", "is_paid", "INTEGER DEFAULT 0");
          await addCol("deleted_history", "paid_amount", "REAL DEFAULT 0");
          await addCol("deleted_history", "is_edited", "INTEGER DEFAULT 0");
          await addCol("sales", "receipt_id", "TEXT");
          await addCol("deleted_history", "device_source", "TEXT DEFAULT 'Desktop'");

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
              device_source TEXT DEFAULT 'Desktop',
              deleted_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS deleted_stock (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              item TEXT,
              quantity TEXT,
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

  Future<void> clearAllData() async {
      final db = await instance.database;
      await db.transaction((txn) async {
          await txn.execute("DELETE FROM sales");
          await txn.execute("DELETE FROM stock");
          await txn.execute("DELETE FROM deleted_history");
          await txn.execute("DELETE FROM yearly_summaries");
          await txn.execute("UPDATE settings SET value = '0' WHERE key = 'last_backup_timestamp'");
      });
      print("DATABASE: All local data cleared.");
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

  // Dashboard: Weekly Profit (Last 7 Days)
  Future<double> getWeeklyProfit() async {
    final db = await instance.database;
    final now = DateTime.now();
    // 7 days including today (e.g., today is Sunday, range is last Monday to today)
    final sevenDaysAgo = now.subtract(const Duration(days: 6)).toIso8601String().split('T')[0];
    final today = now.toIso8601String().split('T')[0];
    
    final result = await db.rawQuery('''
      SELECT SUM(amount - (cost_price * base_quantity)) as total_profit
      FROM sales 
      WHERE date >= ? AND date <= ? AND type != 'NEW STOCK'
    ''', [sevenDaysAgo, today]);

    if (result.isNotEmpty && result.first['total_profit'] != null) {
      return (result.first['total_profit'] as num).toDouble();
    }
    return 0.0;
  }

  // Dashboard: Previous Weekly Profit (7-13 days ago)
  Future<double> getPrevWeeklyProfit() async {
    final db = await instance.database;
    final now = DateTime.now();
    final thirteenDaysAgo = now.subtract(const Duration(days: 13)).toIso8601String().split('T')[0];
    final sevenDaysAgo = now.subtract(const Duration(days: 7)).toIso8601String().split('T')[0];
    
    final result = await db.rawQuery('''
      SELECT SUM(amount - (cost_price * base_quantity)) as total_profit
      FROM sales 
      WHERE date >= ? AND date <= ? AND type != 'NEW STOCK'
    ''', [thirteenDaysAgo, sevenDaysAgo]);

    if (result.isNotEmpty && result.first['total_profit'] != null) {
      return (result.first['total_profit'] as num).toDouble();
    }
    return 1.0; // Return 1.0 to avoid division by zero and show some change if no data
  }
  
  // Dashboard: Available Stock List
  Future<List<Map<String, dynamic>>> getAvailableStock() async {
    final db = await instance.database;
    // Java: SELECT item, quantity, available_pieces, price, supplier, date FROM stock ORDER BY item
    // Changed to include 0 available_pieces items
    return await db.rawQuery('SELECT * FROM stock ORDER BY item');
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

  Future<void> updateItemPrice(int id, double newPrice) async {
    final db = await instance.database;
    await db.rawUpdate(
      'UPDATE stock SET price = ?, is_edited = 1 WHERE id = ?',
      [newPrice, id]
    );
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
        'UPDATE stock SET available_pieces = ?, price = ?, supplier = ?, date = ?, unit = ?, is_edited = 1 WHERE id = ?',
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
    double multiplier = getUnitMultiplier(u, q, u);
    double totalPieces = unitCount * multiplier;
    
    // Price per single piece (base unit)
    double pricePerSinglePiece = p / (multiplier > 0 ? multiplier : 1); 

    await db.rawInsert(
      "INSERT INTO stock(supplier, item, quantity, unit, price, available_pieces, date, is_edited, device_source) VALUES(?, ?, ?, ?, ?, ?, ?, 1, 'Mobile')",
      [s, i, q, cleanUnitLabel(u), pricePerSinglePiece, totalPieces, d]
    );
  }

  Future<void> updateStockQuantity(String itemName, String soldSize, String soldUnit) async {
      final db = await instance.database;
      final result = await db.rawQuery(
        'SELECT id, unit, available_pieces FROM stock WHERE item = ? AND quantity = ?',
        [itemName, soldSize]
      );

      if (result.isNotEmpty) {
          int id = result.first['id'] as int;
          String bulkUnit = result.first['unit'] as String? ?? "";
          double currentPieces = result.first['available_pieces'] as double;
          
          double multiplier = getUnitMultiplier(soldUnit, soldSize, bulkUnit);
          double soldPieces = extractNumericValue(soldUnit) * multiplier;
          double remaining = currentPieces - soldPieces;

          if (remaining >= 0) {
              await db.rawUpdate(
                  'UPDATE stock SET available_pieces = ?, is_edited = 1 WHERE id = ?',
                  [remaining, id]
              );
          }
      }
  }

  Future<bool> hasEnoughStock(String itemName, String size, String soldUnit) async {
      final db = await instance.database;
      final result = await db.rawQuery(
          "SELECT unit, available_pieces FROM stock WHERE item = ? AND quantity = ?",
          [itemName, size]
      );
      if (result.isNotEmpty) {
          double stockAvailable = result.first['available_pieces'] as double;
          String bulkUnit = result.first['unit'] as String? ?? "";
          
          double multiplier = getUnitMultiplier(soldUnit, size, bulkUnit);
          double amountTryingToSell = extractNumericValue(soldUnit) * multiplier;
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
      if (availablePieces <= 0) return "0 pcs";

      String sizeLower = size.toLowerCase();

      // --- WEIGHT-BASED (Sacks / kg) ---
      if (sizeLower.contains("kg")) {
          double kgPerSack = extractNumericValue(size);
          if (kgPerSack >= 10.0) {
              int sacks = (availablePieces / kgPerSack).floor();
              double remainingKg = availablePieces % kgPerSack;
              if (sacks > 0 && remainingKg > 0.01) {
                  return "$sacks Sacks / ${remainingKg.toStringAsFixed(1)} kg";
              }
              if (sacks > 0) return "$sacks Sacks";
              return "${remainingKg.toStringAsFixed(1)} kg";
          } else {
              return "${availablePieces.toStringAsFixed(1)} kg";
          }
      }

      // --- PIECE-BASED: Multi-tier cascading breakdown (Bulk → Doz → pcs) ---
      double multiplier = getUnitMultiplier(unitLabel, size, unitLabel);

      if (multiplier <= 1.0) {
          int total = availablePieces.round();
          return "$total pcs";
      }

      List<String> parts = [];
      double remaining = availablePieces;

      // Friendly name for the highest unit
      String friendlyName;
      String sizeLowerClean = size.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      
      if (multiplier == 6.0) friendlyName = "Half Doz";
      else if (multiplier == 12.0) friendlyName = "Doz";
      else if (sizeLowerClean.contains("crate")) friendlyName = "Crates";
      else if (sizeLowerClean.contains("carton")) friendlyName = "Cartons";
      else if (sizeLowerClean.contains("pack")) friendlyName = "Pks";
      else if (sizeLowerClean.contains("bundle")) friendlyName = "Bndls";
      else friendlyName = "Bx"; 

      int mainCount = (remaining / multiplier).floor();
      int leftover = (remaining % multiplier).round();

      if (mainCount > 0) {
          parts.add("$mainCount $friendlyName");
      }

      // Level 2: Dozens (only if highest unit > 12)
      if (multiplier > 12.0 && leftover >= 12) {
          int dozens = (leftover / 12).floor();
          leftover = leftover % 12;
          parts.add("$dozens Doz");
      }

      // Level 3: Remaining pcs
      if (leftover > 0) {
          parts.add("$leftover pcs");
      }

      return parts.isEmpty ? "0 pcs" : parts.join(" / ");
  }

  // --- SALES OPERATIONS ---

  Future<void> addSaleWithProfit(String customer, String item, String size, String unit, double sellingPrice, double totalAmount, String type, {bool isDebt = false, String? receiptId}) async {
      final db = await instance.database;
      double costPrice = await getLastRecordedPrice(item, size);
      
      // Retrieve bulk unit from stock to ensure correct multiplier detection
      String bulkUnit = "";
      final stockRes = await db.rawQuery("SELECT unit FROM stock WHERE item = ? AND quantity = ? LIMIT 1", [item, size]);
      if (stockRes.isNotEmpty) {
        bulkUnit = stockRes.first['unit'] as String? ?? "";
      }

      double quantityFactor = extractNumericValue(unit);
      double multiplier = getUnitMultiplier(unit, size, bulkUnit);
      double baseQty = quantityFactor * multiplier;
      
      // Normalize cost basis for Bulk Items
      double sizeVal = extractNumericValue(size);
      bool isBulk = size.toLowerCase().contains("kg") && sizeVal >= 10.0;
      
      if (isBulk && sizeVal > 0) {
           baseQty = baseQty / sizeVal;
      }

      await db.rawInsert(
          "INSERT INTO sales(customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date, is_debt, is_paid, paid_amount, is_edited, device_source, receipt_id, created_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 'Mobile', ?, ?)",
          [
              customer, item, size, unit, sellingPrice, 
              costPrice, baseQty, totalAmount, type, 
              DateTime.now().toIso8601String().split('T')[0],
              isDebt ? 1 : 0, isDebt ? 0 : 1, isDebt ? 0 : totalAmount,
              receiptId,
              DateTime.now().toIso8601String()
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

    double piecesToRevert = extractNumericValue(unit) * getUnitMultiplier(unit, size, unit);

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
        {'available_pieces': newPieces, 'is_edited': 1},
        where: 'id = ?',
        whereArgs: [stockId],
      );

      // If we just deleted the ONLY stock entry that existed (e.g. initial stock) 
      // and it results in 0 pieces, we might want to remove it entirely.
      // The user requested: "unless if its new stock is deleted entirely."
      if (type == 'NEW STOCK' && newPieces <= 0) {
          await db.insert('deleted_stock', {'item': itemName, 'quantity': size});
          await db.delete('stock', where: 'id = ?', whereArgs: [stockId]);
      }
    }

    // 4. Delete from sales
    await db.delete('sales', where: 'id = ?', whereArgs: [id]);
  }


  Future<void> cleanupZombieStock() async {
    final db = await instance.database;
    // Delete from stock where available_pieces <= 0 AND no active NEW STOCK history persists
    // This cleans up items whose stock history was deleted entirely before the previous fix.
    await db.rawDelete('''
      DELETE FROM stock 
      WHERE available_pieces <= 0 
      AND NOT EXISTS (
        SELECT 1 FROM sales 
        WHERE sales.item = stock.item 
        AND sales.quantity = stock.quantity 
        AND sales.type = 'NEW STOCK'
      )
    ''');
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

    // Remove known fractions to avoid confusing regex
    String cleaned = lowercaseText.replaceAll("1/4", "").replaceAll("1/2", "").replaceAll(",", "").trim();
    
    // Find the leading numeric part (start of string only)
    final match = RegExp(r'^(\d+(\.\d+)?)').firstMatch(cleaned);
    
    if (match != null) {
        try {
            double value = double.parse(match.group(1)!);
            if (fractionValue > 0) {
                return value + fractionValue; // Fixed: Addition instead of multiplication
            }
            return value;
        } catch (e) {
            return fractionValue;
        }
    }
    
    return fractionValue;
  }

  /// Ported from Java getUnitMultiplier
  double getUnitMultiplier(String unitText, String size, [String? bulkUnit]) {
      if (unitText.isEmpty) return 1.0;
      String type = unitText.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      String sizeLower = size.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      String bulkLower = (bulkUnit ?? "").toLowerCase().replaceAll(RegExp(r'\s+'), '');

      double sizeNum = extractNumericValue(sizeLower);
      bool isBulkSack = sizeLower.contains("kg") && sizeNum >= 10.0;

      if (type.contains("sack") || (isBulkSack && (type.contains("pc") || type.contains("item")))) {
          return sizeNum;
      }

      // 1. Explicit star multiplier in unit (e.g. "pcs*12" or "box*72")
      if (type.contains("*")) {
          try {
              String afterStar = type.substring(type.lastIndexOf("*") + 1);
              double val = extractNumericValue(afterStar);
              if (val > 0) return val;
          } catch (e) {}
      }
      
      // Normalize 'type' by removing leading quantities
      String normalizedType = type.replaceFirst(RegExp(r'^[0-9./* ]+'), '');

      // 2. Piece or Item units (always 1.0)
      if (normalizedType == "pc" || normalizedType == "pcs" || normalizedType == "item" || normalizedType == "items") {
          return 1.0;
      }

      // 3. Packaging logic
      if (normalizedType.contains("halfdoz")) return 6.0;
      if (normalizedType.contains("half")) return 0.5;
      if (normalizedType.contains("quarter")) return 0.25;
      if (normalizedType.contains("dozen") || normalizedType.contains("doz")) return 12.0;

      // 4. Generic units matching bulk metadata
      if (normalizedType == "box" || normalizedType == "boxes" || normalizedType.contains("carton") || normalizedType.contains("crate")) {
          if (sizeLower.contains("*")) {
              try {
                  String afterStar = sizeLower.substring(sizeLower.lastIndexOf("*") + 1);
                  double val = extractNumericValue(afterStar);
                  if (val > 0) return val;
              } catch (e) {}
          }
          if (bulkLower.contains("*")) {
              try {
                  String afterStar = bulkLower.substring(bulkLower.lastIndexOf("*") + 1);
                  double val = extractNumericValue(afterStar);
                  if (val > 0) return val;
              } catch (e) {}
          }
          
          // Fallback if no star but it's a known bulk term
          if (normalizedType.contains("carton")) return 24.0;
          if (normalizedType.contains("crate")) return 25.0;
          return 20.0; // Default box
      }

      // Legacy Fallbacks (space-insensitive)
      if (type.contains("box*10")) return 10.0;
      if (type.contains("box*12")) return 12.0;
      if (type.contains("box*24")) return 24.0;
      if (type.contains("crate*25")) return 25.0;
      if (type.contains("box*72")) return 72.0;
      if (type.contains("box*20")) return 20.0; 

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

  // --- CONFLICT MERGING HELPERS ---

  Future<List<Map<String, dynamic>>> getDirtyRecords(String table) async {
    final db = await instance.database;
    return await db.query(table, where: 'is_edited = 1');
  }

  Future<List<Map<String, dynamic>>> getDeletedStock() async {
    final db = await instance.database;
    return await db.query('deleted_stock');
  }

  Future<List<Map<String, dynamic>>> getDeletedHistoryRaw() async {
    final db = await instance.database;
    return await db.query('deleted_history', columns: ['customer', 'item', 'amount', 'date']);
  }

  Future<bool> isStockDeleted(String item, String quantity) async {
    final db = await instance.database;
    final results = await db.query('deleted_stock',
        where: 'item = ? AND quantity = ?', whereArgs: [item, quantity]);
    return results.isNotEmpty;
  }

  Future<bool> isSaleDeleted(String customer, String item, double amount, String date) async {
    final db = await instance.database;
    final results = await db.query('deleted_history',
        where: 'customer = ? AND item = ? AND amount = ? AND date = ?',
        whereArgs: [customer, item, amount, date]);
    return results.isNotEmpty;
  }

  Future<void> applyDirtyRecord(String table, Map<String, dynamic> record) async {
    final db = await instance.database;

    // Create a copy and remove ID to prevent Primary Key conflicts
    final Map<String, dynamic> data = Map.from(record);
    data.remove('id');

    // TOMBSTONE CHECK: Don't restore if deleted in the cloud (other device)
    if (table == 'stock') {
      if (await isStockDeleted(data['item'] as String, data['quantity'] as String)) {
        print("SYNC: Skipping restore of ${data['item']} - Deleted in cloud.");
        return;
      }
    }
    if (table == 'sales') {
      if (await isSaleDeleted(
          data['customer'] as String,
          data['item'] as String,
          (data['amount'] as num).toDouble(),
          data['date'] as String)) {
        print("SYNC: Skipping restore of sale ${data['item']} - Deleted in cloud.");
        return;
      }
    }
    
    if (table == 'stock') {
      // For stock, we want to update the existing entry if it exists (by Name + Size)
      // instead of creating a duplicate.
      final existing = await db.query('stock', 
        where: 'item = ? AND quantity = ?', 
        whereArgs: [data['item'], data['quantity']]
      );
      
      if (existing.isNotEmpty) {
        await db.update('stock', data, 
          where: 'id = ?', 
          whereArgs: [existing.first['id']]
        );
        return;
      }
    }
    
    if (table == 'sales') {
      // For sales, check if an identical record exists to avoid duplicates
      final existing = await db.query('sales', 
        where: 'customer = ? AND item = ? AND amount = ? AND date = ?', 
        whereArgs: [data['customer'], data['item'], data['amount'], data['date']]
      );
      if (existing.isNotEmpty) return; // Already there
    }
    
    // Otherwise, just insert it as a new row
    await db.insert(table, data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> applyStockDeletion(String item, String quantity) async {
    final db = await instance.database;
    await db.delete('stock', where: 'item = ? AND quantity = ?', whereArgs: [item, quantity]);
  }

  Future<void> applyHistoryDeletion(String customer, String item, double amount, String date) async {
    final db = await instance.database;
    await db.delete('sales', 
      where: 'customer = ? AND item = ? AND amount = ? AND date = ?', 
      whereArgs: [customer, item, amount, date]
    );
  }

  Future<void> clearDirtyFlags() async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.update('stock', {'is_edited': 0});
      await txn.update('sales', {'is_edited': 0});
      await txn.execute('DELETE FROM deleted_stock');
    });
  }
}

