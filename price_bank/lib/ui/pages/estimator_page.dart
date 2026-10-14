import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/estimator.dart';
import '../../core/calc/methods.dart';
import '../../core/calc/pump_engine.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/factor_dialog.dart';
import 'generic_estimator_tab.dart';

class EstimatorPage extends StatefulWidget {
  const EstimatorPage({super.key});

  @override
  State<EstimatorPage> createState() => _EstimatorPageState();
}

class _EstimatorPageState extends State<EstimatorPage> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this);

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
            Tab(icon: Icon(Icons.auto_graph_rounded), text: 'تخمین پمپ جدید'),
            Tab(icon: Icon(Icons.category_rounded), text: 'تخمین سایر تجهیزات'),
            Tab(icon: Icon(Icons.trending_up_rounded), text: 'انتقال قیمت قدیم به سال هدف'),
          ],
        ),
      ),
      Expanded(child: TabBarView(controller: _tabs, children: const [_NewPumpEstimator(), GenericEstimatorTab(), _TransferCalculator()])),
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
  /// ضرایب موردی همین تخمین: «گروه|گزینه» ← ضریب
  final Map<String, double> _overrides = {};
  final _kw = TextEditingController();
  final _q = TextEditingController(text: '80');
  final _h = TextEditingController(text: '600');
  final _qty = TextEditingController(text: '2');

  /// راندمان پمپ برای برآورد توان از دبی و هد (خالی = مقدار تنظیمات)
  final _eta = TextEditingController();

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
    for (final c in [_kw, _q, _h, _qty, _eta]) {
      c.dispose();
    }
    super.dispose();
  }

  static String? _groupOf(String key) => switch (key) {
        'material_class' => 'MAT',
        'seal_arrangement' => 'SEAL_ARR',
        'api682_category' => 'SEAL_CAT',
        'api682_plan' => 'SEAL_PLAN',
        'driver_type' => 'DRV',
        'nace' => 'NACE',
        'scope_driver' => 'SC_DRV',
        'scope_baseplate' => 'SC_BSP',
        'scope_seal_support' => 'SC_SEAL',
        'scope_comm_spares' => 'SC_COMM',
        'scope_2yr_spares' => 'SC_2Y',
        'scope_tpi' => 'SC_TPI',
        'scope_fat' => 'SC_FAT',
        _ => null,
      };

  Future<void> _editFactor(BuildContext context, String key, String label) async {
    final g = _groupOf(key);
    final opt = _p[key] ?? '';
    if (g == null) return;
    final res = await showFactorDialog(context,
        group: g, option: opt, label: label, localOverride: _overrides['$g|$opt']);
    if (res == null || !mounted) return;
    setState(() {
      if (res.clearLocal) _overrides.remove('$g|$opt');
      if (res.local != null) _overrides['$g|$opt'] = res.local!;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final base = app.pb.pumpEngine();
    final f = app.pb.factorTable.withOverrides(_overrides);
    final etaIn = parseUserNumber(_eta.text);
    // راندمان به درصد (مثلاً ۶۵) یا کسر (۰٫۶۵) پذیرفته می‌شود
    final eta = etaIn == null ? null : (etaIn > 1 ? etaIn / 100 : etaIn);
    final engine = PumpEngine(
        base.series, eta == null || eta <= 0 || eta > 1 ? base.settings : base.settings.copyWith(pumpEfficiency: eta), f);
    final peers = app.pb.peersFrom(app.pumps);
    final qty = parseUserNumber(_qty.text) ?? 1;
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
        quantity: qty,
      ),
      peers,
    );
    final unit = app.unit;
    final canEditFactors = app.user.isAdmin || app.user.role == 'reviewer';

    final inputs = SectionCard(
      title: 'مشخصات پمپ مورد نظر',
      subtitle: 'روی ضریب هر ردیف بزنید تا ویرایش شود',
      icon: Icons.tune_rounded,
      trailing: _overrides.isEmpty
          ? null
          : TextButton.icon(
              onPressed: () => setState(_overrides.clear),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: Text('حذف ${fa(_overrides.length)} ضریب موردی'),
            ),
      child: Column(children: [
        for (final (key, label, list) in _params)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              SizedBox(width: 170, child: Text(label, style: t.textTheme.bodySmall)),
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
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: _groupOf(key) == null
                    ? const SizedBox()
                    : _FactorChip(
                        value: f.get(_groupOf(key)!, _p[key] ?? ''),
                        local: _overrides.containsKey('${_groupOf(key)}|${_p[key]}'),
                        onTap: () => _editFactor(context, key, label),
                      ),
              ),
            ]),
          ),
        const Divider(height: 20),
        _numRow(context, 'توان (kW) — اگر معلوم است', _kw),
        _numRow(context, 'دبی (m³/h)', _q),
        _numRow(context, 'هد اختلافی (m)', _h),
        _numRow(context, 'راندمان پمپ η (٪) — اختیاری', _eta,
            hint: 'پیش‌فرض ${faNum(base.settings.pumpEfficiency * 100)}٪',
            help: 'فقط وقتی توان وارد نشده و توان از دبی و هد برآورد می‌شود استفاده می‌شود: kW = Q·H ÷ (367·η). عدد را به درصد بنویسید (مثلاً ۶۵).'),
        _numRow(context, 'تعداد (دستگاه)', _qty),
        if (!canEditFactors)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('ضریب‌های موردی فقط روی همین تخمین اثر دارند.',
                style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
          ),
      ]),
    );

    final ok = r.eurExpected != null;
    final results = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionCard(
        title: 'نتیجه‌ی تخمین',
        subtitle: 'سال هدف ${fa(app.settings.targetYear)} · روش ${engine.settings.method} · ${fa(r.peerCount)} پمپ همتا',
        icon: Icons.insights_rounded,
        child: !ok
            ? Text(
                r.peerCount == 0
                    ? 'پمپ همتایی با این خانواده/استاندارد${_p['match'] == 'Y' ? '/زیرگروه' : ''} و ضریب هزینه‌ی معتبر پیدا نشد. «فقط همتاهای همین زیرگروه» را «خیر» کنید.'
                    : 'توان یا دبی و هد را وارد کنید.',
                style: TextStyle(color: Tones.warn(context), height: 1.8),
              )
            : EstimateResultsView(r: r, unit: unit, qty: qty),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: 'جزئیات محاسبه',
        icon: Icons.functions_rounded,
        child: Column(children: [
          _line(context, 'توان مبنا', '${faSmart(r.sizeKw)} kW${parseUserNumber(_kw.text) == null ? ' (برآورد از Q·H/367η)' : ''}'),
          _line(context, 'ضریب کل پیکربندی',
              'متریال ${faSmart(r.matF)} × آب‌بند ${faSmart(r.sealF)} × محرک ${faSmart(r.driveF)} × Scope ${faSmart(r.scopeF)} = ${faSmart(r.allF)}'),
          _line(context, 'ضریب هزینه‌ی همتاها (یورو/kWⁿ)',
              'میانگین ${faSmart(r.coefAvg)} · کمینه ${faSmart(r.coefMin)} · بیشینه ${faSmart(r.coefMax)}'),
          _line(context, 'فرمول', 'ضریب هزینه × kW^${faSmart(engine.settings.costExponent)} × ضریب پیکربندی'),
          _line(context, 'کف قیمت API 610', r.floorApplies ? '${faNum(r.floorEur)} یورو (اعمال می‌شود)' : 'مشمول نیست'),
          _line(context, 'نرخ یوروی سال هدف', r.eurRate == null ? 'وارد نشده' : '${faNum(r.eurRate)} ریال'),
          _line(context, 'نرخ دلار سال هدف', r.usdRate == null ? 'وارد نشده' : '${faNum(r.usdRate)} ریال'),
        ]),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: 'پمپ‌های همتا',
        subtitle: 'مبنای میانگین ضریب هزینه',
        icon: Icons.people_alt_outlined,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: r.peers.isEmpty
            ? const Padding(padding: EdgeInsets.all(8), child: Text('—'))
            : Column(children: [
                for (var i = 0; i < r.peers.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    decoration: BoxDecoration(
                      color: i.isOdd ? AppColors.zebra : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      SizedBox(
                        width: 120,
                        child: Text(r.peers[i].tag,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.right,
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.petrolDark)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(r.peers[i].name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
                      Text(faSmart(r.peers[i].costCoef), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
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
          'تخمین = میانگین ضریب × kWⁿ × ضریب کل پیکربندی (متریال، آب‌بند، محرک، NACE و Scope)؛ در روش M6 حداقل برابر کف قیمت API 610.',
          'روی عدد «× ضریب» کنار هر پارامتر بزنید تا آن را تغییر دهید: فقط برای همین تخمین (نارنجی) یا به عنوان ضریب کالیبره در بانک.',
          'ترتیب نتیجه: یورو ← دلار ← بازه‌ی یورویی همتاها ← قیمت ریالی/تومانی ← بازه‌ی ریالی/تومانی همتاها ← جمع برای تعداد دستگاه.',
          'مقادیر پیش‌فرض همان مثال شیت Estimator فایل v8 است؛ با سال هدف ۱۴۰۴، «جدول پیش‌فرض» و روش M6، نتیجه برابر اکسل است.',
        ],
      ),
      LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 1000) return Column(children: [inputs, const SizedBox(height: 14), results]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 480, child: inputs),
          const SizedBox(width: 16),
          Expanded(child: results),
        ]);
      }),
    ]);
  }

  Widget _numRow(BuildContext context, String label, TextEditingController c, {String? hint, String? help}) => Padding(
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
          Expanded(
            child: TextField(
              controller: c,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(hintText: hint),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 104),
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
  String? _method; // null = روش فعال برنامه
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
        method: _method ?? s.method,
      ),
      app.pb.factorTable,
    );
    final method = methodByCode(_method ?? s.method);
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

    final inputs = SectionCard(
      title: 'ورودی‌ها',
      icon: Icons.edit_note_rounded,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            SizedBox(width: 210, child: _label(context, 'روش تعدیل', 'پیش‌فرض = روش فعال برنامه (نوار بالا). تغییر در اینجا فقط روی همین محاسبه اثر دارد.')),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: method.code,
                isExpanded: true,
                items: [
                  for (final m in escalationMethods.where((m) => m.selectable))
                    DropdownMenuItem(value: m.code, child: Text('${m.code} — ${m.nameFa}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _method = v),
              ),
            ),
          ]),
        ),
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
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            SizedBox(
              width: 210,
              child: _label(context, 'اعمال کف قیمت',
                  'خودکار: فقط برای «گریز از مرکز API 610» با کلاس متریال S یا D و فقط در روش M6.'),
            ),
            Expanded(
              child: DropdownButtonFormField<FloorMode>(
                value: _floor,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: FloorMode.auto, child: Text('خودکار (طبق نوع پمپ و کلاس متریال)')),
                  DropdownMenuItem(value: FloorMode.yes, child: Text('همیشه اعمال شود')),
                  DropdownMenuItem(value: FloorMode.no, child: Text('اعمال نشود')),
                ],
                onChanged: (v) => setState(() => _floor = v ?? FloorMode.auto),
              ),
            ),
          ]),
        ),
      ]),
    );

    String n(double? v) => v == null ? '—' : faSmart(v);
    final qty = parseUserNumber(_qty.text) ?? 1;
    final ppiMethod = method.code == 'M4' || method.code == 'M6';
    final steps = r == null
        ? const Text('قیمت و سال پایه را وارد کنید.')
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final w in r.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('⚠ $w', style: TextStyle(color: Tones.warn(context))),
              ),
            _step(context, '۱', 'نرخ تبدیل ارز پایه به یورو', '${n(r.toEurRate)}  (${r.toEurSource})'),
            _step(context, '۲', 'قیمت پایه به یورو', eur(r.baseEur)),
            if (ppiMethod) _step(context, '۳', 'شاخص قیمت پمپ در سال پایه / هدف', '${n(r.ppiBase)} / ${n(r.ppiTarget)}'),
            _step(context, ppiMethod ? '۴' : '۳', 'ضریب تعدیل یورویی (${method.code})',
                r.ppiFactor == null ? '—' : '${n(r.ppiFactor)}${ppiMethod ? '' : '  (${r.factorDetail})'}'),
            _step(context, '۵', 'قیمت یورویی تعدیل‌شده', eur(r.escalatedEur)),
            _step(context, '۶', 'کف قیمت در سال هدف', r.floorApplies ? eur(r.floorEur) : (method.usesFloor ? 'مشمول نیست' : 'در این روش اعمال نمی‌شود')),
            _step(context, '۷', 'قیمت یورویی نهایی (واحد)', eur(r.finalEurUnit), strong: true),
            _step(context, '۸', 'نرخ یوروی سال هدف', r.eurRate == null ? 'وارد نشده' : '${faNum(r.eurRate)} ریال'),
            _step(context, '۹', 'قیمت واحد بدون گمرک', money(r.irrUnitNoCustoms, unit)),
            _step(context, '۱۰', 'گمرک/حمل/ترخیص (واحد)', money(r.customsIrrUnit, unit)),
            if (r.irrUnit != null) ...[
              const Divider(height: 28),
              _TransferResults(r: r, unit: unit, qty: qty),
            ],
          ]);

    return ListView(padding: const EdgeInsets.all(20), children: [
      HelpPanel(
        id: 'transfer',
        title: 'انتقال قیمت قدیم به سال هدف',
        initiallyOpen: false,
        lines: [
          'روش M6: ریال(هدف) = MAX[ قیمت پایه ÷ نرخ تسعیر منبع × PPI(هدف)/PPI(پایه) ، کف × PPI(هدف)/PPI(${fa(s.floorBaseYear)}) ] × نرخ یورو(هدف)',
          'روش تعدیل به طور پیش‌فرض همان روش فعال برنامه است؛ برای مقایسه می‌توانید در همین صفحه روش دیگری انتخاب کنید.',
          'سال هدف و جدول نرخ ارز از نوار بالای برنامه خوانده می‌شود (الان: ${fa(s.targetYear)}).',
          'مقادیر پیش‌فرض همان مثال شیت «ماشین_حساب» فایل صحت‌سنجی است؛ با سال هدف ۱۴۰۵، نرخ «بازار آزاد» و روش M6 نتیجه برابر اکسل است.',
          'تورم ریالی (CPI) برای پمپ استفاده نمی‌شود؛ فایل صحت‌سنجی نشان داد آن روش حدود ۵۰٪ کم‌برآورد می‌کند.',
        ],
      ),
      LayoutBuilder(builder: (context, c) {
        final res = SectionCard(title: 'محاسبه‌ی گام‌به‌گام', subtitle: 'روش ${method.code} — ${method.nameFa}', icon: Icons.stairs_outlined, child: steps);
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


// =============================================================================
// اجزای نمایش نتیجه

/// دکمه‌ی ضریب کنار هر پارامتر: «× ۱٫۹»؛ نارنجی = ضریب موردی همین تخمین.
class _FactorChip extends StatelessWidget {
  const _FactorChip({required this.value, required this.local, required this.onTap});
  final double value;
  final bool local;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = local ? AppColors.amberText : AppColors.petrol;
    return Tooltip(
      message: local ? 'ضریب موردی همین تخمین — برای تغییر بزنید' : 'ضریب بانک — برای تغییر بزنید',
      child: Material(
        color: local ? AppColors.amberSoft : AppColors.petrol.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            height: 34,
            padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.withValues(alpha: 0.35)),
            ),
            // عدد سمت راست، قلم ویرایش در لبه‌ی چپ و جدا از عدد
            child: Row(children: [
              Text('× ${faSmart(value)}', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12.5)),
              const Spacer(),
              Container(width: 1, height: 18, color: c.withValues(alpha: 0.25)),
              const SizedBox(width: 4),
              Icon(Icons.edit_rounded, size: 13, color: c.withValues(alpha: 0.8)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// یک کاشی نتیجه: برچسب، عدد درشت با نشان ارز، توضیح.
class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.label,
    required this.value,
    required this.currency,
    this.sub,
    this.big = false,
    this.child,
  });
  final String label;
  final String value;
  final String currency; // EUR, USD, IRR, IRT
  final String? sub;
  final bool big;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = CurrencyBadge.colorOf(currency);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.22)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: Text(label,
                style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ),
          CurrencyBadge(currency),
        ]),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(value,
              style: TextStyle(fontSize: big ? 26 : 20, fontWeight: FontWeight.w800, color: c, height: 1.3)),
        ),
        if (sub != null)
          Text(sub!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        if (child != null) ...[const SizedBox(height: 8), child!],
      ]),
    );
  }
}

