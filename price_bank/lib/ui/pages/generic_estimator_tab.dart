// تخمین قیمت تجهیزات غیرپمپ: انتخاب رده ← مشخصات (پارامتر اندازه و پیکربندی) ← روش تخمین ← نتیجه و همتاها.

import 'package:flutter/material.dart';
import 'generic_equipment.dart' show CategorySettingsDialog;

import '../../app/app_state.dart';
import '../../core/calc/generic_estimator.dart';
import '../../core/catalog/profiles.dart';
import '../../core/repo/catalog_repo.dart' show FieldType;
import '../../core/price_bank.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import '../widgets/equipment_columns.dart';
import '../widgets/item_picker.dart';
import '../widgets/factor_dialog.dart';
import 'estimator_page.dart';

/// تخمین یک رده‌ی غیرپمپ؛ [picker] انتخاب رده است (پمپ هم در آن هست) و بالای ورودی‌ها نمایش داده می‌شود.
class GenericEstimatorTab extends StatefulWidget {
  const GenericEstimatorTab({super.key, required this.code, required this.picker});
  final String code;
  final Widget picker;

  @override
  State<GenericEstimatorTab> createState() => _GenericEstimatorTabState();
}

const _factorField = {
  'MAT': 'material_class',
  'NACE': 'nace',
  'PRESS': 'design_pressure_barg',
  'LUBE': 'lubrication',
  'WEIGHT': weightFieldKey,
};
const _factorLabel = {'MAT': 'کلاس جنس', 'NACE': 'NACE', 'PRESS': 'فشار طراحی', 'LUBE': 'روغن‌کاری', 'WEIGHT': 'وزن'};

class _GenericEstimatorTabState extends State<GenericEstimatorTab> {
  String get _code => widget.code;
  final Map<String, TextEditingController> _num = {};
  final Map<String, String?> _enum = {};
  final Map<String, double> _overrides = {};
  final _qty = TextEditingController(text: '1');
  final _manual = TextEditingController();
  GenEstMethod? _method;
  bool _sameType = false;
  int? _fromItem;

  @override
  void dispose() {
    for (final c in [..._num.values, _qty, _manual]) {
      c.dispose();
    }
    super.dispose();
  }

  EquipmentProfile get _p => equipmentProfiles[_code]!;

  /// فیلدهای ورودی: مشخصات کلیدی عددی/انتخابی + فیلدهای مؤثر در ضرایب
  List<ProfileField> get _inputs {
    final keys = <String>{};
    final out = <ProfileField>[];
    for (final f in _p.fields) {
      if (f.group == 'key_specs' && (f.type == 'number' || f.type == 'enum')) {
        if (keys.add(f.key)) out.add(f);
      }
    }
    for (final g in _p.factorGroups) {
      final f = _p.field(_factorField[g]!);
      if (f != null && keys.add(f.key)) out.add(f);
    }
    return out;
  }

  TextEditingController _c(String key) => _num[key] ??= TextEditingController();

  Map<String, Object?> get _values => {
        for (final f in _inputs)
          f.key: f.type == 'number' ? parseUserNumber(_c(f.key).text) : _enum[f.key],
      };

  void _fill(GenericRow r) {
    _fromItem = r.item.id;
    for (final f in _inputs) {
      final v = r.item.values[f.key];
      if (f.type == 'number') {
        _c(f.key).text = v is num ? _plain(v.toDouble()) : (v?.toString() ?? '');
      } else {
        _enum[f.key] = v?.toString();
      }
    }
    _qty.text = (r.item.quantity ?? 1).toStringAsFixed(0);
  }

