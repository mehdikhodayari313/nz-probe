// نوار سرصفحه‌ی پررنگ (رنگ یکدست، بدون گرادیان): پلاک تگ، نام، مشخصات کلیدی، خوانش‌های قیمت با شمارش
// نرم و زبانه‌ها. یک لحظه‌ی ورود هماهنگ (محو و بالا آمدن پشت‌سرهم)؛ با خاموش بودن جلوه‌ها در ویندوز بی‌حرکت.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme.dart';

/// رنگ نوار: نسخه‌ی تیره‌ی رنگ اصلی پالت
Color heroBandColor(BuildContext context) =>
    AppColors.isDark ? Color.lerp(AppColors.navy, Colors.black, 0.15)! : AppColors.petrolDark;

/// یک خوانش داخل نوار. [number] برای شمارش نرم؛ [format] متن نهایی را می‌سازد.
class HeroReadout {
  const HeroReadout({
    required this.label,
    this.number,
    this.text,
    this.format,
    this.unit,
    this.sub,
    this.primary = false,
    this.tooltip,
  });
  final String label;
  final num? number;
  final String? text;
  final String Function(num v)? format;
  final String? unit;
  final String? sub;
  final bool primary;
  final String? tooltip;
}

/// برچسب مشخصه‌ی کلیدی (دبی، هد، توان، …)
class HeroChip {
  const HeroChip(this.icon, this.text, {this.tooltip});
  final IconData icon;
  final String text;
  final String? tooltip;
}

class HeroBand extends StatelessWidget {
  const HeroBand({
    super.key,
    this.tag,
    this.tagMuted = false,
    required this.title,
    this.subtitle,
    this.icon,
    this.chips = const [],
    this.actions = const [],
    this.readouts = const [],
    this.footer,
    this.tabs,
    this.onBack,
  });
  final String? tag;
  final bool tagMuted;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<HeroChip> chips;
  final List<Widget> actions;
  final List<HeroReadout> readouts;
  final Widget? footer;
  final TabBar? tabs;
  final VoidCallback? onBack;

  static const _fg = Colors.white;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final still = MediaQuery.of(context).disableAnimations;
    final bg = heroBandColor(context);
    final muted = _fg.withValues(alpha: 0.68);

    final head = Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      if (onBack != null) ...[
        IconButton(
          tooltip: 'بازگشت',
          onPressed: onBack,
          icon: const Icon(LucideIcons.arrowRight, color: _fg, size: 22),
        ),
        const SizedBox(width: 4),
      ],
      if (icon != null) ...[
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _fg.withValues(alpha: 0.06),
            border: Border.all(color: _fg.withValues(alpha: 0.35), width: 1.4),
          ),
          child: Icon(icon, color: _fg, size: 21),
        ),
        const SizedBox(width: 14),
      ],
      if (tag != null) ...[
        _DarkTagPlate(tag: tag!, muted: tagMuted),
        const SizedBox(width: 14),
      ],
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.headlineSmall?.copyWith(color: _fg, fontWeight: FontWeight.w700, height: 1.2)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodySmall?.copyWith(color: muted)),
            ),
        ]),
      ),
      if (actions.isNotEmpty)
        Theme(
          data: heroActionsTheme(t),
          child: Wrap(spacing: 8, children: actions),
        ),
    ]);

    final sections = <Widget>[
      head,
      if (chips.isNotEmpty)
        Padding(
          padding: EdgeInsetsDirectional.only(start: onBack != null ? 52 : 0, top: 14),
          child: Wrap(spacing: 8, runSpacing: 8, children: [for (final c in chips) _Chip(c)]),
        ),
      if (readouts.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 18), child: _Readouts(readouts)),
      if (footer != null) Padding(padding: const EdgeInsets.only(top: 12), child: footer!),
    ];

    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: still
                  ? sections
                  : sections
                      .animate(interval: 70.ms)
                      .fadeIn(duration: 360.ms, curve: Curves.easeOutCubic)
                      .slideY(begin: 0.18, end: 0, duration: 420.ms, curve: Curves.easeOutCubic),
            ),
          ),
          if (tabs != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Theme(
                data: t.copyWith(
                  tabBarTheme: t.tabBarTheme.copyWith(
                    labelColor: bg,
                    unselectedLabelColor: _fg.withValues(alpha: 0.75),
                    indicator: ShapeDecoration(
                      color: _fg,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                    overlayColor: WidgetStatePropertyAll(_fg.withValues(alpha: 0.08)),
                  ),
                ),
                // زبانه‌ها در یک ظرف تکه‌ای تیره‌تر؛ قرص سفید زیر زبانه‌ی فعال نرم جابه‌جا می‌شود
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: _fg.withValues(alpha: 0.12)),
                    ),
                    child: tabs!,
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _DarkTagPlate extends StatelessWidget {
  const _DarkTagPlate({required this.tag, this.muted = false});
  final String tag;
  final bool muted;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 1.4),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 5, color: AppColors.amber),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(tag,
                  textDirection: muted ? null : TextDirection.ltr,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: muted ? 0.75 : 1),
                    fontWeight: FontWeight.w700,
                    fontSize: muted ? 15 : 20,
                    letterSpacing: muted ? 0 : 0.8,
                  )),
            ),
          ]),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip(this.c);
  final HeroChip c;

  @override
  Widget build(BuildContext context) {
    final w = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(c.icon, size: 14, color: AppColors.amber),
        const SizedBox(width: 6),
        Text(c.text, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w500)),
      ]),
    );
    return c.tooltip == null ? w : Tooltip(message: c.tooltip!, child: w);
  }
}

