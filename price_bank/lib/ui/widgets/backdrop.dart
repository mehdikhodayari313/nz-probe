import 'package:flutter/material.dart';

/// زمینه‌ی نقطه‌ای ملایم پشت محتوای صفحه‌ها (الگو: Dot Grid، 21st.dev).
/// فقط رنگ یکدست و نقطه؛ بدون گرادیان و بدون پویانمایی.
class DotGridBackdrop extends StatelessWidget {
  const DotGridBackdrop({super.key, required this.child, this.spacing = 22});
  final Widget child;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    // روشنایی از Theme خوانده می‌شود تا با تغییر روز/شب دوباره ساخته شود
    final dark = Theme.of(context).brightness == Brightness.dark;
    final dot = dark ? const Color(0xFF1F3133) : const Color(0xFFC9D6D8);
    return ColoredBox(
      color: dark ? const Color(0xFF071112) : const Color(0xFFF4F8F9),
      child: CustomPaint(
        painter: _DotPainter(dot, spacing),
        isComplex: true,
        child: RepaintBoundary(child: child),
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.color, this.spacing);
  final Color color;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1, p);
      }
    }
  }

  @override
  bool shouldRepaint(_DotPainter o) => o.color != color || o.spacing != spacing;
}