/// چیدمان نتیجه‌ی تخمین: یورو ← دلار ← بازه‌ی یورو ← ریال/تومان ← بازه‌ی ریالی ← جمع.
class EstimateResultsView extends StatelessWidget {
  const EstimateResultsView({super.key, required this.r, required this.unit, required this.qty});
  final EstimatorResult r;
  final MoneyUnit unit;
  final double qty;

  @override
  Widget build(BuildContext context) {
    final cur = unit == MoneyUnit.toman ? 'IRT' : 'IRR';
    Widget pair(Widget a, Widget b) => LayoutBuilder(builder: (context, c) {
          if (c.maxWidth < 560) return Column(children: [a, const SizedBox(height: 10), b]);
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: a),
              const SizedBox(width: 10),
              Expanded(child: b),
            ]),
          );
        });
    final peerRangeEur = r.eurLow != null && r.eurHigh != null;
    final peerRangeIrr = r.irrLow != null && r.irrHigh != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ۱ و ۲: یورو و دلار
      pair(
        _ResultTile(label: '۱. قیمت مورد انتظار (یورو)', value: faNum(r.eurExpected), currency: 'EUR', big: true,
            sub: 'هر دستگاه، سال هدف'),
        _ResultTile(label: '۲. قیمت مورد انتظار (دلار)', value: faNum(r.usdExpected), currency: 'USD', big: true,
            sub: r.usdExpected == null ? 'نرخ دلار سال هدف وارد نشده' : 'هر دستگاه، با نسبت یورو/دلار سال هدف'),
      ),
      const SizedBox(height: 10),
      // ۳: بازه‌ی یورویی
      _ResultTile(
        label: '۳. بازه‌ی قیمت (کمینه تا بیشینه‌ی همتاها) — یورو',
        value: peerRangeEur ? '${faNum(r.eurLow)}  تا  ${faNum(r.eurHigh)}' : '—',
        currency: 'EUR',
        child: peerRangeEur ? RangeBar(low: r.eurLow!, high: r.eurHigh!, mid: r.eurExpected, color: AppColors.eur) : null,
      ),
      const SizedBox(height: 10),
      // ۴ و ۵: ریال/تومان و بازه‌ی آن
      pair(
        _ResultTile(
          label: '۴. قیمت واحد (${unitLabel(unit)})',
          value: money(r.irrExpected, unit, withUnit: false),
          currency: cur,
          big: true,
          sub: r.irrExpected == null ? 'نرخ یوروی سال هدف وارد نشده' : money(r.irrExpected, unit, compact: true),
        ),
        _ResultTile(
          label: '۵. بازه‌ی همتاها (${unitLabel(unit)})',
          value: peerRangeIrr
              ? '${money(r.irrLow, unit, compact: true, withUnit: false)} تا ${money(r.irrHigh, unit, compact: true, withUnit: false)}'
              : '—',
          currency: cur,
          sub: peerRangeIrr ? 'کمینه و بیشینه بر اساس ضریب هزینه‌ی همتاها' : null,
          child: peerRangeIrr ? RangeBar(low: r.irrLow!, high: r.irrHigh!, mid: r.irrExpected, color: AppColors.irr) : null,
        ),
      ),
      const SizedBox(height: 12),
      // ۶: جمع
      _TotalBand(
        title: '۶. جمع برای ${fa(qty % 1 == 0 ? qty.toInt() : qty)} دستگاه',
        main: r.irrTotal == null ? '—' : money(r.irrTotal, unit),
        items: [
          if (r.irrTotal != null) ('به عدد خلاصه', money(r.irrTotal, unit, compact: true)),
          if (r.eurExpected != null) ('معادل یورویی', '${faNum(r.eurExpected! * qty)} یورو'),
          if (r.usdExpected != null) ('معادل دلاری', '${faNum(r.usdExpected! * qty)} دلار'),
        ],
      ),
    ]);
  }
}

