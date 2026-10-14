import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/pump_engine.dart';
import '../../core/price_bank.dart';
import '../../core/repo/catalog_repo.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import 'pump_detail_page.dart';

class EquipmentPage extends StatefulWidget {
  const EquipmentPage({super.key});

  @override
  State<EquipmentPage> createState() => _EquipmentPageState();
}

/// فیلترهای انتخابی فهرست پمپ‌ها: کلید فیلد → برچسب
const _enumFilters = <String, String>{
  'project': 'پروژه',
  'sub_category': 'زیرگروه',
  'pump_family': 'خانواده',
  'pump_standard': 'استاندارد',
  'api610_type': 'نوع API 610',
  'material_class': 'کلاس متریال',
  'seal_arrangement': 'آب‌بند',
  'driver_type': 'محرک',
  'service_fluid': 'سیال سرویس',
  'nace': 'NACE',
  'cost_year': 'سال قیمت',
  'currency': 'ارز',
  'include_in_totals': 'شمارش در جمع',
};

class _EquipmentPageState extends State<EquipmentPage> {
  final _search = TextEditingController();
  final Map<String, String?> _filters = {};
  final _ranges = <String, (TextEditingController, TextEditingController)>{
    'capacity_m3h': (TextEditingController(), TextEditingController()),
    'diff_head_m': (TextEditingController(), TextEditingController()),
    'size_kw': (TextEditingController(), TextEditingController()),
  };
  bool _onlyPriced = false;
  bool _onlyIssues = false;
  bool _showFilters = true;

  /// ستون‌های قابل نمایش (بین اجراهای صفحه حفظ می‌شود)
  static final Set<String> _hiddenCols = {'sub', 'qty', 'coef'};
  static bool? _showCats;

  @override
  void dispose() {
    _search.dispose();
    for (final r in _ranges.values) {
      r.$1.dispose();
      r.$2.dispose();
    }
    super.dispose();
  }

  String _val(PumpRow r, String key) {
    if (key == 'size_kw') return r.result.sizeKw.number?.toString() ?? '';
    return asText(r.item.valueOf(key));
  }

