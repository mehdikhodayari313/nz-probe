// جدول داده: ستون‌های وسط‌چین با خط جداکننده، سرستون رنگی، ردیف‌های راه‌راه با رنگ متمایز،
// مرتب‌سازی، نمایش مجازی (ده‌ها هزار ردیف) و پر کردن خودکار عرض صفحه.

import 'package:flutter/material.dart';

import '../theme.dart';

/// مقدار خالی یا «نامشخص» در جدول‌ها به شکل یک خط تیره‌ی کم‌رنگ نمایش داده می‌شود.
const gridEmpty = '—';

/// متن‌های «نامشخص» منبع (Not stated و …) → خالی.
String cleanCell(String? s) {
  if (s == null) return gridEmpty;
  final v = s.trim();
  if (v.isEmpty) return gridEmpty;
  const empties = {'Not stated', '(Not stated)', 'N/A', 'n/a', 'NA', '-', '(Cost year not stated)', 'None'};
  return empties.contains(v) ? gridEmpty : v;
}

class GridColumn<T> {
  const GridColumn({
    required this.label,
    required this.width,
    required this.text,
    this.sortKey,
    this.numeric = false,
    this.cell,
    this.tooltip,
    this.align = TextAlign.center,
    this.grow = true,
    this.ltr = false,
    this.clean = true,
    this.fitMax,
  });
  final String label;

  /// عرض پایه؛ اگر جا باشد ستون‌های [grow] به تناسب پهن‌تر می‌شوند.
  final double width;
  final String Function(T row) text;

  /// کلید مرتب‌سازی؛ null = این ستون قابل مرتب‌سازی نیست.
  final Comparable<Object>? Function(T row)? sortKey;
  final bool numeric;
  final Widget Function(BuildContext context, T row)? cell;
  final String? tooltip;
  final TextAlign align;
  final bool grow;

  /// متن لاتین (تگ، کد) چپ‌به‌راست نمایش داده شود.
  final bool ltr;

  /// «Not stated» و مشابه آن به «—» تبدیل شود (در تاریخچه خاموش است تا متن اصلی دیده شود).
  final bool clean;

  /// اگر مقدار دارد: عرض ستون به اندازه‌ی بلندترین متن (حداکثر همین مقدار) و متن بلندتر در دو خط.
  final double? fitMax;
}

class DataGrid<T> extends StatefulWidget {
  const DataGrid({
    super.key,
    required this.rows,
    required this.columns,
    this.onTap,
    this.rowHeight = 42,
    this.selected,
    this.rowColor,
  });
  final List<T> rows;
  final List<GridColumn<T>> columns;
  final void Function(T row)? onTap;
  final double rowHeight;
  final bool Function(T row)? selected;
  final Color? Function(BuildContext context, T row)? rowColor;

  @override
  State<DataGrid<T>> createState() => _DataGridState<T>();
}

class _DataGridState<T> extends State<DataGrid<T>> {
  int? _sortCol;
  bool _asc = true;
  final _h = ScrollController();
  final _v = ScrollController();

  @override
  void dispose() {
    _h.dispose();
    _v.dispose();
    super.dispose();
  }

  List<T> get _sorted {
    final c = _sortCol;
    if (c == null || c >= widget.columns.length || widget.columns[c].sortKey == null) return widget.rows;
    final key = widget.columns[c].sortKey!;
    final list = [...widget.rows];
    list.sort((a, b) {
      final ka = key(a), kb = key(b);
      if (ka == null && kb == null) return 0;
      if (ka == null) return 1; // خالی‌ها همیشه آخر
      if (kb == null) return -1;
      final r = ka.compareTo(kb);
      return _asc ? r : -r;
    });
    return list;
  }

  /// عرض نهایی ستون‌ها: اگر جا هست، اضافه به تناسب بین ستون‌های قابل رشد تقسیم می‌شود.
  List<double> _widths(BuildContext context, double available) {
    final base = [for (final c in widget.columns) c.fitMax == null ? c.width : _fitWidth(context, c)];
    final total = base.fold<double>(0, (s, w) => s + w);
    if (total >= available) return base;
    var growable = 0.0;
    for (var i = 0; i < base.length; i++) {
      if (widget.columns[i].grow) growable += base[i];
    }
    if (growable == 0) return base;
    final extra = available - total;
    return [
      for (var i = 0; i < base.length; i++) widget.columns[i].grow ? base[i] + extra * base[i] / growable : base[i]
    ];
  }

  final _fitCache = <String, (List<T>, double)>{};

