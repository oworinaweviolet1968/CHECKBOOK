import 'dart:io';
import 'dart:math';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/history_item.dart';
import '../models/sale_item.dart';
import '../main.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  static String generateUUID() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    
    final charCodes = <int>[];
    for (int i = 0; i < 16; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) {
        charCodes.add(45); // '-'
      }
      final byte = bytes[i];
      charCodes.add(_hexDigit(byte >> 4));
      charCodes.add(_hexDigit(byte & 0x0F));
    }
    return String.fromCharCodes(charCodes);
  }

  static int _hexDigit(int value) => value < 10 ? 48 + value : 97 + value - 10;

  static int _getSecondsDifference(String? t1, String? t2) {
    if (t1 == null || t2 == null) return 9999;
    try {
      final cleanT1 = t1.replaceAll('Z', '').replaceAll(' ', 'T');
      final cleanT2 = t2.replaceAll('Z', '').replaceAll(' ', 'T');
      if (cleanT1.length >= 19 && cleanT2.length >= 19) {
        final dt1 = DateTime.parse(cleanT1.substring(0, 19));
        final dt2 = DateTime.parse(cleanT2.substring(0, 19));
        return (dt1.difference(dt2)).inSeconds.abs();
      }
    } catch (_) {}
    return 9999;
  }

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
      sql = "SELECT MIN(id) as id, customer, GROUP_CONCAT(quantity || ' ' || unit || ' ' || item || ' @ ' || price || ' = ' || amount || ' (' || date || ')', '\n') as item, type, SUM(amount) as amount, SUM(COALESCE(paid_amount, 0)) as paid_amount, SUM(amount - (cost_price * base_quantity)) as profit, MAX(date) as date, is_debt, is_paid, is_edited, device_source FROM sales WHERE is_debt = 1 AND is_paid = 0 AND customer != 'Walk-in Customer' GROUP BY customer ORDER BY MAX(date) DESC, MAX(REPLACE(created_at, 'T', ' ')) DESC";
    } else if (filter != "ALL") {
      sql = "SELECT MIN(id) as id, customer, GROUP_CONCAT(quantity || ' ' || unit || ' ' || item || ' @ ' || price || ' = ' || amount, '\n') as item, type, SUM(amount) as amount, SUM(COALESCE(paid_amount, 0)) as paid_amount, SUM(amount - (cost_price * base_quantity)) as profit, date, is_debt, is_paid, is_edited, device_source FROM sales WHERE type = ? GROUP BY COALESCE(NULLIF(receipt_id, ''), CASE WHEN (created_at IS NOT NULL AND created_at != '') THEN (created_at || customer) ELSE id END) ORDER BY date DESC, REPLACE(created_at, 'T', ' ') DESC";
    } else {
      sql = "SELECT MIN(id) as id, customer, GROUP_CONCAT(quantity || ' ' || unit || ' ' || item || ' @ ' || price || ' = ' || amount, '\n') as item, type, SUM(amount) as amount, SUM(COALESCE(paid_amount, 0)) as paid_amount, SUM(amount - (cost_price * base_quantity)) as profit, date, is_debt, is_paid, is_edited, device_source FROM sales GROUP BY COALESCE(NULLIF(receipt_id, ''), CASE WHEN (created_at IS NOT NULL AND created_at != '') THEN (created_at || customer) ELSE id END) ORDER BY date DESC, REPLACE(created_at, 'T', ' ') DESC";
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

  Future<List<HistoryItem>> getSettledDebts() async {
    final db = await instance.database;
    final String sql = '''
      SELECT 
          MIN(s.id) as id, 
          s.customer, 
          GROUP_CONCAT(s.quantity || ' ' || s.unit || ' ' || s.item || ' @ ' || s.price || ' = ' || s.amount, '\\n') as item, 
          s.type, 
          SUM(s.amount) as amount, 
          SUM(COALESCE(s.paid_amount, 0)) as paid_amount, 
          SUM(s.amount - (s.cost_price * s.base_quantity)) as profit, 
          s.date, 
          s.is_debt, 
          s.is_paid, 
          s.is_edited, 
          s.device_source,
          MAX(COALESCE(dp.created_at, s.created_at)) as last_paid_at
      FROM sales s
      LEFT JOIN debt_payments dp ON s.id = dp.sale_id
      WHERE s.is_debt = 1 AND s.is_paid = 1 AND s.customer != 'Walk-in Customer'
      GROUP BY COALESCE(NULLIF(s.receipt_id, ''), CASE WHEN (s.created_at IS NOT NULL AND s.created_at != '') THEN (s.created_at || s.customer) ELSE s.id END)
      ORDER BY last_paid_at DESC
    ''';

    final List<Map<String, dynamic>> result = await db.rawQuery(sql);

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

  Future<int> getDebtorCount() async {
    final db = await instance.database;
    final result = await db.rawQuery(
      "SELECT COUNT(DISTINCT customer) as count FROM sales WHERE is_debt = 1 AND is_paid = 0 AND customer != 'Walk-in Customer'"
    );
    if (result.isNotEmpty) {
      return result.first['count'] as int? ?? 0;
    }
    return 0;
  }

  Future<double> getTotalOutstandingDebt() async {
    final db = await instance.database;
    final result = await db.rawQuery(
      "SELECT SUM(amount - COALESCE(paid_amount, 0)) as total FROM sales WHERE is_debt = 1 AND is_paid = 0 AND customer != 'Walk-in Customer'"
    );
    if (result.isNotEmpty && result.first['total'] != null) {
      return (result.first['total'] as num).toDouble();
    }
    return 0.0;
  }

  Future<List<HistoryItem>> getTodaysSales() async {
    final db = await instance.database;
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    final String sql = "SELECT MIN(id) as id, customer, GROUP_CONCAT(quantity || ' ' || unit || ' ' || item || ' @ ' || price || ' = ' || amount, '\n') as item, type, SUM(amount) as amount, SUM(COALESCE(paid_amount, 0)) as paid_amount, SUM(amount - (cost_price * base_quantity)) as profit, date, is_debt, is_paid, is_edited, device_source FROM sales WHERE date = ? AND type != 'NEW STOCK' GROUP BY COALESCE(NULLIF(receipt_id, ''), CASE WHEN (created_at IS NOT NULL AND created_at != '') THEN (created_at || customer) ELSE id END) ORDER BY REPLACE(created_at, 'T', ' ') DESC";

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
        item: rs['item'] as String,
        quantity: rs['quantity'] as String,
        unit: rs['unit'] as String,
        price: (rs['price'] as num).toStringAsFixed(0),
        amount: (rs['amount'] as num).toStringAsFixed(0),
      );
    }).toList().cast<SaleItem>();
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

          await db.execute('''
            CREATE TABLE IF NOT EXISTS debt_payments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sale_id INTEGER NOT NULL,
                amount_paid REAL NOT NULL,
                payment_date TEXT NOT NULL,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                sync_id TEXT,
                FOREIGN KEY (sale_id) REFERENCES sales(id)
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
          
          // Postgres Sync Migration
          await addCol("stock", "sync_id", "TEXT");
          await addCol("sales", "sync_id", "TEXT");
          await addCol("deleted_history", "sync_id", "TEXT");
          await addCol("deleted_stock", "sync_id", "TEXT");
          await addCol("debt_payments", "sync_id", "TEXT");
          await addCol("notifications", "sync_id", "TEXT");
          
          // Backfill sync_id if null using standard dashed UUIDs
          final uuidGenSql = "lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))),2) || '-a' || substr(lower(hex(randomblob(2))),2) || '-' || lower(hex(randomblob(6)))";
          await db.execute("UPDATE stock SET sync_id = $uuidGenSql WHERE sync_id IS NULL");
          await db.execute("UPDATE sales SET sync_id = $uuidGenSql WHERE sync_id IS NULL");
          await db.execute("UPDATE deleted_history SET sync_id = $uuidGenSql WHERE sync_id IS NULL");
          await db.execute("UPDATE deleted_stock SET sync_id = $uuidGenSql WHERE sync_id IS NULL");

          // Normalize any existing 32-character hex sync_ids to standard 36-character dashed UUIDs
          final tables = ["stock", "sales", "deleted_history", "deleted_stock", "notifications", "debt_payments"];
          for (var t in tables) {
            try {
              await db.execute("UPDATE $t SET sync_id = substr(sync_id, 1, 8) || '-' || substr(sync_id, 9, 4) || '-' || substr(sync_id, 13, 4) || '-' || substr(sync_id, 17, 4) || '-' || substr(sync_id, 21, 12) WHERE length(sync_id) = 32");
            } catch (e) {
              print("Failed to normalize sync_id on table $t: $e");
              try {
                // If update failed due to UNIQUE constraint, delete the undashed duplicate (length 32)
                // whose normalized version already exists in the table as a 36-character dashed UUID.
                await db.execute('''
                  DELETE FROM $t 
                  WHERE length(sync_id) = 32 
                    AND (substr(sync_id, 1, 8) || '-' || substr(sync_id, 9, 4) || '-' || substr(sync_id, 13, 4) || '-' || substr(sync_id, 17, 4) || '-' || substr(sync_id, 21, 12)) 
                        IN (SELECT sync_id FROM $t WHERE length(sync_id) = 36)
                ''');
                // Retry the update
                await db.execute("UPDATE $t SET sync_id = substr(sync_id, 1, 8) || '-' || substr(sync_id, 9, 4) || '-' || substr(sync_id, 13, 4) || '-' || substr(sync_id, 17, 4) || '-' || substr(sync_id, 21, 12) WHERE length(sync_id) = 32");
              } catch (innerErr) {
                print("Failed to resolve unique constraint conflict on table $t: $innerErr");
              }
            }
          }

          // Normalize is_debt and is_paid to strict 0 and 1 integers
          await db.execute("UPDATE sales SET is_debt = CASE WHEN is_debt = 'true' OR is_debt = 1 THEN 1 ELSE 0 END, is_paid = CASE WHEN is_paid = 'true' OR is_paid = 1 THEN 1 ELSE 0 END");
          await db.execute("UPDATE deleted_history SET is_debt = CASE WHEN is_debt = 'true' OR is_debt = 1 THEN 1 ELSE 0 END, is_paid = CASE WHEN is_paid = 'true' OR is_paid = 1 THEN 1 ELSE 0 END");


          // --- ENFORCE UNIQUE INDEXES FOR DELTA SYNC ---
          try {
            // One-time cleanup for zombie duplicates from previous sync bugs
            final hasReset = await db.rawQuery("SELECT value FROM settings WHERE key = 'has_reset_zombies_v3'");
            if (hasReset.isEmpty) {
                await db.execute("DELETE FROM sales WHERE is_edited = 0");
                await db.execute("DELETE FROM stock WHERE is_edited = 0");
                await db.execute("UPDATE settings SET value = '0' WHERE key = 'last_backup_timestamp'");
                await db.execute("INSERT INTO settings (key, value) VALUES ('has_reset_zombies_v3', '1')");
                print("ZOMBIE CLEANUP: Wiped corrupt local cloud data and reset sync cursor.");
            }

            // One-time migration to re-sync all sales to restore any missing records deleted by buggy deduplication
            try {
              final hasReSynced = await db.rawQuery("SELECT value FROM settings WHERE key = 'has_re_synced_missing_sales_v3'");
              if (hasReSynced.isEmpty) {
                await db.execute("UPDATE sales SET is_edited = 1");
                await db.execute("DELETE FROM deleted_history"); // Clear all stale deletion logs!
                await db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('last_backup_timestamp', '0')"); // force sync cursor reset
                await db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('has_re_synced_missing_sales_v3', '1')");
                print("RE-SYNC MIGRATION: Marked all sales as edited and reset sync cursor.");
              }
            } catch (e) {
              print("Failed to run re-sync migration: $e");
            }

            await db.execute("DELETE FROM stock WHERE id NOT IN (SELECT MAX(id) FROM stock GROUP BY item, quantity)");
            await db.execute("DELETE FROM sales WHERE id NOT IN (SELECT MAX(id) FROM sales GROUP BY created_at, customer, item, amount, date)");
            
            await db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_stock_item_qty ON stock(item, quantity)");
            await db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_stock_sync_id ON stock(sync_id)");
            await db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_sync_id ON sales(sync_id)");

            await db.execute("UPDATE sales SET receipt_id = NULL, is_edited = 1 WHERE receipt_id = '' OR receipt_id = 'null'");

            // Reconcile/cleanup legacy sales that lack a receipt_id but were created around the same time for the same customer
            try {
              final legacySales = await db.rawQuery(
                "SELECT id, customer, date, created_at FROM sales WHERE (receipt_id IS NULL OR receipt_id = '') AND customer != 'Walk-in Customer' ORDER BY customer, created_at"
              );
              
              int i = 0;
              while (i < legacySales.length) {
                final base = legacySales[i];
                final baseId = base['id'] as int;
                final baseCustomer = base['customer'] as String;
                final baseCreatedAt = base['created_at'] as String?;
                
                final List<int> idsToGroup = [baseId];
                
                int j = i + 1;
                while (j < legacySales.length) {
                  final next = legacySales[j];
                  final nextId = next['id'] as int;
                  final nextCustomer = next['customer'] as String;
                  final nextCreatedAt = next['created_at'] as String?;
                  
                  if (baseCustomer == nextCustomer) {
                    final diffSeconds = _getSecondsDifference(baseCreatedAt, nextCreatedAt);
                    if (diffSeconds >= 0 && diffSeconds <= 30) {
                      idsToGroup.add(nextId);
                      j++;
                    } else {
                      break;
                    }
                  } else {
                    break;
                  }
                }
                
                if (idsToGroup.length > 1) {
                  final newReceiptId = DatabaseHelper.generateUUID();
                  final idsCsv = idsToGroup.join(",");
                  await db.rawUpdate(
                    "UPDATE sales SET receipt_id = ?, is_edited = 1 WHERE id IN ($idsCsv)",
                    [newReceiptId]
                  );
                  print("DEBUG: Consolidated legacy sales: $idsToGroup under receipt_id: $newReceiptId");
                }
                i = j;
              }
            } catch (e) {
              print("Failed to clean up legacy sales: $e");
            }

            // Deduplicate zombie duplicate sales entries (e.g. from checkout double-taps)
            try {
              final duplicateSales = await db.rawQuery('''
                SELECT id, sync_id, customer 
                FROM sales 
                WHERE sync_id IS NOT NULL AND id NOT IN (
                  SELECT MIN(id) 
                  FROM sales 
                  GROUP BY sync_id
                )
              ''');
              
              for (var row in duplicateSales) {
                final dupId = row['id'] as int;
                final dupSyncId = row['sync_id'] as String?;
                final dupCustomer = row['customer'] as String? ?? '';
                
                await db.rawDelete('DELETE FROM sales WHERE id = ?', [dupId]);
                print("DEDUPLICATE CLEANUP: Deleted duplicate sale ID: $dupId (sync_id: $dupSyncId) for customer: $dupCustomer");
              }
            } catch (e) {
              print("Failed to deduplicate sales: $e");
            }
          } catch (e) {
            print("Index creation failed: $e");
          }
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
        sync_id TEXT,
        supplier $textType,
        item $textType,
        quantity $textType,
        unit $textType,
        price $realType,
        available_pieces $realDefault0,
        is_edited INTEGER DEFAULT 0,
        date $dateType,
        device_source TEXT DEFAULT 'Mobile',
        created_at $dateTimeDefault
      )
    ''');

    // Sales Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales (
        id $idType,
        sync_id TEXT,
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
        device_source TEXT DEFAULT 'Mobile',
        receipt_id TEXT,
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

    // Notifications Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message TEXT,
        source TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        is_read INTEGER DEFAULT 0
      )
    ''');

    // Debt Payments Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS debt_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        amount_paid REAL NOT NULL,
        payment_date TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        sync_id TEXT,
        FOREIGN KEY (sale_id) REFERENCES sales(id)
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
     try {
       final db = await instance.database;
       final today = DateTime.now().toIso8601String().split('T')[0]; // YYYY-MM-DD
       
       // Profit = amount - (cost_price * base_quantity)
       // Filter: date = today AND type != 'NEW STOCK'
       final result = await db.rawQuery('''
         SELECT 
           SUM(CASE WHEN is_debt = 0 THEN amount ELSE 0 END) as total_sales,
           SUM(CASE WHEN is_debt = 1 THEN amount ELSE 0 END) as total_debt,
           SUM(amount - (cost_price * base_quantity)) as total_profit
         FROM sales 
         WHERE date = ? AND type != 'NEW STOCK'
       ''', [today]);
       
       if (result.isNotEmpty) {
         return {
           'sales': (result.first['total_sales'] as num?)?.toDouble() ?? 0.0,
           'debt': (result.first['total_debt'] as num?)?.toDouble() ?? 0.0,
           'profit': (result.first['total_profit'] as num?)?.toDouble() ?? 0.0,
         };
       }
     } catch (e) {
       print("Error fetching todays stats: $e");
     }
     return {'sales': 0.0, 'debt': 0.0, 'profit': 0.0};
  }

  Future<double> getYesterdaysProfit() async {
     try {
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
     } catch (e) {
       print("Error fetching yesterday's profit: $e");
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

  // Dashboard: Total Unsettled Debt
  Future<double> getTotalDebt() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT SUM(amount - COALESCE(paid_amount, 0)) as total FROM sales WHERE is_debt = 1 AND is_paid = 0 AND customer != \'Walk-in Customer\'');
    if (result.isNotEmpty && result.first['total'] != null) {
      return (result.first['total'] as num).toDouble();
    }
    return 0.0;
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
      "SELECT * FROM sales WHERE date = ? AND type != 'NEW STOCK' ORDER BY REPLACE(created_at, 'T', ' ') DESC", 
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
    final List<Map<String, dynamic>> result = await db.query(
      'stock',
      columns: ['item', 'quantity', 'price', 'unit'],
      where: 'id = ?',
      whereArgs: [id],
    );

    if (result.isNotEmpty) {
      final item = result.first;
      final String itemName = item['item'] as String? ?? 'Unknown';
      final String size = item['quantity'] as String? ?? '';
      final double oldPiecePrice = (item['price'] as num? ?? 0.0).toDouble();
      final String unit = item['unit'] as String? ?? 'pcs';
      final double multiplier = getUnitMultiplier(unit, size, unit);
      
      final double oldUnitPrice = oldPiecePrice * multiplier;
      final double newUnitPrice = newPrice * multiplier;

      await db.rawUpdate(
        'UPDATE stock SET price = ?, is_edited = 1 WHERE id = ?',
        [newPrice, id]
      );

      if (oldPiecePrice != newPrice) {
        await addNotification(
          "Price updated for $itemName ($size): UGX ${oldUnitPrice.toStringAsFixed(0)} ➔ UGX ${newUnitPrice.toStringAsFixed(0)} per $unit",
          "Mobile"
        );
      }
    } else {
      await db.rawUpdate(
        'UPDATE stock SET price = ?, is_edited = 1 WHERE id = ?',
        [newPrice, id]
      );
    }
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
    String syncId = generateUUID();
    await db.rawInsert(
      "INSERT INTO stock(sync_id, supplier, item, quantity, unit, price, available_pieces, date, is_edited, device_source) VALUES(?, ?, ?, ?, ?, ?, ?, ?, 1, 'Mobile')",
      [syncId, s, i, q, cleanUnitLabel(u), pricePerSinglePiece, totalPieces, d]
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

      String syncId = generateUUID();
      await db.rawInsert(
          "INSERT INTO sales(sync_id, customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date, is_debt, is_paid, paid_amount, is_edited, device_source, receipt_id, created_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 'Mobile', ?, ?)",
          [
              syncId, customer, item, size, unit, sellingPrice, 
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
              await db.rawUpdate('UPDATE sales SET paid_amount = amount, is_paid = 1, is_edited = 1 WHERE id = ?', [id]);
          } else {
              await db.rawUpdate('UPDATE sales SET paid_amount = ?, is_edited = 1 WHERE id = ?', [updatedPaid, id]);
          }
      }
  }

  Future<void> markDebtAsPaid(String customer, double newPayment) async {
      final db = await instance.database;
      
      final result = await db.rawQuery('SELECT id, amount, paid_amount FROM sales WHERE customer = ? AND is_debt = 1 AND is_paid = 0 ORDER BY date ASC, created_at ASC', [customer]);
      
      double remainingPayment = newPayment;
      
      for (var row in result) {
          if (remainingPayment <= 0) break;
          
          int id = row['id'] as int;
          double totalAmount = (row['amount'] as num).toDouble();
          double currentPaid = (row['paid_amount'] as num? ?? 0).toDouble();
          double debtRemainingOnItem = totalAmount - currentPaid;
          
          double amountToApply = debtRemainingOnItem < remainingPayment ? debtRemainingOnItem : remainingPayment;
          double updatedPaid = currentPaid + amountToApply;
          remainingPayment -= amountToApply;
          
          // Do not set is_paid = 1 yet. Wait until the whole debt is cleared.
          await db.rawUpdate('UPDATE sales SET paid_amount = ?, is_edited = 1 WHERE id = ?', [updatedPaid, id]);
          
          // Record payment locally
          final uuidGenSql = "lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))),2) || '-a' || substr(lower(hex(randomblob(2))),2) || '-' || lower(hex(randomblob(6)))";
          await db.rawInsert('''
            INSERT INTO debt_payments (sale_id, amount_paid, payment_date, sync_id)
            VALUES (?, ?, ?, ($uuidGenSql))
          ''', [id, amountToApply, DateTime.now().toIso8601String().split('T')[0]]);
      }
      
      // Check if total outstanding debt for this customer is cleared
      final debtCheck = await db.rawQuery('SELECT SUM(amount - COALESCE(paid_amount, 0)) as total FROM sales WHERE customer = ? AND is_debt = 1 AND is_paid = 0', [customer]);
      if (debtCheck.isNotEmpty && (debtCheck.first['total'] as num? ?? 0).toDouble() <= 0) {
          // Entire debt cycle cleared! Mark all as paid.
          await db.rawUpdate('UPDATE sales SET is_paid = 1, is_edited = 1 WHERE customer = ? AND is_debt = 1 AND is_paid = 0', [customer]);
      }
      
      await addNotification("Payment of $newPayment received for $customer", "Mobile");
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
      'sync_id': item['sync_id'],
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
      'is_edited': 1,
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
          await db.insert('deleted_stock', {
              'sync_id': stockResult.first['sync_id'],
              'item': itemName, 
              'quantity': size
          });
          await db.delete('stock', where: 'id = ?', whereArgs: [stockId]);
      }
    }

    // 4. Delete from sales
    await db.delete('sales', where: 'id = ?', whereArgs: [id]);

    // 5. Record a notification for audit trail
    String customer = item['customer'] as String;
    double amount = (item['amount'] as num).toDouble();
    String actionLabel = type == 'NEW STOCK'
        ? 'Deleted stock entry: $itemName'
        : 'Deleted sale for $customer: $itemName (UGX ${amount.toStringAsFixed(0)})';
    await addNotification(actionLabel, 'Mobile');
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
          "SELECT supplier FROM ("
          "SELECT supplier, created_at FROM stock WHERE supplier IS NOT NULL AND supplier != '' "
          "UNION ALL "
          "SELECT customer AS supplier, created_at FROM sales WHERE type = 'NEW STOCK' AND customer IS NOT NULL AND customer != ''"
          ") GROUP BY supplier ORDER BY MAX(created_at) DESC LIMIT 10"
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
    final result = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (result.isNotEmpty) {
      return result.first['value'] as String?;
    }
    return null;
  }

  // --- POSTGRES SYNC HELPERS ---

  Future<void> clearDirtyFlags() async {
    final db = await instance.database;
    await db.rawUpdate("UPDATE stock SET is_edited = 0");
    await db.rawUpdate("UPDATE sales SET is_edited = 0");
    await db.rawDelete("DELETE FROM deleted_stock");
  }

  Future<List<Map<String, dynamic>>> getDirtyStock() async {
    final db = await instance.database;
    return await db.rawQuery("SELECT sync_id, item, quantity, unit, price, available_pieces, device_source, date FROM stock WHERE is_edited = 1 AND sync_id IS NOT NULL");
  }

  Future<List<Map<String, dynamic>>> getDirtySales() async {
    final db = await instance.database;
    return await db.rawQuery("SELECT sync_id, customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date, is_debt, is_paid, paid_amount, receipt_id, device_source, created_at FROM sales WHERE is_edited = 1 AND sync_id IS NOT NULL");
  }

  Future<List<Map<String, dynamic>>> getDirtyDeletedStock() async {
    final db = await instance.database;
    return await db.rawQuery("SELECT sync_id, item, quantity, deleted_at FROM deleted_stock WHERE sync_id IS NOT NULL");
  }

  Future<List<Map<String, dynamic>>> getDirtyDeletedHistory() async {
    final db = await instance.database;
    return await db.rawQuery("SELECT sync_id, customer, item, amount, date, deleted_at FROM deleted_history WHERE sync_id IS NOT NULL");
  }

  /// Pull cloud stock into local DB.
  /// [forceAcceptPieces] = true on manual/full sync to correct drift.
  /// During incremental background sync, set false so delta merge handles counts.
  Future<void> upsertCloudStock(List<dynamic> cloudStock, {bool forceAcceptPieces = false}) async {
    if (cloudStock.isEmpty) return;
    final db = await instance.database;
    
    for (var obj in cloudStock) {
      final existing = await db.rawQuery('SELECT is_edited, price, item, quantity, unit FROM stock WHERE sync_id = ?', [obj['sync_id']]);
      if (existing.isNotEmpty) {
        bool localIsDirty = (existing.first['is_edited'] as int? ?? 0) == 1;

        double parsePrice(dynamic v) {
          if (v == null) return 0.0;
          if (v is num) return v.toDouble();
          if (v is String) return double.tryParse(v) ?? 0.0;
          return 0.0;
        }

        final double oldPrice = parsePrice(existing.first['price']);
        final double newPrice = parsePrice(obj['price']);
        final String deviceSource = obj['device_source'] ?? 'Cloud';

        if (oldPrice != newPrice && deviceSource != 'Mobile') {
          final String itemName = existing.first['item'] as String? ?? obj['item'] ?? 'Unknown';
          final String size = existing.first['quantity'] as String? ?? obj['quantity'] ?? '';
          final String unit = existing.first['unit'] as String? ?? obj['unit'] ?? 'pcs';
          final double multiplier = getUnitMultiplier(unit, size, unit);

          final double oldUnitPrice = oldPrice * multiplier;
          final double newUnitPrice = newPrice * multiplier;

          await addNotification(
            "Price updated for $itemName ($size): UGX ${oldUnitPrice.toStringAsFixed(0)} ➔ UGX ${newUnitPrice.toStringAsFixed(0)} per $unit",
            deviceSource
          );
        }

        if (!localIsDirty && forceAcceptPieces) {
          // Manual/full sync: accept cloud available_pieces to correct any drift
          await db.rawUpdate('''
            UPDATE stock SET supplier=?, item=?, quantity=?, unit=?, price=?, available_pieces=?, device_source=?, date=?, is_edited=0 WHERE sync_id=?
          ''', [
            obj['supplier'] ?? 'Unknown',
            obj['item'] ?? 'Unknown',
            obj['quantity'] ?? '0',
            obj['unit'] ?? '',
            obj['price'] ?? 0,
            obj['available_pieces'] ?? 0,
            obj['device_source'] ?? 'Cloud',
            obj['date'] ?? DateTime.now().toIso8601String().split('T')[0],
            obj['sync_id']
          ]);
        } else {
          // Incremental sync OR local is dirty: preserve local available_pieces, delta merge handles adjustments
          await db.rawUpdate('''
            UPDATE stock SET supplier=?, item=?, quantity=?, unit=?, price=?, device_source=?, date=? WHERE sync_id=?
          ''', [
            obj['supplier'] ?? 'Unknown',
            obj['item'] ?? 'Unknown',
            obj['quantity'] ?? '0',
            obj['unit'] ?? '',
            obj['price'] ?? 0,
            obj['device_source'] ?? 'Cloud',
            obj['date'] ?? DateTime.now().toIso8601String().split('T')[0],
            obj['sync_id']
          ]);
        }
      } else {
        // New stock row: always accept cloud available_pieces
        await db.rawInsert('''
          INSERT INTO stock (sync_id, supplier, item, quantity, unit, price, available_pieces, device_source, date, is_edited) 
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
        ''', [
          obj['sync_id'],
          obj['supplier'] ?? 'Unknown',
          obj['item'] ?? 'Unknown',
          obj['quantity'] ?? '0',
          obj['unit'] ?? '',
          obj['price'] ?? 0,
          obj['available_pieces'] ?? 0,
          obj['device_source'] ?? 'Cloud',
          obj['date'] ?? DateTime.now().toIso8601String().split('T')[0]
        ]);
      }
    }
  }

  Future<void> upsertCloudSales(List<dynamic> cloudSales, bool isIncremental) async {
    if (cloudSales.isEmpty) return;
    final db = await instance.database;
    
    for (var obj in cloudSales) {
      final existing = await db.rawQuery('SELECT id, paid_amount FROM sales WHERE sync_id = ?', [obj['sync_id']]);
      bool isNew = existing.isEmpty;
      int localId = isNew ? -1 : existing.first['id'] as int;
      double localPaidAmount = isNew ? 0.0 : double.tryParse(existing.first['paid_amount']?.toString() ?? '0') ?? 0.0;
      
      int isDebtVal = (obj['is_debt'] == true || obj['is_debt'] == 1 || obj['is_debt'] == 'true') ? 1 : 0;
      int isPaidVal = (obj['is_paid'] == true || obj['is_paid'] == 1 || obj['is_paid'] == 'true') ? 1 : 0;
      double cloudPaidAmount = double.tryParse(obj['paid_amount']?.toString() ?? '0') ?? 0.0;
      String deviceSource = obj['device_source'] ?? 'Cloud';
      String type = obj['type'] ?? '';
      String item = obj['item'] ?? '';
      double amount = double.tryParse(obj['amount']?.toString() ?? '0') ?? 0.0;
      String customer = obj['customer'] ?? '';

      String? receiptId = obj['receipt_id'];
      if (receiptId == '' || receiptId == 'null') {
        receiptId = null;
      }

      if (isNew) {
        await db.rawInsert('''
          INSERT INTO sales (sync_id, customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date, is_debt, is_paid, paid_amount, receipt_id, device_source, created_at, is_edited) 
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
        ''', [
          obj['sync_id'],
          customer,
          item,
          obj['quantity'] ?? '0',
          obj['unit'] ?? '',
          obj['price'] ?? 0,
          obj['cost_price'] ?? 0,
          obj['base_quantity'] ?? 0,
          amount,
          type,
          obj['date'] ?? DateTime.now().toIso8601String().split('T')[0],
          isDebtVal,
          isPaidVal,
          cloudPaidAmount,
          receiptId,
          deviceSource,
          obj['created_at'] ?? DateTime.now().toIso8601String()
        ]);
      } else {
        await db.rawUpdate('''
          UPDATE sales SET customer = ?, item = ?, quantity = ?, unit = ?, price = ?, cost_price = ?, base_quantity = ?, amount = ?, type = ?, date = ?, is_debt = ?, is_paid = ?, paid_amount = ?, receipt_id = ?, device_source = ?, is_edited = 0 WHERE sync_id = ?
        ''', [
          customer,
          item,
          obj['quantity'] ?? '0',
          obj['unit'] ?? '',
          obj['price'] ?? 0,
          obj['cost_price'] ?? 0,
          obj['base_quantity'] ?? 0,
          amount,
          type,
          obj['date'] ?? DateTime.now().toIso8601String().split('T')[0],
          isDebtVal,
          isPaidVal,
          cloudPaidAmount,
          receiptId,
          deviceSource,
          obj['sync_id']
        ]);
      }
      
      if (isNew) {
        if (deviceSource == 'Desktop' && isIncremental) {
          if (type == 'NEW STOCK') {
            await addNotification("Added stock: $item", "Desktop");
          } else {
            await addNotification("Sale recorded for $customer: $item (UGX ${amount.toStringAsFixed(0)})", "Desktop");
          }
        }

        if (isIncremental && item.isNotEmpty && (obj['quantity'] ?? '').isNotEmpty && (obj['unit'] ?? '').isNotEmpty) {
          double multiplier = getUnitMultiplier(obj['unit'] ?? '', obj['quantity'] ?? '');
          double count = extractNumericValue(obj['unit'] ?? '') * multiplier;
          
          if (type == 'NEW STOCK') {
             await db.rawUpdate('''
               UPDATE stock SET available_pieces = available_pieces + ?, supplier = ?, is_edited = 1 WHERE item = ? AND quantity = ?
             ''', [count, customer, item, obj['quantity']]);
          } else if (type.isNotEmpty && type != 'Debt Payment' && type != 'Payment') {
             await db.rawUpdate('''
               UPDATE stock SET available_pieces = available_pieces - ?, is_edited = 1 WHERE item = ? AND quantity = ?
             ''', [count, item, obj['quantity']]);
          }
        }
      } else {
        if (cloudPaidAmount > localPaidAmount) {
          double diff = cloudPaidAmount - localPaidAmount;
          if (deviceSource == 'Desktop' && isIncremental) {
            await addNotification("Payment of UGX ${diff.toStringAsFixed(0)} received for $customer", "Desktop");
          }
          if (localId != -1) {
            final uuidGenSql = "lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))),2) || '-a' || substr(lower(hex(randomblob(2))),2) || '-' || lower(hex(randomblob(6)))";
            await db.rawInsert('''
              INSERT INTO debt_payments (sale_id, amount_paid, payment_date, sync_id)
              VALUES (?, ?, ?, ($uuidGenSql))
            ''', [localId, diff, DateTime.now().toIso8601String().split('T')[0]]);
          }
        }
      }
    }
  }

  Future<void> processCloudDeletions(List<dynamic> deletedStock, List<dynamic> deletedSales) async {
    final db = await instance.database;

    // Notify for each desktop-originated stock deletion
    for (var obj in deletedStock) {
      final syncId = obj['sync_id'];
      final existing = await db.rawQuery('SELECT item, quantity FROM stock WHERE sync_id = ?', [syncId]);
      if (existing.isNotEmpty) {
        String item = existing.first['item'] as String;
        await addNotification('Deleted stock: $item', 'Desktop');
      }
    }

    // Notify for each desktop-originated sale deletion
    for (var obj in deletedSales) {
      final syncId = obj['sync_id'];
      final existing = await db.rawQuery('SELECT customer, item, amount FROM sales WHERE sync_id = ?', [syncId]);
      if (existing.isNotEmpty) {
        String customer = existing.first['customer'] as String;
        String item = existing.first['item'] as String;
        double amount = (existing.first['amount'] as num).toDouble();
        await addNotification('Deleted sale for $customer: $item (UGX ${amount.toStringAsFixed(0)})', 'Desktop');
      }
    }

    // Now perform the actual deletions
    Batch batch = db.batch();
    for (var obj in deletedStock) {
      batch.rawDelete("DELETE FROM stock WHERE sync_id = ?", [obj['sync_id']]);
    }
    for (var obj in deletedSales) {
      batch.rawDelete("DELETE FROM sales WHERE sync_id = ?", [obj['sync_id']]);
    }
    await batch.commit(noResult: true);
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



  Future<void> showLocalNotification(String title, String body) async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await flutterLocalNotificationsPlugin.show(
          body.hashCode,
          title,
          body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'high_importance_channel',
              'High Importance Notifications',
              channelDescription: 'This channel is used for important notifications.',
              icon: '@mipmap/ic_launcher',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
        );
      } catch (e) {
        print("Error showing local notification: $e");
      }
    }
  }

  Future<void> addNotification(String message, String source) async {
      final db = await instance.database;
      String syncId = generateUUID();
      await db.rawInsert(
          "INSERT INTO notifications (message, source, sync_id) VALUES (?, ?, ?)",
          [message, source, syncId]
      );
      if (source == 'Desktop') {
          await showLocalNotification("Desktop App Input", message);
      }
  }

  Future<List<Map<String, dynamic>>> getNotifications() async {
      try {
          final db = await instance.database;
          return await db.rawQuery("SELECT id, message, source, created_at, is_read FROM notifications ORDER BY created_at DESC");
      } catch (e) {
          print("Error fetching notifications: $e");
          return [];
      }
  }

  Future<void> markNotificationAsRead(int id) async {
      final db = await instance.database;
      await db.rawUpdate("UPDATE notifications SET is_read = 1 WHERE id = ?", [id]);
  }
}
