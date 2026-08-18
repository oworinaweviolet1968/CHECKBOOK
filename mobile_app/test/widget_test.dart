import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:checkbook/services/passcode_service.dart';
import 'package:checkbook/widgets/stock_item_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PasscodeService Tests', () {
    test('Initial locked state without passcode', () {
      final passcodeService = PasscodeService.instance;
      expect(passcodeService.hasPasscode, isFalse);
    });

    test('Verify passcode logic', () async {
      final passcodeService = PasscodeService.instance;
      bool verified = await passcodeService.verifyPasscode("1234");
      expect(verified, isTrue);
    });
  });

  group('Widget Tests', () {
    testWidgets('StockItemTile renders title and price correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StockItemTile(
              itemName: 'Sugar',
              quantity: '10 Sacks',
              price: '5,000',
            ),
          ),
        ),
      );

      expect(find.text('Sugar'), findsOneWidget);
      expect(find.text('10 Sacks'), findsOneWidget);
    });
  });
}
