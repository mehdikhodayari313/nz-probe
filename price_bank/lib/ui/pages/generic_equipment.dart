// فهرست اقلام یک رده‌ی غیرپمپ (ظرف، مخزن، پکیج، …) با قیمت تعدیل‌شده و آمار استعلام‌ها.

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/compressor.dart';
import '../../core/calc/desalter.dart';
import '../../core/calc/generic_estimator.dart';
import '../../core/calc/methods.dart';
import '../../core/catalog/profiles.dart';
import '../../core/price_bank.dart';
import '../../core/repo/catalog_repo.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import '../widgets/equipment_columns.dart';
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
        _onlyQuoted = false;
        _enumF.clear();
        for (final r in _rangeF.values) {
          r.$1.clear();
          r.$2.clear();
        }
      });

  /// [except]: فیلتری که برای شمارش گزینه‌های خودش نادیده گرفته می‌شود ('_project' = پروژه)
  bool _match(GenericRow r, {String? except}) {
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      final hay = [r.item.tag, r.item.name, r.item.projectName, r.item.remarks, ...r.item.values.values.map((v) => v?.toString())]
          .whereType<String>()
          .join(' ')
          .toLowerCase();
      if (!q.split(RegExp(r'\s+')).every(hay.contains)) return false;
    }
    if (_project != null && except != '_project') {
      final pn = r.item.projectName ?? '';
      if (_project == kEmptyOption ? pn.isNotEmpty : pn != _project) return false;
    }
    if (_onlyQuoted && r.quoteCount == 0) return false;
    for (final e in _enumF.entries) {
      if (e.value == null || e.key == except) continue;
      final v = r.item.values[e.key]?.toString() ?? '';
      if (e.value == kEmptyOption ? !isUnknownValue(v) : v != e.value) return false;
    }
    for (final e in _rangeF.entries) {
      final lo = parseUserNumber(e.value.$1.text), hi = parseUserNumber(e.value.$2.text);
      if (lo == null && hi == null) continue;
      if (e.key == '_cap') {
        if (!capacityInRange(AppScope.read(context).projectCapacity(r.item.projectId), lo, hi)) return false;
        continue;
      }
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
    // شمارش هر فیلتر بر پایه‌ی بقیه‌ی فیلترها: «همه» = تعداد ردیف‌های ممکن = جمع گزینه‌ها
    final forProject = all.where((r) => _match(r, except: '_project')).toList();
    final noProject = forProject.where((r) => (r.item.projectName ?? '').isEmpty).length;
    final totalIrr = rows
        .where((r) => r.item.include && r.result.irrTarget.isNumber)
        .fold<double>(0, (a, r) => a + r.result.irrTarget.number! * (r.item.quantity ?? 1));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(
          icon: _iconOf(cat.code),
          title: cat.nameFa,
          subtitle: '${cat.nameEn ?? ''} · ${fa(all.length)} قلم · قیمت‌ها تعدیل‌شده به سال ${fa(s.targetYear)} با روش ${s.methodFor(cat.code)}'
              '${s.methodFor(cat.code) == 'M7' ? ' (شاخص ترکیبی ${fa(mixLabel(s.catMix(cat.code)))})' : ''}',
          actions: [
            if (widget.onShowCategories != null)
              OutlinedButton.icon(
                onPressed: widget.onShowCategories,
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('رده‌ها'),
              ),
            _columnsMenu(context, cat.code, keySpecs, unit),
            OutlinedButton.icon(
              onPressed: rows.isEmpty ? null : () => _exportCsv(context, cat, rows, keySpecs, unit),
              icon: const Icon(Icons.download_rounded),
              label: const Text('خروجی CSV'),
            ),
            if (app.canEdit(cat.disciplineCode)) ...[
              OutlinedButton.icon(
                onPressed: () => showMtoImportDialog(context),
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('ورود MTO'),
              ),
              FilledButton.icon(
                key: const ValueKey('generic-new'),
                onPressed: () => _newItem(context, cat),
                icon: const Icon(Icons.add_rounded),
                label: const Text('تجهیز جدید'),
              ),
            ],
          ],
        ),
        HelpPanel(
          id: 'generic_equipment',
          title: 'راهنمای این صفحه',
          initiallyOpen: false,
          lines: [
            'اقلام این رده از فایل‌های MTO وارد می‌شوند: شرح، تعداد، قیمت مبنای مشاور، استعلام‌های فروشندگان و قیمت بازنگری قبلی.',
            '«قیمت مبنا» قیمت اصلی هر قلم است (معمولاً قیمت GOING مشاور). در صفحه‌ی هر قلم می‌توانید یکی از استعلام‌ها را مبنا قرار دهید.',
            'قیمت مبنا با روش ${s.methodFor(cat.code)} (روش همین رده) به سال ${fa(s.targetYear)} تعدیل می‌شود. در روش M6 کف قیمت فقط برای پمپ‌هاست؛ برای این رده M6 همان M4 است.',
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
                    TextSpan(text: ' از ${fa(all.length)} قلم · '),
                    TextSpan(
                        text: fa(rows.where((r) => r.result.eurTarget.isNumber).length),
                        style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.strong)),
                    TextSpan(text: ' با قیمت تعدیل‌شده · جمع: ${money(totalIrr, unit, compact: true)}'),
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
                  child: DropdownButtonFormField<String?>(itemHeight: null, 
                    value: projects.contains(_project) || (_project == kEmptyOption && noProject > 0) ? _project : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'پروژه'),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: CountedLabel('همه', forProject.length)),
                      for (final p in projects.toList()..sort())
                        DropdownMenuItem<String?>(
                            value: p, child: CountedLabel(p, forProject.where((r) => r.item.projectName == p).length)),
                      if (noProject > 0)
                        DropdownMenuItem<String?>(value: kEmptyOption, child: CountedLabel('بدون پروژه', noProject)),
                    ],
                    onChanged: (v) => setState(() => _project = v),
                  ),
                ),
                if (_profile != null)
                  for (final f in _profile!.enumFields)
                    _enumFilter(context, all.where((r) => _match(r, except: f.key)).toList(), f.key, f.labelFa, f.list),
              ]),
              if (_profile != null) ...[
                const SizedBox(height: 10),
                // بازه‌ها در یک سطر، عنوان چسبیده به کادرها (مثل پمپ‌ها)
                Wrap(spacing: 20, runSpacing: 8, children: [
                  _rangeFilter(context, '_size', '${_profile!.driver.labelFa} (${_profile!.driver.unit})'),
                  for (final k in _profile!.rangeKeys)
                    if (_profile!.field(k) case final f?)
                      _rangeFilter(context, k, '${f.labelFa}${f.unit == null ? '' : ' (${f.unit})'}'),
                  _rangeFilter(context, '_cap', capacityRangeLabel),
                ]),
              ] else ...[
                const SizedBox(height: 10),
                _rangeFilter(context, '_cap', capacityRangeLabel),
              ],
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
                    columns: [
                      for (final c in _columns(keySpecs, unit))
                        if (!(_hiddenCols[cat.code] ?? const {}).contains(c.label)) c,
                    ],
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
          cell: (c, r) => isNotStated(r.item.tag)
              ? notStatedCell(c, r.item.tag)
              : Text(r.item.tag!,
                  textDirection: TextDirection.ltr,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.strong)),
        ),
        GridColumn(label: 'نام / سرویس', width: 200, fitMax: 330, align: TextAlign.start, ltr: true, text: (r) => r.item.name, sortKey: (r) => r.item.name),
        GridColumn(label: 'پروژه', width: 110, notStated: true, text: (r) => r.item.projectName ?? '', sortKey: (r) => r.item.projectName ?? ''),
        capacityColumn<GenericRow>((r) => AppScope.read(context).projectCapacity(r.item.projectId)),
        for (final f in keySpecs)
          GridColumn(
            label: '${f.labelFa}${f.unit == null ? '' : '\n${f.unit}'}',
            width: f.type == FieldType.number ? 92 : 120,
            ltr: f.type != FieldType.number,
            numeric: f.type == FieldType.number,
            tooltip: f.labelEn,
            text: (r) {
              final v = r.item.values[f.key];
              if (v is num) return faSmart(v);
              return v?.toString() ?? '';
            },
            sortKey: (r) {
              final v = r.item.values[f.key];
              if (f.type == FieldType.number) return v is num ? v.toDouble() : double.negativeInfinity;
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
        costYearColumn<GenericRow>((r) => r.item),
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
    final (:counts, :empty) = countValues(all, (GenericRow r) => r.item.values[key]?.toString() ?? '');
    final opts = listKey == null ? const <EnumOption>[] : AppScope.read(context).pb.catalog.options(listKey);
    final labels = {for (final o in opts) o.value: o.labelFa};
    final values = [
      for (final o in opts)
        if (!isUnknownValue(o.value)) o.value,
      for (final v in counts.keys) if (!labels.containsKey(v)) v,
    ];
    if (empty > 0 || _enumF[key] == kEmptyOption) values.add(kEmptyOption);
    counts[kEmptyOption] = empty;
    final cur = _enumF[key];
    String show(String v) =>
        v == kEmptyOption ? kEmptyOptionLabel : ((labels[v] == null || labels[v] == v) ? v : '${labels[v]}');
    return SizedBox(
      width: 178,
      child: DropdownButtonFormField<String?>(itemHeight: null, 
        value: values.contains(cur) ? cur : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: labelFa,
          fillColor: cur != null ? t.colorScheme.primaryContainer : null,
        ),
        selectedItemBuilder: (_) => [const DdText('همه'), for (final v in values) DdText(show(v))],
        items: [
          DropdownMenuItem<String?>(value: null, child: DdText('همه (${fa(all.length)})')),
          for (final v in values)
            DropdownMenuItem<String?>(
              value: v,
              child: Row(children: [
                Expanded(
                  child: DdText(show(v),
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

  /// ستون‌های پنهان هر رده (بین اجراهای صفحه حفظ می‌شود)
  static final Map<String, Set<String>> _hiddenCols = {};

  /// انتخاب ستون‌های جدول (مثل پمپ‌ها)؛ تگ و نام همیشه دیده می‌شوند
  Widget _columnsMenu(BuildContext context, String code, List<FieldDef> keySpecs, MoneyUnit unit) => MenuAnchor(
        menuChildren: [
          for (final c in _columns(keySpecs, unit).skip(2))
            CheckboxMenuButton(
              value: !(_hiddenCols[code] ?? const {}).contains(c.label),
              onChanged: (v) => setState(() {
                final h = _hiddenCols.putIfAbsent(code, () => <String>{});
                v == true ? h.remove(c.label) : h.add(c.label);
              }),
              child: Text(c.label.replaceAll('\n', ' ')),
            ),
        ],
        builder: (context, ctl, _) => OutlinedButton.icon(
          onPressed: () => ctl.isOpen ? ctl.close() : ctl.open(),
          icon: const Icon(Icons.view_column_outlined),
          label: const Text('ستون‌ها'),
        ),
      );

  /// افزودن دستی تجهیز در همین رده (بند ۱۳): نام، تگ و پروژه؛ سپس صفحه‌ی قلم در حالت ویرایش
  Future<void> _newItem(BuildContext context, Category cat) async {
    final name = TextEditingController(), tag = TextEditingController(), project = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${cat.nameFa} جدید'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                key: const ValueKey('new-name'),
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'نام تجهیز / سرویس')),
            const SizedBox(height: 10),
            TextField(controller: tag, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'شماره تگ')),
            const SizedBox(height: 10),
            TextField(controller: project, decoration: const InputDecoration(labelText: 'پروژه')),
            const SizedBox(height: 8),
            Text('بقیه‌ی مشخصات و قیمت را پس از ایجاد در صفحه‌ی همین قلم وارد کنید.',
                style: Theme.of(ctx).textTheme.bodySmall),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, name.text.trim().isNotEmpty), child: const Text('ایجاد')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final app = AppScope.read(context);
    final p = project.text.trim();
    final id = app.pb.items.create(
      categoryId: cat.id,
      values: {'name': name.text.trim(), if (tag.text.trim().isNotEmpty) 'tag': tag.text.trim()},
      projectId: p.isEmpty ? null : app.pb.docs.ensureProject(p),
      reason: 'افزودن دستی',
    );
    app.dataChanged();
    if (!context.mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => GenericItemPage(itemId: id, startEditing: true)));
  }

  Widget _rangeFilter(BuildContext context, String key, String label) {
    final c = _range(key);
    return RangeFilter(label: label, from: c.$1, to: c.$2, onChanged: () => setState(() {}));
  }

  Future<void> _exportCsv(
      BuildContext context, Category cat, List<GenericRow> rows, List<FieldDef> keySpecs, MoneyUnit unit) async {
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    final b = StringBuffer('﻿');
    b.writeln([
      'تگ', 'نام', 'پروژه', capacityRangeLabel, for (final f in keySpecs) f.labelFa, 'تعداد', 'قیمت مبنا', 'ارز', 'سال',
      'تعداد استعلام', 'یورو تعدیل‌شده', '${unitLabel(unit)} تعدیل‌شده (واحد)',
    ].map(esc).join(','));
    for (final r in rows) {
      final o = r.item.primary;
      b.writeln([
        esc(r.item.tag ?? ''), esc(r.item.name), esc(r.item.projectName ?? ''),
        capacityColumn<GenericRow>((r) => AppScope.read(context).projectCapacity(r.item.projectId)).text(r),
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

  // سبد شاخص ترکیبی (M7)
  final List<(String?, TextEditingController)> _mix = [];
  bool _strict = false;

  // پارامترهای بانک دیسالتر
  final _desN = <String, TextEditingController>{};
  final _desB = <String, bool>{};
  String _desFinal = DesalterParams.weighted;
  bool get _isDes => widget.code == 'DESALTER';

  // پارامترهای بانک کمپرسور هوا
  final _cmpN = <String, TextEditingController>{};
  bool _cmpFit = false;
  String _cmpFinal = CompressorParams.weighted;
  bool get _isCmp => widget.code == 'COMPRESSOR';

  @override
  void initState() {
    super.initState();
    final s = AppScope.read(context).settings;
    for (final p in s.catMix(widget.code)) {
      _mix.add((p.series, TextEditingController(text: '${p.weight}')));
    }
    _strict = s.catMixStrict(widget.code);
    if (_isDes) {
      final d = s.desalterParams;
      for (final (k, v) in [('des_n_a', d.nA), ('des_n_b', d.nB), ('des_kva_m', d.kvaExponent), ('des_kva_base', d.kvaBase)]) {
        _desN[k] = TextEditingController(text: '$v');
      }
      _desB['des_fit_a'] = d.useFittedA;
      _desB['des_fit_b'] = d.useFittedB;
      _desB['des_kva_on'] = d.kvaActive;
      _desFinal = d.finalBasis;
    }
    if (_isCmp) {
      final c = s.compressorParams;
      for (final (k, v) in [('cmp_n', c.n), ('cmp_kw', c.specificPower), ('cmp_bench', c.benchmarkFactor), ('cmp_min_peers', c.minPeers)]) {
        _cmpN[k] = TextEditingController(text: '$v');
      }
      _cmpFit = c.useFitted;
      _cmpFinal = c.finalBasis;
    }
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
    for (final (_, c) in _mix) {
      c.dispose();
    }
    for (final c in [..._desN.values, ..._cmpN.values]) {
      c.dispose();
    }
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
    final mix = [
      for (final (code, c) in _mix)
        if (code != null && (parseUserNumber(c.text) ?? 0) > 0) MixPart(code, parseUserNumber(c.text)!),
    ];
    if (_desN.entries.any((e) => parseUserNumber(e.value.text) == null || parseUserNumber(e.value.text)! < 0)) {
      showSnack(context, 'پارامترهای دیسالتر باید عدد مثبت باشند.', error: true);
      return;
    }
    if (_cmpN.entries.any((e) => parseUserNumber(e.value.text) == null || parseUserNumber(e.value.text)! <= 0)) {
      showSnack(context, 'پارامترهای کمپرسور باید عدد مثبت باشند.', error: true);
      return;
    }
    app.pb.settingsRepo.set('cat_wexp_${widget.code}', w == null ? null : '$w', reason: 'تنظیمات رده');
    const reason = 'تنظیمات رده';
    final defMix = MixPart.format(defaultCategoryMix(widget.code));
    final newMix = MixPart.format(mix);
    app.pb.settingsRepo.set('cat_mix_${widget.code}', newMix == defMix ? null : newMix, reason: reason);
    app.pb.settingsRepo.set('cat_mixrule_${widget.code}', _strict ? 'Strict' : null, reason: reason);
    if (_isDes) {
      const def = DesalterParams();
      final defs = {'des_n_a': def.nA, 'des_n_b': def.nB, 'des_kva_m': def.kvaExponent, 'des_kva_base': def.kvaBase};
      for (final e in _desN.entries) {
        final v = parseUserNumber(e.value.text)!;
        app.pb.settingsRepo.set(e.key, v == defs[e.key] ? null : '$v', reason: reason);
      }
      for (final e in _desB.entries) {
        app.pb.settingsRepo.set(e.key, e.value ? 'Y' : null, reason: reason);
      }
      app.pb.settingsRepo.set('des_final', _desFinal == DesalterParams.weighted ? null : _desFinal, reason: reason);
    }
    if (_isCmp) {
      const def = CompressorParams();
      final defs = {'cmp_n': def.n, 'cmp_kw': def.specificPower, 'cmp_bench': def.benchmarkFactor, 'cmp_min_peers': def.minPeers};
      for (final e in _cmpN.entries) {
        final v = parseUserNumber(e.value.text)!;
        final s = e.key == 'cmp_min_peers' ? '${v.round()}' : '$v';
        app.pb.settingsRepo.set(e.key, v == defs[e.key] ? null : s, reason: reason);
      }
      app.pb.settingsRepo.set('cmp_fit', _cmpFit ? 'Y' : null, reason: reason);
      app.pb.settingsRepo.set('cmp_final', _cmpFinal == CompressorParams.weighted ? null : _cmpFinal, reason: reason);
    }
    app.pb.settingsRepo.set('cat_method_${widget.code}', _method, reason: reason);
    app.pb.settingsRepo.set('cat_ppi_${widget.code}', _ppi, reason: reason);
    app.pb.settingsRepo.set('cat_est_${widget.code}', _est, reason: reason);
    app.pb.settingsRepo.set('cat_n_${widget.code}', n == null ? null : '$n', reason: reason);
    app.dataChanged(calcInputs: true);
    Navigator.pop(context);
    showSnack(context, 'تنظیمات ذخیره شد؛ قیمت‌ها دوباره محاسبه شدند.');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final cat = app.pb.catalog.categoryByCode(widget.code)!;
    final p = equipmentProfiles[widget.code];
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
        Expanded(child: Text('تنظیمات تخمین و تعدیل: ${cat.nameFa}')),
      ]),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          row(
            'روش تعدیل این رده',
            DropdownButtonFormField<String?>(itemHeight: null, 
              value: _method,
              isExpanded: true,
              items: [
                DropdownMenuItem<String?>(
                    value: null, child: DdText('پیش‌فرض این رده (${defaultCategoryMethod(widget.code)})')),
                for (final m in [...escalationMethods.where((m) => m.selectable), compositeMethod])
                  DropdownMenuItem<String?>(value: m.code, child: DdText('${m.code} — ${m.nameFa}')),
              ],
              onChanged: (v) => setState(() => _method = v),
            ),
            help: 'هر تجهیز روش تعدیل خودش را دارد و روش پمپ‌ها روی آن اثر ندارد. '
                'کف قیمت M6 فقط برای پمپ‌هاست؛ در این رده M6 همان M4 است. M7 = شاخص ترکیبی با سبد پایین.'
                '${_isCmp ? ' M5 در این رده = PPI کمپرسور هوا و گاز آمریکا (BLS 333912) به یورو — گزینه‌ی BLS بانک کمپرسور.' : ''}',
          ),
          _mixEditor(context, app),
          row(
            'شاخص PPI (روش‌های M4/M6)',
            DropdownButtonFormField<String?>(itemHeight: null, 
              value: ppiSeries.any((x) => x.code == _ppi) ? _ppi : null,
              isExpanded: true,
              items: [
                const DropdownMenuItem<String?>(value: null, child: DdText('پیش‌فرض برنامه')),
                for (final x in ppiSeries)
                  DropdownMenuItem<String?>(value: x.code, child: DdText(x.nameFa, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _ppi = v),
            ),
            help: 'برای تجهیزات ساخت داخل (ظرف، مخزن، سازه) می‌توانید PPI بخشی ایران (مثلاً ISIC 25 محصولات فلزی) را انتخاب کنید؛ ابتدا مقادیر آن را در «شاخص‌ها و ارز» کامل کنید.',
          ),
          if (p != null) ...[
          if (!_isDes && !_isCmp)
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
          if (!_isDes && !_isCmp)
          row(
            'روش تخمین پیش‌فرض',
            DropdownButtonFormField<String?>(itemHeight: null, 
              value: _est,
              isExpanded: true,
              items: [
                for (final m in GenEstMethod.values) DropdownMenuItem<String?>(value: m.name, child: DdText(m.titleFa)),
              ],
              onChanged: (v) => setState(() => _est = v),
            ),
          ),
          if (_isDes) _desalterParams(context),
          if (_isCmp) _compressorParams(context),
          Text('پارامتر اندازه‌ی این رده: ${p.driver.labelFa} (${p.driver.unit}). ضرایب نرمال‌سازی: ${p.factorGroups.isEmpty ? 'ندارد' : p.factorGroups.join('، ')} — در صفحه‌ی «ضرایب».',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.8)),
          ] else
            Text('این رده قالب تخصصی (پارامتر اندازه) ندارد؛ فقط روش تعدیل و شاخص آن قابل تنظیم است.',
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.8)),
        ])),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: _save, child: const Text('ذخیره')),
      ],
    );
  }

  Widget _label(BuildContext context, String label, {String? help}) => SizedBox(
        width: 170,
        child: Row(children: [
          Flexible(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          if (help != null)
            Tooltip(
              message: help,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 4),
                child: Icon(Icons.info_outline_rounded, size: 14, color: Theme.of(context).colorScheme.outline),
              ),
            ),
        ]),
      );

  /// ویرایش سبد شاخص ترکیبی (روش M7): سری PPI + وزن
  Widget _mixEditor(BuildContext context, AppState app) {
    final t = Theme.of(context);
    final series = app.pb.indices.series().where((x) => x.group.startsWith('ppi')).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('سبد شاخص ترکیبی (روش M7)',
                style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800)),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _mix.add((null, TextEditingController()))),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('افزودن شاخص'),
          ),
          if (defaultCategoryMix(widget.code).isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                _mix
                  ..clear()
                  ..addAll([
                    for (final p in defaultCategoryMix(widget.code)) (p.series, TextEditingController(text: '${p.weight}')),
                  ]);
              }),
              child: const Text('سبد پیش‌فرض'),
            ),
        ]),
        if (_mix.isEmpty)
          Text('سبدی تعریف نشده؛ روش M7 برای این رده محاسبه نمی‌شود.',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
        for (var i = 0; i < _mix.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  itemHeight: null,
                  value: series.any((x) => x.code == _mix[i].$1) ? _mix[i].$1 : null,
                  isExpanded: true,
                  items: [
                    for (final x in series)
                      DropdownMenuItem<String?>(value: x.code, child: DdText(x.nameFa, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _mix[i] = (v, _mix[i].$2)),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _mix[i].$2,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(hintText: 'وزن'),
                ),
              ),
              IconButton(
                tooltip: 'حذف',
                onPressed: () => setState(() => _mix.removeAt(i).$2.dispose()),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ]),
          ),
        SwitchListTile(
          value: _strict,
          onChanged: (v) => setState(() => _strict = v),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('سخت‌گیرانه: اگر یکی از شاخص‌ها در سالی نباشد، تعدیل انجام نشود'),
          subtitle: const Text('خاموش = وزن‌ها روی شاخص‌های موجود بازتوزیع می‌شوند (Renormalize)'),
        ),
      ]),
    );
  }

  /// پارامترهای بانک کمپرسور هوا: نمای دبی، برازش، توان ویژه، بنچمارک E و مبنای نتیجه‌ی نهایی
  Widget _compressorParams(BuildContext context) {
    Widget num(String key, String label, {String? help}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            _label(context, label, help: help),
            Expanded(child: TextField(controller: _cmpN[key], textDirection: TextDirection.ltr)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Divider(height: 20),
      Text('پارامترهای بانک کمپرسور هوا', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      num('cmp_n', 'نمای دبی n', help: 'قیمت ∝ Nm³/h^n (روش A و C) — Provisional ۰٫۴ از دو رکورد گچساران'),
      SwitchListTile(
        value: _cmpFit,
        onChanged: (v) => setState(() => _cmpFit = v),
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: const Text('استفاده از n برازش‌شده از همتاها (حداقل ۳ نقطه، بین ۰٫۲ و ۱٫۰)'),
      ),
      num('cmp_kw', 'توان ویژه (kW به ازای Nm³/h)', help: 'فقط برای kW تخمینی و روش E'),
      num('cmp_bench', 'ضریب پکیج نفتی روش E', help: 'Seider × BLS 333912 × این ضریب — فقط کنترل'),
      num('cmp_min_peers', 'حداقل همتا پیش از هشدار'),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          _label(context, 'نتیجه‌ی نهایی تخمین'),
          Expanded(
            child: DropdownButtonFormField<String>(
              itemHeight: null,
              value: _cmpFinal,
              isExpanded: true,
              items: [
                for (final b in CompressorParams.finalBases)
                  DropdownMenuItem(value: b, child: DdText(CompressorParams.finalBasesFa[b]!)),
              ],
              onChanged: (v) => setState(() => _cmpFinal = v ?? CompressorParams.weighted),
            ),
          ),
        ]),
      ),
    ]);
  }

  /// پارامترهای بانک دیسالتر: نماها، برازش از داده‌ی بانک، محرک kVA و مبنای نتیجه‌ی نهایی تخمین
  Widget _desalterParams(BuildContext context) {
    Widget num(String key, String label, {String? help}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            _label(context, label, help: help),
            Expanded(child: TextField(controller: _desN[key], textDirection: TextDirection.ltr)),
          ]),
        );
    Widget sw(String key, String label) => SwitchListTile(
          value: _desB[key] ?? false,
          onChanged: (v) => setState(() => _desB[key] = v),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(label),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Divider(height: 20),
      Text('پارامترهای بانک دیسالتر', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      num('des_n_a', 'نمای ظرفیت n_A', help: 'قیمت ∝ BPD^n (روش A) — Provisional ۰٫۶'),
      sw('des_fit_a', 'استفاده از n_A برازش‌شده از داده‌ی بانک (حداقل ۳ نقطه، بین ۰٫۲ و ۱٫۲)'),
      num('des_n_b', 'نمای حجم n_B', help: 'قیمت ∝ m³^n (روش B) — Provisional ۰٫۶'),
      sw('des_fit_b', 'استفاده از n_B برازش‌شده از داده‌ی بانک'),
      sw('des_kva_on', 'محرک kVA فعال (KVA_F = (توان لازم ÷ مبنا)^m)'),
      num('des_kva_m', 'توان m محرک kVA'),
      num('des_kva_base', 'kVA مبنا'),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          _label(context, 'نتیجه‌ی نهایی تخمین'),
          Expanded(
            child: DropdownButtonFormField<String>(
              itemHeight: null,
              value: _desFinal,
              isExpanded: true,
              items: [
                for (final b in DesalterParams.finalBases)
                  DropdownMenuItem(value: b, child: DdText(DesalterParams.finalBasesFa[b]!)),
              ],
              onChanged: (v) => setState(() => _desFinal = v ?? DesalterParams.weighted),
            ),
          ),
        ]),
      ),
    ]);
  }
}