  List<PumpRow> _apply(List<PumpRow> all) {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final r in all)
        if (_match(r, q)) r,
    ];
  }

  bool _match(PumpRow r, String q) {
    if (q.isNotEmpty) {
      final hay = [
        r.item.tag, r.item.name, r.item.remarks, r.item.projectName,
        asText(r.item.values['manufacturer']), asText(r.item.values['service_fluid']),
      ].whereType<String>().join(' ').toLowerCase();
      if (!q.split(RegExp(r'\s+')).every(hay.contains)) return false;
    }
    for (final e in _filters.entries) {
      if (e.value == null) continue;
      if (_val(r, e.key) != e.value) return false;
    }
    for (final e in _ranges.entries) {
      final lo = parseUserNumber(e.value.$1.text), hi = parseUserNumber(e.value.$2.text);
      if (lo == null && hi == null) continue;
      final v = e.key == 'size_kw' ? r.result.sizeKw.number : asNumber(r.item.values[e.key]);
      if (v == null) return false;
      if (lo != null && v < lo) return false;
      if (hi != null && v > hi) return false;
    }
    if (_onlyPriced && !r.result.eurTarget.isNumber) return false;
    if (_onlyIssues && r.result.qaFlags.isEmpty) return false;
    return true;
  }

  void _clear() => setState(() {
        _search.clear();
        _filters.clear();
        for (final r in _ranges.values) {
          r.$1.clear();
          r.$2.clear();
        }
        _onlyPriced = false;
        _onlyIssues = false;
      });

  Future<void> _open(BuildContext context, int? itemId) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PumpDetailPage(itemId: itemId)));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final all = app.pumps;
    final rows = _apply(all);
    final unit = app.unit;
    final canEdit = app.canEdit('MECH');

    final width = MediaQuery.sizeOf(context).width;
    final showCats = _showCats ?? width >= 1700;
    final method = app.settings.escalationMethod;

    return Row(children: [
      if (showCats) _CategoryPanel(count: all.length, onClose: () => setState(() => _showCats = false)),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PageHeader(
              icon: Icons.water_rounded,
              title: 'پمپ‌ها',
              subtitle: 'مکانیک ← تجهیزات دوار ← پمپ · قیمت‌ها تعدیل‌شده به سال ${fa(app.settings.targetYear)} با روش $method',
              actions: [
                if (!showCats)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _showCats = true),
                    icon: const Icon(Icons.account_tree_outlined),
                    label: const Text('رده‌ها'),
                  ),
                _columnsMenu(context),
                OutlinedButton.icon(
                  onPressed: rows.isEmpty ? null : () => _exportCsv(context, rows, unit),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('خروجی CSV'),
                ),
                if (canEdit)
                  FilledButton.icon(
                    onPressed: () => _open(context, null),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('پمپ جدید'),
                  ),
              ],
            ),
            HelpPanel(
              id: 'equipment',
              title: 'راهنمای این صفحه',
              initiallyOpen: false,
              lines: [
                'برای جستجو، بخشی از تگ، نام سرویس، سازنده یا پروژه را بنویسید؛ چند کلمه = همه باید باشند.',
                'هر فیلتر همه‌ی گزینه‌های فهرست را با تعداد پمپ‌های هر گزینه نشان می‌دهد (عدد کنار گزینه). روی سرستون‌ها بزنید تا مرتب شوند.',
                'قیمت‌های «تعدیل‌شده» با روش $method به سال هدف (نوار بالا) و با جدول نرخ ارز انتخاب‌شده محاسبه شده‌اند.',
                'خط تیره (—) یعنی مقدار در منبع ثبت نشده یا قابل محاسبه نیست؛ نشانگر ماوس را روی آن نگه دارید تا علت را ببینید.',
                'علامت ⚠ یعنی داده‌ی ناقص. روی هر ردیف بزنید تا جزئیات، محاسبه‌ی گام‌به‌گام و ویرایش باز شود. با دکمه‌ی «ستون‌ها» ستون‌های اضافی را نشان دهید.',
              ],
            ),
            _filtersBar(context, all, rows),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  boxShadow: softShadow(context),
                ),
                clipBehavior: Clip.antiAlias,
                child: rows.isEmpty
                    ? EmptyState(
                        icon: all.isEmpty ? Icons.inventory_2_outlined : Icons.filter_alt_off_outlined,
                        title: all.isEmpty ? 'هنوز پمپی ثبت نشده' : 'هیچ پمپی با این فیلترها پیدا نشد',
                        message: all.isEmpty
                            ? 'از داشبورد، داده‌های فایل v8 را وارد کنید یا پمپ جدید بسازید.'
                            : 'فیلترها را کم کنید یا پاک کنید.',
                        action: all.isEmpty ? null : TextButton(onPressed: _clear, child: const Text('پاک کردن فیلترها')),
                      )
                    : DataGrid<PumpRow>(
                        rows: rows,
                        onTap: (r) => _open(context, r.item.id),
                        rowColor: (c, r) => r.item.include ? null : (AppColors.isDark ? const Color(0xFF2E2620) : const Color(0xFFF6EFE6)),
                        columns: _columns(unit).where((c) => !_hiddenCols.contains(c.$1)).map((c) => c.$2).toList(),
                      ),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  static const _optionalCols = {'sub': 'زیرگروه', 'qty': 'تعداد', 'coef': 'ضریب هزینه', 'project': 'پروژه', 'src': 'قیمت منبع'};

  Widget _columnsMenu(BuildContext context) => MenuAnchor(
        menuChildren: [
          for (final e in _optionalCols.entries)
            CheckboxMenuButton(
              value: !_hiddenCols.contains(e.key),
              onChanged: (v) => setState(() => v == true ? _hiddenCols.remove(e.key) : _hiddenCols.add(e.key)),
              child: Text(e.value),
            ),
        ],
        builder: (context, ctl, _) => OutlinedButton.icon(
          onPressed: () => ctl.isOpen ? ctl.close() : ctl.open(),
          icon: const Icon(Icons.view_column_outlined),
          label: const Text('ستون‌ها'),
        ),
      );

  /// سلول متنی با «—» کم‌رنگ برای مقدار خالی و توضیح علت در راهنمای شناور.
  static Widget _txt(BuildContext c, String? v, {String? why, bool ltr = false, bool bold = false, Color? color}) {
    final t = Theme.of(c);
    final s = cleanCell(v);
    if (s == gridEmpty) {
      final w = Text(gridEmpty, style: TextStyle(color: t.colorScheme.outline));
      return why == null ? w : Tooltip(message: why, child: w);
    }
    return Text(s,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textDirection: ltr ? TextDirection.ltr : null,
        style: t.textTheme.bodySmall?.copyWith(
          fontWeight: bold ? FontWeight.w700 : null,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ));
  }

  List<(String, GridColumn<PumpRow>)> _columns(MoneyUnit unit) => [
        (
          'qa',
          GridColumn(
            label: '',
            width: 34,
            grow: false,
            text: (r) => '',
            sortKey: (r) => r.result.qaFlags.isEmpty ? 0 : 1,
            cell: (c, r) => r.result.qaFlags.isEmpty
                ? const SizedBox()
                : Tooltip(
                    message: qaFlagsFa(r.result.qaFlags).join('\n'),
                    child: Icon(Icons.warning_amber_rounded, size: 18, color: Tones.warn(c)),
                  ),
          )
        ),
        (
          'tag',
          GridColumn(
            label: 'تگ',
            width: 104,
            ltr: true,
            text: (r) => r.item.tag ?? '',
            sortKey: (r) => r.item.tag ?? '',
            cell: (c, r) => _txt(c, r.item.tag, ltr: true, bold: true, color: AppColors.petrolDark),
          )
        ),
        (
          'name',
          GridColumn(
            label: 'نام / سرویس',
            width: 190,
            align: TextAlign.start,
            text: (r) => r.item.name,
            sortKey: (r) => r.item.name,
          )
        ),
        ('project', GridColumn(label: 'پروژه', width: 120, text: (r) => r.item.projectName ?? '', sortKey: (r) => r.item.projectName ?? '')),
        ('sub', GridColumn(label: 'زیرگروه', width: 84, ltr: true, text: (r) => _val(r, 'sub_category'), sortKey: (r) => _val(r, 'sub_category'))),
        ('type', GridColumn(label: 'نوع', width: 58, ltr: true, text: (r) => _val(r, 'api610_type'), sortKey: (r) => _val(r, 'api610_type'))),
        ('mat', GridColumn(label: 'متریال', width: 62, ltr: true, text: (r) => _val(r, 'material_class'), sortKey: (r) => _val(r, 'material_class'))),
        (
          'q',
          GridColumn(
              label: 'دبی\nm³/h', width: 64, numeric: true,
              text: (r) => _num(asNumber(r.item.values['capacity_m3h'])),
              sortKey: (r) => asNumber(r.item.values['capacity_m3h']))
        ),
        (
          'h',
          GridColumn(
              label: 'هد\nm', width: 58, numeric: true,
              text: (r) => _num(asNumber(r.item.values['diff_head_m'])),
              sortKey: (r) => asNumber(r.item.values['diff_head_m']))
        ),
        (
          'kw',
          GridColumn(
              label: 'توان\nkW', width: 64, numeric: true, tooltip: 'توان اعلام‌شده یا برآوردی (Q·H/367η)',
              text: (r) => _num(r.result.sizeKw.number),
              sortKey: (r) => r.result.sizeKw.number)
        ),
        ('qty', GridColumn(label: 'تعداد', width: 54, numeric: true, text: (r) => _num(r.item.quantity), sortKey: (r) => r.item.quantity)),
        (
          'year',
          GridColumn(
            label: 'سال قیمت',
            width: 62,
            text: (r) => r.item.primary?.costYear == null ? '' : fa(r.item.primary!.costYear),
            sortKey: (r) => r.item.primary?.costYear,
            cell: (c, r) => _txt(c, r.item.primary?.costYear == null ? null : fa(r.item.primary!.costYear),
                why: 'سال قیمت در منبع ذکر نشده${(r.item.primary?.costYearText ?? '').isEmpty ? '' : ' («${r.item.primary!.costYearText}»)'}'),
          )
        ),
        (
          'src',
          GridColumn(
            label: 'قیمت منبع',
            width: 132,
            numeric: true,
            text: (r) => r.item.primary?.amount == null ? '' : '${faNum(r.item.primary!.amount)} ${r.item.primary?.currency ?? ''}',
            sortKey: (r) => r.result.eurSource.number,
            cell: (c, r) {
              final o = r.item.primary;
              if (o?.amount == null) return _txt(c, null, why: 'قیمت عددی در منبع ثبت نشده${(o?.amountText ?? '').isEmpty ? '' : ' («${o!.amountText}»)'}');
              final cur = o!.currency ?? '';
              return Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: _txt(c, faNum(o.amount), bold: true)),
                const SizedBox(width: 4),
                Text(CurrencyBadge.faOf(cur), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: CurrencyBadge.colorOf(cur))),
              ]);
            },
          )
        ),
        (
          'eur',
          GridColumn(
            label: 'یورو\nتعدیل‌شده',
            width: 104,
            numeric: true,
            text: (r) => r.result.eurTarget.isNumber ? faNum(r.result.eurTarget.number) : '',
            sortKey: (r) => r.result.eurTarget.number,
            cell: (c, r) => r.result.eurTarget.isNumber
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    _txt(c, faNum(r.result.eurTarget.number), bold: true, color: AppColors.eur),
                    if (r.result.floorBinding)
                      const Padding(
                        padding: EdgeInsetsDirectional.only(start: 3),
                        child: Tooltip(message: 'کف قیمت اعمال شده', child: Icon(Icons.vertical_align_bottom_rounded, size: 14, color: AppColors.amber)),
                      ),
                  ])
                : _txt(c, null, why: calcMessageFa(r.result.eurTarget.text)),
          )
        ),
        (
          'irr',
          GridColumn(
            label: '${unitLabel(unit)}\nتعدیل‌شده (واحد)',
            width: 142,
            numeric: true,
            text: (r) => r.result.irrTarget.isNumber ? money(r.result.irrTarget.number, unit, withUnit: false) : '',
            sortKey: (r) => r.result.irrTarget.number,
            cell: (c, r) => r.result.irrTarget.isNumber
                ? Tooltip(
                    message: money(r.result.irrTarget.number, unit, compact: true),
                    child: _txt(c, money(r.result.irrTarget.number, unit, withUnit: false), bold: true, color: AppColors.irr),
                  )
                : _txt(c, null, why: r.result.eurTarget.isNumber ? 'نرخ یوروی سال هدف وارد نشده' : calcMessageFa(r.result.eurTarget.text)),
          )
        ),
        (
          'coef',
          GridColumn(
              label: 'ضریب\nهزینه', width: 80, numeric: true, tooltip: 'یورو نرمال‌شده‌ی تعدیل‌شده ÷ kWⁿ',
              text: (r) => _num(r.result.costCoef.number),
              sortKey: (r) => r.result.costCoef.number)
        ),
      ];

  static String _num(num? v) => v == null ? '' : faSmart(v);

  Widget _filtersBar(BuildContext context, List<PumpRow> all, List<PumpRow> rows) {
    final t = Theme.of(context);
    final active = _filters.values.whereType<String>().length +
        _ranges.values.where((r) => r.$1.text.isNotEmpty || r.$2.text.isNotEmpty).length +
        (_onlyPriced ? 1 : 0) +
        (_onlyIssues ? 1 : 0);
    final priced = rows.where((r) => r.result.eurTarget.isNumber).length;
    final fields = {for (final f in AppScope.read(context).pb.catalog.fields(AppScope.read(context).pb.pumpCategory.id)) f.key: f};
    return SectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'جستجو در تگ، نام سرویس، پروژه، سازنده، ملاحظات…',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: AppColors.petrol.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10)),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: fa(rows.length), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.petrolDark)),
                TextSpan(text: ' از ${fa(all.length)} پمپ · '),
                TextSpan(text: fa(priced), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.petrolDark)),
                const TextSpan(text: ' با قیمت تعدیل‌شده'),
              ]),
              style: t.textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 10),
          ToggleChip(
            label: _showFilters ? 'بستن فیلترها${active > 0 ? ' (${fa(active)} فعال)' : ''}' : 'فیلترها${active > 0 ? ' (${fa(active)} فعال)' : ''}',
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
            for (final e in _enumFilters.entries) _enumFilter(context, all, e.key, e.value, fields[e.key]?.listKey),
            for (final e in _ranges.entries) _rangeFilter(context, e.key, e.value),
            ToggleChip(
              label: 'فقط دارای قیمت تعدیل‌شده',
              selected: _onlyPriced,
              color: Tones.good(context),
              onChanged: (v) => setState(() => _onlyPriced = v),
            ),
            ToggleChip(
              label: 'فقط دارای هشدار داده',
              selected: _onlyIssues,
              color: Tones.warn(context),
              onChanged: (v) => setState(() => _onlyIssues = v),
            ),
          ]),
        ],
      ]),
    );
  }

  /// فیلتر انتخابی: همه‌ی گزینه‌های فهرست قالب (حتی بدون پمپ) + مقادیر موجود، با تعداد هر گزینه.
  Widget _enumFilter(BuildContext context, List<PumpRow> all, String key, String label, String? listKey) {
    final t = Theme.of(context);
    final counts = <String, int>{};
    for (final r in all) {
      final v = _val(r, key);
      if (v.isEmpty) continue;
      counts[v] = (counts[v] ?? 0) + 1;
    }
    final catalog = listKey == null ? const <EnumOption>[] : AppScope.read(context).pb.catalog.options(listKey);
    final labels = <String, String?>{for (final o in catalog) o.value: o.labelFa};
    final values = <String>[
      for (final o in catalog) o.value,
      for (final v in (counts.keys.toList()..sort())) if (!labels.containsKey(v)) v,
    ];
    if (key == 'cost_year') values.sort();
    final current = _filters[key];
    String show(String v) {
      if (v == 'Not stated' || v == '(Not stated)') return 'نامشخص';
      if (key == 'cost_year') return fa(v);
      if (listKey == 'YN' || listKey == 'YNS') return labels[v] ?? v;
      return v;
    }

    return SizedBox(
      width: 178,
      child: DropdownButtonFormField<String?>(
        value: values.contains(current) ? current : null,
        isExpanded: true,
        menuMaxHeight: 420,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: current != null ? t.colorScheme.primaryContainer : null,
        ),
        selectedItemBuilder: (_) => [
          const Text('همه'),
          for (final v in values) Text(show(v), overflow: TextOverflow.ellipsis),
        ],
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Row(children: [
              const Expanded(child: Text('همه')),
              Text(fa(all.length), style: TextStyle(fontSize: 11.5, color: t.colorScheme.outline)),
            ]),
          ),
          for (final v in values)
            DropdownMenuItem<String?>(
              value: v,
              child: Row(children: [
                Expanded(
                  child: Text(show(v),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: (counts[v] ?? 0) == 0 ? t.colorScheme.outline : null)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: (counts[v] ?? 0) == 0 ? null : AppColors.petrol.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(fa(counts[v] ?? 0),
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: (counts[v] ?? 0) == 0 ? t.colorScheme.outline : AppColors.petrolDark)),
                ),
              ]),
            ),
        ],
        onChanged: (v) => setState(() => _filters[key] = v),
      ),
    );
  }

  Widget _rangeFilter(BuildContext context, String key, (TextEditingController, TextEditingController) c) {
    final label = switch (key) { 'capacity_m3h' => 'دبی m³/h', 'diff_head_m' => 'هد m', _ => 'توان kW' };
    InputDecoration dec(String h) => InputDecoration(hintText: h, isDense: true);
    return SizedBox(
      width: 220,
      child: Row(children: [
        SizedBox(width: 62, child: Text(label, style: Theme.of(context).textTheme.labelMedium)),
        Expanded(child: TextField(controller: c.$1, decoration: dec('از'), onChanged: (_) => setState(() {}))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('تا')),
        Expanded(child: TextField(controller: c.$2, decoration: dec('تا'), onChanged: (_) => setState(() {}))),
      ]),
    );
  }

  Future<void> _exportCsv(BuildContext context, List<PumpRow> rows, MoneyUnit unit) async {
    final cols = _columns(unit).skip(1).map((c) => c.$2).toList();
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    final b = StringBuffer('﻿');
    b.writeln(cols.map((c) => esc(c.label.replaceAll('\n', ' '))).join(','));
    for (final r in rows) {
      b.writeln([
        esc(r.item.tag ?? ''),
        esc(r.item.name),
        esc(r.item.projectName ?? ''),
        esc(_val(r, 'sub_category')),
        esc(_val(r, 'api610_type')),
        esc(_val(r, 'material_class')),
        asText(r.item.values['capacity_m3h']),
        asText(r.item.values['diff_head_m']),
        r.result.sizeKw.number?.toStringAsFixed(2) ?? '',
        asText(r.item.quantity),
        esc(_val(r, 'cost_year')),
        esc('${asText(r.item.primary?.amountValue)} ${r.item.primary?.currency ?? ''}'),
        r.result.eurTarget.number?.toStringAsFixed(2) ?? '',
        r.result.irrTarget.number == null
            ? ''
            : (unit == MoneyUnit.toman ? r.result.irrTarget.number! / 10 : r.result.irrTarget.number!).toStringAsFixed(0),
        r.result.costCoef.number?.toStringAsFixed(4) ?? '',
      ].join(','));
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'ذخیره‌ی فهرست پمپ‌ها',
      fileName: 'pumps_${AppScope.read(context).settings.targetYear}.csv',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (path == null) return;
    await File(path).writeAsBytes(utf8.encode(b.toString()));
    if (context.mounted) showSnack(context, 'فایل ذخیره شد: $path');
  }
}

