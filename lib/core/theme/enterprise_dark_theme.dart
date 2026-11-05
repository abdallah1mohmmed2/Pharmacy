import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

abstract final class AppColors {
  static const bg = Color(0xFF121212);
  static const surface = Color(0xFF1E1E1E);
  static const surfaceHigh = Color(0xFF262626);
  static const outline = Color(0xFF333333);
  static const primary = Color(0xFF4DB6AC);
  static const onPrimary = Color(0xFF00201D);
  static const success = Color(0xFF66BB6A);
  static const warning = Color(0xFFFFB74D);
  static const danger = Color(0xFFEF5350);
  static const info = Color(0xFF64B5F6);
}

abstract final class MoneyFormatter {
  static final NumberFormat _format = NumberFormat('#,##0.00', 'en_US');
  static String format(num value, {String currency = 'ر.ي'}) =>
      _format.format(MoneyRound.two(value)) + ' ' + currency;
}

abstract final class MoneyRound {
  static double two(num value) => (value * 100).roundToDouble() / 100;
  static double whole(num value) => value.roundToDouble();
}

abstract final class EnterpriseDarkTheme {
  static ThemeData get data => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.info,
      surface: AppColors.surface,
      error: AppColors.danger,
    ),
    useMaterial3: true,
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.outline),
      ),
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
    ),
    dividerColor: AppColors.outline,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.outline)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.outline)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
    ),
    navigationBarTheme: const NavigationBarThemeData(backgroundColor: AppColors.surface, indicatorColor: Color(0x334DB6AC)),
    navigationRailTheme: const NavigationRailThemeData(backgroundColor: AppColors.surface, indicatorColor: Color(0x334DB6AC)),
  );
}
