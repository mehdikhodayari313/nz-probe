// جدول داده با ستون‌های ثابت، مرتب‌سازی و نمایش مجازی (برای ده‌ها هزار ردیف).

import 'dart:math' as math;

import 'package:flutter/material.dart';

class GridColumn<T> {
  const GridColumn({
    required this.label,
    required this.width,
    required this.text,
    this.sortKey,
    this.numeric = false,
    this.cell,
    this.tooltip,
  });
  final String label;
  final double width;
  final String Function(T row) text;

  /// کلید مرتب‌سازی؛ null = این ستون قابل مرتب‌سازی نیست.
  final Comparable<Object>? Function(T row)? sortKey;
  final bool numeric;
  final Widget Function(BuildContext context, T row)? cell;
  final String? tooltip;
}

class DataGrid<T> extends StatefulWidget {
  const DataGrid({
    super.key,
    required this.rows,
    required this.columns,
    this.onTap,
    this.rowHeight = 40,
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
    if (c == null || widget.columns[c].sortKey == null) return widget.rows;
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final rows = _sorted;
    final total = widget.columns.fold<double>(0, (s, c) => s + c.width);
    return LayoutBuilder(builder: (context, cons) {
      final width = math.max(total, cons.maxWidth);
      return Scrollbar(
        controller: _h,
        thumbVisibility: total > cons.maxWidth,
        notificationPredicate: (n) => n.depth == 0,
        child: SingleChildScrollView(
          controller: _h,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            height: cons.maxHeight,
            child: Column(children: [
              // سرستون
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: t.colorScheme.surfaceContainerHigh,
                  border: Border(bottom: BorderSide(color: t.colorScheme.outlineVariant)),
                ),
                child: Row(children: [
                  for (var i = 0; i < widget.columns.length; i++) _header(context, i),
                ]),
              ),
              Expanded(
                child: Scrollbar(
                  controller: _v,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _v,
                    itemCount: rows.length,
                    itemExtent: widget.rowHeight,
                    itemBuilder: (context, i) => _row(context, rows[i], i),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }

  Widget _header(BuildContext context, int i) {
    final t = Theme.of(context);
    final c = widget.columns[i];
    final active = _sortCol == i;
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
        width: c.width,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: AlignmentDirectional.centerStart,
        child: Row(children: [
          Expanded(
            child: Text(c.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.3)),
          ),
          if (active) Icon(_asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 14),
        ]),
      ),
    );
    return c.tooltip == null ? w : Tooltip(message: c.tooltip!, child: w);
  }

  Widget _row(BuildContext context, T r, int index) {
    final t = Theme.of(context);
    final sel = widget.selected?.call(r) ?? false;
    final custom = widget.rowColor?.call(context, r);
    final bg = sel
        ? t.colorScheme.primaryContainer.withValues(alpha: 0.6)
        : (custom ?? (index.isOdd ? t.colorScheme.surfaceContainerLowest : t.colorScheme.surface));
    return Material(
      color: bg,
      child: InkWell(
        onTap: widget.onTap == null ? null : () => widget.onTap!(r),
        child: Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.colorScheme.outlineVariant.withValues(alpha: 0.4)))),
          child: Row(children: [
            for (final c in widget.columns)
              Container(
                width: c.width,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: c.numeric ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                child: c.cell != null
                    ? c.cell!(context, r)
                    : Text(c.text(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall),
              ),
          ]),
        ),
      ),
    );
  }
}
