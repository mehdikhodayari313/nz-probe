import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';
import 'common.dart';

/// کاشی شاخص با روند: عنوان، عدد اصلی، نشان تغییر (پیکان چرخان) و نمودار خطی کوچک.
/// با نگه داشتن نشانگر روی نمودار، مقدار و نام همان نقطه جای عدد اصلی را می‌گیرد.
/// بدون روند، نوار پیشرفت (`progress`) یا جای خالی هم‌ارتفاع نشان داده می‌شود تا کاشی‌ها هم‌قد بمانند.
class TrendKpiTile extends StatefulWidget {
  const TrendKpiTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.color,
    this.delta,
    this.deltaLabel,
    this.lowerIsBetter = false,
    this.trend = const [],
    this.trendLabels = const [],
    this.formatPoint,
    this.progress,
    this.width = 236,
    this.onTap,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final Color? color;

  /// تغییر به درصد (۴٫۲ یعنی ۴٫۲٪) و مبنای آن («نسبت به سال قبل»).
  final double? delta;
  final String? deltaLabel;

  /// برای هزینه و نرخ ارز: کاهش خبر خوب است.
  final bool lowerIsBetter;

  /// مقادیر از قدیم به جدید و نام هر نقطه (مثلاً سال).
  final List<double> trend;
  final List<String> trendLabels;
  final String Function(double v)? formatPoint;

  /// سهم ۰ تا ۱ برای کاشی‌های بی‌روند (مثلاً اقلام دارای قیمت از کل).
  final double? progress;
  final double width;
  final VoidCallback? onTap;

  @override
  State<TrendKpiTile> createState() => _TrendKpiTileState();
}

enum _Dir { up, down, flat }

class _TrendKpiTileState extends State<TrendKpiTile> {
  int? _hover;

  static const _chartH = 40.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final accent = widget.color ?? cs.primary;
    final d = widget.delta;
    final dir = d == null || d.abs() < 0.05 ? _Dir.flat : (d > 0 ? _Dir.up : _Dir.down);
    final good = dir != _Dir.flat && ((dir == _Dir.up) != widget.lowerIsBetter);
    final tone = d == null || dir == _Dir.flat ? cs.onSurfaceVariant : (good ? Tones.good(context) : Tones.bad(context));
    final pts = widget.trend.where((v) => v.isFinite).toList();
    final h = _hover;
    final headline = h == null ? widget.value : (widget.formatPoint ?? (v) => faNum(v))(pts[h]);
    final caption = h == null
        ? widget.caption
        : (h < widget.trendLabels.length ? widget.trendLabels[h] : '${fa(h + 1)} از ${fa(pts.length)}');

    final body = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ),
          if (widget.icon != null) Icon(widget.icon, size: 18, color: accent),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 30,
          child: Row(children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(headline,
                    style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1, color: cs.onSurface)),
              ),
            ),
            if (d != null && h == null) ...[const SizedBox(width: 8), _DeltaPill(delta: d, dir: dir, tone: tone)],
          ]),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 16,
          child: Text(
            caption ?? (d != null ? widget.deltaLabel ?? '' : ''),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _chartH,
          child: pts.length >= 2
              ? _Spark(
                  points: pts,
                  color: d == null ? accent : tone,
                  card: cs.surface,
                  hover: h,
                  onHover: (i) => setState(() => _hover = i),
                )
              : widget.progress != null
                  ? _Progress(value: widget.progress!.clamp(0, 1).toDouble(), color: accent)
                  : const SizedBox.shrink(),
        ),
      ]),
    );

    return HoverLift(
      radius: 16,
      child: Container(
        width: widget.width,
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassLine),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 2, offset: const Offset(0, 1))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(onTap: widget.onTap, child: body),
        ),
      ),
    );
  }
}

/// نشان تغییر: قرص گرد با زمینه‌ی کم‌رنگ؛ پیکان رو به بالا، با کاهش ۹۰ درجه و بی‌تغییر ۴۵ درجه می‌چرخد.
class _DeltaPill extends StatelessWidget {
  const _DeltaPill({required this.delta, required this.dir, required this.tone});
  final double delta;
  final _Dir dir;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final turn = switch (dir) { _Dir.up => 0.0, _Dir.flat => 0.125, _Dir.down => 0.25 };
    final sign = delta > 0 ? '+' : (delta < 0 ? '−' : '');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedRotation(
            turns: turn,
            duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 500),
            child: Icon(Icons.north_east_rounded, size: 14, color: tone),
          ),
          const SizedBox(width: 2),
          Text('$sign${faNum(delta.abs(), decimals: 1)}٪',
              style: t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: tone)),
        ]),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.value, required this.color});
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.bottomStart,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: value,
          minHeight: 6,
          color: color,
          backgroundColor: color.withValues(alpha: 0.12),
        ),
      ),
    );
  }
}

/// نمودار خطی کوچک: زمان همیشه از چپ (قدیم) به راست (جدید)؛ با ورود، خط کشیده می‌شود.
class _Spark extends StatelessWidget {
  const _Spark({required this.points, required this.color, required this.card, required this.hover, required this.onHover});
  final List<double> points;
  final Color color;
  final Color card;
  final int? hover;
  final ValueChanged<int?> onHover;

  int _index(double dx, double w) {
    final step = (w - 6) / (points.length - 1);
    return ((dx - 3) / step).round().clamp(0, points.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(builder: (context, c) {
        return MouseRegion(
          onHover: (e) => onHover(_index(e.localPosition.dx, c.maxWidth)),
          onExit: (_) => onHover(null),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: still ? 1 : 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, p, _) => CustomPaint(
              size: Size(c.maxWidth, c.maxHeight),
              painter: _SparkPainter(points, color, card, hover, p),
            ),
          ),
        );
      }),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.points, this.color, this.card, this.hover, this.reveal);
  final List<double> points;
  final Color color;
  final Color card;
  final int? hover;
  final double reveal;

  static const _pad = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = points.reduce(math.min), span = points.reduce(math.max) - lo;
    final step = (size.width - _pad * 2) / (points.length - 1);
    Offset at(int i) => Offset(
          _pad + i * step,
          span == 0 ? size.height / 2 : size.height - _pad - (points[i] - lo) / span * (size.height - _pad * 2),
        );
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      final a = at(i - 1), b = at(i);
      final mx = (a.dx + b.dx) / 2;
      line.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    final area = Path.from(line)
      ..lineTo(at(points.length - 1).dx, size.height)
      ..lineTo(at(0).dx, size.height)
      ..close();

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(-_pad, -_pad, (size.width + _pad * 2) * reveal, size.height + _pad * 2));
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    if (reveal < 1) return;
    final i = hover ?? points.length - 1;
    final p = at(i);
    if (hover != null) {
      canvas.drawLine(Offset(p.dx, 0), Offset(p.dx, size.height),
          Paint()
            ..color = color.withValues(alpha: 0.35)
            ..strokeWidth = 1);
    }
    canvas.drawCircle(p, 5, Paint()..color = card);
    canvas.drawCircle(p, 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter o) =>
      o.reveal != reveal || o.hover != hover || o.color != color || o.card != card || !identical(o.points, points);
}
