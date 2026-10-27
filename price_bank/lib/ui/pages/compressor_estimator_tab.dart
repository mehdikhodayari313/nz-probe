// تخمین کمپرسور / پکیج هوای جدید — مطابق شیت Estimator بانک Air_Compressor v8:
// روش‌های A (توانی)، A2 (ثابت + متغیر)، B (وزن)، C (نزدیک‌ترین مرجع) کنار هم، E (بنچمارک Seider) فقط کنترل؛
// نتیجه‌ی نهایی میانگین وزنی با وزن تعداد همتا.

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/compressor.dart';
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

class CompressorEstimatorTab extends StatefulWidget {
  const CompressorEstimatorTab({super.key, required this.picker});
  final Widget picker;

  @override
  State<CompressorEstimatorTab> createState() => _CompressorEstimatorTabState();
}

/// ورودی‌های انتخابی: (کلید، برچسب، فهرست، گروه ضریب)
const _enums = <(String, String, String, String?)>[
  ('sub_category', 'زیرگروه', 'CMP_SUBCAT', null),
  ('compressor_type', 'نوع کمپرسور', 'CMP_TYPE', 'TYPE'),
  ('design_standard', 'استاندارد', 'CMP_STD', 'STD'),
  ('supply_origin', 'مبدأ ساخت', 'CMP_ORIGIN', 'ORIGIN'),
  ('driver', 'محرک', 'CMP_DRV', 'DRV'),
  ('scope_dryer', 'Scope: خشک‌کن هوا', 'YNS', 'SC_DRY'),
  ('scope_receiver', 'Scope: مخزن هوا', 'YNS', 'SC_REC'),
  ('scope_filters', 'Scope: فیلترهای Pre/After', 'YNS', 'SC_FLT'),
  ('scope_coolers', 'Scope: کولر میانی و انتهایی', 'YNS', 'SC_ACL'),
  ('scope_control_panel', 'Scope: پنل کنترل محلی', 'YNS', 'SC_PNL'),
  ('scope_spares', 'Scope: قطعات یدکی', 'YNS', 'SC_SPR'),
  ('scope_vendor_services', 'Scope: خدمات سازنده در سایت', 'YNS', 'SC_VS'),
  ('scope_transport', 'Scope: حمل تا سایت', 'YNS', 'SC_TRN'),
];

/// ورودی‌های عددی: (کلید، برچسب، واحد، مقدار پیش‌فرض)
const _nums = <(String, String, String?, String)>[
  ('flow_m3h', 'دبی هر کمپرسور', 'Nm³/h', '450'),
  ('discharge_pressure_barg', 'فشار رانش (اطلاعاتی)', 'barg', '9'),
  ('unit_weight_kg', 'وزن هر کمپرسور (اختیاری)', 'kg', '4500'),
  ('compressors_per_price_unit', 'تعداد کمپرسور در واحد قیمت', null, '1'),
];

class _CompressorEstimatorTabState extends State<CompressorEstimatorTab> {
  // پیش‌فرض‌ها همان نمونه‌ی شیت Estimator بانک کمپرسور است
  final Map<String, String?> _enum = {
    'sub_category': 'CMP-PKG',
    'compressor_type': 'Screw – oil-free',
    'design_standard': 'API 619',
    'supply_origin': 'Import',
    'driver': 'Electric Motor',
    'scope_dryer': 'N',
    'scope_receiver': 'N',
    'scope_filters': 'N',
    'scope_coolers': 'Y',
    'scope_control_panel': 'Y',
    'scope_spares': 'N',
    'scope_vendor_services': 'N',
    'scope_transport': 'N',
  };
  late final Map<String, TextEditingController> _num = {
    for (final (k, _, _, d) in _nums) k: TextEditingController(text: d),
  };
  final _qty = TextEditingController(text: '2');
  final Map<String, double> _overrides = {};
  bool _match = false;
  bool _basisWeight = false;
  int? _ref;
  bool _refInit = false;
  int? _fromItem;

