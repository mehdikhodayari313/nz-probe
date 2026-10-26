import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';
import 'hero_band.dart';

/// سرصفحه‌ی هر صفحه: نشان رنگی، عنوان، زیرعنوان و دکمه‌ها.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.icon, this.actions = const []});
  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    const fg = Colors.white;
    // نوار سرصفحه‌ی تیره (هم‌خانواده‌ی سرصفحه‌ی تجهیز)، رنگ یکدست
    final band = Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(color: heroBandColor(context), borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        if (icon != null) ...[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fg.withValues(alpha: 0.06),
              border: Border.all(color: fg.withValues(alpha: 0.35), width: 1.4),
            ),
            child: Icon(icon, color: fg, size: 21),
          ),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: fg, height: 1.2)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(subtitle!, style: t.textTheme.bodySmall?.copyWith(color: fg.withValues(alpha: 0.68))),
              ),
          ]),
        ),
        if (actions.isNotEmpty)
          Flexible(
            child: Theme(
              data: heroActionsTheme(t),
              child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: actions),
            ),
          ),
      ]),
    );
    return FadeIn(child: band);
  }
}

/// قاب بخش‌ها: کارت سفید با سایه‌ی نرم و سرصفحه‌ی آیکن‌دار.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.icon,
    this.accent,
  });
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final IconData? icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = accent ?? t.colorScheme.primary;
    // Material (نه Container رنگی) تا ListTile و افکت‌های لمس درون کارت درست نمایش داده شوند.
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), boxShadow: softShadow(context)),
      child: Material(
        color: t.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: t.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(children: [
                  if (icon != null) ...[
                    // نشان بخش به شکل دایره‌ی ابزار دقیق نقشه‌های P&ID
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.06),
                        shape: BoxShape.circle,
                        border: Border.all(color: c.withValues(alpha: 0.45), width: 1.2),
                      ),
                      child: Icon(icon, size: 16, color: c),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title!,
                          style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 14.5)),
                      if (subtitle != null)
                        Text(subtitle!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                    ]),
                  ),
                  if (trailing != null)
                    Flexible(child: Align(alignment: AlignmentDirectional.centerEnd, child: trailing!)),
                ]),
              ),
              Divider(height: 1, thickness: 1, color: t.colorScheme.outlineVariant.withValues(alpha: 0.7)),
            ],
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// پنل راهنما با قابلیت جمع شدن (وضعیت هر پنل در طول اجرا حفظ می‌شود).
class HelpPanel extends StatefulWidget {
  const HelpPanel({super.key, required this.id, required this.title, required this.lines, this.initiallyOpen = true});
  final String id;
  final String title;
  final List<String> lines;
  final bool initiallyOpen;

  @override
  State<HelpPanel> createState() => _HelpPanelState();
}

class _HelpPanelState extends State<HelpPanel> {
  static final Map<String, bool> _open = {};

  bool get open => _open[widget.id] ?? widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = Tones.info(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _open[widget.id] = !open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Icon(Icons.lightbulb_outline_rounded, size: 20, color: c),
              const SizedBox(width: 8),
              Expanded(
                child:
                    Text(widget.title, style: t.textTheme.labelLarge?.copyWith(color: c, fontWeight: FontWeight.w700)),
              ),
              Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: c),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final l in widget.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 8),
                      child:
                          Container(width: 5, height: 5, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                    ),
                    Expanded(child: Text(l, style: t.textTheme.bodySmall?.copyWith(height: 1.9))),
                  ]),
                ),
            ]),
          ),
      ]),
    );
  }
}

/// کاشی شاخص کلیدی: نوار رنگی کناری، آیکن در دایره‌ی رنگی، عدد درشت.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.icon,
    this.color,
    this.width = 220,
    this.onTap,
  });
  final String label;
  final String value;
  final String? sub;
  final IconData? icon;
  final Color? color;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = color ?? t.colorScheme.primary;
    return HoverLift(
      radius: 14,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: t.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: Stack(children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 14, 12),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(label,
                          style: t.textTheme.labelMedium
                              ?.copyWith(color: t.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2),
                    ),
                    if (icon != null)
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: c.withValues(alpha: 0.06),
                          shape: BoxShape.circle,
                          border: Border.all(color: c.withValues(alpha: 0.45), width: 1.2),
                        ),
                        child: Icon(icon, size: 15, color: c),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(value,
                        style: t.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700, color: c, fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                  if (sub != null)
                    Text(sub!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// بلند شدن نرم کارت زیر نشانگر ماوس (سایه‌ی عمیق‌تر و جابه‌جایی چند پیکسلی).
class HoverLift extends StatefulWidget {
  const HoverLift({super.key, required this.child, this.radius = 16, this.lift = 3});
  final Widget child;
  final double radius;
  final double lift;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _h = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _h ? -widget.lift : 0, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: softShadow(context, hover: _h),
          ),
          child: widget.child,
        ),
      );
}

