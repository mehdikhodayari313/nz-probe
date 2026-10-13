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

    return Row(children: [
      _CategoryPanel(count: all.length),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PageHeader(
              icon: Icons.water_rounded,
              title: 'پمپ‌ها',
              subtitle: 'مکانیک ← تجهیزات دوار ← پمپ — ${fa(all.length)} قلم، قیمت‌ها به سال ${fa(app.settings.targetYear)}',
              actions: [
                OutlinedButton.icon(
                  onPressed: rows.isEmpty ? null : () => _exportCsv(context, rows, unit),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('خروجی اکسل (CSV)'),
                ),
                if (canEdit)
                  FilledButton.icon(
                    onPressed: () => _open(context, null),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('پمپ جدید'),
                  ),
              ],
            ),
            const HelpPanel(
              id: 'equipment',
              title: 'راهنمای این صفحه',
              initiallyOpen: false,
              lines: [
                'برای جستجو، بخشی از تگ، نام سرویس، سازنده یا پروژه را بنویسید؛ چند کلمه = همه باید باشند.',
                'با فیلترها و بازه‌های عددی (دبی، هد، توان) همتاهای یک پمپ را پیدا کنید. روی سرستون‌ها بزنید تا مرتب شوند.',
                'قیمت‌های «تعدیل‌شده» با روش M6 به سال هدف (نوار بالا) و با نوع نرخ ارز انتخاب‌شده محاسبه شده‌اند.',
                'علامت ⚠ یعنی داده‌ی ناقص (مثلاً کلاس متریال یا آب‌بند نامشخص). روی هر ردیف بزنید تا جزئیات، محاسبه‌ی گام‌به‌گام و ویرایش باز شود.',
              ],
            ),
            _filtersBar(context, all),
            const SizedBox(height: 10),
            _summary(context, rows, unit),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
                        rowColor: (c, r) => r.item.include ? null : Theme.of(c).colorScheme.surfaceContainerHighest,
                        columns: _columns(unit),
                      ),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  List<GridColumn<PumpRow>> _columns(MoneyUnit unit) => [
        GridColumn(
          label: '',
          width: 36,
          text: (r) => '',
          sortKey: (r) => r.result.qaFlags.isEmpty ? 0 : 1,
          cell: (c, r) => r.result.qaFlags.isEmpty
              ? const SizedBox()
              : Tooltip(
                  message: qaFlagsFa(r.result.qaFlags).join('\n'),
                  child: Icon(Icons.warning_amber_rounded, size: 18, color: Tones.warn(c)),
                ),
        ),
        GridColumn(label: 'تگ', width: 120, text: (r) => r.item.tag ?? '', sortKey: (r) => r.item.tag ?? ''),
        GridColumn(label: 'نام / سرویس', width: 240, text: (r) => r.item.name, sortKey: (r) => r.item.name),
        GridColumn(label: 'پروژه', width: 150, text: (r) => r.item.projectName ?? '', sortKey: (r) => r.item.projectName ?? ''),
        GridColumn(label: 'زیرگروه', width: 86, text: (r) => _val(r, 'sub_category'), sortKey: (r) => _val(r, 'sub_category')),
        GridColumn(label: 'نوع', width: 70, text: (r) => _val(r, 'api610_type'), sortKey: (r) => _val(r, 'api610_type')),
        GridColumn(label: 'متریال', width: 80, text: (r) => _val(r, 'material_class'), sortKey: (r) => _val(r, 'material_class')),
        GridColumn(
            label: 'دبی m³/h', width: 80, numeric: true,
            text: (r) => faSmart(asNumber(r.item.values['capacity_m3h'])),
            sortKey: (r) => asNumber(r.item.values['capacity_m3h'])),
        GridColumn(
            label: 'هد m', width: 70, numeric: true,
            text: (r) => faSmart(asNumber(r.item.values['diff_head_m'])),
            sortKey: (r) => asNumber(r.item.values['diff_head_m'])),
        GridColumn(
            label: 'توان kW', width: 76, numeric: true, tooltip: 'توان اعلام‌شده یا برآوردی (Q·H/367η)',
            text: (r) => faSmart(r.result.sizeKw.number),
            sortKey: (r) => r.result.sizeKw.number),
        GridColumn(label: 'تعداد', width: 54, numeric: true, text: (r) => faSmart(r.item.quantity), sortKey: (r) => r.item.quantity),
        GridColumn(label: 'سال قیمت', width: 70, text: (r) => fa(_val(r, 'cost_year')), sortKey: (r) => _val(r, 'cost_year')),
        GridColumn(
            label: 'قیمت منبع', width: 150, numeric: true,
            text: (r) {
              final a = r.item.primary?.amount;
              return a == null ? '—' : '${faNum(a)} ${r.item.primary?.currency ?? ''}';
            },
            sortKey: (r) => r.result.eurSource.number),
        GridColumn(
            label: 'یورو تعدیل‌شده', width: 120, numeric: true,
            text: (r) => r.result.eurTarget.isNumber ? faNum(r.result.eurTarget.number) : calcMessageFa(r.result.eurTarget.text),
            sortKey: (r) => r.result.eurTarget.number),
        GridColumn(
            label: '${unitLabel(unit)} تعدیل‌شده (واحد)', width: 170, numeric: true,
            text: (r) => money(r.result.irrTarget.number, unit, withUnit: false),
            sortKey: (r) => r.result.irrTarget.number),
        GridColumn(
            label: 'ضریب هزینه', width: 90, numeric: true, tooltip: 'یورو نرمال‌شده‌ی تعدیل‌شده ÷ kWⁿ',
            text: (r) => faSmart(r.result.costCoef.number),
            sortKey: (r) => r.result.costCoef.number),
      ];

  Widget _filtersBar(BuildContext context, List<PumpRow> all) {
    final t = Theme.of(context);
    final active = _filters.values.whereType<String>().length +
        _ranges.values.where((r) => r.$1.text.isNotEmpty || r.$2.text.isNotEmpty).length +
        (_onlyPriced ? 1 : 0) +
        (_onlyIssues ? 1 : 0);
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
          FilterChip(
            label: Text('فیلترها${active > 0 ? ' (${fa(active)})' : ''}'),
            selected: _showFilters,
            onSelected: (v) => setState(() => _showFilters = v),
            avatar: const Icon(Icons.tune_rounded, size: 18),
          ),
          const SizedBox(width: 6),
          TextButton.icon(onPressed: _clear, icon: const Icon(Icons.clear_all_rounded), label: const Text('پاک کردن')),
        ]),
        if (_showFilters) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final e in _enumFilters.entries) _enumFilter(context, all, e.key, e.value),
            for (final e in _ranges.entries) _rangeFilter(context, e.key, e.value),
            FilterChip(
              label: const Text('فقط دارای قیمت تعدیل‌شده'),
              selected: _onlyPriced,
              onSelected: (v) => setState(() => _onlyPriced = v),
            ),
            FilterChip(
              label: const Text('فقط دارای هشدار داده'),
              selected: _onlyIssues,
              onSelected: (v) => setState(() => _onlyIssues = v),
              selectedColor: Tones.warn(context).withValues(alpha: 0.2),
            ),
          ]),
          if (active == 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('هیچ فیلتری فعال نیست.',
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ),
        ],
      ]),
    );
  }

  Widget _enumFilter(BuildContext context, List<PumpRow> all, String key, String label) {
    final values = {for (final r in all) _val(r, key)}..remove('');
    final sorted = values.toList()..sort();
    final current = _filters[key];
    return SizedBox(
      width: 168,
      child: DropdownButtonFormField<String?>(
        value: sorted.contains(current) ? current : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: current != null ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
        ),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('همه')),
          for (final v in sorted)
            DropdownMenuItem<String?>(
              value: v,
              child: Text(_displayEnum(key, v), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => setState(() => _filters[key] = v),
      ),
    );
  }

  String _displayEnum(String key, String v) {
    if (key == 'include_in_totals' || key == 'nace') {
      return switch (v) { 'Y' => 'بله', 'N' => 'خیر', 'Not stated' => 'نامشخص', _ => v };
    }
    if (key == 'cost_year') return fa(v);
    return v;
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

  Widget _summary(BuildContext context, List<PumpRow> rows, MoneyUnit unit) {
    final priced = rows.where((r) => r.result.eurTarget.isNumber).toList();
    final eurs = priced.map((r) => r.result.eurTarget.number!).toList()..sort();
    final totalIrr = rows
        .where((r) => r.item.include && r.result.irrTarget.isNumber)
        .fold<double>(0, (s, r) => s + r.result.irrTarget.number! * (r.item.quantity ?? 1));
    final avg = eurs.isEmpty ? null : eurs.reduce((a, b) => a + b) / eurs.length;
    final median = eurs.isEmpty ? null : eurs[eurs.length ~/ 2];
    return Wrap(spacing: 10, runSpacing: 10, children: [
      KpiTile(label: 'تعداد نتایج', value: fa(rows.length), sub: '${fa(priced.length)} دارای قیمت تعدیل‌شده', icon: Icons.list_alt_rounded, width: 190),
      KpiTile(label: 'یورو تعدیل‌شده — کمینه / بیشینه', value: eurs.isEmpty ? '—' : '${compactNum(eurs.first)} / ${compactNum(eurs.last)}', icon: Icons.unfold_more_rounded, width: 250),
      KpiTile(label: 'یورو تعدیل‌شده — میانگین / میانه', value: avg == null ? '—' : '${compactNum(avg)} / ${compactNum(median!)}', icon: Icons.functions_rounded, width: 250),
      KpiTile(
        label: 'جمع ${unitLabel(unit)} (× تعداد، فقط شمارش‌شده‌ها)',
        value: money(totalIrr, unit, compact: true, withUnit: false),
        sub: unitLabel(unit),
        icon: Icons.account_balance_wallet_outlined,
        width: 280,
      ),
    ]);
  }

  Future<void> _exportCsv(BuildContext context, List<PumpRow> rows, MoneyUnit unit) async {
    final cols = _columns(unit).skip(1).toList();
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    final b = StringBuffer('﻿');
    b.writeln(cols.map((c) => esc(c.label)).join(','));
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
  const _CategoryPanel({required this.count});
  final int count;

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
      width: 250,
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        border: BorderDirectional(end: BorderSide(color: t.colorScheme.outlineVariant)),
      ),
      child: ListView(padding: const EdgeInsets.symmetric(vertical: 14), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('رده‌های تجهیزات', style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
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
