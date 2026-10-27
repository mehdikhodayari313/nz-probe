// تخمین پکیج دیسالتر جدید — مطابق شیت Estimator بانک Desalters v8:
// سه روش کنار هم (A ظرفیت‌محور، B حجم‌محور، C نزدیک‌ترین مرجع) و نتیجه‌ی نهایی میانگین وزنی با وزن تعداد همتا.

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/desalter.dart';
import '../../core/calc/estimator.dart';
import '../../core/catalog/profiles.dart';
import '../../core/price_bank.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/factor_dialog.dart';
import '../widgets/data_grid.dart';
import '../widgets/help_info.dart';
import '../widgets/item_picker.dart';
import '../widgets/profile_columns.dart';
import '../help/topics.dart';
import 'generic_equipment.dart' show CategorySettingsDialog;
import 'estimator_page.dart';

class DesalterEstimatorTab extends StatefulWidget {
  const DesalterEstimatorTab({super.key, required this.picker});
  final Widget picker;

  @override
  State<DesalterEstimatorTab> createState() => _DesalterEstimatorTabState();
}

/// ورودی‌های انتخابی: (کلید، برچسب، فهرست، گروه ضریب)
const _enums = <(String, String, String, String?)>[
  ('sub_category', 'زیرگروه', 'DES_SUBCAT', null),
  ('desalting_technology', 'فناوری دیسالتر', 'DES_TECH', 'TECH'),
  ('des_material', 'متریال بدنه', 'DES_MAT', 'MAT'),
  ('nace', 'NACE MR0175', 'YNS', 'NACE'),
  ('no_of_stages', 'تعداد مرحله', 'DES_STAGE', 'STAGE'),
  ('scope_transformers', 'ترانس‌ها در قیمت', 'YNS', 'SC_TRF'),
  ('scope_recycle_pumps', 'پمپ‌های Recycle در قیمت', 'YNS', 'SC_PMP'),
  ('scope_related_piping', 'لوله‌کشی مربوط در قیمت', 'YNS', 'SC_PIP'),
  ('scope_instruments', 'ابزار دقیق و کنترل در قیمت', 'YNS', 'SC_INS'),
  ('scope_customs_transport', 'گمرک و حمل در قیمت', 'YNS', 'SC_CT'),
];

/// ورودی‌های عددی: (کلید، برچسب، واحد، مقدار پیش‌فرض)
const _nums = <(String, String, String?, String)>[
  ('capacity_bpd', 'ظرفیت کل پکیج', 'BPD', '60000'),
  ('vessel_id_mm', 'قطر داخلی وسل (ID)', 'mm', '3658'),
  ('vessel_tl_mm', 'طول TL-TL وسل', 'mm', '16764'),
  ('vessels_per_package', 'تعداد وسل در پکیج', null, '2'),
];

class _DesalterEstimatorTabState extends State<DesalterEstimatorTab> {
  // پیش‌فرض‌ها همان نمونه‌ی شیت Estimator بانک دیسالتر است
  final Map<String, String?> _enum = {
    'sub_category': 'PKG-DES-2S',
    'desalting_technology': 'Electrostatic AC/DC',
    'des_material': 'CS (SA-516 Gr.70)',
    'nace': 'Y',
    'no_of_stages': '2-stage',
    'scope_transformers': 'Y',
    'scope_recycle_pumps': 'Y',
    'scope_related_piping': 'Y',
    'scope_instruments': 'Y',
    'scope_customs_transport': 'N',
  };
  late final Map<String, TextEditingController> _num = {
    for (final (k, _, _, d) in _nums) k: TextEditingController(text: d),
  };
  final _kva = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _m3h = TextEditingController();
  final Map<String, double> _overrides = {};
  bool _match = false;
  bool _basisCapacity = false;
  int? _ref;
  bool _refInit = false;
  int? _fromItem;