/// ظاهر شدن نرم (محو + کمی بالا آمدن) هنگام ورود به صفحه.
class FadeIn extends StatelessWidget {
  const FadeIn({super.key, required this.child, this.delay = 0});
  final Widget child;
  final int delay; // ترتیب (۰، ۱، ۲، …)

  @override
  Widget build(BuildContext context) => MediaQuery.of(context).disableAnimations
      ? child
      : TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 320 + delay * 60),
          curve: Curves.easeOutCubic,
          builder: (context, v, child) => Opacity(
            opacity: v,
            child: Transform.translate(offset: Offset(0, (1 - v) * 12), child: child),
          ),
          child: child,
        );
}

/// نشان ارز (یورو/دلار/ریال/تومان) تا هیچ عددی بدون واحد خوانده نشود.
class CurrencyBadge extends StatelessWidget {
  const CurrencyBadge(this.code, {super.key, this.label});
  final String code; // EUR, USD, IRR, IRT
  final String? label;

  static Color colorOf(String code) => switch (code) {
        'EUR' => AppColors.eur,
        'USD' => AppColors.usd,
        _ => AppColors.irr,
      };

  static String faOf(String code) => switch (code) {
        'EUR' => 'یورو',
        'USD' => 'دلار',
        'IRT' => 'تومان',
        _ => 'ریال',
      };

  @override
  Widget build(BuildContext context) {
    final c = colorOf(code);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Text(label ?? faOf(code), style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }
}

/// نوار بازه: کمینه تا بیشینه با نشانگر مقدار مورد انتظار.
/// با CustomPaint ساخته شده (نه LayoutBuilder) تا داخل IntrinsicHeight هم کار کند.
class RangeBar extends StatelessWidget {
  const RangeBar({super.key, required this.low, required this.high, this.mid, required this.color, this.height = 10});
  final double low;
  final double high;
  final double? mid;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final span = high - low;
    final pos = (mid == null || span <= 0) ? null : ((mid! - low) / span).clamp(0.0, 1.0);
    return SizedBox(
      height: height + 8,
      width: double.infinity,
      child: CustomPaint(
        painter: _RangePainter(pos, color, height, Directionality.of(context) == TextDirection.rtl),
      ),
    );
  }
}

class _RangePainter extends CustomPainter {
  _RangePainter(this.pos, this.color, this.barH, this.rtl);
  final double? pos;
  final Color color;
  final double barH;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final rect = Rect.fromLTWH(0, cy - barH / 2, size.width, barH);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barH)), Paint()..color = color.withValues(alpha: 0.22));
    if (pos != null) {
      // بخش کمینه تا مقدار مورد انتظار پررنگ‌تر
      final xm = rtl ? size.width * (1 - pos!) : size.width * pos!;
      final filled =
          rtl ? Rect.fromLTRB(xm, rect.top, size.width, rect.bottom) : Rect.fromLTRB(0, rect.top, xm, rect.bottom);
      canvas.drawRRect(
          RRect.fromRectAndRadius(filled, Radius.circular(barH)), Paint()..color = color.withValues(alpha: 0.6));
    }
    if (pos != null) {
      final r = size.height / 2 - 1;
      final x = rtl ? size.width - r - (size.width - 2 * r) * pos! : r + (size.width - 2 * r) * pos!;
      canvas.drawCircle(Offset(x, cy), r, Paint()..color = Colors.white);
      canvas.drawCircle(
          Offset(x, cy),
          r - 1.5,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }
  }

  @override
  bool shouldRepaint(_RangePainter old) => old.pos != pos || old.color != color || old.rtl != rtl;
}

/// دکمه‌ی روشن/خاموش خوانا (جایگزین FilterChip که روی بعضی سیستم‌ها متنش کم‌رنگ دیده می‌شد).
class ToggleChip extends StatelessWidget {
  const ToggleChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onChanged,
    this.icon,
    this.color,
  });
  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = color ?? AppColors.petrol;
    final fg = selected ? Colors.white : t.colorScheme.onSurface;
    return Material(
      color: selected ? c : t.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? c : t.colorScheme.outline.withValues(alpha: 0.6), width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(!selected),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              icon ?? (selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded),
              size: 19,
              color: selected ? Colors.white : c,
            ),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

/// برچسب کوچک رنگی.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.icon, this.tooltip});
  final String text;
  final Color? color;
  final IconData? icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    final w = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 11.5, color: c, fontWeight: FontWeight.w600)),
      ]),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