  @override
  void dispose() {
    for (final c in [..._num.values, _qty]) {
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
      _enum[k] = r.item.values[k]?.toString();
    }
    for (final (k, _, _, _) in _nums) {
      final v = r.item.values[k];
      _num[k]!.text = v is num ? _plain(v.toDouble()) : '';
    }
    _qty.text = (r.item.quantity ?? 1).toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final cat = app.pb.catalog.categoryByCode('COMPRESSOR')!;
    final rows = app.genericRows(cat.id);
    final bank = rows.isEmpty ? null : rows.first.cmp?.bank;
    final setCode = factorSetOf('COMPRESSOR');
    final unit = app.unit;

    // مرجع پیش‌فرض روش C: گچساران PK-401 (ردیف ۴) مانند شیت Estimator، وگرنه اولین همتا
    final refs = [for (final r in rows) if (r.cmp?.normEsc != null && r.item.include) r];
    if (!_refInit && refs.isNotEmpty) {
      _refInit = true;
      _ref = (refs.where((r) => r.item.legacyRef == 'CMP-0004').firstOrNull ?? refs.first).item.id;
    }
    if (_ref != null && !refs.any((r) => r.item.id == _ref)) _ref = refs.isEmpty ? null : refs.first.item.id;

    final qty = parseUserNumber(_qty.text) ?? 1;
    final e = bank == null
        ? null
        : app.pb.estimateCompressorPackage(
            CompressorEstimateInput(
              values: _values,
              matchSubCategory: _match,
              referenceId: _ref,
              basisWeight: _basisWeight,
              quantity: qty,
            ),
            bank,
            overrides: _overrides,
          );
    int countOf(String key, String v) => rows.where((r) => r.item.values[key]?.toString() == v).length;

    final inputs = SectionCard(
      title: 'مشخصات کمپرسور / پکیج هوای جدید',
      subtitle: 'پیش‌فرض‌ها یک کمپرسور نمونه است؛ مشخصات مورد نظر را جایگزین کنید',
      icon: Icons.tune_rounded,
      trailing: Wrap(spacing: 4, children: [
        TextButton.icon(
          onPressed: () => showDialog<void>(context: context, builder: (_) => const CategorySettingsDialog(code: 'COMPRESSOR')),
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
                title: 'انتخاب کمپرسور / پکیج هوا از بانک',
                rows: rows,
                columns: profileColumns<GenericRow>(app, 'COMPRESSOR', (r) => r, legacyRef: true, extra: [adjustedEurColumn()]),
                searchText: rowSearchText,
              );
              if (r != null && mounted) setState(() => _fill(r));
            },
          ),
          help: 'مشخصات یک کمپرسور موجود را به عنوان نقطه‌ی شروع وارد می‌کند؛ سپس هر مقدار را تغییر دهید.',
        ),
        const Divider(height: 20),
        for (final (k, label, list, g) in _enums)
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
                    child: CountedLabel(
                        o.labelFa == null || o.labelFa == o.value ? o.value : '${o.labelFa} (${o.value})', countOf(k, o.value),
                        dimZero: false),
                  ),
              ],
              onChanged: (v) => setState(() => _enum[k] = v),
            ),
            trailing: g == null || e == null ? null : _factorChip(context, g, label, setCode, e),
          ),
        if (_enum['sub_category'] != null)
          SwitchListTile(
            value: _match,
            onChanged: (v) => setState(() => _match = v),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('فقط همتاهای هم‌زیرگروه (روش‌های A و B)'),
          ),
        const Divider(height: 20),
        for (final (k, label, u, _) in _nums)
          _row(
            context,
            '$label${u == null ? '' : ' ($u)'}',
            TextField(controller: _num[k], textDirection: TextDirection.ltr, onChanged: (_) => setState(() {})),
            help: k == 'compressors_per_price_unit' ? 'پکیج کمپرسور = ۱؛ پکیج کامل ۲×۱۰۰٪ = ۲ (قیمت برای کل واحد قیمت).' : null,
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
              ButtonSegment(value: false, label: Text('دبی')),
              ButtonSegment(value: true, label: Text('وزن')),
            ],
            selected: {_basisWeight},
            onSelectionChanged: (v) => setState(() => _basisWeight = v.first),
          ),
        ),
        _row(context, 'تعداد (واحد قیمت)',
            TextField(controller: _qty, textDirection: TextDirection.ltr, onChanged: (_) => setState(() {}))),
        if (e != null)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.petrol.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
            child: Text(
              'ALL_F = ${faSmart(e.factors.all)} · نمای دبی n = ${faSmart(e.n)} · '
              'توان محور تخمینی = ${e.shaftKw == null ? '—' : '${faSmart(e.shaftKw)} kW'}'
              '${e.hp == null ? '' : ' (${faSmart(e.hp)} hp)'}',
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
        child: Text('هنوز کمپرسوری در بانک نیست. ابتدا فایل بانک قیمت کمپرسور را از داشبورد وارد کنید.',
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
      final ms = [e.a.eur, e.eurA2, e.b.eur, e.eurC].whereType<double>().toList();
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
          title: 'نتیجه‌ی تخمین (هر واحد قیمت)',
          subtitle: '${CompressorParams.finalBasesFa[e.finalBasis]} · سال هدف ${fa(app.settings.targetYear)} · '
              'روش تعدیل ${app.settings.methodFor('COMPRESSOR')} · بازه = کمینه تا بیشینه‌ی روش‌های A، A2، B و C',
          icon: Icons.insights_rounded,
          child: e.finalEur == null
              ? Text('هیچ روشی نتیجه نداد؛ دبی یا وزن را وارد کنید.', style: TextStyle(color: Tones.warn(context), height: 1.8))
              : EstimateResultsView(r: r, unit: unit, qty: qty),
        ),
        const SizedBox(height: 14),
        _methodsCard(context, e),
      ]);
    }

    return ListView(padding: const EdgeInsets.all(20), children: [
      HelpPanel(
        id: 'compressor_estimator',
        title: 'تخمین کمپرسور هوا چگونه کار می‌کند؟',
        initiallyOpen: false,
        lines: const [
          'همه‌ی قیمت‌های بانک به «هر کمپرسور، پیکربندی پایه، سال هدف» نرمال می‌شوند: یورو ÷ تعداد کمپرسور در واحد قیمت ÷ ALL_F.',
          'روش A (توانی): میانگین Coef A همتاها × دبی^n × ALL_F × تعداد کمپرسور. Coef A = یورو نرمال‌شده ÷ دبی^n.',
          'روش A2 (ثابت + متغیر): رگرسیون خطی a + b × دبی روی همه‌ی همتاها؛ بخش ثابت بزرگ پکیج‌های کوچک را نشان می‌دهد.',
          'روش B (وزن): میانگین یورو بر کیلوگرم همتاها × وزن × ALL_F × تعداد کمپرسور.',
          'روش C (نزدیک‌ترین مرجع): یورو نرمال‌شده‌ی قلم مرجع × (اندازه‌ی جدید ÷ مرجع)^n × ALL_F × تعداد کمپرسور.',
          'روش E (فقط کنترل): رابطه‌ی Seider برای اسکرو با موتور برقی × شاخص BLS 333912 × ضریب پکیج نفتی؛ در نتیجه‌ی نهایی نیست.',
          'نتیجه‌ی نهایی = میانگین وزنی: وزن A و B = تعداد همتا، A2 = تعداد نقاط برازش، C = ۱ (قابل تغییر در «تنظیمات تخمین و تعدیل رده»).',
          'ALL_F = نوع × استاندارد × مبدأ × محرک × ۸ ضریب Scope. خشک‌کن × مخزن × فیلتر = ۱٫۵۳ (تصمیم ۱۴۰۵/۰۷/۲۳).',
          'همتاها: «شمارش در جمع‌ها = بله» و «همتای تخمین = بله» با دبی و قیمت. کوپال (پرت) و رکوردهای تاریخی و یکجا همتا نیستند.',
        ],
      ),
      LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 1000) return Column(children: [inputs, const SizedBox(height: 14), results]);
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

  Widget _methodsCard(BuildContext context, CompressorEstimate e) {
    final t = Theme.of(context);
    final head = t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.strong);
    String pctOf(double? m) {
      final s = e.spread(m);
      if (s == null) return '—';
      return '${s > 0 ? '+' : ''}${faNum(s * 100, decimals: 0)}٪';
    }

    Widget line(String code, String name, int? peers, String coef, double? eurV, String range, {bool strong = false}) =>
        Container(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
          decoration: BoxDecoration(
            color: strong ? AppColors.amberSoft : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            SizedBox(width: 34, child: Text(code, style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.petrol))),
            Expanded(child: Text(name, style: const TextStyle(fontSize: 12.5))),
            SizedBox(width: 56, child: Text(peers == null ? '' : fa(peers), textAlign: TextAlign.center)),
            SizedBox(width: 150, child: Text(fa(coef), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
            SizedBox(
              width: 120,
              child: Text(eurV == null ? '—' : '${faNum(eurV)} €',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, fontWeight: strong ? FontWeight.w900 : FontWeight.w700, color: AppColors.eur)),
            ),
            SizedBox(width: 150, child: Text(fa(range), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5))),
            SizedBox(width: 56, child: Text(strong ? '' : pctOf(eurV), textAlign: TextAlign.end, style: const TextStyle(fontSize: 12))),
          ]),
        );
    String rng(double? lo, double? hi) => lo == null || hi == null ? '' : '${compactNum(lo)} تا ${compactNum(hi)}';
    String cf(CompressorMethodResult m) =>
        m.coefAvg == null ? '—' : '${faSmart(m.coefAvg)}${m.peers > 1 ? ' (${compactNum(m.coefMin!)}–${compactNum(m.coefMax!)})' : ''}';
    return SectionCard(
      title: 'روش‌های تخمین',
      subtitle: 'یورو هر واحد قیمت، سال هدف · اختلاف = نسبت به نتیجه‌ی نهایی',
      icon: Icons.alt_route_rounded,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          color: AppColors.headerBg,
          child: Row(children: [
            const SizedBox(width: 34),
            Expanded(child: Text('روش', style: head)),
            SizedBox(width: 56, child: Text('همتا', textAlign: TextAlign.center, style: head)),
            SizedBox(width: 150, child: Text('ضریب هزینه (کمینه–بیشینه)', textAlign: TextAlign.center, style: head)),
            SizedBox(width: 120, child: Text('یورو', textAlign: TextAlign.center, style: head)),
            SizedBox(width: 150, child: Text('بازه با ضریب همتاها', textAlign: TextAlign.center, style: head)),
            SizedBox(width: 56, child: Text('اختلاف', textAlign: TextAlign.end, style: head)),
          ]),
        ),
        line('A', 'توانی (Nm³/h^${faSmart(e.n)})', e.a.peers, cf(e.a), e.a.eur, rng(e.a.low, e.a.high)),
        line('A2', 'ثابت + متغیر (a + b × دبی)', e.a2Points,
            e.a2Slope == null ? '—' : 'a ${compactNum(e.a2Fixed!)} · b ${faSmart(e.a2Slope)}', e.eurA2, ''),
        line('B', 'وزن‌محور (€/kg)', e.b.peers, cf(e.b), e.b.eur, rng(e.b.low, e.b.high)),
        line(
          'C',
          e.reference == null
              ? 'نزدیک‌ترین مرجع (انتخاب نشده)'
              : 'مرجع: ${e.reference!.record.label}${e.sizeRatio == null ? '' : ' · نسبت اندازه ${faSmart(e.sizeRatio)}'}',
          1,
          e.referenceNormEsc == null ? '—' : 'NormEsc ${compactNum(e.referenceNormEsc!)}',
          e.eurC,
          '',
        ),
        line('E', 'بنچمارک Seider × BLS 333912 (فقط کنترل)', null,
            e.blsTarget == null ? 'BLS سال هدف نیست' : 'BLS ${faSmart(e.blsTarget)}', e.eurE, ''),
        const Divider(height: 14),
        line('', 'میانگین ساده‌ی روش‌ها (A، A2، B، C)', null, '', e.simpleAvg, ''),
        line('', 'میانگین وزنی (وزن = تعداد همتا)', null, '', e.weightedAvg, ''),
        line('', 'نتیجه‌ی نهایی — ${CompressorParams.finalBasesFa[e.finalBasis]}', null, '', e.finalEur, '', strong: true),
        for (final w in e.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('⚠ ${compressorWarningFa(w)}', style: TextStyle(color: Tones.warn(context), fontSize: 12.5)),
          ),
        _escalationNote(context),
      ]),
    );
  }

  /// سطر «قیمت همتاها با روش … به سال هدف تعدیل شده‌اند» با ⓘ
  Widget _escalationNote(BuildContext context) {
    final app = AppScope.of(context);
    final m = app.settings.methodFor('COMPRESSOR');
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

  Widget _peersCard(BuildContext context, CompressorEstimate e, List<GenericRow> rows) {
    final app = AppScope.of(context);
    final byId = {for (final r in rows) r.item.id: r};
    final list = [for (final p in e.peers) (p, byId[p.record.id])];
    String n(double? v) => v == null ? '—' : faNum(v);
    return SectionCard(
      title: 'همتاها (${fa(e.peers.length)})',
      subtitle: 'یورو نرمال‌شده = یوروی تعدیل‌شده ÷ تعداد کمپرسور ÷ ALL_F · Coef A = NormEsc ÷ دبی^n · Coef B = NormEsc ÷ kg · '
          'روی هر ردیف بزنید تا گام‌های تعدیل همان همتا را ببینید',
      icon: Icons.people_alt_outlined,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: PeerTable<(CompressorCalc, GenericRow?)>(
        rows: list,
        highlight: (x) => e.reference?.record.id == x.$1.record.id,
        onTap: (x) => showCalcSteps(context,
            title: '${x.$2?.item.legacyRef ?? ''} · ${x.$1.record.label}',
            subtitle: 'گام‌های تعدیل قیمت این همتا به سال ${fa(app.settings.targetYear)} با روش ${app.settings.methodFor('COMPRESSOR')}',
            steps: x.$1.price.steps),
        columns: profileColumns<(CompressorCalc, GenericRow?)>(app, 'COMPRESSOR', (x) => x.$2, legacyRef: true, extra: [
          GridColumn(label: 'دبی\nNm³/h', width: 76, numeric: true, text: (x) => n(x.$1.flow), sortKey: (x) => x.$1.flow),
          GridColumn(label: 'وزن\nkg', width: 72, numeric: true, text: (x) => n(x.$1.weight), sortKey: (x) => x.$1.weight),
          GridColumn(label: 'یورو\nنرمال‌شده', width: 100, numeric: true,
              text: (x) => x.$1.normEsc == null ? '—' : compactNum(x.$1.normEsc!), sortKey: (x) => x.$1.normEsc),
          GridColumn(label: 'Coef A', width: 80, numeric: true, text: (x) => faSmart(x.$1.coefA), sortKey: (x) => x.$1.coefA),
          GridColumn(label: 'Coef B', width: 80, numeric: true, text: (x) => faSmart(x.$1.coefB), sortKey: (x) => x.$1.coefB),
        ]),
      ),
    );
  }

  Widget _factorChip(BuildContext context, String g, String label, String setCode, CompressorEstimate e) {
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
