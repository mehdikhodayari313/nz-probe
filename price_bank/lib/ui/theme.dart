// زبان بصری برنامه: پالت رنگی قابل انتخاب (نفتی، آبی، سبز، …)، حالت روز و شب،
// کارت‌ها با سایه‌ی نرم و رنگ‌های معنایی خوانا.
//
// نکته: از گرادیان (LinearGradient) استفاده نمی‌شود؛ روی بعضی کارت‌های گرافیک ویندوز
// گرادیان سفید نمایش داده می‌شد. همه‌ی سطوح رنگ یکدست دارند.

import 'package:flutter/material.dart';

/// یک پالت رنگی قابل انتخاب در تنظیمات.
class AppPalette {
  const AppPalette(this.code, this.nameFa, this.primary, this.dark, this.navy, this.accent2);
  final String code;
  final String nameFa;
  final Color primary; // رنگ اصلی
  final Color dark; // نسخه‌ی تیره برای متن
  final Color navy; // نوار کناری
  final Color accent2; // رنگ دوم (نمودارها، آواتار)
}

const appPalettes = <AppPalette>[
  // الگو: Velaris «Living gradients» و Northline در 21st.dev (زمردی روی زمینه‌ی تیره، تأکید لیمویی)
  AppPalette('aurora', 'زمردی', Color(0xFF138A5B), Color(0xFF0A4A31), Color(0xFF04100C), Color(0xFF2FBF85)),
  // الگو: تم «Teal Mist» از 21st.dev (فیروزه‌ای روشن، خنثی‌های سرد)
  AppPalette('mist', 'فیروزه‌ای', Color(0xFF0D8077), Color(0xFF0B4F4A), Color(0xFF0E262A), Color(0xFF14B8A6)),
  AppPalette('petrol', 'نفتی', Color(0xFF0F5C6E), Color(0xFF0A3D4A), Color(0xFF0B2B36), Color(0xFF1C8C9E)),
  AppPalette('blue', 'آبی', Color(0xFF1F4E9C), Color(0xFF15356B), Color(0xFF0F1F3D), Color(0xFF3B7DD8)),
  AppPalette('green', 'سبز', Color(0xFF1E6B4E), Color(0xFF134734), Color(0xFF0D2A20), Color(0xFF2E9E72)),
  AppPalette('purple', 'بنفش', Color(0xFF5B3E96), Color(0xFF3D2867), Color(0xFF221838), Color(0xFF8566C9)),
  AppPalette('maroon', 'زرشکی', Color(0xFF8A2E3B), Color(0xFF5E1D27), Color(0xFF331116), Color(0xFFC0505F)),
  AppPalette('graphite', 'خاکستری', Color(0xFF3E5260), Color(0xFF283640), Color(0xFF1B252C), Color(0xFF6E8798)),
];

AppPalette paletteByCode(String? code) => appPalettes.firstWhere((p) => p.code == code, orElse: () => appPalettes.first);

/// رنگ‌های جاری برنامه (با انتخاب پالت و حالت روز/شب عوض می‌شوند).
class AppColors {
  static AppPalette _p = appPalettes.first;
  static bool isDark = false;

  static void apply(String? paletteCode, {required bool dark}) {
    _p = paletteByCode(paletteCode);
    isDark = dark;
  }

  static Color get petrol => _p.primary;
  static Color get petrolDark => _p.dark;
  static Color get navy => _p.navy;
  static Color get teal => _p.accent2;

  static const amber = Color(0xFFE8A33D); // تأکید
  static const eur = Color(0xFF2B59C3);
  static const usd = Color(0xFF1E8A4C);
  static const irr = Color(0xFFB5651D);

  /// تأکید لیمویی (دکمه‌ی اصلی نوار معرفی، نقطه‌ی پایان عنوان؛ الگوی Northline)
  static const lime = Color(0xFFC6F24E);

  /// رنگ‌های وابسته به حالت روز/شب
  static Color get bg => isDark ? const Color(0xFF050B09) : const Color(0xFFEEF4F1);
  static Color get surface => isDark ? const Color(0xFF0B1512) : Colors.white;
  static Color get ink => isDark ? const Color(0xFFE6EFEA) : const Color(0xFF0D221A);
  static Color get line => isDark ? const Color(0xFF1B2823) : const Color(0xFFD7E2DC);

  /// سطح شیشه‌ای روی تصویر زمینه (رنگ یکدست نیمه‌شفاف؛ بدون محوسازی و گرادیان)
  static Color get glass => isDark ? const Color(0xFF0A1310).withValues(alpha: 0.80) : Colors.white.withValues(alpha: 0.84);
  static Color get glassLine => isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFF0D221A).withValues(alpha: 0.08);

  /// نوار کناری و نوار بالا: شیشه‌ای روی زمینه
  static Color get sidebar => isDark ? Colors.black.withValues(alpha: 0.38) : Colors.white.withValues(alpha: 0.62);
  static Color get sidebarActive =>
      isDark ? _p.accent2.withValues(alpha: 0.18) : Color.lerp(_p.accent2, Colors.white, 0.80)!;
  static Color get muted => isDark ? const Color(0xFF7A9596) : const Color(0xFF50686D);
  static Color get amberSoft => isDark ? const Color(0xFF3A2E17) : const Color(0xFFFFF3DE);
  static Color get amberText => isDark ? const Color(0xFFF2C46B) : const Color(0xFF8A5A00);

  /// پس‌زمینه‌ی سرستون جدول‌ها
  static Color get headerBg => isDark ? const Color(0xFF102326) : Color.lerp(_p.primary, Colors.white, 0.88)!;

  /// ردیف‌های یک‌درمیان
  static Color get zebra => isDark ? const Color(0xFF0A1719) : Color.lerp(_p.primary, Colors.white, 0.965)!;

  /// متن پررنگ هم‌رنگ پالت (عنوان جدول، تگ، …)
  static Color get strong => isDark ? Color.lerp(_p.primary, Colors.white, 0.62)! : _p.dark;
}