/// حالت خالی با توضیح.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 52, color: t.colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: t.textTheme.titleMedium),
          if (message != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(message!,
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.8)),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

void showSnack(BuildContext context, String msg, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    width: 560,
    backgroundColor: error ? Tones.bad(context) : null,
  ));
}

/// پرسیدن دلیل تغییر (اختیاری). null = انصراف.
Future<String?> askReason(BuildContext context, {String title = 'ثبت تغییرات', String? summary}) async {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (summary != null) ...[Text(summary), const SizedBox(height: 12)],
          TextField(
            controller: ctl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'دلیل یا مرجع تغییر (اختیاری)',
              hintText: 'مثلاً: اصلاح طبق دیتاشیت، نامه‌ی شماره‌ی …',
            ),
            onSubmitted: (_) => Navigator.pop(ctx, ctl.text.trim()),
          ),
          const SizedBox(height: 8),
          Text('این توضیح همراه تغییر در تاریخچه ذخیره می‌شود.',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('ثبت')),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String message, {String ok = 'تأیید'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: 440, child: Text(message, style: const TextStyle(height: 1.8))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

/// متن با جهت خودکار (خطوط لاتین چپ‌به‌راست).
TextDirection dirOf(String s) {
  for (final ch in s.runes) {
    if (ch >= 0x0600 && ch <= 0x06FF) return TextDirection.rtl;
    if ((ch >= 0x41 && ch <= 0x5A) || (ch >= 0x61 && ch <= 0x7A)) return TextDirection.ltr;
  }
  return TextDirection.rtl;
}

/// تعداد اقلام کنار گزینه‌ی دراپ‌داون (همان شکل فیلترهای پمپ).
class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key});
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: count == 0 ? null : AppColors.petrol.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(fa(count),
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: count == 0 ? t.colorScheme.outline : AppColors.petrolDark)),
    );
  }
}

/// متن گزینه‌ی دراپ‌داون + تعداد اقلام آن (دراپ‌داون باید isExpanded باشد).
/// گزینه‌ی «نامشخص» فیلترها: اقلامی که آن مشخصه را ندارند یا منبع «Not stated» گفته (جمع گزینه‌ها = «همه»)
const kEmptyOption = '\u0000empty';
const kEmptyOptionLabel = 'نامشخص';

/// مقدار نامشخص: خالی (در منبع نبود یا ناقص وارد شده) یا «Not stated» منبع — در فیلترها یک گزینه‌ی «نامشخص»
bool isUnknownValue(String v) {
  final t = v.trim();
  return t.isEmpty || t == 'Not stated' || t == '(Not stated)' || t == 'نامشخص' || t == 'Unknown';
}

/// شمارش گزینه‌های یک فیلتر: (تعداد هر مقدار، تعداد نامشخص)؛ جمع همه = تعداد ردیف‌ها
({Map<String, int> counts, int empty}) countValues<T>(Iterable<T> rows, String Function(T) valueOf) {
  final counts = <String, int>{};
  var empty = 0;
  for (final r in rows) {
    final v = valueOf(r);
    if (isUnknownValue(v)) {
      empty++;
    } else {
      counts[v] = (counts[v] ?? 0) + 1;
    }
  }
  return (counts: counts, empty: empty);
}

class CountedLabel extends StatelessWidget {
  const CountedLabel(this.text, this.count, {super.key, this.dimZero = true});
  final String text;
  final int? count;
  final bool dimZero;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(children: [
      Expanded(child: DdText(text, style: TextStyle(color: dimZero && count == 0 ? t.colorScheme.outline : null))),
      if (count != null) ...[const SizedBox(width: 6), CountBadge(count!)],
    ]);
  }
}

/// متن گزینه‌ی دراپ‌داون:
/// در فهرستِ باز، کامل و در صورت نیاز چندخطی؛ در کادرِ مقدار انتخاب‌شده، یک‌خطی و متن کامل با نگه داشتن ماوس.
class DdText extends StatelessWidget {
  const DdText(this.text, {super.key, this.style, this.overflow, this.textAlign, this.textDirection});
  final String text;
  final TextStyle? style;
  final TextOverflow? overflow; // برای سازگاری با Text؛ نادیده گرفته می‌شود
  final TextAlign? textAlign;
  final TextDirection? textDirection;

  /// آیا این ویجت داخل کادر دراپ‌داون (نه فهرست باز آن) است؟
  static bool inField(BuildContext context) =>
      context.findAncestorWidgetOfExactType<InputDecorator>() != null ||
      context.findAncestorWidgetOfExactType<IndexedStack>() != null;