/// ستون رده‌ها: رشته ← گروه ← رده. رده‌های غیرفعال با برچسب «به‌زودی».
class _CategoryPanel extends StatelessWidget {
  const _CategoryPanel({required this.count, required this.onClose});
  final int count;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final discs = app.pb.catalog.disciplines();
    final cats = app.pb.catalog.categories();
    List<Category> children(String disc, int? parent) =>
        cats.where((c) => c.disciplineCode == disc && c.parentId == parent).toList();

    Widget node(Category c, int depth) {
      final kids = cats.where((k) => k.parentId == c.id).toList();
      final isPump = c.code == 'PUMP';
      final isGroup = kids.isNotEmpty;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          margin: EdgeInsetsDirectional.only(start: 8.0 + depth * 14, end: 8, top: 2, bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: isPump ? t.colorScheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Expanded(
              child: Text(c.nameFa,
                  style: (isGroup ? t.textTheme.labelLarge : t.textTheme.bodySmall)?.copyWith(
                    fontWeight: isGroup || isPump ? FontWeight.w700 : null,
                    color: c.enabled || isGroup ? null : t.colorScheme.outline,
                  )),
            ),
            if (isPump) Pill(fa(count))
            else if (!c.enabled && !isGroup) Pill('به‌زودی', color: t.colorScheme.outline),
          ]),
        ),
        for (final k in kids) node(k, depth + 1),
      ]);
    }

    return Container(
      width: 236,
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        border: BorderDirectional(end: BorderSide(color: t.colorScheme.outlineVariant)),
      ),
      child: ListView(padding: const EdgeInsets.symmetric(vertical: 14), children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 6, 8),
          child: Row(children: [
            Expanded(child: Text('رده‌های تجهیزات', style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
            IconButton(
              tooltip: 'بستن این ستون (جای بیشتر برای جدول)',
              onPressed: onClose,
              icon: const Icon(Icons.keyboard_double_arrow_right_rounded, size: 20),
            ),
          ]),
        ),
        for (final d in discs) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(children: [
              Icon(_discIcon(d.code), size: 18, color: t.colorScheme.primary),
              const SizedBox(width: 6),
              Text(d.nameFa, style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
            ]),
          ),
          for (final c in children(d.code, null)) node(c, 0),
        ],
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'رده‌های «به‌زودی» در مراحل بعد (ورود MTO، پایپینگ، برق و ابزار دقیق) فعال می‌شوند. ساختار دیتابیس از هم‌اکنون برای همه‌ی آن‌ها آماده است.',
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.8),
          ),
        ),
      ]),
    );
  }

  IconData _discIcon(String code) => switch (code) {
        'MECH' => Icons.settings_suggest_rounded,
        'PIPE' => Icons.plumbing_rounded,
        'ELEC' => Icons.bolt_rounded,
        _ => Icons.speed_rounded,
      };
}
