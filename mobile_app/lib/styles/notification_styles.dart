import 'package:flutter/material.dart';
import '../utils/colors.dart';

class NotificationStyles {
  static const double cardMarginHorizontal = 16.0;
  static const double cardMarginVertical = 6.0;
  static const double cardElevation = 0.0;
  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(12));
  static const EdgeInsets listTilePadding = EdgeInsets.all(16);

  static const TextStyle titleStyleUnread = TextStyle(
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );
  static const TextStyle titleStyleRead = TextStyle(
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
  );
  static const TextStyle subtitleStyle = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 12,
  );
}
