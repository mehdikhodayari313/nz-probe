import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/estimator.dart';
import '../../core/calc/pump_engine.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';

class EstimatorPage extends StatefulWidget {
  const EstimatorPage({super.key});

  @override
  State<EstimatorPage> createState() => _EstimatorPageState();
}

class _EstimatorPageState extends State<EstimatorPage> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Material(
        color: Theme.of(context).colorScheme.surface,
        child: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.auto_graph_rounded), text: 'تخمین قیمت پمپ جدید (از روی همتاها)'),
            Tab(icon: Icon(Icons.trending_up_rounded), text: 'انتقال قیمت قدیم به سال هدف (M6)'),
          ],
        ),
      ),
      Expanded(child: TabBarView(controller: _tabs, children: const [_NewPumpEstimator(), _TransferCalculator()])),
    ]);
  }
}

// =============================================================================
// تخمین پمپ جدید

class _NewPumpEstimator extends StatefulWidget {
  const _NewPumpEstimator();

  @override
  State<_NewPumpEstimator> createState() => _NewPumpEstimatorState();
}

class _NewPumpEstimatorState extends State<_NewPumpEstimator> {
  // مقادیر پیش‌فرض = مثال شیت Estimator فایل v8 (برای مقایسه با اکسل)
  final Map<String, String> _p = {
    'sub_category': 'ROT-INJ',
    'match': 'Y',
    'pump_standard': 'API 610',
    'pump_family': 'Centrifugal',
    'api610_type': 'BB3',
    'material_class': 'D-2',
    'seal_arrangement': 'Arr 2 - Dual Unpressurized',
    'api682_category': 'Cat 2',
    'api682_plan': '11+52',
    'driver_type': 'Electric Motor',
    'nace': 'Y',
    'scope_driver': 'Y',
    'scope_baseplate': 'Y',
    'scope_seal_support': 'Y',
    'scope_comm_spares': 'Y',
    'scope_2yr_spares': 'N',
    'scope_tpi': 'Y',
    'scope_fat': 'N',
  };
  final _kw = TextEditingController();
  final _q = TextEditingController(text: '80');
  final _h = TextEditingController(text: '600');
  final _qty = TextEditingController(text: '2');

  static const _params = <(String, String, String)>[
    ('sub_category', 'زیرگروه', 'SubCat'),
    ('match', 'فقط همتاهای همین زیرگروه؟', 'YN'),
    ('pump_standard', 'استاندارد پمپ', 'Std'),
    ('pump_family', 'خانواده پمپ', 'Family'),
    ('api610_type', 'نوع API 610 (اطلاعاتی)', 'API610'),
    ('material_class', 'کلاس متریال', 'MAT'),
    ('seal_arrangement', 'آرایش آب‌بند', 'SEAL_ARR'),
    ('api682_category', 'گروه API 682', 'SEAL_CAT'),
    ('api682_plan', 'پلن آب‌بندی', 'SEAL_PLAN'),
    ('driver_type', 'محرک', 'DRV'),
    ('nace', 'NACE MR0175', 'YNS'),
    ('scope_driver', 'Scope: محرک', 'YNS'),
    ('scope_baseplate', 'Scope: شاسی و کوپلینگ', 'YNS'),
    ('scope_seal_support', 'Scope: سیستم آب‌بند', 'YNS'),
    ('scope_comm_spares', 'Scope: یدکی راه‌اندازی', 'YNS'),
    ('scope_2yr_spares', 'Scope: یدکی دوساله', 'YNS'),
    ('scope_tpi', 'Scope: بازرسی شخص ثالث', 'YNS'),
    ('scope_fat', 'Scope: آزمون کارخانه با حضور', 'YNS'),
  ];

