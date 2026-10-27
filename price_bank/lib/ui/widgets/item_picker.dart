import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';
import 'command_palette.dart' show paletteNorm;
import 'data_grid.dart';

/// انتخاب یک قلم از جدولی مثل صفحه‌ی جستجو (بند ۱۲): کادر جستجو + جدول با سرستون مشخصات فنی.
/// زدن روی هر ردیف همان قلم را برمی‌گرداند.
Future<T?> showItemPicker<T>(
  BuildContext context, {
  required String title,
  required List<T> rows,
  required List<GridColumn<T>> columns,
  required String Function(T row) searchText,
}) =>
    showDialog<T>(
      context: context,
      builder: (_) => _ItemPicker<T>(title: title, rows: rows, columns: columns, searchText: searchText),
    );

class _ItemPicker<T> extends StatefulWidget {
  const _ItemPicker({required this.title, required this.rows, required this.columns, required this.searchText});
  final String title;
  final List<T> rows;
  final List<GridColumn<T>> columns;
  final String Function(T row) searchText;

  @override
  State<_ItemPicker<T>> createState() => _ItemPickerState<T>();
}

class _ItemPickerState<T> extends State<_ItemPicker<T>> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final words = paletteNorm(_q.text).split(' ').where((w) => w.isNotEmpty).toList();
    final rows = [
      for (final r in widget.rows)
        if (words.isEmpty || words.every(paletteNorm(widget.searchText(r)).contains)) r,
    ];
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: (size.width - 48).clamp(320, 1200).toDouble(),
        height: (size.height - 48).clamp(320, 720).toDouble(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.manage_search_rounded, color: AppColors.petrol),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.title, style: t.textTheme.titleMedium)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('item-picker-search'),
                  controller: _q,
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'جستجو در تگ، نام، پروژه و مشخصات…',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Text('${fa(rows.length)} از ${fa(widget.rows.length)} قلم',
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ]),
            const SizedBox(height: 4),
            Text('روی قلم مورد نظر بزنید؛ مشخصاتش در فرم تخمین وارد می‌شود و می‌توانید هر مقدار را تغییر دهید.',
                style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
            const SizedBox(height: 10),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.colorScheme.outlineVariant),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: rows.isEmpty
                      ? Center(child: Text('قلمی پیدا نشد', style: t.textTheme.bodyMedium))
                      : DataGrid<T>(
                          rows: rows,
                          columns: widget.columns,
                          rowHeight: 42,
                          onTap: (r) => Navigator.pop(context, r),
                        ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