/// نوار جمع کل (پس‌زمینه‌ی تیره).
class _TotalBand extends StatelessWidget {
  const _TotalBand({required this.title, required this.main, required this.items});
  final String title;
  final String main;

  /// معادل‌ها با برچسب روشن: (برچسب، مقدار)
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Icon(Icons.summarize_rounded, color: AppColors.amber, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12.5, fontWeight: FontWeight.w600)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(main, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final (label, value) in items)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '$label: ', style: TextStyle(color: Colors.white.withValues(alpha: 0.75))),
                      TextSpan(text: value, style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w800)),
                    ]), style: const TextStyle(fontSize: 12.5)),
                  ),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// نتیجه‌ی ماشین‌حساب انتقال: یورو ← دلار ← ریال/تومان ← جمع.
class _TransferResults extends StatelessWidget {
  const _TransferResults({required this.r, required this.unit, required this.qty});
  final TransferResult r;
  final MoneyUnit unit;
  final double qty;

  @override
  Widget build(BuildContext context) {
    final cur = unit == MoneyUnit.toman ? 'IRT' : 'IRR';
    final eurUnit = r.eurTotal == null || qty == 0 ? null : r.eurTotal! / qty;
    final usdUnit = r.usdTotal == null || qty == 0 ? null : r.usdTotal! / qty;
    Widget pair(Widget a, Widget b) => LayoutBuilder(builder: (context, c) {
          if (c.maxWidth < 560) return Column(children: [a, const SizedBox(height: 10), b]);
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: a),
              const SizedBox(width: 10),
              Expanded(child: b),
            ]),
          );
        });
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      pair(
        _ResultTile(label: 'قیمت واحد (یورو، با گمرک)', value: faNum(eurUnit), currency: 'EUR', big: true),
        _ResultTile(label: 'قیمت واحد (دلار، با گمرک)', value: faNum(usdUnit), currency: 'USD', big: true,
            sub: usdUnit == null ? 'نرخ دلار سال هدف وارد نشده' : null),
      ),
      const SizedBox(height: 10),
      _ResultTile(
        label: 'قیمت واحد (${unitLabel(unit)})',
        value: money(r.irrUnit, unit, withUnit: false),
        currency: cur,
        big: true,
        sub: money(r.irrUnit, unit, compact: true),
      ),
      const SizedBox(height: 12),
      _TotalBand(
        title: 'جمع برای ${fa(qty % 1 == 0 ? qty.toInt() : qty)} دستگاه',
        main: money(r.irrTotal, unit),
        items: [
          ('به عدد خلاصه', money(r.irrTotal, unit, compact: true)),
          if (r.eurTotal != null) ('معادل یورویی', '${faNum(r.eurTotal)} یورو'),
          if (r.usdTotal != null) ('معادل دلاری', '${faNum(r.usdTotal)} دلار'),
        ],
      ),
    ]);
  }
}