  @override
  void dispose() {
    for (final c in [_kw, _q, _h, _qty]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final engine = app.pb.pumpEngine();
    final peers = app.pb.peersFrom(app.pumps);
    final r = PumpEstimator(engine).estimate(
      EstimatorInput(
        subCategory: _p['sub_category']!,
        matchSubCategory: _p['match'] == 'Y',
        standard: _p['pump_standard']!,
        family: _p['pump_family']!,
        spec: _p,
        powerKw: parseUserNumber(_kw.text),
        capacity: parseUserNumber(_q.text),
        head: parseUserNumber(_h.text),
        quantity: parseUserNumber(_qty.text) ?? 1,
      ),
      peers,
    );
    final unit = app.unit;
    final f = app.pb.factorTable;
    double factorOf(String key, String v) => switch (key) {
          'material_class' => f.get('MAT', v),
          'seal_arrangement' => f.get('SEAL_ARR', v),
          'api682_category' => f.get('SEAL_CAT', v),
          'api682_plan' => f.get('SEAL_PLAN', v),
          'driver_type' => f.get('DRV', v),
          'nace' => f.get('NACE', v),
          'scope_driver' => f.get('SC_DRV', v),
          'scope_baseplate' => f.get('SC_BSP', v),
          'scope_seal_support' => f.get('SC_SEAL', v),
          'scope_comm_spares' => f.get('SC_COMM', v),
          'scope_2yr_spares' => f.get('SC_2Y', v),
          'scope_tpi' => f.get('SC_TPI', v),
          'scope_fat' => f.get('SC_FAT', v),
          _ => double.nan,
        };

    final inputs = SectionCard(
      title: 'مشخصات پمپ مورد نظر',
      icon: Icons.tune_rounded,
      child: Column(children: [
        for (final (key, label, list) in _params)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              SizedBox(width: 190, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: app.pb.catalog.options(list).any((o) => o.value == _p[key]) ? _p[key] : null,
                  isExpanded: true,
                  items: [
                    for (final o in app.pb.catalog.options(list))
                      DropdownMenuItem(
                        value: o.value,
                        child: Text(
                          (list == 'YN' || list == 'YNS') && o.labelFa != null ? o.labelFa! : o.value,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _p[key] = v ?? ''),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  factorOf(key, _p[key] ?? '').isNaN ? '' : '× ${faSmart(factorOf(key, _p[key] ?? ''))}',
                  textAlign: TextAlign.end,
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
              ),
            ]),
          ),
        const Divider(),
        _numRow(context, 'توان (kW) — اگر معلوم است', _kw),
        _numRow(context, 'دبی (m³/h)', _q),
        _numRow(context, 'هد اختلافی (m)', _h),
        _numRow(context, 'تعداد (دستگاه)', _qty),
      ]),
    );

    final results = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionCard(
        title: 'نتیجه‌ی تخمین',
        subtitle: 'سال هدف ${fa(app.settings.targetYear)} · ${fa(r.peerCount)} پمپ همتا',
        icon: Icons.insights_rounded,
        child: r.eurExpected == null
            ? Text(
                r.peerCount == 0
                    ? 'پمپ همتایی با این خانواده/استاندارد${_p['match'] == 'Y' ? '/زیرگروه' : ''} و ضریب هزینه‌ی معتبر پیدا نشد. «فقط همتاهای همین زیرگروه» را «خیر» کنید.'
                    : 'توان یا دبی و هد را وارد کنید.',
                style: TextStyle(color: Tones.warn(context)),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Wrap(spacing: 10, runSpacing: 10, children: [
                  KpiTile(label: 'یورو — مورد انتظار', value: faNum(r.eurExpected), icon: Icons.euro_rounded, width: 200),
                  KpiTile(label: 'بازه (کمینه – بیشینه همتاها)', value: '${compactNum(r.eurLow!)} – ${compactNum(r.eurHigh!)}', sub: 'یورو', width: 230),
                  KpiTile(label: 'قیمت واحد (${unitLabel(unit)})', value: money(r.irrExpected, unit, withUnit: false), icon: Icons.payments_outlined, width: 250),
                  KpiTile(label: 'جمع (${fa(parseUserNumber(_qty.text) ?? 1)} دستگاه)', value: money(r.irrTotal, unit, compact: true, withUnit: false), sub: unitLabel(unit), width: 220),
                  KpiTile(label: 'دلار — مورد انتظار', value: faNum(r.usdExpected), icon: Icons.attach_money_rounded, width: 200),
                ]),
                const SizedBox(height: 14),
                _line(context, 'توان مبنا', '${faSmart(r.sizeKw)} kW${parseUserNumber(_kw.text) == null ? ' (برآورد از Q·H/367η)' : ''}'),
                _line(context, 'ضریب کل پیکربندی', '${faSmart(r.matF)} × ${faSmart(r.sealF)} × ${faSmart(r.driveF)} × ${faSmart(r.scopeF)} = ${faSmart(r.allF)}'),
                _line(context, 'ضریب هزینه‌ی همتاها (یورو/kWⁿ)', 'میانگین ${faSmart(r.coefAvg)} · کمینه ${faSmart(r.coefMin)} · بیشینه ${faSmart(r.coefMax)}'),
                _line(context, 'فرمول', 'میانگین ضریب × kW^${faSmart(engine.settings.costExponent)} × ضریب پیکربندی'),
                _line(context, 'کف قیمت API 610', r.floorApplies ? '${faNum(r.floorEur)} یورو (اعمال می‌شود)' : 'مشمول نیست'),
                _line(context, 'نرخ یوروی سال هدف', r.eurRate == null ? 'وارد نشده' : '${faNum(r.eurRate)} ریال'),
              ]),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: 'پمپ‌های همتا',
        subtitle: 'مبنای میانگین ضریب هزینه',
        icon: Icons.people_alt_outlined,
        child: r.peers.isEmpty
            ? const Text('—')
            : Column(children: [
                for (final p in r.peers)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      SizedBox(width: 120, child: Text(p.tag, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5))),
                      Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
                      Text(faSmart(p.costCoef), style: const TextStyle(fontSize: 12.5)),
                    ]),
                  ),
              ]),
      ),
    ]);

    return ListView(padding: const EdgeInsets.all(20), children: [
      const HelpPanel(
        id: 'estimator',
        title: 'تخمین قیمت پمپ جدید چگونه کار می‌کند؟',
        initiallyOpen: false,
        lines: [
          'هر پمپ بانک یک «ضریب هزینه» دارد: یوروی تعدیل‌شده‌ی نرمال (پیکربندی پایه) ÷ kWⁿ. میانگین این ضریب در پمپ‌های همتا مبنای تخمین است.',
          'همتا = همان خانواده و استاندارد، شمارش‌شده در جمع‌ها، و (اختیاری) همان زیرگروه.',
          'تخمین = میانگین ضریب × kWⁿ × ضریب کل پیکربندی (متریال، آب‌بند، محرک، NACE و Scope)، حداقل برابر کف قیمت API 610.',
          'مقادیر پیش‌فرض همان مثال شیت Estimator فایل v8 است؛ با سال هدف ۱۴۰۴ و نرخ «جدول مرجع v8»، نتیجه دقیقاً برابر اکسل است.',
        ],
      ),
      LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 1000) return Column(children: [inputs, const SizedBox(height: 14), results]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 470, child: inputs),
          const SizedBox(width: 16),
          Expanded(child: results),
        ]);
      }),
    ]);
  }

  Widget _numRow(BuildContext context, String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(width: 190, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(
            child: TextField(controller: c, textDirection: TextDirection.ltr, onChanged: (_) => setState(() {})),
          ),
          const SizedBox(width: 64),
        ]),
      );

  Widget _line(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 220, child: Text(k, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
          Expanded(child: Text(v, style: Theme.of(context).textTheme.bodySmall)),
        ]),
      );
}