  /// عرض لازم برای بلندترین متن ستون (اندازه‌گیری با همان سبک خانه‌ها).
  double _fitWidth(BuildContext context, GridColumn<T> c) {
    final hit = _fitCache[c.label];
    if (hit != null && identical(hit.$1, widget.rows)) return hit.$2;
    final style = Theme.of(context).textTheme.bodySmall;
    final scale = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final r in widget.rows) {
      final tp = TextPainter(
        text: TextSpan(text: c.text(r), style: style),
        textDirection: TextDirection.rtl,
        textScaler: scale,
        maxLines: 1,
      )..layout();
      if (tp.width > widest) widest = tp.width;
      tp.dispose();
    }
    final w = (widest + 20).clamp(c.width, c.fitMax!).toDouble();
    _fitCache[c.label] = (widget.rows, w);
    return w;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _sorted;
    return LayoutBuilder(builder: (context, cons) {
      final widths = _widths(context, cons.maxWidth - 1);
      final total = widths.fold<double>(0, (s, w) => s + w);
      final scrollH = total > cons.maxWidth;
      return Scrollbar(
        controller: _h,
        thumbVisibility: scrollH,
        notificationPredicate: (n) => n.depth == 0,
        child: SingleChildScrollView(
          controller: _h,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: scrollH ? total : cons.maxWidth,
            height: cons.maxHeight,
            child: Column(children: [
              _headerRow(context, widths),
              Expanded(
                child: Scrollbar(
                  controller: _v,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _v,
                    padding: EdgeInsets.only(bottom: scrollH ? 12 : 0),
                    itemCount: rows.length,
                    itemExtent: widget.rowHeight,
                    itemBuilder: (context, i) => _row(context, rows[i], i, widths),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }

  Widget _headerRow(BuildContext context, List<double> widths) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.headerBg,
        border: Border(bottom: BorderSide(color: AppColors.petrol, width: 1.6)),
      ),
      child: Row(children: [
        for (var i = 0; i < widget.columns.length; i++) _header(context, i, widths[i], i == widget.columns.length - 1),
      ]),
    );
  }

  Widget _header(BuildContext context, int i, double width, bool last) {
    final t = Theme.of(context);
    final c = widget.columns[i];
    final active = _sortCol == i;
    final fg = AppColors.strong;
    final w = InkWell(
      onTap: c.sortKey == null
          ? null
          : () => setState(() {
                if (_sortCol == i) {
                  _asc = !_asc;
                } else {
                  _sortCol = i;
                  _asc = true;
                }
              }),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          border: last ? null : BorderDirectional(end: BorderSide(color: AppColors.petrol.withValues(alpha: 0.15))),
        ),
        alignment: Alignment.center,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(
            child: Text(c.label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.3, color: fg)),
          ),
          if (active)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 3),
              child: Icon(_asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 14, color: AppColors.amber),
            ),
        ]),
      ),
    );
    return c.tooltip == null ? w : Tooltip(message: c.tooltip!, child: w);
  }

  Widget _row(BuildContext context, T r, int index, List<double> widths) {
    final t = Theme.of(context);
    final sel = widget.selected?.call(r) ?? false;
    final custom = widget.rowColor?.call(context, r);
    final zebra = AppColors.zebra;
    final bg = sel
        ? t.colorScheme.primaryContainer
        : (custom ?? (index.isOdd ? zebra : t.colorScheme.surface));
    final lineC = t.colorScheme.outlineVariant;
    return Material(
      color: bg,
      child: InkWell(
        onTap: widget.onTap == null ? null : () => widget.onTap!(r),
        hoverColor: AppColors.amber.withValues(alpha: 0.12),
        child: Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: lineC.withValues(alpha: 0.7)))),
          child: Row(children: [
            for (var i = 0; i < widget.columns.length; i++)
              Container(
                width: widths[i],
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: i == widget.columns.length - 1
                      ? null
                      : BorderDirectional(end: BorderSide(color: lineC.withValues(alpha: 0.9))),
                ),
                alignment: switch (widget.columns[i].align) {
                  TextAlign.start || TextAlign.right => AlignmentDirectional.centerStart,
                  TextAlign.end || TextAlign.left => AlignmentDirectional.centerEnd,
                  _ => Alignment.center,
                },
                child: _cell(context, widget.columns[i], r),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, GridColumn<T> c, T r) {
    if (c.cell != null) return c.cell!(context, r);
    final t = Theme.of(context);
    final raw = c.text(r);
    final s = c.clean ? cleanCell(raw) : (raw.isEmpty ? gridEmpty : raw);
    final empty = s == gridEmpty;
    return Text(
      s,
      maxLines: c.fitMax == null ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      textAlign: c.align,
      textDirection: c.ltr && !empty ? TextDirection.ltr : null,
      style: t.textTheme.bodySmall?.copyWith(
        color: empty ? t.colorScheme.outline : null,
        fontWeight: c.numeric ? FontWeight.w600 : null,
        fontFeatures: c.numeric ? const [FontFeature.tabularFigures()] : null,
      ),
    );
  }
}
