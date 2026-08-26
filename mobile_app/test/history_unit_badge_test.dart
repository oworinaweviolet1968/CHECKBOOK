import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

// Helper matching _buildUnitChipWidget in history_screen.dart & debt_history_screen.dart
Widget buildTestUnitChipWidget(String qtyVal, String unitLabel) {
  String formattedQty = '';
  if (qtyVal.trim().isNotEmpty) {
    double? val = double.tryParse(qtyVal.trim());
    if (val != null) {
      if (val == val.roundToDouble()) {
        formattedQty = val.toInt().toString();
      } else {
        String s = val.toString();
        if (s.contains('.')) {
          s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
        }
        formattedQty = s;
      }
    } else {
      formattedQty = qtyVal.trim();
    }
  }

  String unitText;
  String u = unitLabel.toLowerCase().replaceAll(' ', '');

  if (u.isEmpty || u == 'pcs' || u == 'pc') {
    unitText = (formattedQty == '1') ? 'pc' : 'pcs';
  } else if (u.contains('halfdoz')) {
    unitText = 'half doz';
  } else if (u.contains('box*')) {
    final match = RegExp(r'box\*\d+').firstMatch(u);
    if (match != null) {
      unitText = match.group(0)!;
    } else {
      unitText = unitLabel.toLowerCase();
    }
  } else {
    unitText = unitLabel.toLowerCase();
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFFE0F7FA),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFF00A389).withValues(alpha: 0.25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (formattedQty.isNotEmpty) ...[
          Text(
            '$formattedQty • ',
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF00A389),
            ),
          ),
        ],
        const Icon(Icons.inventory_2_outlined, size: 13, color: Color(0xFF00A389)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            unitText,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF00A389),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Transaction History Unit Badge Tests', () {
    testWidgets('Renders [ 8 • 🗃️ box*12 ] correctly for quantity 8 and box*12', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildTestUnitChipWidget('8', 'box*12'),
          ),
        ),
      );

      expect(find.text('8 • '), findsOneWidget);
      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
      expect(find.text('box*12'), findsOneWidget);
    });

    testWidgets('Renders [ 8 • 🗃️ box*12 ] cleanly when quantity is integer double 8.0', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildTestUnitChipWidget('8.0', 'box*12'),
          ),
        ),
      );

      expect(find.text('8 • '), findsOneWidget);
      expect(find.text('8.0 • '), findsNothing);
      expect(find.text('box*12'), findsOneWidget);
    });

    testWidgets('Renders [ 8 • 🗃️ pcs ] for fallback unit/pieces', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildTestUnitChipWidget('8', 'pcs'),
          ),
        ),
      );

      expect(find.text('8 • '), findsOneWidget);
      expect(find.text('pcs'), findsOneWidget);
    });

    testWidgets('Renders [ 1 • 🗃️ pc ] for single piece item', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildTestUnitChipWidget('1', 'pcs'),
          ),
        ),
      );

      expect(find.text('1 • '), findsOneWidget);
      expect(find.text('pc'), findsOneWidget);
    });
  });
}
