import 'package:flutter_test/flutter_test.dart';
import 'package:checkbook/services/database_helper.dart';

bool isUnitSelected(String selectedUnitLabel, String? btnValue) {
  if (btnValue == null) return false;
  String selected = selectedUnitLabel.toLowerCase().replaceAll(' ', '');
  String button = btnValue.toLowerCase().replaceAll(' ', '');

  if (selected == button) return true;
  if (button == "pcs" && (selected == "pcs" || selected == "pc" || selected == "1pc")) return true;

  if (selected.contains('*') && button.contains('*')) {
    String selectedNum = selected.split('*').last;
    String buttonNum = button.split('*').last;
    return selectedNum == buttonNum;
  }

  return false;
}

void main() {
  group('Unit Packaging Presets & Multiplier Tests', () {
    test('Verify multipliers for 36, 48, 96, 100 pcs presets', () {
      expect(DatabaseHelper.instance.getUnitMultiplier('box*36', ''), equals(36.0));
      expect(DatabaseHelper.instance.getUnitMultiplier('box*48', ''), equals(48.0));
      expect(DatabaseHelper.instance.getUnitMultiplier('box*96', ''), equals(96.0));
      expect(DatabaseHelper.instance.getUnitMultiplier('box*100', ''), equals(100.0));
    });

    test('Verify cleanUnitLabel for 36, 48, 96, 100 pcs presets', () {
      expect(DatabaseHelper.instance.cleanUnitLabel('box*36'), equals('box*36'));
      expect(DatabaseHelper.instance.cleanUnitLabel('1 Box * 48'), equals('box*48'));
      expect(DatabaseHelper.instance.cleanUnitLabel('box*96'), equals('box*96'));
      expect(DatabaseHelper.instance.cleanUnitLabel('box*100'), equals('box*100'));
    });

    test('Verify 100pcs selection does NOT highlight 10pcs chip', () {
      expect(isUnitSelected('box*100', 'box*100'), isTrue);
      expect(isUnitSelected('box*100', 'box*10'), isFalse);
      expect(isUnitSelected('box*10', 'box*10'), isTrue);
      expect(isUnitSelected('box*10', 'box*100'), isFalse);
    });

    test('Verify standard existing multipliers continue to work', () {
      expect(DatabaseHelper.instance.getUnitMultiplier('pcs', ''), equals(1.0));
      expect(DatabaseHelper.instance.getUnitMultiplier('half doz', ''), equals(6.0));
      expect(DatabaseHelper.instance.getUnitMultiplier('box*10', ''), equals(10.0));
      expect(DatabaseHelper.instance.getUnitMultiplier('box*12', ''), equals(12.0));
      expect(DatabaseHelper.instance.getUnitMultiplier('box*24', ''), equals(24.0));
    });
  });
}