// =============================================================================
// ماشین‌حساب انتقال قیمت (M6)

class _TransferCalculator extends StatefulWidget {
  const _TransferCalculator();

  @override
  State<_TransferCalculator> createState() => _TransferCalculatorState();
}

class _TransferCalculatorState extends State<_TransferCalculator> {
  static const _types = ['گریز از مرکز API 610', 'گریز از مرکز غیر API', 'جابه‌جایی مثبت', 'آتش‌نشانی', 'پرتابل/کوچک'];
  String _type = _types.first;
  String _cls = 'D-2';
  String _cur = 'EUR';
  FloorMode _floor = FloorMode.auto;
  final _price = TextEditingController(text: '260000');
  final _year = TextEditingController(text: '1393');
  final _month = TextEditingController();
  final _srcFx = TextEditingController();
  final _qty = TextEditingController(text: '2');
  final _customs = TextEditingController(text: '0');
  final _eurOverride = TextEditingController();

  @override
  void dispose() {
    for (final c in [_price, _year, _month, _srcFx, _qty, _customs, _eurOverride]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final unit = app.unit;
    final s = app.settings.toPumpSettings();
    final override = parseUserNumber(_eurOverride.text);
    final engine = PumpEngine(
      app.pb.seriesSnapshot,
      PumpCalcSettings(
        targetYear: s.targetYear,
        targetMonth: s.targetMonth,
        fxType: s.fxType,
        ppiSeries: s.ppiSeries,
        floorEur: s.floorEur,
        floorBaseYear: s.floorBaseYear,
        eurTargetOverride: override ?? s.eurTargetOverride,
        usdTargetOverride: s.usdTargetOverride,
      ),
      app.pb.factorTable,
    );
    final price = parseUserNumber(_price.text);
    final year = parseUserNumber(_year.text)?.toInt();
    final month = parseUserNumber(_month.text)?.toInt();
    TransferResult? r;
    if (price != null && year != null) {
      r = PriceTransferCalculator(engine).run(TransferInput(
        basePrice: price,
        currency: _cur,
        baseYear: year,
        baseMonth: (month != null && month >= 1 && month <= 12) ? month : null,
        sourceFxRate: _cur == 'IRR' ? parseUserNumber(_srcFx.text) : null,
        isApiCentrifugal: _type == _types.first,
        materialClass: _cls,
        quantity: parseUserNumber(_qty.text) ?? 1,
        customsPercent: (parseUserNumber(_customs.text) ?? 0) / 100,
        floorMode: _floor,
      ));
    }

    final t = Theme.of(context);
    final inputs = SectionCard(
      title: 'ورودی‌ها',
      icon: Icons.edit_note_rounded,
      child: Column(children: [
        _dd(context, 'نوع پمپ', _type, _types, (v) => _type = v,
            help: 'کف قیمت فقط به «گریز از مرکز API 610» با کلاس S یا D اعمال می‌شود.'),
        _dd(context, 'کلاس متریال API 610', _cls, [for (final o in app.pb.catalog.options('MAT')) o.value], (v) => _cls = v),
        _tf(context, 'قیمت واحد پایه', _price, help: 'قیمت یک دستگاه در منبع قدیمی، به همان ارز منبع.'),
        _dd(context, 'ارز قیمت پایه', _cur, const ['EUR', 'USD', 'IRR'], (v) => _cur = v),
        _tf(context, 'سال پایه (شمسی)', _year, help: 'سال تاریخ قیمت/استعلام منبع، نه سال انتشار گزارش.'),
        _tf(context, 'ماه پایه (اختیاری، ۱ تا ۱۲)', _month, help: 'اگر شاخص یا نرخ ماهانه/فصلی وارد شده باشد، دقیق‌تر می‌شود.'),
        if (_cur == 'IRR')
          _tf(context, 'نرخ تسعیر منبع (ریال/یورو) — اختیاری', _srcFx,
              help: 'قاعده‌ی طلایی: ریال را با همان نرخی به یورو برگردانید که منبع ساخته است (مثلاً گچساران ۴۵۵٬۶۹۲، پازنان ۹۳: ۴۰٬۵۳۱).'),
        _tf(context, 'تعداد', _qty),
        _tf(context, 'گمرک/حمل/ترخیص (٪ از قیمت)', _customs, help: 'برای کالای وارداتی؛ ساخت داخل صفر.'),
        _tf(context, 'نرخ یوروی هدف (ریال) — اختیاری', _eurOverride,
            help: 'خالی = نرخ سال هدف از جدول نوع نرخ انتخاب‌شده در نوار بالا.'),
        Row(children: [
          SizedBox(width: 210, child: Text('اعمال کف قیمت', style: t.textTheme.bodySmall)),
          Expanded(
            child: SegmentedButton<FloorMode>(
              segments: const [
                ButtonSegment(value: FloorMode.auto, label: Text('خودکار')),
                ButtonSegment(value: FloorMode.yes, label: Text('بله')),
                ButtonSegment(value: FloorMode.no, label: Text('خیر')),
              ],
              selected: {_floor},
              onSelectionChanged: (v) => setState(() => _floor = v.first),
            ),
          ),
        ]),
      ]),
    );

    String n(double? v) => v == null ? '—' : faSmart(v);
    final steps = r == null
        ? const Text('قیمت و سال پایه را وارد کنید.')
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final w in r.warnings) Text('⚠ $w', style: TextStyle(color: Tones.warn(context))),
            _step(context, '۱', 'نرخ تبدیل ارز پایه به یورو', '${n(r.toEurRate)}  (${r.toEurSource})'),
            _step(context, '۲', 'قیمت پایه به یورو', eur(r.baseEur)),
            _step(context, '۳', 'شاخص قیمت پمپ در سال پایه / هدف', '${n(r.ppiBase)} / ${n(r.ppiTarget)}'),
            _step(context, '۴', 'ضریب تعدیل یورویی', n(r.ppiFactor)),
            _step(context, '۵', 'قیمت یورویی تعدیل‌شده', eur(r.escalatedEur)),
            _step(context, '۶', 'کف قیمت در سال هدف', r.floorApplies ? eur(r.floorEur) : 'مشمول نیست'),
            _step(context, '۷', 'قیمت یورویی نهایی (واحد)', eur(r.finalEurUnit), strong: true),
            _step(context, '۸', 'نرخ یوروی سال هدف', r.eurRate == null ? 'وارد نشده' : '${faNum(r.eurRate)} ریال'),
            _step(context, '۹', 'قیمت واحد بدون گمرک', money(r.irrUnitNoCustoms, unit)),
            _step(context, '۱۰', 'گمرک/حمل/ترخیص (واحد)', money(r.customsIrrUnit, unit)),
            const Divider(height: 24),
            Wrap(spacing: 10, runSpacing: 10, children: [
              KpiTile(label: 'قیمت واحد', value: money(r.irrUnit, unit, withUnit: false), sub: unitLabel(unit), width: 240),
              KpiTile(label: 'قیمت کل', value: money(r.irrTotal, unit, compact: true, withUnit: false), sub: unitLabel(unit), width: 220),
              KpiTile(label: 'قیمت کل (یورو)', value: faNum(r.eurTotal), width: 180),
              KpiTile(label: 'قیمت کل (دلار)', value: faNum(r.usdTotal), width: 180),
            ]),
          ]);

    return ListView(padding: const EdgeInsets.all(20), children: [
      HelpPanel(
        id: 'transfer',
        title: 'انتقال قیمت قدیم به سال هدف — روش M6',
        initiallyOpen: false,
        lines: [
          'فرمول: ریال(هدف) = MAX[ قیمت پایه ÷ نرخ تسعیر منبع × PPI(هدف)/PPI(پایه) ، کف × PPI(هدف)/PPI(${fa(s.floorBaseYear)}) ] × نرخ یورو(هدف)',
          'سال هدف و نوع نرخ ارز از نوار بالای برنامه خوانده می‌شود (الان: ${fa(s.targetYear)} · «${s.fxType}»).',
          'مقادیر پیش‌فرض همان مثال شیت «ماشین_حساب» فایل صحت‌سنجی است؛ با سال هدف ۱۴۰۵ و نرخ «بازار آزاد»، نتیجه دقیقاً برابر اکسل است.',
          'تورم ریالی (CPI) برای پمپ استفاده نمی‌شود؛ فایل صحت‌سنجی نشان داد آن روش حدود ۵۰٪ کم‌برآورد می‌کند.',
        ],
      ),
      LayoutBuilder(builder: (context, c) {
        final res = SectionCard(title: 'محاسبه‌ی گام‌به‌گام', icon: Icons.stairs_outlined, child: steps);
        if (c.maxWidth < 1000) return Column(children: [inputs, const SizedBox(height: 14), res]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 500, child: inputs),
          const SizedBox(width: 16),
          Expanded(child: res),
        ]);
      }),
    ]);
  }

  Widget _dd(BuildContext context, String label, String value, List<String> items, void Function(String) set, {String? help}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(width: 210, child: _label(context, label, help)),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: items.contains(value) ? value : null,
              isExpanded: true,
              items: [for (final i in items) DropdownMenuItem(value: i, child: Text(i))],
              onChanged: (v) => setState(() => set(v ?? value)),
            ),
          ),
        ]),
      );

  Widget _tf(BuildContext context, String label, TextEditingController c, {String? help}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(width: 210, child: _label(context, label, help)),
          Expanded(child: TextField(controller: c, textDirection: TextDirection.ltr, onChanged: (_) => setState(() {}))),
        ]),
      );

  Widget _label(BuildContext context, String label, String? help) {
    final t = Theme.of(context);
    return Row(children: [
      Flexible(child: Text(label, style: t.textTheme.bodySmall)),
      if (help != null)
        Tooltip(message: help, child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 4),
          child: Icon(Icons.info_outline_rounded, size: 14, color: t.colorScheme.outline),
        )),
    ]);
  }

  Widget _step(BuildContext context, String n, String title, String value, {bool strong = false}) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        CircleAvatar(radius: 12, backgroundColor: t.colorScheme.primaryContainer, child: Text(n, style: const TextStyle(fontSize: 11))),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: t.textTheme.bodySmall)),
        Text(value, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w600, color: strong ? t.colorScheme.primary : null)),
      ]),
    );
  }
}
