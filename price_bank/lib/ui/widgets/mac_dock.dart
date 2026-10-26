import 'dart:math' as math;

import 'package:flutter/material.dart';

/// یک گزینه‌ی Dock: نام، آیکن و رنگ کاشی.
class DockItem {
  const DockItem({required this.id, required this.label, required this.icon, required this.color});
  final String id;
  final String label;
  final IconData icon;
  final Color color;
}

/// Dock شناور به سبک مک (الگو: Mac-style Floating Dock، 21st.dev): کاشی‌ها زیر نشانگر بزرگ می‌شوند
/// (منحنی زنگوله‌ای)، همسایه‌ها کنار می‌روند، نام گزینه‌ی نزدیک بالای آن نوشته می‌شود، گزینه‌ی فعال نقطه دارد
/// و با زدن، کاشی یک جهش کوتاه می‌کند. کاشی‌ها رنگ یکدست دارند (بدون گرادیان) و قاب شیشه‌ای نیمه‌شفاف است.
/// با «کاهش حرکت» ویندوز، بزرگ‌نمایی و جهش خاموش‌اند.
class MacDock extends StatefulWidget {
  const MacDock({super.key, required this.items, required this.active, required this.onSelect});
  final List<DockItem> items;
  final String? active;
  final ValueChanged<String> onSelect;

  static const base = 46.0, gap = 10.0, pad = 11.0, maxScale = 1.7, spread = 58.0;

  @override
  State<MacDock> createState() => _MacDockState();
}

class _MacDockState extends State<MacDock> with SingleTickerProviderStateMixin {
  double? _mouseX;
  String? _bouncing;
  late final AnimationController _bounce = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  // جهش: بالا ۲۲، پایین، بالا ۹، پایین (مثل keyframes نسخه‌ی اصلی)
  static final _hop = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -22.0).chain(CurveTween(curve: Curves.easeOut)), weight: 30),
    TweenSequenceItem(tween: Tween(begin: -22.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 25),
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -9.0).chain(CurveTween(curve: Curves.easeOut)), weight: 20),
    TweenSequenceItem(tween: Tween(begin: -9.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 25),
  ]);

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  void _select(String id, bool still) {
    widget.onSelect(id);
    if (still) return;
    setState(() => _bouncing = id);
    _bounce.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _bouncing = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    const b = MacDock.base, g = MacDock.gap, p = MacDock.pad;
    final still = MediaQuery.of(context).disableAnimations;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final n = widget.items.length;
    final rowWidth = n * b + (n - 1) * g;
    final centers = [for (var i = 0; i < n; i++) i * (b + g) + b / 2];
    final scales = [
      for (final c in centers)
        _mouseX == null || still
            ? 1.0
            : 1 + (MacDock.maxScale - 1) * math.exp(-math.pow(_mouseX! - c, 2) / (2 * MacDock.spread * MacDock.spread)),
    ];
    final extra = [for (final s in scales) (s - 1) * b];
    final totalExtra = extra.fold<double>(0, (a, e) => a + e);
    final shifts = [
      for (var i = 0; i < n; i++) extra.take(i).fold<double>(0, (a, e) => a + e) + extra[i] / 2 - totalExtra / 2,
    ];
    var nearest = 0;
    for (var i = 1; i < n; i++) {
      if (scales[i] > scales[nearest]) nearest = i;
    }
    final showLabel = _mouseX != null && scales[nearest] > 1.3;
    const dur = Duration(milliseconds: 90);

    // هندسه چپ‌به‌راست است؛ ترتیب گزینه‌ها برای خواننده‌ی فارسی از راست شروع می‌شود (فهرست برعکس‌شده از بیرون)
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MouseRegion(
        onHover: (e) => setState(() => _mouseX = e.localPosition.dx - 40),
        onExit: (_) => setState(() => _mouseX = null),
        child: Padding(
          // ناحیه‌ی حساس کمی بزرگ‌تر از Dock تا اثر پیش از رسیدن نشانگر شروع شود
          padding: const EdgeInsets.fromLTRB(40, 70, 40, 4),
          child: SizedBox(
            width: rowWidth,
            height: b,
            child: Stack(clipBehavior: Clip.none, children: [
              // قاب شیشه‌ای که با بزرگ شدن کاشی‌ها پهن می‌شود
              Positioned(
                left: -p - totalExtra / 2,
                width: rowWidth + 2 * p + totalExtra,
                top: -p,
                bottom: -p,
                child: Container(
                  decoration: BoxDecoration(
                    color: dark ? Colors.white.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.15 : 0.7)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: dark ? 0.55 : 0.18),
                          blurRadius: 40,
                          offset: const Offset(0, 16)),
                    ],
                  ),
                ),
              ),
              for (var i = 0; i < n; i++)
                AnimatedPositioned(
                  duration: dur,
                  curve: Curves.easeOut,
                  left: i * (b + g) + shifts[i],
                  top: 0,
                  width: b,
                  height: b,
                  child: _Tile(
                    key: ValueKey('dock-${widget.items[i].id}'),
                    item: widget.items[i],
                    scale: scales[i],
                    active: widget.active == widget.items[i].id,
                    label: showLabel && nearest == i,
                    hop: _bouncing == widget.items[i].id ? _bounce.drive(_hop) : null,
                    onTap: () => _select(widget.items[i].id, still),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(
      {super.key,
      required this.item,
      required this.scale,
      required this.active,
      required this.label,
      required this.hop,
      required this.onTap});
  final DockItem item;
  final double scale;
  final bool active;
  final bool label;
  final Animation<double>? hop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const b = MacDock.base;
    final tile = Semantics(
      button: true,
      label: item.label,
      selected: active,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: item.color,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.30), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              // برق نیمه‌ی بالای کاشی (لایه‌ی سفید نیمه‌شفاف، نه گرادیان)
              Positioned(left: 0, right: 0, top: 0, height: b / 2, child: ColoredBox(color: Colors.white.withValues(alpha: 0.16))),
              Center(child: Icon(item.icon, color: Colors.white, size: 24)),
            ]),
          ),
        ),
      ),
    );
    Widget body = AnimatedScale(
      scale: scale,
      alignment: Alignment.bottomCenter,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      child: tile,
    );
    if (hop != null) {
      body = AnimatedBuilder(
        animation: hop!,
        builder: (context, child) => Transform.translate(offset: Offset(0, hop!.value), child: child),
        child: body,
      );
    }
    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(child: body),
      // نام گزینه بالای کاشی نزدیک به نشانگر
      Positioned(
        left: -60,
        right: -60,
        bottom: b * scale + 10,
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: label ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: Text(item.label,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ),
      // نقطه‌ی زیر گزینه‌ی فعال
      Positioned(
        left: b / 2 - 2,
        bottom: -MacDock.pad + 3,
        child: AnimatedOpacity(
          opacity: active ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), shape: BoxShape.circle),
          ),
        ),
      ),
    ]);
  }
}