  /// ستون‌های جدول اقلام این رده (انتخاب قلم و همتاها) با سرستون مشخصات کلیدی
  List<GridColumn<T>> _columns<T>(AppState app, int catId, GenericRow? Function(T) rowOf, {List<GridColumn<T>> extra = const []}) {
    final fields = {for (final f in app.pb.catalog.fields(catId)) f.key: f};
    String txt(Object? v) => v is num ? faSmart(v) : (v?.toString() ?? '');
    return [
      GridColumn<T>(label: 'تگ', width: 100, ltr: true, notStated: true, text: (r) => rowOf(r)?.item.tag ?? '', sortKey: (r) => rowOf(r)?.item.tag ?? ''),
      GridColumn<T>(label: 'نام / سرویس', width: 190, fitMax: 300, align: TextAlign.start, ltr: true, text: (r) => rowOf(r)?.item.name ?? '', sortKey: (r) => rowOf(r)?.item.name ?? ''),
      GridColumn<T>(label: 'پروژه', width: 110, notStated: true, text: (r) => rowOf(r)?.item.projectName ?? '', sortKey: (r) => rowOf(r)?.item.projectName ?? ''),
      for (final k in _p.gridKeys)
        if (fields[k] case final f?)
          GridColumn<T>(
            label: '${f.labelFa}${f.unit == null ? '' : '\n${f.unit}'}',
            width: 92,
            numeric: f.type == FieldType.number,
            ltr: f.type != FieldType.number,
            text: (r) => txt(rowOf(r)?.item.values[k]),
            sortKey: (r) {
              final v = rowOf(r)?.item.values[k];
              if (f.type == FieldType.number) return v is num ? v.toDouble() : double.negativeInfinity;
              return v?.toString() ?? '';
            },
          ),
      GridColumn<T>(
          label: '${_p.driver.labelFa}\n${_p.driver.unit}', width: 92, numeric: true,
          text: (r) => faSmart(rowOf(r)?.size), sortKey: (r) => rowOf(r)?.size),
      costYearColumn<T>((r) => rowOf(r)!.item),
      ...extra,
    ];
  }

  Future<void> _pick(BuildContext context, AppState app, int catId, List<GenericRow> rows) async {
    final r = await showItemPicker<GenericRow>(
      context,
      title: 'انتخاب قلم از بانک (${app.pb.catalog.categoryByCode(_code)?.nameFa ?? ''})',
      rows: rows,
      columns: _columns<GenericRow>(app, catId, (r) => r, extra: [
        GridColumn<GenericRow>(
            label: 'یورو\nتعدیل‌شده', width: 100, numeric: true,
            text: (r) => faNum(r.result.eurTarget.number), sortKey: (r) => r.result.eurTarget.number),
      ]),
      searchText: (r) => [r.item.tag, r.item.name, r.item.projectName, ...r.item.values.values.map((v) => v?.toString())]
          .whereType<String>()
          .join(' '),
    );
    if (r == null || !mounted) return;
    setState(() => _fill(r));
  }

