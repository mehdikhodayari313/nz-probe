import 'package:flutter/material.dart';

import '../probe/checks.dart';

const _seed = Color(0xFF0B6B6F); // سبز-آبی نفتی

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Vazirmatn',
    scaffoldBackgroundColor: brightness == Brightness.light ? const Color(0xFFF5F7F7) : scheme.surface,
    visualDensity: VisualDensity.standard,
    dividerColor: scheme.outlineVariant,
  );
}

/// رنگ‌های وضعیت که در حالت روشن و تاریک خوانا هستند.
class StatusColors {
  static Color fg(BuildContext context, CheckStatus s) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (s) {
      CheckStatus.passed => dark ? const Color(0xFF6FD39A) : const Color(0xFF1B7A43),
      CheckStatus.warning => dark ? const Color(0xFFF2C14E) : const Color(0xFF8A5A00),
      CheckStatus.failed => dark ? const Color(0xFFFF8A80) : const Color(0xFFB3261E),
      CheckStatus.needsUser => dark ? const Color(0xFF8AB4F8) : const Color(0xFF1A56A8),
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }

  static Color bg(BuildContext context, CheckStatus s) =>
      fg(context, s).withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.16 : 0.10);

  static IconData icon(CheckStatus s) => switch (s) {
        CheckStatus.passed => Icons.check_circle_rounded,
        CheckStatus.warning => Icons.warning_amber_rounded,
        CheckStatus.failed => Icons.cancel_rounded,
        CheckStatus.needsUser => Icons.visibility_rounded,
        CheckStatus.running => Icons.hourglass_top_rounded,
        CheckStatus.pending => Icons.radio_button_unchecked_rounded,
      };
}

/// تبدیل ارقام لاتین به فارسی برای نمایش اعداد.
String faDigits(Object v) {
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  return v.toString().replaceAllMapped(RegExp(r'[0-9]'), (m) => fa[int.parse(m[0]!)]);
}

/// نمایش عدد صحیح با جداکننده‌ی هزارگان فارسی.
String faNumber(num v) {
  final s = v.round().abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('٬');
    buf.write(s[i]);
  }
  return faDigits('${v < 0 ? '-' : ''}$buf');
}

final _rtlChar = RegExp(r'[؀-ۿ]');

/// جهت هر خط بر اساس اولین حرف: خطوط فارسی راست‌به‌چپ، مسیرها و کدها چپ‌به‌راست.
TextDirection directionOf(String line) {
  for (final ch in line.split('')) {
    if (_rtlChar.hasMatch(ch)) return TextDirection.rtl;
    if (RegExp(r'[A-Za-z]').hasMatch(ch)) return TextDirection.ltr;
  }
  return TextDirection.rtl;
}
