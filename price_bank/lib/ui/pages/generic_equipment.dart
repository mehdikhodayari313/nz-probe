// فهرست اقلام یک رده‌ی غیرپمپ (ظرف، مخزن، پکیج، …) با قیمت تعدیل‌شده و آمار استعلام‌ها.

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/price_bank.dart';
import '../../core/repo/catalog_repo.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import '../widgets/mto_import_dialog.dart';
import 'generic_item_page.dart';

class GenericCategoryView extends StatefulWidget {
  const GenericCategoryView({super.key, required this.code, this.onShowCategories});
  final String code;
  final VoidCallback? onShowCategories;

  @override
  State<GenericCategoryView> createState() => _GenericCategoryViewState();
}

class _GenericCategoryViewState extends State<GenericCategoryView> {
  final _search = TextEditingController();
  String? _project;
  bool _onlyPriced = false;
  bool _onlyQuoted = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _match(GenericRow r) {
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      final hay = [r.item.tag, r.item.name, r.item.projectName, r.item.remarks, ...r.item.values.values.map((v) => v?.toString())]
          .whereType<String>()
          .join(' ')
          .toLowerCase();
      if (!q.split(RegExp(r'\s+')).every(hay.contains)) return false;
    }
    if (_project != null && r.item.projectName != _project) return false;
    if (_onlyPriced && !r.result.eurTarget.isNumber) return false;
    if (_onlyQuoted && r.quoteCount == 0) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final cat = app.pb.catalog.categoryByCode(widget.code)!;
    final all = app.genericRows(cat.id);
    final rows = all.where(_match).toList();
    final unit = app.unit;
    final s = app.settings;
    final specFields = app.pb.catalog
        .fields(cat.id)
        .where((f) => f.groupKey == 'mto_specs')
        .toList(); // به ترتیب پیدایش در MTO
    final keySpecs = specFields.take(2).toList();
    final projects = {for (final r in all) r.item.projectName ?? ''}..remove('');
    final totalIrr = rows
        .where((r) => r.item.include && r.result.irrTarget.isNumber)
        .fold<double>(0, (a, r) => a + r.result.irrTarget.number! * (r.item.quantity ?? 1));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(
          icon: _iconOf(cat.code),
          title: cat.nameFa,
          subtitle: '${cat.nameEn ?? ''} · ${fa(all.length)} قلم · قیمت‌ها تعدیل‌شده به سال ${fa(s.targetYear)} با روش ${s.escalationMethod}',
          actions: [
            if (widget.onShowCategories != null)
              OutlinedButton.icon(
                onPressed: widget.onShowCategories,
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('رده‌ها'),
              ),
            OutlinedButton.icon(
              onPressed: rows.isEmpty ? null : () => _exportCsv(context, cat, rows, keySpecs, unit),
              icon: const Icon(Icons.download_rounded),
              label: const Text('خروجی CSV'),
            ),
            if (app.canEdit(cat.disciplineCode))
              FilledButton.icon(
                onPressed: () => showMtoImportDialog(context),
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('ورود MTO'),
              ),
          ],
        ),
        HelpPanel(
          id: 'generic_equipment',
          title: 'راهنمای این صفحه',
          initiallyOpen: false,
          lines: [
            'اقلام این رده از فایل‌های MTO وارد می‌شوند: شرح، تعداد، قیمت مبنای مشاور، استعلام‌های فروشندگان و قیمت بازنگری قبلی.',
            '«قیمت مبنا» قیمت اصلی هر قلم است (معمولاً قیمت GOING مشاور). در صفحه‌ی هر قلم می‌توانید یکی از استعلام‌ها را مبنا قرار دهید.',
            'قیمت مبنا با روش ${s.escalationMethod} به سال ${fa(s.targetYear)} تعدیل می‌شود. در روش M6 کف قیمت فقط برای پمپ‌هاست؛ برای این رده M6 همان M4 است.',
            'ستون «استعلام‌ها» تعداد استعلام عددی را نشان می‌دهد؛ نشانگر ماوس را نگه دارید تا کمینه و بیشینه‌ی آن‌ها (تعدیل‌شده به یوروی سال هدف) دیده شود.',
          ],
        ),
        SectionCard(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 360,
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'جستجو در تگ، نام، مشخصات، پروژه…',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                value: projects.contains(_project) ? _project : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'پروژه'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('همه')),
                  for (final p in projects.toList()..sort()) DropdownMenuItem<String?>(value: p, child: Text(p)),
                ],
                onChanged: (v) => setState(() => _project = v),
              ),
            ),
            ToggleChip(
              label: 'فقط دارای قیمت تعدیل‌شده',
              selected: _onlyPriced,
              color: Tones.good(context),
              onChanged: (v) => setState(() => _onlyPriced = v),
            ),
            ToggleChip(
              label: 'فقط دارای استعلام',
              selected: _onlyQuoted,
              onChanged: (v) => setState(() => _onlyQuoted = v),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(color: AppColors.petrol.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10)),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: fa(rows.length), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.strong)),
                  TextSpan(text: ' از ${fa(all.length)} قلم · جمع تعدیل‌شده (× تعداد): '),
                  TextSpan(
                      text: money(totalIrr, unit, compact: true),
                      style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.strong)),
                ]),
                style: t.textTheme.bodySmall,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: t.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.colorScheme.outlineVariant),
              boxShadow: softShadow(context),
            ),
            clipBehavior: Clip.antiAlias,
            child: rows.isEmpty
                ? EmptyState(
                    icon: all.isEmpty ? Icons.upload_file_rounded : Icons.filter_alt_off_outlined,
                    title: all.isEmpty ? 'هنوز قلمی در این رده ثبت نشده' : 'قلمی با این فیلترها پیدا نشد',
                    message: all.isEmpty
                        ? 'فایل MTO پروژه (مثلاً MTO پازنان ۲) را وارد کنید؛ اقلام هر شیت به رده‌ی مربوط می‌روند.'
                        : null,
                    action: all.isEmpty
                        ? FilledButton.icon(
                            onPressed: () => showMtoImportDialog(context),
                            icon: const Icon(Icons.upload_file_rounded),
                            label: const Text('ورود MTO'),
                          )
                        : null,
                  )
                : DataGrid<GenericRow>(
                    rows: rows,
                    rowHeight: 46,
                    onTap: (r) => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => GenericItemPage(itemId: r.item.id))),
                    rowColor: (c, r) =>
                        r.item.include ? null : (AppColors.isDark ? const Color(0xFF2E2620) : const Color(0xFFF6EFE6)),
                    columns: _columns(keySpecs, unit),
                  ),
          ),
        ),
      ]),
    );
  }

  List<GridColumn<GenericRow>> _columns(List<FieldDef> keySpecs, MoneyUnit unit) => [
        GridColumn(
          label: 'تگ',
          width: 110,
          ltr: true,
          text: (r) => r.item.tag ?? '',
          sortKey: (r) => r.item.tag ?? '',
          cell: (c, r) => Text(r.item.tag ?? '—',
              textDirection: TextDirection.ltr,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.strong)),
        ),
        GridColumn(label: 'نام / سرویس', width: 200, align: TextAlign.start, ltr: true, text: (r) => r.item.name, sortKey: (r) => r.item.name),
        GridColumn(label: 'پروژه', width: 110, text: (r) => r.item.projectName ?? '', sortKey: (r) => r.item.projectName ?? ''),
        for (final f in keySpecs)
          GridColumn(
            label: f.labelFa,
            width: 140,
            ltr: true,
            tooltip: f.labelEn,
            text: (r) => r.item.values[f.key]?.toString() ?? '',
            sortKey: (r) => r.item.values[f.key]?.toString(),
          ),
        GridColumn(label: 'تعداد', width: 54, numeric: true, text: (r) => r.item.quantity == null ? '' : faSmart(r.item.quantity), sortKey: (r) => r.item.quantity),
        GridColumn(
          label: 'قیمت مبنا',
          width: 150,
          numeric: true,
          text: (r) => r.item.primary?.amount == null ? '' : faNum(r.item.primary!.amount),
          sortKey: (r) => r.result.eurSource.number,
          cell: (c, r) {
            final o = r.item.primary;
            if (o?.amount == null) return Text('—', style: TextStyle(color: Theme.of(c).colorScheme.outline));
            final cur = o!.currency ?? '';
            return Tooltip(
              message: '${o.notes ?? ''}\nسال ${fa(o.costYearValue ?? '؟')}',
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(compactNum(o.amount!),
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
                const SizedBox(width: 4),
                Text(CurrencyBadge.faOf(cur),
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: CurrencyBadge.colorOf(cur))),
                const SizedBox(width: 4),
                Text(fa(o.costYearValue ?? ''), style: TextStyle(fontSize: 10.5, color: Theme.of(c).colorScheme.outline)),
              ]),
            );
          },
        ),
        GridColumn(
          label: 'استعلام‌ها',
          width: 80,
          text: (r) => '${r.quoteCount}',
          sortKey: (r) => r.quoteCount,
          cell: (c, r) => r.quoteCount == 0
              ? Text('—', style: TextStyle(color: Theme.of(c).colorScheme.outline))
              : Tooltip(
                  message: r.quoteMin == null
                      ? 'استعلام‌ها قابل تعدیل نبودند'
                      : 'تعدیل‌شده به یوروی سال هدف:\nکمینه ${faNum(r.quoteMin)} · میانگین ${faNum(r.quoteAvg)} · بیشینه ${faNum(r.quoteMax)}',
                  child: Pill(fa(r.quoteCount), icon: Icons.request_quote_outlined),
                ),
        ),
        GridColumn(
          label: 'یورو\nتعدیل‌شده',
          width: 110,
          numeric: true,
          text: (r) => r.result.eurTarget.isNumber ? faNum(r.result.eurTarget.number) : '',
          sortKey: (r) => r.result.eurTarget.number,
          cell: (c, r) => r.result.eurTarget.isNumber
              ? Text(faNum(r.result.eurTarget.number),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.eur))
              : Text('—', style: TextStyle(color: Theme.of(c).colorScheme.outline)),
        ),
        GridColumn(
          label: '${unitLabel(unit)}\nتعدیل‌شده (واحد)',
          width: 150,
          numeric: true,
          text: (r) => r.result.irrTarget.isNumber ? money(r.result.irrTarget.number, unit, withUnit: false) : '',
          sortKey: (r) => r.result.irrTarget.number,
          cell: (c, r) => r.result.irrTarget.isNumber
              ? Tooltip(
                  message: money(r.result.irrTarget.number, unit, compact: true),
                  child: Text(money(r.result.irrTarget.number, unit, withUnit: false),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.irr)),
                )
              : Text('—', style: TextStyle(color: Theme.of(c).colorScheme.outline)),
        ),
      ];

  Future<void> _exportCsv(
      BuildContext context, Category cat, List<GenericRow> rows, List<FieldDef> keySpecs, MoneyUnit unit) async {
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    final b = StringBuffer('﻿');
    b.writeln([
      'تگ', 'نام', 'پروژه', for (final f in keySpecs) f.labelFa, 'تعداد', 'قیمت مبنا', 'ارز', 'سال',
      'تعداد استعلام', 'یورو تعدیل‌شده', '${unitLabel(unit)} تعدیل‌شده (واحد)',
    ].map(esc).join(','));
    for (final r in rows) {
      final o = r.item.primary;
      b.writeln([
        esc(r.item.tag ?? ''), esc(r.item.name), esc(r.item.projectName ?? ''),
        for (final f in keySpecs) esc(r.item.values[f.key]?.toString() ?? ''),
        r.item.quantity?.toString() ?? '', o?.amount?.toStringAsFixed(2) ?? '', o?.currency ?? '',
        '${o?.costYearValue ?? ''}', '${r.quoteCount}',
        r.result.eurTarget.number?.toStringAsFixed(2) ?? '',
        r.result.irrTarget.number == null
            ? ''
            : (unit == MoneyUnit.toman ? r.result.irrTarget.number! / 10 : r.result.irrTarget.number!).toStringAsFixed(0),
      ].join(','));
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'ذخیره‌ی فهرست ${cat.nameFa}',
      fileName: '${cat.code.toLowerCase()}_${AppScope.read(context).settings.targetYear}.csv',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (path == null) return;
    await File(path).writeAsBytes(utf8.encode(b.toString()));
    if (context.mounted) showSnack(context, 'فایل ذخیره شد: $path');
  }
}

IconData _iconOf(String code) => switch (code) {
      'VESSEL' => Icons.propane_tank_outlined,
      'TANK' => Icons.oil_barrel_outlined,
      'HEX' => Icons.heat_pump_outlined,
      'HEATER' => Icons.local_fire_department_outlined,
      'DESALTER' => Icons.water_drop_outlined,
      'CIP' => Icons.science_outlined,
      'FLARE' => Icons.local_fire_department_rounded,
      'COMPRESSOR' => Icons.air_rounded,
      'AIR_DRYER' => Icons.air_outlined,
      'CRANE' => Icons.construction_rounded,
      'FILTER' => Icons.filter_alt_outlined,
      _ => Icons.precision_manufacturing_outlined,
    };