ThemeData buildTheme(Brightness b) {
  final light = b == Brightness.light;
  final p = AppColors.petrol;
  var scheme = ColorScheme.fromSeed(seedColor: p, brightness: b);
  scheme = light
      ? scheme.copyWith(
          primary: p,
          onPrimary: Colors.white,
          primaryContainer: Color.lerp(p, Colors.white, 0.82),
          onPrimaryContainer: AppColors.petrolDark,
          secondary: AppColors.amber,
          onSecondary: const Color(0xFF3A2500),
          secondaryContainer: const Color(0xFFFFF3DE),
          onSecondaryContainer: const Color(0xFF5A3A00),
          tertiary: AppColors.teal,
          surface: Colors.white,
          onSurface: const Color(0xFF0D221A),
          onSurfaceVariant: const Color(0xFF4E665C),
          surfaceContainerLowest: const Color(0xFFFBFDFC),
          surfaceContainerLow: const Color(0xFFF4F8F6),
          surfaceContainer: const Color(0xFFECF3EF),
          surfaceContainerHigh: const Color(0xFFE4EEE8),
          surfaceContainerHighest: const Color(0xFFDAE6DF),
          outline: const Color(0xFF889E94),
          outlineVariant: const Color(0xFFD7E2DC),
          error: const Color(0xFFCE514D),
        )
      : scheme.copyWith(
          primary: Color.lerp(AppColors.teal, Colors.white, 0.15),
          onPrimary: const Color(0xFF04100C),
          primaryContainer: Color.lerp(p, Colors.black, 0.35),
          onPrimaryContainer: Color.lerp(p, Colors.white, 0.8),
          secondary: AppColors.amber,
          tertiary: AppColors.teal,
          surface: const Color(0xFF0B1512),
          onSurface: const Color(0xFFE6EFEA),
          onSurfaceVariant: const Color(0xFF9FB4AB),
          surfaceContainerLowest: const Color(0xFF07100D),
          surfaceContainerLow: const Color(0xFF0E1A16),
          surfaceContainer: const Color(0xFF12211C),
          surfaceContainerHigh: const Color(0xFF172822),
          surfaceContainerHighest: const Color(0xFF1D3029),
          outline: const Color(0xFF6E8A7F),
          outlineVariant: const Color(0xFF1B2823),
        );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Vazirmatn', brightness: b);
  final tt = base.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  // گوشه‌ی ۸ برای دکمه و ورودی (shadcn/Teal Mist: radius 0.5rem)
  final radius = BorderRadius.circular(8);
  return base.copyWith(
    // زمینه‌ی تصویری زیر همه‌ی صفحه‌ها (AppBackdrop در main.dart)؛ Scaffoldها شفاف‌اند
    scaffoldBackgroundColor: Colors.transparent,
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
      fillColor: light ? Colors.white : scheme.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: radius),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.outlineVariant)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
      hintStyle: TextStyle(color: scheme.outline, fontSize: 13),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        elevation: 0,
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w600, fontSize: 13.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: light ? Colors.white.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.04),
        foregroundColor: scheme.onSurface,
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
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? scheme.primary : scheme.surface),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? scheme.onPrimary : scheme.onSurface),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w600, fontSize: 12.5)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: TextStyle(fontFamily: 'Vazirmatn', fontSize: 12.5, color: scheme.onSurface),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorColor: scheme.primary,
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
      waitDuration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(color: const Color(0xFF0D221A).withValues(alpha: 0.96), borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontSize: 12.5, color: Colors.white, height: 1.7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF0D221A),
      contentTextStyle: const TextStyle(fontFamily: 'Vazirmatn', color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    scrollbarTheme: ScrollbarThemeData(
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(8),
      thumbColor: WidgetStatePropertyAll(scheme.onSurface.withValues(alpha: 0.18)),
    ),
  );
}

/// سایه‌ی نرم کارت‌ها.
List<BoxShadow> softShadow(BuildContext c, {bool hover = false}) => AppColors.isDark
    ? [
        if (hover) BoxShadow(color: AppColors.teal.withValues(alpha: 0.22), blurRadius: 16, spreadRadius: 0),
      ]
    : [
        BoxShadow(color: const Color(0xFF2D2D53).withValues(alpha: hover ? 0.10 : 0.05), blurRadius: hover ? 18 : 10, offset: Offset(0, hover ? 6 : 4)),
        BoxShadow(color: const Color(0xFF2D2D53).withValues(alpha: 0.04), blurRadius: 1, offset: const Offset(0, 1)),
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
