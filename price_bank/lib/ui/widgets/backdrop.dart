import 'package:flutter/material.dart';

import '../theme.dart';

/// زمینه‌ی تصویری زیر همه‌ی صفحه‌ها: نور سبز مه‌آلود با دانه‌ی فیلم (الگو: Velaris «Living gradients»، 21st.dev).
/// تصویر آماده است (tool/make_backdrops.py)، نه گرادیان Flutter؛ گرادیان زنده روی بعضی کارت‌های گرافیک سفید می‌شد.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});
  final Widget child;

  static const darkImage = AssetImage('assets/images/backdrop_dark.jpg');
  static const lightImage = AssetImage('assets/images/backdrop_light.jpg');
  static const heroImage = AssetImage('assets/images/hero_dark.jpg');

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(fit: StackFit.expand, children: [
      ColoredBox(color: AppColors.bg),
      Image(image: dark ? darkImage : lightImage, fit: BoxFit.cover, gaplessPlayback: true, excludeFromSemantics: true),
      child,
    ]);
  }
}
