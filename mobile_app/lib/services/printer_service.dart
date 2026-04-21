import 'dart:typed_data';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import '../models/sale_item.dart';

class PrinterService {
  static final PrinterService instance = PrinterService._();
  PrinterService._();

  final BlueThermalPrinter _bluetooth = BlueThermalPrinter.instance;
  BluetoothDevice? _connectedDevice;

  /// Automatically discovers and connects to an MPT-II or POS printer.
  Future<bool> connectToPrinter() async {
    bool? isConnected = await _bluetooth.isConnected;
    if (isConnected == true) return true;

    List<BluetoothDevice> devices = await _bluetooth.getBondedDevices();
    
    // Fuzzy search for MPT, POS, Thermal, etc.
    BluetoothDevice? printerDevice;
    for (var device in devices) {
      String name = (device.name ?? "").toLowerCase();
      if (name.contains("mpt") || name.contains("pos") || name.contains("thermal") || name.contains("demo")) {
        printerDevice = device;
        break;
      }
    }

    if (printerDevice != null) {
      try {
        await _bluetooth.connect(printerDevice);
        _connectedDevice = printerDevice;
        return true;
      } catch (e) {
        print("Error connecting to printer: $e");
        return false;
      }
    }
    return false;
  }

  /// Prints a formatted invoice to the connected thermal printer.
  Future<void> printInvoice(String customer, List<SaleItem> cart) async {
    bool connected = await connectToPrinter();
    if (!connected) throw Exception("Could not connect to thermal printer. Ensure it is paired and turned on.");

    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    List<int> bytes = [];

    // Header
    bytes += generator.text("CHECKBOOK APP", 
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    bytes += generator.text("Smart Inventory Management", styles: const PosStyles(align: PosAlign.center));
    bytes += generator.hr();

    // Sales Info
    bytes += generator.text("Date: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}");
    bytes += generator.text("Customer: ${customer.isEmpty ? 'Walk-in Customer' : customer}");
    bytes += generator.hr();

    // Table Header
    bytes += generator.row([
      PosColumn(text: 'Item', width: 6, styles: const PosStyles(bold: true)),
      PosColumn(text: 'Qty', width: 2, styles: const PosStyles(bold: true, align: PosAlign.right)),
      PosColumn(text: 'Total', width: 4, styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]);

    // Items
    double total = 0;
    final formatter = NumberFormat("#,###");
    
    for (var item in cart) {
      double amt = double.tryParse(item.amount) ?? 0;
      total += amt;
      
      // Print item name on its own line if long, or in a row if short
      bytes += generator.text("${item.item} (${item.quantity})", styles: const PosStyles(bold: true));
      
      bytes += generator.row([
        PosColumn(text: ' ${item.unit}', width: 8),
        PosColumn(text: formatter.format(amt), width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    bytes += generator.hr();

    // Total
    bytes += generator.row([
      PosColumn(text: 'TOTAL AMOUNT', width: 6, styles: const PosStyles(bold: true, height: PosTextSize.size2)),
      PosColumn(text: formatter.format(total), width: 6, styles: const PosStyles(align: PosAlign.right, bold: true, height: PosTextSize.size2)),
    ]);

    // Footer
    bytes += generator.feed(2);
    bytes += generator.text("Thank you for your business!", styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text("Powered by METO IMS", styles: const PosStyles(align: PosAlign.center));
    bytes += generator.feed(3);
    bytes += generator.cut();

    await _bluetooth.writeBytes(Uint8List.fromList(bytes));
  }
}
