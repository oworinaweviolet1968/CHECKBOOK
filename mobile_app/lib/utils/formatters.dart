import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class ThousandsFormatter extends TextInputFormatter {
  final NumberFormat _formatter = NumberFormat("#,###");

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    // Remove all non-essential formatting characters
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return newValue;

    try {
      final double value = double.parse(digits);
      final String formatted = _formatter.format(value);
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    } catch (_) {
      return oldValue;
    }
  }
}

class UnitFormatter {
  /// Strips leading numeric prefixes, secondary slash breakdowns,
  /// and formats standard unit strings (e.g., "7 box*12" -> "Box*12", "14 Half Doz" -> "Half Dozen").
  static String formatUnitLabel(String input) {
    if (input.trim().isEmpty) return "";

    // 1. Remove slash-separated secondary piece breakdowns (e.g. "/ 6 pcs")
    String text = input.split('/').first.trim();

    // 2. Strip leading numeric prefixes and whitespace (e.g. "7 box*12" -> "box*12", "14 Half Doz" -> "Half Doz")
    text = text.replaceFirst(RegExp(r'^\d+(\.\d+)?\s*'), '').trim();

    if (text.isEmpty) return input.trim();

    // 3. Standardize / format known unit strings
    String lower = text.toLowerCase();

    if (lower == 'pcs' || lower == 'pc') {
      return 'Pcs';
    } else if (lower == 'half doz' || lower == 'half dozen' || lower == 'halfdoz') {
      return 'Half Dozen';
    } else if (lower == 'doz' || lower == 'dozen') {
      return 'Dozen';
    } else if (lower.startsWith('box')) {
      return text.replaceFirst(RegExp(r'^box', caseSensitive: false), 'Box');
    } else if (lower.startsWith('crate')) {
      return text.replaceFirst(RegExp(r'^crate', caseSensitive: false), 'Crate');
    } else if (lower.startsWith('carton')) {
      return text.replaceFirst(RegExp(r'^carton', caseSensitive: false), 'Carton');
    } else if (lower.startsWith('sack')) {
      return text.replaceFirst(RegExp(r'^sack', caseSensitive: false), 'Sack');
    } else if (lower == 'pks' || lower == 'pack' || lower == 'packs') {
      return 'Pack';
    }

    // Fallback: Capitalize first letter
    return text[0].toUpperCase() + text.substring(1);
  }
}

