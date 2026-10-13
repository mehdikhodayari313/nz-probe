// زبان بصری برنامه: پالت نفتی-سرمه‌ای با رنگ تأکید کهربایی، کارت‌های سفید با سایه‌ی نرم،
// و رنگ‌های معنایی خوانا در حالت روشن و تاریک.

import 'package:flutter/material.dart';

/// پالت پایه.
class AppColors {
  static const petrol = Color(0xFF0F5C6E); // رنگ اصلی
  static const petrolDark = Color(0xFF0A3D4A);
  static const navy = Color(0xFF0B2B36); // نوار کناری
  static const teal = Color(0xFF1C8C9E);
  static const amber = Color(0xFFE8A33D); // تأکید
  static const amberSoft = Color(0xFFFFF3DE);
  static const bg = Color(0xFFF1F4F7);
  static const ink = Color(0xFF1D2939);
  static const line = Color(0xFFE2E8EE);

  /// رنگ ارزها (برای تشخیص سریع یورو/دلار/ریال)
  static const eur = Color(0xFF2B59C3);
  static const usd = Color(0xFF1E8A4C);
  static const irr = Color(0xFFB5651D);
}

const seedColor = AppColors.petrol;

ThemeData buildTheme(Brightness b) {
  final light = b == Brightness.light;
  var scheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: b);
  if (light) {
    scheme = scheme.copyWith(
      primary: AppColors.petrol,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFD5EEF2),
      onPrimaryContainer: AppColors.petrolDark,
      secondary: AppColors.amber,
      onSecondary: const Color(0xFF3A2500),
      secondaryContainer: AppColors.amberSoft,
      onSecondaryContainer: const Color(0xFF5A3A00),
      tertiary: AppColors.teal,
      surface: Colors.white,
      onSurface: AppColors.ink,
      surfaceContainerLowest: const Color(0xFFFBFCFD),
      surfaceContainerLow: const Color(0xFFF5F8FA),
      surfaceContainer: const Color(0xFFEFF3F6),
      surfaceContainerHigh: const Color(0xFFE8EEF2),
      surfaceContainerHighest: const Color(0xFFE0E7EC),
      outlineVariant: AppColors.line,
    );
  }
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Vazirmatn', brightness: b);
  final tt = base.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  final radius = BorderRadius.circular(10);
  return base.copyWith(
    scaffoldBackgroundColor: light ? AppColors.bg : scheme.surface,
    dividerColor: scheme.outlineVariant,
    visualDensity: VisualDensity.compact,
    textTheme: tt.copyWith(
      titleLarge: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0),
      titleMedium: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      labelLarge: tt.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: light ? const Color(0xFFF8FAFB) : scheme.surfaceContainerHigh,
      border: OutlineInputBorder(borderRadius: radius),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.outlineVariant)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.primary, width: 1.6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
      hintStyle: TextStyle(color: scheme.outline, fontSize: 13),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: radius),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w700, fontSize: 13.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: radius),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w600, fontSize: 13.5),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius)),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? scheme.primary : (light ? Colors.white : null)),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? scheme.onPrimary : scheme.onSurface),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w600, fontSize: 12.5)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: const TextStyle(fontFamily: 'Vazirmatn', fontSize: 12.5),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorColor: AppColors.amber,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: scheme.outlineVariant,
      labelStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w700, fontSize: 13.5),
      unselectedLabelStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w500, fontSize: 13.5),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titleTextStyle: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontFamily: 'Vazirmatn'),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 350),
      decoration: BoxDecoration(color: AppColors.navy.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontSize: 12.5, color: Colors.white, height: 1.7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.navy,
      contentTextStyle: const TextStyle(fontFamily: 'Vazirmatn', color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    scrollbarTheme: ScrollbarThemeData(
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(8),
      thumbColor: WidgetStatePropertyAll(scheme.primary.withValues(alpha: 0.35)),
    ),
  );
}

/// سایه‌ی نرم کارت‌ها.
List<BoxShadow> softShadow(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? const []
    : const [
        BoxShadow(color: Color(0x0F101828), blurRadius: 10, offset: Offset(0, 3)),
        BoxShadow(color: Color(0x08101828), blurRadius: 2, offset: Offset(0, 1)),
      ];

/// رنگ‌های معنایی که در حالت روشن و تاریک خوانا هستند.
class Tones {
  static bool _dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  static Color good(BuildContext c) => _dark(c) ? const Color(0xFF6FD39A) : const Color(0xFF1B7A43);
  static Color warn(BuildContext c) => _dark(c) ? const Color(0xFFF2C14E) : const Color(0xFF9A6200);
  static Color bad(BuildContext c) => _dark(c) ? const Color(0xFFFF8A80) : const Color(0xFFB3261E);
  static Color info(BuildContext c) => _dark(c) ? const Color(0xFF8AB4F8) : const Color(0xFF1A56A8);
  static Color muted(BuildContext c) => Theme.of(c).colorScheme.outline;
  static Color inferredBg(BuildContext c) => _dark(c) ? const Color(0x33F2C14E) : const Color(0xFFFFF4C2);
  static Color fxBg(BuildContext c) => _dark(c) ? const Color(0x338AB4F8) : const Color(0xFFDDEBF7);
}
