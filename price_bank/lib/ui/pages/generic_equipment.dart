// فهرست اقلام یک رده‌ی غیرپمپ (ظرف، مخزن، پکیج، …) با قیمت تعدیل‌شده و آمار استعلام‌ها.

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/generic_estimator.dart';
import '../../core/calc/methods.dart';
import '../../core/catalog/profiles.dart';
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
  bool _showFilters = true;
  final Map<String, String?> _enumF = {};
  final Map<String, (TextEditingController, TextEditingController)> _rangeF = {};

  EquipmentProfile? get _profile => equipmentProfiles[widget.code];

  (TextEditingController, TextEditingController) _range(String key) =>
      _rangeF[key] ??= (TextEditingController(), TextEditingController());

  @override
  void dispose() {
    _search.dispose();
    for (final r in _rangeF.values) {
      r.$1.dispose();
      r.$2.dispose();
    }
    super.dispose();
  }

  static double? _numOf(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  void _clear() => setState(() {
        _search.clear();
        _project = null;
        _onlyPriced = false;
        _onlyQuoted = false;
        _enumF.clear();
        for (final r in _rangeF.values) {
          r.$1.clear();
          r.$2.clear();
        }
      });

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
    for (final e in _enumF.entries) {
      if (e.value == null) continue;
      if (r.item.values[e.key]?.toString() != e.value) return false;
    }
    for (final e in _rangeF.entries) {
      final lo = parseUserNumber(e.value.$1.text), hi = parseUserNumber(e.value.$2.text);
      if (lo == null && hi == null) continue;
      final v = e.key == '_size' ? r.size : _numOf(r.item.values[e.key]);
      if (v == null) return false;
      if (lo != null && v < lo) return false;
      if (hi != null && v > hi) return false;
    }
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
    final fieldsByKey = {for (final f in app.pb.catalog.fields(cat.id)) f.key: f};
    final keySpecs = _profile != null
        ? [for (final k in _profile!.gridKeys) if (fieldsByKey[k] != null) fieldsByKey[k]!]
        : specFields.take(2).toList();
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
          subtitle: '${cat.nameEn ?? ''} · ${fa(all.length)} قلم · قیمت‌ها تعدیل‌شده به سال ${fa(s.targetYear)} با روش ${s.catMethod(cat.code) ?? s.escalationMethod}'
              '${s.catMethod(cat.code) == null ? '' : ' (اختصاصی این رده)'}',
          actions: [
            if (widget.onShowCategories != null)
              OutlinedButton.icon(
                onPressed: widget.onShowCategories,
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('رده‌ها'),
              ),
            if (_profile != null)
              OutlinedButton.icon(
                onPressed: () => showDialog<void>(context: context, builder: (_) => CategorySettingsDialog(code: cat.code)),
                icon: const Icon(Icons.settings_suggest_outlined),
                label: const Text('تنظیمات رده'),
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'جستجو در تگ، نام، مشخصات، پروژه…',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(color: AppColors.petrol.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10)),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: fa(rows.length), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.strong)),
                    TextSpan(text: ' از ${fa(all.length)} قلم · جمع (× تعداد): '),
                    TextSpan(
                        text: money(totalIrr, unit, compact: true),
                        style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.strong)),
                  ]),
                  style: t.textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 10),
              ToggleChip(
                label: _showFilters ? 'بستن فیلترها' : 'فیلترها',
                icon: Icons.tune_rounded,
                selected: _showFilters,
                onChanged: (v) => setState(() => _showFilters = v),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                onPressed: _clear,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Tones.bad(context),
                  side: BorderSide(color: Tones.bad(context).withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                icon: const Icon(Icons.filter_alt_off_rounded, size: 19),
                label: const Text('پاک کردن فیلترها'),
              ),
            ]),
            if (_showFilters) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String?>(
                    value: projects.contains(_project) ? _project : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'پروژه'),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: CountedLabel('همه', all.length)),
                      for (final p in projects.toList()..sort())
                        DropdownMenuItem<String?>(
                            value: p, child: CountedLabel(p, all.where((r) => r.item.projectName == p).length)),
                    ],
                    onChanged: (v) => setState(() => _project = v),
                  ),
                ),
                if (_profile != null)
                  for (final f in _profile!.enumFields) _enumFilter(context, all, f.key, f.labelFa, f.list),
                if (_profile != null)
                  _rangeFilter(context, '_size', '${_profile!.driver.labelFa} (${_profile!.driver.unit})'),
                if (_profile != null)
                  for (final k in _profile!.rangeKeys)
                    if (_profile!.field(k) case final f?)
                      _rangeFilter(context, k, '${f.labelFa}${f.unit == null ? '' : ' (${f.unit})'}'),
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
              ]),
            ],
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
            label: '${f.labelFa}${f.unit == null ? '' : '\n${f.unit}'}',
            width: f.type == 'number' ? 92 : 120,
            ltr: f.type != 'number',
            numeric: f.type == 'number',
            tooltip: f.labelEn,
            text: (r) {
              final v = r.item.values[f.key];
              if (v is num) return faSmart(v);
              return v?.toString() ?? '';
            },
            sortKey: (r) {
              final v = r.item.values[f.key];
              if (f.type == 'number') return v is num ? v.toDouble() : double.negativeInfinity;
              return v?.toString() ?? '';
            },
          ),
        if (_profile != null)
          GridColumn(
            label: '${_profile!.driver.labelFa}\n${_profile!.driver.unit}',
            width: 96,
            numeric: true,
            tooltip: 'پارامتر اندازه برای تخمین',
            text: (r) => r.size == null ? '' : faSmart(r.size),
            sortKey: (r) => r.size,
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

  Widget _enumFilter(BuildContext context, List<GenericRow> all, String key, String labelFa, String? listKey) {
    final t = Theme.of(context);
    final counts = <String, int>{};
    for (final r in all) {
      final v = r.item.values[key]?.toString();
      if (v == null || v.isEmpty) continue;
      counts[v] = (counts[v] ?? 0) + 1;
    }
    final opts = listKey == null ? const <EnumOption>[] : AppScope.read(context).pb.catalog.options(listKey);
    final labels = {for (final o in opts) o.value: o.labelFa};
    final values = [for (final o in opts) o.value, for (final v in counts.keys) if (!labels.containsKey(v)) v];
    final cur = _enumF[key];
    String show(String v) => (labels[v] == null || labels[v] == v) ? v : '${labels[v]}';
    return SizedBox(
      width: 178,
      child: DropdownButtonFormField<String?>(
        value: values.contains(cur) ? cur : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: labelFa,
          fillColor: cur != null ? t.colorScheme.primaryContainer : null,
        ),
        selectedItemBuilder: (_) => [const Text('همه'), for (final v in values) Text(show(v), overflow: TextOverflow.ellipsis)],
        items: [
          DropdownMenuItem<String?>(value: null, child: Text('همه (${fa(all.length)})')),
          for (final v in values)
            DropdownMenuItem<String?>(
              value: v,
              child: Row(children: [
                Expanded(
                  child: Text(show(v),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: (counts[v] ?? 0) == 0 ? t.colorScheme.outline : null)),
                ),
                Text(fa(counts[v] ?? 0),
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: (counts[v] ?? 0) == 0 ? t.colorScheme.outline : AppColors.strong)),
              ]),
            ),
        ],
        onChanged: (v) => setState(() => _enumF[key] = v),
      ),
    );
  }

  Widget _rangeFilter(BuildContext context, String key, String label) {
    final c = _range(key);
    InputDecoration dec(String h) => InputDecoration(hintText: h, isDense: true);
    return SizedBox(
      width: 300,
      child: Row(children: [
        SizedBox(width: 120, child: Text(label, style: Theme.of(context).textTheme.labelMedium)),
        Expanded(child: TextField(controller: c.$1, textDirection: TextDirection.ltr, decoration: dec('از'), onChanged: (_) => setState(() {}))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('تا')),
        Expanded(child: TextField(controller: c.$2, textDirection: TextDirection.ltr, decoration: dec('تا'), onChanged: (_) => setState(() {}))),
      ]),
    );
  }

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