  @override
  Widget build(BuildContext context) {
    if (inField(context)) {
      return Tooltip(
        message: text,
        waitDuration: const Duration(milliseconds: 350),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: style,
            textAlign: textAlign,
            textDirection: textDirection),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Text(text, softWrap: true, style: style, textAlign: textAlign, textDirection: textDirection),
    );
  }
}

/// دکمه‌ی انتخاب رده با تعداد اقلام.
class CategoryChip extends StatelessWidget {
  const CategoryChip(
      {super.key, required this.label, required this.count, required this.selected, required this.onTap});
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Material(
      color: selected ? AppColors.petrol : t.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? AppColors.petrol : t.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (selected)
              const Padding(
                padding: EdgeInsetsDirectional.only(end: 6),
                child: Icon(Icons.check_rounded, size: 16, color: Colors.white),
              ),
            Text(label,
                style:
                    TextStyle(fontWeight: FontWeight.w700, color: selected ? Colors.white : t.colorScheme.onSurface)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.22) : AppColors.petrol.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(fa(count),
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : AppColors.petrolDark)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// یک خوانش در [ReadoutStrip].
class Readout {
  const Readout({required this.label, required this.value, this.sub, this.color, this.unit, this.primary = false});
  final String label;
  final String value;
  final String? unit;
  final String? sub;
  final Color? color;

  /// خوانش اصلی (قیمت مبنا): خط کهربایی «جریان» زیر آن
  final bool primary;
}

/// نوار خوانش‌ها مثل صفحه‌ی نمایشگر تابلو کنترل: یک قاب، خوانش‌ها با خط مویی از هم جدا،
/// خوانش اصلی با خط کهربایی. در پنجره‌ی باریک خوانش‌ها به سطر بعد می‌روند.
class ReadoutStrip extends StatelessWidget {
  const ReadoutStrip({super.key, required this.items, this.footer});
  final List<Readout> items;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final line = t.colorScheme.outlineVariant;
    Widget cell(Readout r) {
      final c = r.color ?? t.colorScheme.onSurface;
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(r.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.labelMedium
                  ?.copyWith(color: t.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(r.value,
                    style: t.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: c,
                        height: 1.15,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ),
            if (r.unit != null) ...[
              const SizedBox(width: 6),
              Text(r.unit!, style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ],
          ]),
          if (r.primary)
            Container(
              margin: const EdgeInsets.only(top: 6),
              width: 36,
              height: 3,
              decoration: BoxDecoration(color: AppColors.amber, borderRadius: BorderRadius.circular(2)),
            ),
          if (r.sub != null)
            Padding(
              padding: EdgeInsets.only(top: r.primary ? 5 : 4),
              child: Text(r.sub!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ),
        ]),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: line),
        boxShadow: softShadow(context),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        LayoutBuilder(builder: (context, cons) {
          final perRow = (cons.maxWidth / 230).floor().clamp(1, items.length);
          final rows = <List<Readout>>[];
          for (var i = 0; i < items.length; i += perRow) {
            rows.add(items.sublist(i, (i + perRow).clamp(0, items.length)));
          }
          return Column(children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) Divider(height: 1, color: line),
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var i = 0; i < perRow; i++) ...[
                    if (i > 0) VerticalDivider(width: 1, thickness: 1, color: line),
                    Expanded(child: i < rows[r].length ? cell(rows[r][i]) : const SizedBox()),
                  ],
                ]),
              ),
            ],
          ]);
        }),
        if (footer != null) ...[
          Divider(height: 1, color: line),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: footer!),
        ],
      ]),
    );
  }
}

/// پلاک تگ تجهیز (مثل برچسب تگ روی نقشه): قاب با خط کهربایی در ابتدای آن.
class TagPlate extends StatelessWidget {
  const TagPlate({super.key, required this.tag, this.muted = false});
  final String tag;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.strong.withValues(alpha: 0.55), width: 1.4),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 4, color: AppColors.amber),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Text(tag,
                textDirection: muted ? null : TextDirection.ltr,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: muted ? 14 : 17,
                  letterSpacing: muted ? 0 : 0.6,
                  color: muted ? t.colorScheme.onSurfaceVariant : AppColors.strong,
                )),
          ),
        ]),
      ),
    );
  }
}

/// عنوان صفحه‌ی تجهیز: پلاک تگ، نام و رده
class ItemTitle extends StatelessWidget {
  const ItemTitle({required this.tag, required this.name, required this.sub, this.muted = false});
  final String tag;
  final String name;
  final String sub;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(children: [
      TagPlate(tag: tag, muted: muted),
      const SizedBox(width: 14),
      Flexible(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(name,
              overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text(sub,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ]),
      ),
    ]);
  }
}
