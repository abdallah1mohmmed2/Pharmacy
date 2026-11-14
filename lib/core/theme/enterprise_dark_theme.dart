import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

abstract final class AppColors {
  static const bg = Color(0xFF121212);
  static const surface = Color(0xFF1E1E1E);
  static const surfaceHigh = Color(0xFF262626);
  static const outline = Color(0xFF2C2C2C);
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
      '${_format.format(MoneyRound.two(value))} $currency';
}

abstract final class MoneyRound {
  static double two(num value) => (value * 100).roundToDouble() / 100;
  static double whole(num value) => value.roundToDouble();
}

abstract final class EnterpriseDarkTheme {
  static ThemeData get data {
    const scheme = ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.info,
      surface: AppColors.surface,
      error: AppColors.danger,
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.outline),
    );
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
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
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: border.copyWith(
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: border.copyWith(
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        constraints: const BoxConstraints(minHeight: 48),
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIconColor: Colors.white60,
        suffixIconColor: Colors.white60,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: const BorderSide(color: AppColors.outline),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        modalBackgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: Color(0x334DB6AC),
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: Color(0x334DB6AC),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceHigh,
        selectedColor: const Color(0x334DB6AC),
        side: const BorderSide(color: AppColors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        iconColor: AppColors.primary,
        collapsedIconColor: Colors.white60,
        tilePadding: EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: EdgeInsets.fromLTRB(12, 0, 12, 12),
      ),
    );
  }
}