  static String _plain(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final cat = app.pb.catalog.categoryByCode(_code)!;
    final rows = app.genericRows(cat.id);
    int countOf(String key, String v) => rows.where((r) => r.item.values[key]?.toString() == v).length;
    final method = _method ?? GenEstMethod.byName(app.settings.catEstimation(_code));
    final est = app.pb.genericEstimator(_code, overrides: _overrides);
    final peers = app.pb.genericPeers(_code, rows);
    final qty = parseUserNumber(_qty.text) ?? 1;
    final e = est.estimate(
      values: _values,
      allPeers: peers,
      method: method,
      sameType: _sameType,
      manualCoef: parseUserNumber(_manual.text),
      quantity: qty,
    );
    final unit = app.unit;
    final setCode = factorSetOf(_code);
    final pe = app.pb.pumpEngine();
    final fx = (pe.eurRateTarget, pe.usdRateTarget);

    final inputs = SectionCard(
      title: 'مشخصات تجهیز مورد نظر',
      subtitle: 'پارامتر اندازه: ${_p.driver.labelFa} (${_p.driver.unit}) · قیمت ∝ اندازه^${faSmart(est.n)}',
      icon: Icons.tune_rounded,
      trailing: _overrides.isEmpty
          ? null
          : TextButton.icon(
              onPressed: () => setState(_overrides.clear),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: Text('حذف ${fa(_overrides.length)} ضریب موردی'),
            ),
      child: Column(children: [
        _row(context, 'رده‌ی تجهیز', widget.picker),
        _row(
          context,
          'پر کردن از یک قلم بانک (اختیاری)',
          PickButton(
            key: const Key('estimator-pick'),
            label: () {
              final r = rows.where((r) => r.item.id == _fromItem).firstOrNull;
              return r == null ? null : '${r.item.tag ?? ''} · ${r.item.name}';
            }(),
            onTap: () => _pick(context, app, cat.id, rows),
          ),
          help: 'مشخصات یک قلم موجود را به عنوان نقطه‌ی شروع وارد می‌کند؛ سپس هر مقدار را تغییر دهید.',
        ),
        const Divider(height: 20),
        for (final f in _inputs)
          _row(
            context,
            '${f.labelFa}${f.unit == null ? '' : ' (${f.unit})'}',
            f.type == 'number'
                ? TextField(controller: _c(f.key), textDirection: TextDirection.ltr, onChanged: (_) => setState(() {}))
                : DropdownButtonFormField<String?>(itemHeight: null, 
                    value: app.pb.catalog.options(f.list!).any((o) => o.value == _enum[f.key]) ? _enum[f.key] : null,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: DdText('—')),
                      for (final o in app.pb.catalog.options(f.list!))
                        DropdownMenuItem<String?>(
                            value: o.value,
                            child: CountedLabel(
                                o.labelFa == null || o.labelFa == o.value ? o.value : '${o.labelFa} (${o.value})',
                                countOf(f.key, o.value),
                                dimZero: false)),
                    ],
                    onChanged: (v) => setState(() => _enum[f.key] = v),
                  ),
            trailing: _factorChip(context, f.key, setCode, e),
          ),
        _row(context, 'تعداد (دستگاه)',
            TextField(controller: _qty, textDirection: TextDirection.ltr, onChanged: (_) => setState(() {}))),
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.petrol.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Icon(Icons.straighten_rounded, size: 18, color: AppColors.petrol),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                e.size == null
                    ? '${_p.driver.labelFa}: برای محاسبه، ابعاد/ظرفیت را وارد کنید'
                    : '${_p.driver.labelFa} = ${faSmart(e.size)} ${_p.driver.unit} · ضریب کل پیکربندی = ${faSmart(e.allF)}',
                style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ]),
        ),
      ]),
    );

    final methodCard = SectionCard(
      title: 'روش تخمین',
      icon: Icons.alt_route_rounded,
      trailing: TextButton.icon(
        onPressed: () => showDialog<void>(context: context, builder: (_) => CategorySettingsDialog(code: cat.code)),
        icon: const Icon(Icons.settings_suggest_outlined, size: 18),
        label: const Text('تنظیمات تخمین و تعدیل رده'),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final m in GenEstMethod.values)
          _MethodOption(
            method: m,
            selected: m == method,
            onTap: () => setState(() => _method = m),
          ),
        if (method == GenEstMethod.manual)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              controller: _manual,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: 'ضریب هزینه (یورو به ازای ${_p.driver.unit}^${faSmart(est.n)})'),
              onChanged: (_) => setState(() {}),
            ),
          ),
        if (_p.typeKey != null)
          SwitchListTile(
            value: _sameType,
            onChanged: (v) => setState(() => _sameType = v),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('فقط همتاهای هم‌نوع (${_p.field(_p.typeKey!)?.labelFa ?? ''})'),
          ),
      ]),
    );

    final results = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionCard(
        title: 'نتیجه‌ی تخمین',
        subtitle: '${cat.nameFa} · ${method.titleFa} · سال هدف ${fa(app.settings.targetYear)} · ${fa(e.peers.length)} همتا',
        icon: Icons.insights_rounded,
        child: e.res.eurExpected == null
            ? Text(e.note ?? '—', style: TextStyle(color: Tones.warn(context), height: 1.8))
            : EstimateResultsView(r: e.res, unit: unit, qty: qty),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: 'جزئیات محاسبه',
        icon: Icons.functions_rounded,
        child: Column(children: [
          _line(context, 'پارامتر اندازه', e.size == null ? '—' : '${_p.driver.labelFa} = ${faSmart(e.size)} ${_p.driver.unit}'),
          _line(context, 'ضریب کل پیکربندی', () {
            final parts = [
              for (final g in e.factors.entries)
                if (g.value.$1 != null) '${_factorLabel[g.key] ?? g.key} ${faSmart(g.value.$2)}',
            ].join(' × ');
            return parts.isEmpty ? faSmart(e.allF) : '$parts = ${faSmart(e.allF)}';
          }()),
          _line(context, 'ضریب هزینه‌ی همتاها (یورو/${_p.driver.unit}ⁿ)',
              e.res.coefAvg == null ? '—' : 'میانگین ${faSmart(e.res.coefAvg)} · کمینه ${faSmart(e.res.coefMin)} · بیشینه ${faSmart(e.res.coefMax)}'),
          _line(context, 'فرمول', 'ضریب هزینه × ${_p.driver.labelFa}^${faSmart(est.n)} × ضریب پیکربندی'),
          _line(context, 'نرخ یوروی سال هدف', fx.$1 == null ? 'وارد نشده' : '${faNum(fx.$1)} ریال'),
          _line(context, 'نرخ دلار سال هدف', fx.$2 == null ? 'وارد نشده' : '${faNum(fx.$2)} ریال'),
        ]),
      ),
    ]);
    // جدول همتاها تمام‌عرض زیر ورودی‌ها و نتیجه (ستون‌های مشخصات فنی جا شوند)
    final peersCard = SectionCard(
        title: 'همتاها',
        subtitle: 'یورو نرمال‌شده = یوروی تعدیل‌شده ÷ ضریب پیکربندی · ضریب هزینه = یورو نرمال‌شده ÷ اندازه^n · روی ستون‌ها بزنید تا مرتب شود',
        icon: Icons.people_alt_outlined,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: e.peers.isEmpty
            ? const Padding(padding: EdgeInsets.all(8), child: Text('همتایی با اندازه و قیمت معتبر در این رده نیست.'))
            : () {
                final byId = {for (final r in rows) r.item.id: r};
                final list = [for (final p in e.peers) (p, byId[p.itemId])];
                return PeerTable<(GenericPeer, GenericRow?)>(
                  rows: list,
                  highlight: (x) => e.nearest?.itemId == x.$1.itemId,
                  columns: _columns<(GenericPeer, GenericRow?)>(app, cat.id, (x) => x.$2, extra: [
                    GridColumn(
                        label: 'یورو\nنرمال‌شده', width: 100, numeric: true,
                        text: (x) => compactNum(x.$1.normEur), sortKey: (x) => x.$1.normEur),
                    GridColumn(
                        label: 'ضریب\nهزینه', width: 84, numeric: true,
                        text: (x) => faSmart(x.$1.coef), sortKey: (x) => x.$1.coef),
                  ]),
                );
              }(),
      );

    return ListView(padding: const EdgeInsets.all(20), children: [
      HelpPanel(
        id: 'generic_estimator',
        title: 'تخمین قیمت تجهیزات (غیرپمپ) چگونه کار می‌کند؟',
        initiallyOpen: false,
        lines: [
          'هر رده یک «پارامتر اندازه» دارد: ظرف و دیسالتر حجم (از قطر و طول TL-TL با دو عدسی ۲:۱)، مخزن حجم، مبدل و گرم‌کن توان حرارتی، دی‌اریتور/IGF/فیلتر/کمپرسور/خشک‌کن دبی، تزریق مواد نرخ تزریق، فلر ظرفیت، جرثقیل ظرفیت.',
          'قیمت ∝ اندازه^n (قانون توانی؛ n پیش‌فرض هر رده در «تنظیمات تخمین و تعدیل رده» (صفحه‌ی روش‌های تعدیل یا تخمین) قابل تغییر است).',
          'ضرایب جنس، NACE، فشار و روغن‌کاری قیمت همتاها را به پیکربندی پایه برمی‌گردانند و برای تجهیز جدید اعمال می‌شوند. روی «× ضریب» هر ردیف بزنید تا ویرایش شود.',
          'ظرف‌ها و مخازن (و دیسالتر، دی‌اریتور، IGF، فیلتر) فیلد اختیاری «وزن خالی» دارند. تا خالی است اثری ندارد؛ وقتی وزن این تجهیز و دست‌کم دو قلم بانک ثبت شود، «ضریب وزن» = (وزن ÷ اندازه ÷ میانه‌ی رده)^۰٫۸ اعمال می‌شود و جای ضریب فشار را می‌گیرد.',
          'سه روش: ضریب هزینه‌ی همتاها (میانگین همه)، نزدیک‌ترین همتا (شبیه‌ترین اندازه، بازه از سه همتای نزدیک)، ضریب دستی (وقتی همتا ندارید).',
          'ضرایب و توان‌ها فعلاً «اولیه (قضاوت مهندسی)» هستند؛ با ورود MTOهای بیشتر، در صفحه‌ی «ضرایب» کالیبره کنید.',
        ],
      ),
      LayoutBuilder(builder: (context, c) {
        final left = Column(children: [inputs, const SizedBox(height: 14), methodCard]);
        if (c.maxWidth < 1000) return Column(children: [left, const SizedBox(height: 14), results]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 480, child: left),
          const SizedBox(width: 16),
          Expanded(child: results),
        ]);
      }),
      const SizedBox(height: 14),
      peersCard,
    ]);
  }

  Widget? _factorChip(BuildContext context, String key, String setCode, GenericEstimate e) {
    final g = _factorField.entries.where((x) => x.value == key).map((x) => x.key).firstOrNull;
    if (g == null) return null;
    if (g == 'WEIGHT' ? _p.weightKey == null : !_p.factorGroups.contains(g)) return null;
    final (opt, val) = e.factors[g] ?? (null, 1.0);
    if (g == 'WEIGHT') {
      return Tooltip(
        message: opt == null
            ? 'وزن اختیاری است؛ تا خالی است ضریب وزن ۱ (بی‌اثر) است.\n'
                'وقتی وزن وارد شود و دست‌کم دو قلم این رده در بانک وزن داشته باشند:\n'
                'ضریب وزن = (وزن ÷ ${_p.driver.labelFa} ÷ میانه‌ی همین نسبت در رده)^m و جای ضریب فشار را می‌گیرد.'
            : 'ضریب وزن = (وزن ویژه ÷ میانه‌ی رده)^m — توان m در «تنظیمات تخمین و تعدیل رده» یا صفحه‌ی «ضرایب»',
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: opt == null ? null : AppColors.teal.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Text(opt == null ? 'بی‌اثر' : '× ${faSmart(val)}',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: opt == null ? Theme.of(context).colorScheme.outline : AppColors.teal)),
        ),
      );
    }
    if (g == 'PRESS' && e.factors['WEIGHT']?.$1 != null) {
      return Tooltip(
        message: 'وزن ثبت شده است؛ اثر فشار طراحی در ضخامت و وزن دیده شده و ضریب فشار اعمال نمی‌شود.',
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Text('در وزن', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
        ),
      );
    }
    final local = opt != null && _overrides.containsKey('$g|$opt');
    return Tooltip(
      message: opt == null ? 'ابتدا مقدار را انتخاب/وارد کنید' : 'ضریب ${_factorLabel[g]} «$opt» — برای تغییر بزنید',
      child: Material(
        color: local ? AppColors.amberSoft : AppColors.petrol.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: opt == null
              ? null
              : () async {
                  final res = await showFactorDialog(context,
                      group: g, option: opt, label: _factorLabel[g]!, localOverride: _overrides['$g|$opt'], setCode: setCode);
                  if (res == null || !mounted) return;
                  setState(() {
                    if (res.clearLocal) _overrides.remove('$g|$opt');
                    if (res.local != null) _overrides['$g|$opt'] = res.local!;
                  });
                },
          child: Container(
            height: 34,
            padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
            child: Row(children: [
              Text('× ${faSmart(val)}',
                  style: TextStyle(color: local ? AppColors.amberText : AppColors.petrol, fontWeight: FontWeight.w800, fontSize: 12.5)),
              const Spacer(),
              Icon(Icons.edit_rounded, size: 13, color: AppColors.petrol.withValues(alpha: 0.7)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _line(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 200, child: Text(k, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(v, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700))),
        ]),
      );

  Widget _row(BuildContext context, String label, Widget field, {Widget? trailing, String? help}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(
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
          ),
          Expanded(child: field),
          const SizedBox(width: 8),
          SizedBox(width: 96, child: trailing),
        ]),
      );
}

class _MethodOption extends StatelessWidget {
  const _MethodOption({required this.method, required this.selected, required this.onTap});
  final GenEstMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? AppColors.amberSoft : t.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? AppColors.amber : t.colorScheme.outlineVariant, width: selected ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 20, color: selected ? AppColors.amberText : t.colorScheme.outline),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(method.titleFa, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(method.helpFa, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.7)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
