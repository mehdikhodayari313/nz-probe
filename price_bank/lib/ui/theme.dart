import 'package:flutter/material.dart';

const seedColor = Color(0xFF0B5F66); // سبز-آبی نفتی

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: b);
  final light = b == Brightness.light;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Vazirmatn',
    scaffoldBackgroundColor: light ? const Color(0xFFF3F5F6) : scheme.surface,
    dividerColor: scheme.outlineVariant,
    visualDensity: VisualDensity.compact,
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: light ? Colors.white : scheme.surfaceContainerHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 350),
      textStyle: TextStyle(fontFamily: 'Vazirmatn', fontSize: 12.5, color: scheme.onInverseSurface, height: 1.7),
    ),
  );
}

/// رنگ‌های معنایی که در حالت روشن و تاریک خوانا هستند.
class Tones {
  static bool _dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  static Color good(BuildContext c) => _dark(c) ? const Color(0xFF6FD39A) : const Color(0xFF1B7A43);
  static Color warn(BuildContext c) => _dark(c) ? const Color(0xFFF2C14E) : const Color(0xFF8A5A00);
  static Color bad(BuildContext c) => _dark(c) ? const Color(0xFFFF8A80) : const Color(0xFFB3261E);
  static Color info(BuildContext c) => _dark(c) ? const Color(0xFF8AB4F8) : const Color(0xFF1A56A8);
  static Color inferredBg(BuildContext c) => _dark(c) ? const Color(0x33F2C14E) : const Color(0xFFFFF4C2);
  static Color fxBg(BuildContext c) => _dark(c) ? const Color(0x338AB4F8) : const Color(0xFFDDEBF7);
}