  @override
  void dispose() {
    for (final c in [..._num.values, _kva, _qty, _m3h]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> get _values => {
        ..._enum,
        for (final (k, _, _, _) in _nums) k: parseUserNumber(_num[k]!.text),
      };

  static String _plain(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  void _fill(GenericRow r) {
    _fromItem = r.item.id;
    for (final (k, _, _, _) in _enums) {
      final v = r.item.values[k]?.toString();
      // Scope مشخصه‌ی قلم نیست (انتخاب کاربر برای قیمت)؛ اگر قلم مقدار ندارد، انتخاب فعلی می‌ماند
      if (v == null && desalterScopeFields.containsValue(k)) continue;
      _enum[k] = v;
    }
    for (final (k, _, _, _) in _nums) {
      final v = r.item.values[k];
      _num[k]!.text = v is num ? _plain(v.toDouble()) : '';
    }
    final d = r.des?.demandKva;
    _kva.text = d == null ? '' : _plain(d);
    _qty.text = (r.item.quantity ?? 1).toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final cat = app.pb.catalog.categoryByCode('DESALTER')!;
    final rows = app.genericRows(cat.id);
    final bank = rows.isEmpty ? null : rows.first.des?.bank;
    final setCode = factorSetOf('DESALTER');
    final params = app.settings.desalterParams;
    final unit = app.unit;

    // مرجع پیش‌فرض روش C: کوپال بنگستان (PK-121) مانند شیت Estimator، وگرنه اولین قلم دارای قیمت
    final refs = [for (final r in rows) if (r.des?.normEsc != null && r.item.include) r];
    if (!_refInit && refs.isNotEmpty) {
      _refInit = true;
      _ref = (refs.where((r) => r.item.legacyRef == 'DES-0002').firstOrNull ?? refs.first).item.id;
    }
    if (_ref != null && !refs.any((r) => r.item.id == _ref)) _ref = refs.isEmpty ? null : refs.first.item.id;

    final qty = parseUserNumber(_qty.text) ?? 1;
    final e = bank == null
        ? null
        : app.pb.estimateDesalterPackage(
            DesalterEstimateInput(
              values: _values,
              demandKva: parseUserNumber(_kva.text),
              matchSubCategory: _match,
              referenceId: _ref,
              basisCapacity: _basisCapacity,
              quantity: qty,
            ),
            bank,
            overrides: _overrides,
          );
    int countOf(String key, String v) => rows.where((r) => r.item.values[key]?.toString() == v).length;

    final inputs = SectionCard(
      title: 'مشخصات پکیج دیسالتر جدید',
      subtitle: 'پیش‌فرض‌ها یک دیسالتر نمونه است؛ مشخصات مورد نظر را جایگزین کنید',
      icon: Icons.tune_rounded,
      trailing: Wrap(spacing: 4, children: [
        TextButton.icon(
          onPressed: () => showDialog<void>(context: context, builder: (_) => const CategorySettingsDialog(code: 'DESALTER')),
          icon: const Icon(Icons.settings_suggest_outlined, size: 18),
          label: const Text('تنظیمات تخمین و تعدیل رده'),
        ),
        if (_overrides.isNotEmpty)
          TextButton.icon(
              onPressed: () => setState(_overrides.clear),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: Text('حذف ${fa(_overrides.length)} ضریب موردی')),
      ]),
      child: Column(children: [
        _row(context, 'رده‌ی تجهیز', widget.picker),
        _row(
          context,
          'پر کردن از یک قلم بانک (اختیاری)',
          PickButton(
            key: const Key('estimator-pick'),
            label: () {
              final r = rows.where((r) => r.item.id == _fromItem).firstOrNull;
              return r == null ? null : '${r.item.legacyRef ?? r.item.tag ?? ''} · ${r.item.name}';
            }(),
            onTap: () async {
              final r = await showItemPicker<GenericRow>(
                context,
                title: 'انتخاب دیسالتر از بانک',
                rows: rows,
                columns: profileColumns<GenericRow>(app, 'DESALTER', (r) => r, legacyRef: true, extra: [adjustedEurColumn()]),
                searchText: rowSearchText,
              );
              if (r != null && mounted) setState(() => _fill(r));
            },
          ),
          help: 'مشخصات یک دیسالتر موجود را به عنوان نقطه‌ی شروع وارد می‌کند؛ سپس هر مقدار را تغییر دهید.',
        ),
        const Divider(height: 20),
        for (final (k, label, list, g) in _enums) ...[
          if (k == desalterScopeFields.values.first) ...[
            const Divider(height: 20),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('دامنه‌ی قیمت (Scope) — فقط برای محاسبه‌ی قیمت؛ پایه: همه بله، گمرک و حمل خیر',
                  style: t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.strong)),
            ),
          ],
          _row(
            context,
            label,
            DropdownButtonFormField<String?>(
              itemHeight: null,
              value: app.pb.catalog.options(list).any((o) => o.value == _enum[k]) ? _enum[k] : null,
              isExpanded: true,
              items: [
                const DropdownMenuItem<String?>(value: null, child: DdText('—')),
                for (final o in app.pb.catalog.options(list))
                  DropdownMenuItem<String?>(
                    value: o.value,
                    child: desalterScopeFields.containsValue(k)
                        ? DdText(o.labelFa == null || o.labelFa == o.value ? o.value : o.labelFa!)
                        : CountedLabel(
                            o.labelFa == null || o.labelFa == o.value ? o.value : '${o.labelFa} (${o.value})',
                            countOf(k, o.value),
                            dimZero: false),
                  ),
              ],
              onChanged: (v) => setState(() => _enum[k] = v),
            ),
            trailing: g == null || e == null ? null : _factorChip(context, g, label, setCode, e),
          ),
        ],
        if (_enum['sub_category'] != null)
          SwitchListTile(
            value: _match,
            onChanged: (v) => setState(() => _match = v),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('فقط همتاهای هم‌زیرگروه'),
          ),
        const Divider(height: 20),
        for (final (k, label, u, _) in _nums)
          _row(
            context,
            '$label${u == null ? '' : ' ($u)'}',
            TextField(controller: _num[k], textDirection: TextDirection.ltr, onChanged: (_) => setState(() {})),
          ),
        _row(
          context,
          'یا ظرفیت به m³/h',
          TextField(
            controller: _m3h,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(hintText: 'تبدیل خودکار به BPD'),
            onChanged: (v) => setState(() {
              final m = parseUserNumber(v);
              if (m != null) _num['capacity_bpd']!.text = _plain(m * DesalterParams.bpdPerM3h);
            }),
          ),
          help: '۱ m³/h = ۲۴ × ۶٫۲۸۹۸۱ = ۱۵۰٫۹۶ بشکه در روز',
        ),
        _row(
          context,
          'توان لازم ترانس‌ها (kVA، اختیاری)',
          TextField(
            controller: _kva,
            enabled: params.kvaActive,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(hintText: params.kvaActive ? 'kVA ۱۰۰٪' : 'محرک kVA خاموش است'),
            onChanged: (_) => setState(() {}),
          ),
          trailing: e == null ? null : _plainChip(context, e.factors.kvaF),
          help: 'KVA_F = (kVA ÷ ${faSmart(params.kvaBase)})^${faSmart(params.kvaExponent)}؛ در «تنظیمات تخمین و تعدیل رده» فعال می‌شود.',
        ),
        const Divider(height: 20),
        _row(
          context,
          'روش C — قلم مرجع',
          DropdownButtonFormField<int?>(
            itemHeight: null,
            value: _ref,
            isExpanded: true,
            items: [
              for (final r in refs)
                DropdownMenuItem<int?>(
                    value: r.item.id,
                    child: DdText('${r.item.legacyRef ?? ''} · ${r.item.projectName ?? ''} · ${r.item.tag ?? ''}',
                        overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _ref = v),
          ),
        ),
        _row(
          context,
          'روش C — مبنای اندازه',
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('حجم پوسته')),
              ButtonSegment(value: true, label: Text('ظرفیت')),
            ],
            selected: {_basisCapacity},
            onSelectionChanged: (v) => setState(() => _basisCapacity = v.first),
          ),
        ),
        _row(context, 'تعداد (Set)',
            TextField(controller: _qty, textDirection: TextDirection.ltr, onChanged: (_) => setState(() {}))),
        if (e != null)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.petrol.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
            child: Text(
              'حجم کل پوسته = ${e.volume == null ? '—' : '${faSmart(e.volume)} m³'} · ALL_F = ${faSmart(e.factors.all)} · '
              'STAGE_F = ${faSmart(e.factors.stage)} · نماها n_A / n_B = ${faSmart(e.nA)} / ${faSmart(e.nB)}'
              '${e.kvaOn ? ' · kVA: m = ${faSmart(e.kvaExponent)}' : ' · kVA خاموش'}',
              style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, height: 1.8),
            ),
          ),
      ]),
    );

    Widget results;
    if (e == null) {
      results = SectionCard(
        title: 'نتیجه‌ی تخمین',
        icon: Icons.insights_rounded,
        child: Text('هنوز دیسالتری در بانک نیست. ابتدا فایل بانک قیمت دیسالتر را از داشبورد وارد کنید.',
            style: TextStyle(color: Tones.warn(context), height: 1.8)),
      );
    } else {
      final r = EstimatorResult()
        ..eurExpected = e.finalEur
        ..usdExpected = e.usd
        ..irrExpected = e.irr
        ..irrTotal = e.irrTotal
        ..eurRate = e.eurRate
        ..usdRate = e.usdRate;
      final ms = [e.a.eur, e.b.eur, e.eurC].whereType<double>().toList();
      if (ms.length > 1) {
        r.eurLow = ms.reduce((a, b) => a < b ? a : b);
        r.eurHigh = ms.reduce((a, b) => a > b ? a : b);
        if (e.eurRate != null) {
          r.irrLow = r.eurLow! * e.eurRate!;
          r.irrHigh = r.eurHigh! * e.eurRate!;
        }
      }
      results = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionCard(
          title: 'نتیجه‌ی تخمین',
          subtitle: '${DesalterParams.finalBasesFa[e.finalBasis]} · سال هدف ${fa(app.settings.targetYear)} · '
              'روش تعدیل ${app.settings.methodFor('DESALTER')} · بازه = کمینه تا بیشینه‌ی سه روش',
          icon: Icons.insights_rounded,
          child: e.finalEur == null
              ? Text('هیچ روشی نتیجه نداد؛ ظرفیت یا ابعاد و تعداد وسل را وارد کنید.',
                  style: TextStyle(color: Tones.warn(context), height: 1.8))
              : EstimateResultsView(r: r, unit: unit, qty: qty),
        ),
        const SizedBox(height: 14),
        _methodsCard(context, e),
      ]);
    }

    return ListView(padding: const EdgeInsets.all(20), children: [
      HelpPanel(
        id: 'desalter_estimator',
        title: 'تخمین پکیج دیسالتر چگونه کار می‌کند؟',
        initiallyOpen: false,
        lines: const [
          'روش A (ظرفیت‌محور): میانگین Coef A همتاها × BPD^n_A × ALL_F × STAGE_F. Coef A = یورو نرمال‌شده‌ی تعدیل‌شده ÷ STAGE_F ÷ BPD^n_A.',
          'روش B (حجم‌محور): میانگین Coef B همتاها × حجم کل پوسته^n_B × ALL_F. حجم = π/4 × ID² × T/T × تعداد وسل (فقط استوانه).',
          'روش C (نزدیک‌ترین مرجع): یورو نرمال‌شده‌ی قلم مرجع × (اندازه‌ی جدید ÷ اندازه‌ی مرجع)^n × ALL_F (برای مبنای ظرفیت × نسبت STAGE_F).',
          'نتیجه‌ی نهایی = میانگین وزنی روش‌های موجود؛ وزن A و B = تعداد همتا، وزن C = ۱ (یا میانگین ساده / یک روش، در «تنظیمات تخمین و تعدیل رده»).',
          'ALL_F = فناوری × متریال × NACE × پنج ضریب Scope × ضریب kVA. ضرایب «اولیه» هستند و در صفحه‌ی «ضرایب» کالیبره می‌شوند.',
          'همتاها: دیسالترهای «شمارش در جمع‌ها = بله» با قیمت تعدیل‌شده. اقلام تجمیعی و تکراری بانک (Include = N) همتا نیستند.',
        ],
      ),
      LayoutBuilder(builder: (context, c) {
        // کنار هم فقط وقتی جدول نتایج جا می‌شود (۵۰۰ ورودی + ≥ ۷۲۰ نتایج)
        if (c.maxWidth < 1240) return Column(children: [inputs, const SizedBox(height: 14), results]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 500, child: inputs),
          const SizedBox(width: 16),
          Expanded(child: results),
        ]);
      }),
      // جدول همتاها تمام‌عرض (ستون‌های مشخصات فنی جا شوند)
      if (e != null) ...[const SizedBox(height: 14), _peersCard(context, e, rows)],
    ]);
  }

  Widget _methodsCard(BuildContext context, DesalterEstimate e) {
    final t = Theme.of(context);
    final head = t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.strong);
    String pctOf(double? m) {
      final s = e.spread(m);
      if (s == null) return '—';
      return '${s > 0 ? '+' : ''}${faNum(s * 100, decimals: 0)}٪';
    }

    // جدول پهن (≥ ۷۲۰ پیکسل): ستونی؛ باریک: هر روش دو سطر تا متن عمودی و شکسته نشود.
    Widget line(bool narrow, String code, String name, int? peers, String coef, double? eurV, String range,
        {bool strong = false}) {
      final eurText = Text(eurV == null ? '—' : '${faNum(eurV)} €',
          textAlign: narrow ? TextAlign.end : TextAlign.center,
          style: TextStyle(fontSize: 12.5, fontWeight: strong ? FontWeight.w900 : FontWeight.w700, color: AppColors.eur));
      final deco = BoxDecoration(color: strong ? AppColors.amberSoft : null, borderRadius: BorderRadius.circular(8));
      final codeText = SizedBox(
          width: 28, child: Text(code, style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.petrol)));
      if (narrow) {
        final details = [
          if (peers != null) 'همتا ${fa(peers)}',
          if (coef.isNotEmpty && coef != '—') 'ضریب ${fa(coef)}',
          if (range.isNotEmpty) 'بازه ${fa(range)}',
          if (!strong && pctOf(eurV) != '—') 'اختلاف ${pctOf(eurV)}',
        ];
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
          decoration: deco,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              codeText,
              Expanded(child: Text(name, style: const TextStyle(fontSize: 12.5))),
              const SizedBox(width: 8),
              eurText,
            ]),
            if (details.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 28, top: 3),
                child: Text(details.join(' · '),
                    style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
          ]),
        );
      }
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        decoration: deco,
        child: Row(children: [
          codeText,
          Expanded(child: Text(name, style: const TextStyle(fontSize: 12.5))),
          SizedBox(width: 48, child: Text(peers == null ? '' : fa(peers), textAlign: TextAlign.center)),
          SizedBox(width: 140, child: Text(fa(coef), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          SizedBox(width: 120, child: eurText),
          SizedBox(width: 130, child: Text(fa(range), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5))),
          SizedBox(width: 56, child: Text(strong ? '' : pctOf(eurV), textAlign: TextAlign.end, style: const TextStyle(fontSize: 12))),
        ]),
      );
    }

    String rng(double? lo, double? hi) => lo == null || hi == null ? '' : '${compactNum(lo)} تا ${compactNum(hi)}';
    String cf(DesalterMethodResult m) =>
        m.coefAvg == null ? '—' : '${faSmart(m.coefAvg)}${m.peers > 1 ? ' (${compactNum(m.coefMin!)}–${compactNum(m.coefMax!)})' : ''}';
    return SectionCard(
      title: 'سه روش تخمین',
      subtitle: 'یورو هر دستگاه، سال هدف · اختلاف = نسبت به نتیجه‌ی نهایی',
      icon: Icons.alt_route_rounded,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 720;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!narrow)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            color: AppColors.headerBg,
            child: Row(children: [
              const SizedBox(width: 28),
              Expanded(child: Text('روش', style: head)),
              SizedBox(width: 48, child: Text('همتا', textAlign: TextAlign.center, style: head)),
              SizedBox(width: 140, child: Text('ضریب هزینه (کمینه–بیشینه)', textAlign: TextAlign.center, style: head)),
              SizedBox(width: 120, child: Text('یورو', textAlign: TextAlign.center, style: head)),
              SizedBox(width: 130, child: Text('بازه با ضریب همتاها', textAlign: TextAlign.center, style: head)),
              SizedBox(width: 56, child: Text('اختلاف', textAlign: TextAlign.end, style: head)),
            ]),
          ),
        line(narrow, 'A', 'ظرفیت‌محور (BPD^${faSmart(e.nA)})', e.a.peers, cf(e.a), e.a.eur, rng(e.a.low, e.a.high)),
        line(narrow, 'B', 'حجم‌محور (m³^${faSmart(e.nB)})', e.b.peers, cf(e.b), e.b.eur, rng(e.b.low, e.b.high)),
        line(
          narrow,
          'C',
          e.reference == null
              ? 'نزدیک‌ترین مرجع (انتخاب نشده)'
              : 'مرجع: ${e.reference!.record.label}${e.sizeRatio == null ? '' : ' · نسبت اندازه ${faSmart(e.sizeRatio)}'}',
          1,
          e.referenceNormEsc == null ? '—' : 'NormEsc ${compactNum(e.referenceNormEsc!)}',
          e.eurC,
          '',
        ),
        const Divider(height: 14),
        line(narrow, '', 'میانگین ساده‌ی روش‌ها', null, '', e.simpleAvg, ''),
        line(narrow, '', 'میانگین وزنی (وزن = تعداد همتا)', null, '', e.weightedAvg, ''),
        line(narrow, '', 'نتیجه‌ی نهایی — ${DesalterParams.finalBasesFa[e.finalBasis]}', null, '', e.finalEur, '', strong: true),
        for (final w in e.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('⚠ ${desalterWarningFa[w] ?? w}', style: TextStyle(color: Tones.warn(context), fontSize: 12.5)),
          ),
        _escalationNote(context, 'DESALTER'),
        ]);
      }),
    );
  }

  Widget _peersCard(BuildContext context, DesalterEstimate e, List<GenericRow> rows) {
    final app = AppScope.of(context);
    final byId = {for (final r in rows) r.item.id: r};
    final list = [for (final p in e.peers) (p, byId[p.record.id])];
    String n(double? v) => v == null ? '—' : faNum(v);
    return SectionCard(
      title: 'همتاها (${fa(e.peers.length)})',
      subtitle: 'یورو نرمال‌شده = یوروی تعدیل‌شده ÷ ALL_F · Coef A = NormEsc ÷ STAGE_F ÷ BPD^n · Coef B = NormEsc ÷ m³^n · '
          'روی هر ردیف بزنید تا گام‌های تعدیل همان همتا را ببینید',
      icon: Icons.people_alt_outlined,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: PeerTable<(DesalterCalc, GenericRow?)>(
        rows: list,
        highlight: (x) => e.reference?.record.id == x.$1.record.id,
        onTap: (x) => showCalcSteps(context,
            title: '${x.$2?.item.legacyRef ?? ''} · ${x.$1.record.label}',
            subtitle: 'گام‌های تعدیل قیمت این همتا به سال ${fa(app.settings.targetYear)} با روش ${app.settings.methodFor('DESALTER')}',
            steps: x.$1.price.steps),
        columns: profileColumns<(DesalterCalc, GenericRow?)>(app, 'DESALTER', (x) => x.$2, legacyRef: true, extra: [
          GridColumn(label: 'حجم کل\nm³', width: 76, numeric: true, text: (x) => n(x.$1.totalVolume), sortKey: (x) => x.$1.totalVolume),
          GridColumn(label: 'یورو\nنرمال‌شده', width: 100, numeric: true,
              text: (x) => x.$1.normEsc == null ? '—' : compactNum(x.$1.normEsc!), sortKey: (x) => x.$1.normEsc),
          GridColumn(label: 'Coef A', width: 80, numeric: true, text: (x) => faSmart(x.$1.coefA), sortKey: (x) => x.$1.coefA),
          GridColumn(label: 'Coef B', width: 80, numeric: true, text: (x) => faSmart(x.$1.coefB), sortKey: (x) => x.$1.coefB),
        ]),
      ),
    );
  }

  /// سطر «قیمت همتاها با روش … به سال هدف تعدیل شده‌اند» با ⓘ
  Widget _escalationNote(BuildContext context, String code) {
    final app = AppScope.of(context);
    final m = app.settings.methodFor(code);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        Icon(Icons.stairs_outlined, size: 16, color: AppColors.petrol),
        const SizedBox(width: 6),
        Expanded(
          child: Text('قیمت همتاها با روش $m به سال ${fa(app.settings.targetYear)} تعدیل شده است — روی هر همتا در جدول زیر بزنید تا گام‌هایش را ببینید.',
              style: Theme.of(context).textTheme.bodySmall),
        ),
        InfoButton(peerEscalationTopic(m, app.settings.targetYear), size: 14),
      ]),
    );
  }

  /// جدول با حداقل پهنا: در فضای باریک‌تر، اسکرول افقی به جای شکستن عمودی متن
  static Widget _minWidth(double w, Widget child) => LayoutBuilder(
        builder: (context, c) => c.maxWidth >= w
            ? child
            : SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: w, child: child)),
      );

  Widget _plainChip(BuildContext context, double v) => Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Text('× ${faSmart(v)}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.petrol)),
      );

  Widget _factorChip(BuildContext context, String g, String label, String setCode, DesalterEstimate e) {
    final (opt, val) = e.factors.parts[g] ?? (null, 1.0);
    final local = opt != null && _overrides.containsKey('$g|$opt');
    return Tooltip(
      message: opt == null ? 'ابتدا مقدار را انتخاب کنید (خالی = ضریب ۱)' : 'ضریب $label «$opt» — برای تغییر بزنید',
      child: Material(
        color: local ? AppColors.amberSoft : AppColors.petrol.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: opt == null
              ? null
              : () async {
                  final res = await showFactorDialog(context,
                      group: g, option: opt, label: label, localOverride: _overrides['$g|$opt'], setCode: setCode);
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
              if (help != null) InfoButton.text(label, help),
            ]),
          ),
          Expanded(child: field),
          const SizedBox(width: 8),
          SizedBox(width: 96, child: trailing),
        ]),
      );
}