/// تنظیمات اختصاصی رده: روش تعدیل، شاخص PPI، توان اندازه و روش تخمین پیش‌فرض.
class CategorySettingsDialog extends StatefulWidget {
  const CategorySettingsDialog({super.key, required this.code});
  final String code;

  @override
  State<CategorySettingsDialog> createState() => _CategorySettingsDialogState();
}

class _CategorySettingsDialogState extends State<CategorySettingsDialog> {
  String? _method;
  String? _ppi;
  String? _est;
  late final TextEditingController _n;
  late final TextEditingController _w;

  @override
  void initState() {
    super.initState();
    final s = AppScope.read(context).settings;
    final w = s.catWeightExp(widget.code);
    _w = TextEditingController(text: w == null ? '' : '$w');
    _method = s.catMethod(widget.code);
    _ppi = s.catPpi(widget.code);
    _est = s.catEstimation(widget.code);
    final n = s.catExponent(widget.code);
    _n = TextEditingController(text: n == null ? '' : '$n');
  }

  @override
  void dispose() {
    _n.dispose();
    _w.dispose();
    super.dispose();
  }

  void _save() {
    final app = AppScope.read(context);
    final n = parseUserNumber(_n.text);
    if (_n.text.trim().isNotEmpty && (n == null || n <= 0 || n > 1.5)) {
      showSnack(context, 'توان اندازه باید عددی بین ۰ و ۱٫۵ باشد.', error: true);
      return;
    }
    final w = parseUserNumber(_w.text);
    if (_w.text.trim().isNotEmpty && (w == null || w < 0 || w > 1.5)) {
      showSnack(context, 'توان وزن باید عددی بین ۰ و ۱٫۵ باشد.', error: true);
      return;
    }
    app.pb.settingsRepo.set('cat_wexp_${widget.code}', w == null ? null : '$w', reason: 'تنظیمات رده');
    const reason = 'تنظیمات رده';
    app.pb.settingsRepo.set('cat_method_${widget.code}', _method, reason: reason);
    app.pb.settingsRepo.set('cat_ppi_${widget.code}', _ppi, reason: reason);
    app.pb.settingsRepo.set('cat_est_${widget.code}', _est, reason: reason);
    app.pb.settingsRepo.set('cat_n_${widget.code}', n == null ? null : '$n', reason: reason);
    app.dataChanged(calcInputs: true);
    Navigator.pop(context);
    showSnack(context, 'تنظیمات رده ذخیره شد؛ قیمت‌ها دوباره محاسبه شدند.');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final cat = app.pb.catalog.categoryByCode(widget.code)!;
    final p = equipmentProfiles[widget.code]!;
    final s = app.settings;
    final ppiSeries = app.pb.indices.series().where((x) => x.group.startsWith('ppi') && x.calendar == 'jalali').toList();
    Widget row(String label, Widget w, {String? help}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            SizedBox(
              width: 170,
              child: Row(children: [
                Flexible(child: Text(label, style: t.textTheme.bodySmall)),
                if (help != null)
                  Tooltip(
                    message: help,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 4),
                      child: Icon(Icons.info_outline_rounded, size: 14, color: t.colorScheme.outline),
                    ),
                  ),
              ]),
            ),
            Expanded(child: w),
          ]),
        );
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.settings_suggest_outlined),
        const SizedBox(width: 8),
        Expanded(child: Text('تنظیمات رده: ${cat.nameFa}')),
      ]),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          row(
            'روش تعدیل این رده',
            DropdownButtonFormField<String?>(
              value: _method,
              isExpanded: true,
              items: [
                DropdownMenuItem<String?>(value: null, child: Text('پیش‌فرض برنامه (${s.escalationMethod})')),
                for (final m in escalationMethods.where((m) => m.selectable))
                  DropdownMenuItem<String?>(value: m.code, child: Text('${m.code} — ${m.nameFa}')),
              ],
              onChanged: (v) => setState(() => _method = v),
            ),
            help: 'کف قیمت M6 فقط برای پمپ‌هاست؛ در این رده M6 همان M4 است.',
          ),
          row(
            'شاخص PPI (روش‌های M4/M6)',
            DropdownButtonFormField<String?>(
              value: ppiSeries.any((x) => x.code == _ppi) ? _ppi : null,
              isExpanded: true,
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('پیش‌فرض برنامه')),
                for (final x in ppiSeries)
                  DropdownMenuItem<String?>(value: x.code, child: Text(x.nameFa, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _ppi = v),
            ),
            help: 'برای تجهیزات ساخت داخل (ظرف، مخزن، سازه) می‌توانید PPI بخشی ایران (مثلاً ISIC 25 محصولات فلزی) را انتخاب کنید؛ ابتدا مقادیر آن را در «شاخص‌ها و ارز» کامل کنید.',
          ),
          row(
            'توان اندازه n',
            TextField(
              controller: _n,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(hintText: 'پیش‌فرض ${p.driver.n} (قیمت ∝ ${p.driver.labelFa}^n)'),
            ),
          ),
          if (p.weightKey != null)
            row(
              'توان وزن m',
              TextField(
                controller: _w,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(hintText: 'پیش‌فرض 0.8 — ضریب وزن = (وزن ویژه ÷ میانه‌ی رده)^m'),
              ),
              help: 'فقط وقتی وزن خالی برای قلم و دست‌کم دو قلم این رده ثبت شده باشد اثر دارد. صفر = وزن نادیده گرفته شود.',
            ),
          row(
            'روش تخمین پیش‌فرض',
            DropdownButtonFormField<String?>(
              value: _est,
              isExpanded: true,
              items: [
                for (final m in GenEstMethod.values) DropdownMenuItem<String?>(value: m.name, child: Text(m.titleFa)),
              ],
              onChanged: (v) => setState(() => _est = v),
            ),
          ),
          Text('پارامتر اندازه‌ی این رده: ${p.driver.labelFa} (${p.driver.unit}). ضرایب نرمال‌سازی: ${p.factorGroups.isEmpty ? 'ندارد' : p.factorGroups.join('، ')} — در صفحه‌ی «ضرایب».',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.8)),
        ])),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: _save, child: const Text('ذخیره')),
      ],
    );
  }
}
