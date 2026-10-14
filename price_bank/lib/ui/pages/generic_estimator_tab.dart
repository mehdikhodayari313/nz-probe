// تخمین قیمت تجهیزات غیرپمپ: انتخاب رده ← مشخصات (پارامتر اندازه و پیکربندی) ← روش تخمین ← نتیجه و همتاها.

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/generic_estimator.dart';
import '../../core/catalog/profiles.dart';
import '../../core/price_bank.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
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
          DropdownButtonFormField<int?>(
            value: rows.any((r) => r.item.id == _fromItem) ? _fromItem : null,
            isExpanded: true,
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('—')),
              for (final r in rows)
                DropdownMenuItem<int?>(
                    value: r.item.id, child: Text('${r.item.tag ?? ''} · ${r.item.name}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() {
              final r = rows.where((r) => r.item.id == v).firstOrNull;
              if (r != null) _fill(r);
            }),
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
                : DropdownButtonFormField<String?>(
                    value: app.pb.catalog.options(f.list!).any((o) => o.value == _enum[f.key]) ? _enum[f.key] : null,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('—')),
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
        title: 'همتاها',
        subtitle: 'یورو نرمال‌شده = یوروی تعدیل‌شده ÷ ضریب پیکربندی · ضریب هزینه = یورو نرمال‌شده ÷ اندازه^n',
        icon: Icons.people_alt_outlined,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: e.peers.isEmpty
            ? const Padding(padding: EdgeInsets.all(8), child: Text('همتایی با اندازه و قیمت معتبر در این رده نیست.'))
            : Column(children: [
                for (var i = 0; i < e.peers.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    decoration: BoxDecoration(
                      color: e.nearest?.itemId == e.peers[i].itemId
                          ? AppColors.amberSoft
                          : (i.isOdd ? AppColors.zebra : null),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      SizedBox(
                        width: 100,
                        child: Text(e.peers[i].tag,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.right,
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.strong)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${e.peers[i].name} · ${e.peers[i].project}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
                      SizedBox(width: 110, child: Text('${faSmart(e.peers[i].size)} ${_p.driver.unit}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                      SizedBox(width: 110, child: Text('${compactNum(e.peers[i].normEur)} €', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.eur))),
                      SizedBox(width: 90, child: Text(faSmart(e.peers[i].coef), textAlign: TextAlign.end, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                    ]),
                  ),
              ]),
      ),
    ]);

    return ListView(padding: const EdgeInsets.all(20), children: [
      HelpPanel(
        id: 'generic_estimator',
        title: 'تخمین قیمت تجهیزات (غیرپمپ) چگونه کار می‌کند؟',
        initiallyOpen: false,
        lines: [
          'هر رده یک «پارامتر اندازه» دارد: ظرف و دیسالتر حجم (از قطر و طول TL-TL با دو عدسی ۲:۱)، مخزن حجم، مبدل و گرم‌کن توان حرارتی، دی‌اریتور/IGF/فیلتر/کمپرسور/خشک‌کن دبی، تزریق مواد نرخ تزریق، فلر ظرفیت، جرثقیل ظرفیت.',
          'قیمت ∝ اندازه^n (قانون توانی؛ n پیش‌فرض هر رده در «تنظیمات رده» صفحه‌ی تجهیزات قابل تغییر است).',
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
            : 'ضریب وزن = (وزن ویژه ÷ میانه‌ی رده)^m — توان m در «تنظیمات رده» یا صفحه‌ی «ضرایب»',
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
