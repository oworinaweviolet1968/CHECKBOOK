import 'package:flutter_test/flutter_test.dart';
import 'package:checkbook/screens/notifications_screen.dart';

void main() {
  group('NotificationRouteInfo.parse Tests', () {
    test('NEW STOCK: worry has been stocked', () {
      final route = NotificationRouteInfo.parse('NEW STOCK: worry has been stocked');
      expect(route.type, NotificationTargetType.stock);
      expect(route.query, 'worry');
    });

    test('Added eco gel from VIO', () {
      final route = NotificationRouteInfo.parse('Added eco gel from VIO');
      expect(route.type, NotificationTargetType.stock);
      expect(route.query, 'eco gel');
    });

    test('Added stock from VIO', () {
      final route = NotificationRouteInfo.parse('Added stock from VIO');
      expect(route.type, NotificationTargetType.stock);
      expect(route.query, 'VIO');
    });

    test('Sale recorded for dan: eco gel (UGX 80000)', () {
      final route = NotificationRouteInfo.parse('Sale recorded for dan: eco gel (UGX 80000)');
      expect(route.type, NotificationTargetType.sale);
      expect(route.query, 'eco gel');
    });

    test('Sale recorded: dan bought eco gel (1 half doz * 6, UGX 80,000)', () {
      final route = NotificationRouteInfo.parse('Sale recorded: dan bought eco gel (1 half doz * 6, UGX 80,000)');
      expect(route.type, NotificationTargetType.sale);
      expect(route.query, 'eco gel');
    });

    test('Sale made for Walk-in Customer: eco gel', () {
      final route = NotificationRouteInfo.parse('Sale made for Walk-in Customer: eco gel');
      expect(route.type, NotificationTargetType.sale);
      expect(route.query, 'eco gel');
    });

    test('Debt recorded for dan: eco gel', () {
      final route = NotificationRouteInfo.parse('Debt recorded for dan: eco gel');
      expect(route.type, NotificationTargetType.debt);
      expect(route.query, 'eco gel');
    });

    test('Payment of UGX 240000 received for Mrs Sam', () {
      final route = NotificationRouteInfo.parse('Payment of UGX 240000 received for Mrs Sam');
      expect(route.type, NotificationTargetType.debt);
      expect(route.query, 'Mrs Sam');
    });

    test('Payment of 10000 received for sale #123', () {
      final route = NotificationRouteInfo.parse('Payment of 10000 received for sale #123');
      expect(route.type, NotificationTargetType.debt);
      expect(route.query, '123');
    });

    test('App is online.', () {
      final route = NotificationRouteInfo.parse('App is online.');
      expect(route.type, NotificationTargetType.none);
    });
  });
}