class _Readouts extends StatelessWidget {
  const _Readouts(this.items);
  final List<HeroReadout> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final line = Colors.white.withValues(alpha: 0.16);
    Widget cell(HeroReadout r) {
      final w = Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 2, 18, 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(r.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.labelMedium?.copyWith(color: Colors.white.withValues(alpha: 0.65))),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: CountUpText(
                  number: r.number,
                  text: r.text,
                  format: r.format,
                  style: (r.primary ? t.textTheme.headlineMedium : t.textTheme.titleLarge)?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            if (r.unit != null) ...[
              const SizedBox(width: 6),
              Text(r.unit!, style: t.textTheme.labelMedium?.copyWith(color: Colors.white.withValues(alpha: 0.7))),
            ],
          ]),
          if (r.primary)
            Container(
              margin: const EdgeInsets.only(top: 6),
              width: 34,
              height: 3,
              decoration: BoxDecoration(color: AppColors.amber, borderRadius: BorderRadius.circular(2)),
            ),
          if (r.sub != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(r.sub!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.6))),
            ),
        ]),
      );
      return r.tooltip == null ? w : Tooltip(message: r.tooltip!, child: w);
    }

    return LayoutBuilder(builder: (context, cons) {
      final perRow = (cons.maxWidth / 220).floor().clamp(1, items.length);
      final rows = <List<HeroReadout>>[];
      for (var i = 0; i < items.length; i += perRow) {
        rows.add(items.sublist(i, (i + perRow).clamp(0, items.length)));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) Divider(height: 18, color: line),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < perRow; i++) ...[
                if (i > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: VerticalDivider(width: 1, color: line)),
                Expanded(child: i < rows[r].length ? cell(rows[r][i]) : const SizedBox()),
              ],
            ]),
          ),
        ],
      ]);
    });
  }
}

/// عدد با شمارش نرم از صفر تا مقدار نهایی (یک بار، هنگام نمایش)؛ با خاموش بودن جلوه‌ها مستقیم مقدار نهایی.
class CountUpText extends StatelessWidget {
  const CountUpText({super.key, this.number, this.text, this.format, this.style, this.duration = 900});
  final num? number;
  final String? text;
  final String Function(num v)? format;
  final TextStyle? style;
  final int duration;

  @override
  Widget build(BuildContext context) {
    final n = number;
    final f = format;
    if (n == null || f == null) return Text(text ?? '—', style: style);
    if (MediaQuery.of(context).disableAnimations) return Text(f(n), style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: n.toDouble()),
      duration: Duration(milliseconds: duration),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(f(v == n.toDouble() ? n : v), style: style),
    );
  }
}

/// زبانه‌ی افقی جمع‌وجور (آیکن کنار متن) برای نوار
Tab heroTab(IconData icon, String text, {Key? key}) => Tab(
      key: key,
      height: 40,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 17),
        const SizedBox(width: 7),
        Text(text),
      ]),
    );

/// وضعیت کوچک داخل نوار (پروژه، هشدار داده، بایگانی)
class HeroStatus extends StatelessWidget {
  const HeroStatus(this.text, {super.key, this.icon, this.color, this.tooltip});
  final String text;
  final IconData? icon;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    final w = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 5)],
        Text(text, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w500)),
      ]),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

/// دکمه‌ها روی نوار تیره: قاب‌دار سفید، اصلی کهربایی
ThemeData heroActionsTheme(ThemeData t) {
  const fg = Colors.white;
  return t.copyWith(
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        side: BorderSide(color: fg.withValues(alpha: 0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.amber,
        foregroundColor: const Color(0xFF2B1D00),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: fg)),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: fg)),
  );
}
