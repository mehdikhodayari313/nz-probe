// روش‌های تعدیل قیمت یورویی پمپ از سال قیمت تا سال هدف.
//
// تعریف‌ها و آمار صحت‌سنجی از شیت Val_EUR_Pumps فایل Pump_Escalation_Validation گرفته شده است
// (۱۴ پمپ پازنان ۲: قیمت یورویی بهمن ۱۳۹۳ در برابر میانگین استعلام‌های ۱۴۰۴).
//
//   M0  بدون تعدیل                      ضریب = ۱
//   M1  تورم ارزی مارون ۳               ضریب = Π(۱ + تورم ارزی سال) از سال پایه+۱ تا سال هدف−۱
//   M2  ضریب یورویی پازنان              ۱٫۵۵۲۰۷۶ برای ۱۳۹۳→۱۴۰۴ ؛ برای بازه‌های دیگر نرخ سالانه‌ی معادل
//   M3  مدل فلزی (برای هر ردیف جدا)     قابل تعمیم نیست — فقط برای مقایسه
//   M4  PPI پمپ منطقه‌ی یورو            ضریب = PPI(هدف) ÷ PPI(پایه)
//   M5  PPI پمپ آمریکا به یورو          ضریب = USPPI(هدف)/USPPI(پایه) × (یورو/دلار پایه ÷ یورو/دلار هدف)
//   M6  M4 + کف قیمت پمپ API 610 (S/D)  روش پیش‌فرض
//   M7  شاخص ترکیبی (سبد PPI)          ضریب = Σwᵢ·PPIᵢ(هدف) ÷ Σwᵢ·PPIᵢ(پایه) — هر رده سبد خودش (دیسالتر: ۰٫۷۰ C25.29 + ۰٫۱۵ C27.11 + ۰٫۱۵ C28.13)

import 'dart:math' as math;

import 'series.dart';

class MethodStats {
  const MethodStats({
    required this.bias,
    required this.mdape,
    required this.mape,
    required this.within25,
    required this.totalRatio,
  });

  /// میانه‌ی خطای علامت‌دار (منفی = کم‌برآورد)
  final double bias;

  /// میانه‌ی قدرمطلق درصد خطا
  final double mdape;

  /// میانگین قدرمطلق درصد خطا
  final double mape;

  /// تعداد پمپ‌ها با خطای کمتر از ±۲۵٪ (از ۱۴)
  final int within25;

  /// جمع برآورد ÷ جمع واقعی
  final double totalRatio;
}

class EscalationMethod {
  const EscalationMethod({
    required this.code,
    required this.nameFa,
    required this.summaryFa,
    required this.formulaFa,
    required this.factorRef,
    required this.stats,
    this.selectable = true,
    this.usesFloor = false,
    this.noteFa,
  });

  final String code;
  final String nameFa;
  final String summaryFa;
  final String formulaFa;

  /// ضریب ۱۳۹۳ → ۱۴۰۴ در فایل صحت‌سنجی (برای M3 = null چون برای هر ردیف فرق می‌کند)
  final double? factorRef;
  final MethodStats stats;
  final bool selectable;
  final bool usesFloor;
  final String? noteFa;
}

const defaultMethodCode = 'M6';
const validationSampleSize = 14;

/// ضریب یورویی پازنان (Basic INFO!C138 فایل PZN-Summary-140401 Rev.03) برای ۱۳۹۳ → ۱۴۰۴.
const m2PazananFactor = 1.55207623267439;
const m2BaseYear = 1393, m2TargetYear = 1404;

/// سهم سال شمسی Y از سال میلادی Y+621 (بقیه از Y+622) — همان فرض فایل صحت‌سنجی.
const jalaliBlendWeight = 0.79;

const escalationMethods = <EscalationMethod>[
  EscalationMethod(
    code: 'M0',
    nameFa: 'بدون تعدیل',
    summaryFa: 'قیمت یورویی سال منبع بدون تغییر به سال هدف منتقل می‌شود.',
    formulaFa: 'ضریب = ۱',
    factorRef: 1,
    stats: MethodStats(bias: -0.3737, mdape: 0.3737, mape: 0.3723, within25: 3, totalRatio: 0.7345),
    noteFa: 'فقط برای مقایسه؛ قیمت‌های قدیمی را حدود ۳۷٪ کمتر از واقع نشان می‌دهد.',
  ),
  EscalationMethod(
    code: 'M1',
    nameFa: 'تورم ارزی مارون ۳',
    summaryFa: 'یورو با نرخ‌های سالانه‌ی «تورم ارزی» شیت Inflation مارون ۳ رشد داده می‌شود.',
    formulaFa: 'ضریب = Π (۱ + تورم ارزی سال) از سال پایه+۱ تا سال هدف−۱   (سری INF_FX_M3)',
    factorRef: 1.38108886484153,
    stats: MethodStats(bias: -0.1350, mdape: 0.2200, mape: 0.2614, within25: 8, totalRatio: 1.0144),
  ),
  EscalationMethod(
    code: 'M2',
    nameFa: 'ضریب یورویی پازنان',
    summaryFa: 'ضریب ثابت فایل خلاصه‌ی پازنان (۱٫۵۵۲) برای ۱۳۹۳→۱۴۰۴.',
    formulaFa: 'ضریب = ۱٫۵۵۲۰۷۶ ^ ((سال هدف − سال پایه) ÷ ۱۱)',
    factorRef: m2PazananFactor,
    stats: MethodStats(bias: -0.0279, mdape: 0.1736, mape: 0.2581, within25: 8, totalRatio: 1.1399),
    noteFa: 'برای بازه‌های غیر از ۱۳۹۳→۱۴۰۴، نرخ سالانه‌ی معادل (حدود ۴٫۱٪) به کار می‌رود.',
  ),
  EscalationMethod(
    code: 'M3',
    nameFa: 'مدل فلزی',
    summaryFa: 'ضریب هر پمپ از سبد فلزات (فولاد، نیکل، مولیبدن، مس) و مدل جداگانه محاسبه شده است.',
    formulaFa: 'ضریب = برای هر ردیف جدا (ستون AH شیت Equipment مدل)',
    factorRef: null,
    stats: MethodStats(bias: -0.2041, mdape: 0.2820, mape: 0.2860, within25: 6, totalRatio: 0.9357),
    selectable: false,
    noteFa: 'قابل تعمیم به همه‌ی پمپ‌ها نیست؛ فقط برای مقایسه نمایش داده می‌شود.',
  ),
  EscalationMethod(
    code: 'M4',
    nameFa: 'PPI پمپ منطقه‌ی یورو',
    summaryFa: 'شاخص قیمت تولیدکننده‌ی پمپ و کمپرسور یوروستات (C28.13).',
    formulaFa: 'ضریب = PPI(هدف) ÷ PPI(پایه)',
    factorRef: 1.34541911611766,
    stats: MethodStats(bias: -0.1573, mdape: 0.2401, mape: 0.2688, within25: 8, totalRatio: 0.9882),
  ),
  EscalationMethod(
    code: 'M5',
    nameFa: 'PPI پمپ آمریکا به یورو',
    summaryFa: 'شاخص پمپ آمریکا (NAICS 333914) با اصلاح تغییر نسبت یورو به دلار.',
    formulaFa: 'ضریب = USPPI(هدف) ÷ USPPI(پایه) × (یورو/دلار پایه ÷ یورو/دلار هدف)',
    factorRef: 1.59038228739346,
    stats: MethodStats(bias: -0.0039, mdape: 0.1754, mape: 0.2644, within25: 9, totalRatio: 1.1681),
    noteFa: 'نسبت یورو/دلار از جدول نرخ ارز انتخاب‌شده خوانده می‌شود.',
  ),
  EscalationMethod(
    code: 'M6',
    nameFa: 'PPI یورو + کف قیمت',
    summaryFa: 'همان روش M4 (PPI پمپ منطقه‌ی یورو)، به‌علاوه‌ی کف قیمت برای پمپ‌های گریز از مرکز API 610 با کلاس متریال S یا D.',
    formulaFa: 'یورو(هدف) = MAX[ یورو × PPI(هدف)/PPI(پایه) ، کف × PPI(هدف)/PPI(سال کف) ]',
    factorRef: 1.34541911611766,
    stats: MethodStats(bias: -0.0703, mdape: 0.1307, mape: 0.2085, within25: 10, totalRatio: 1.0098),
    usesFloor: true,
    noteFa: 'روش پیشنهادی و پیش‌فرض: کمترین خطای میانه و بیشترین تعداد پمپ در بازه‌ی ±۲۵٪.',
  ),
];

/// روش شاخص ترکیبی: سبد چند شاخص PPI با وزن‌های هر رده (فقط رده‌های غیرپمپ).
const compositeMethodCode = 'M7';
const compositeMethod = EscalationMethod(
  code: compositeMethodCode,
  nameFa: 'شاخص ترکیبی (سبد PPI)',
  summaryFa: 'میانگین وزنی چند شاخص PPI یوروستات مطابق اجزای تجهیز؛ هر رده سبد و وزن‌های خودش را دارد.',
  formulaFa: 'ضریب = Σ wᵢ·PPIᵢ(هدف) ÷ Σ wᵢ·PPIᵢ(پایه)   (شاخص میلادی با ترکیب ۰٫۷۹×(Y+621) + ۰٫۲۱×(Y+622))',
  factorRef: null,
  stats: MethodStats(bias: 0, mdape: 0, mape: 0, within25: 0, totalRatio: 0),
  noteFa: 'دیسالتر: ۰٫۷۰×C25.29 (بدنه و Internals) + ۰٫۱۵×C27.11 (ترانس) + ۰٫۱۵×C28.13 (پمپ Recycle) — '
      'شاخص ناموجود: وزن‌ها روی شاخص‌های موجود بازتوزیع می‌شود (یا در حالت سخت‌گیرانه، تعدیل انجام نمی‌شود).',
);

EscalationMethod methodByCode(String? code) => code == compositeMethodCode
    ? compositeMethod
    : escalationMethods.firstWhere((m) => m.code == code && m.selectable,
        orElse: () => escalationMethods.firstWhere((m) => m.code == defaultMethodCode));

/// یک جزء سبد شاخص ترکیبی: کد سری PPI و وزن آن. سری میلادی (پسوند _GREG) به سال شمسی ترکیب می‌شود.
class MixPart {
  const MixPart(this.series, this.weight);
  final String series;
  final double weight;

  bool get gregorian => series.endsWith('_GREG');

  /// نام کوتاه: PPI_EU_C2529_GREG ← C25.29
  String get shortName {
    final m = RegExp(r'C(\d{2})(\d{2})').firstMatch(series);
    if (m != null) return 'C${m[1]}.${m[2]}';
    return series.replaceFirst(RegExp(r'^PPI_'), '').replaceFirst(RegExp(r'_GREG$'), '');
  }

  @override
  String toString() => '$series:$weight';

  /// «PPI_EU_C2529_GREG:0.7;PPI_EU_C2711_GREG:0.15» ← فهرست اجزا
  static List<MixPart> parseList(String? s) => [
        for (final p in (s ?? '').split(';'))
          if (p.split(':') case [final c, final w] when c.trim().isNotEmpty && double.tryParse(w.trim()) != null)
            MixPart(c.trim(), double.parse(w.trim())),
      ];

  static String format(List<MixPart> l) => l.map((p) => '${p.series}:${p.weight}').join(';');
}

/// «0.70×C25.29 + 0.15×C27.11 + 0.15×C28.13»
String mixLabel(List<MixPart> mix) =>
    mix.isEmpty ? '—' : mix.map((p) => '${p.weight.toStringAsFixed(2)}×${p.shortName}').join(' + ');

/// نتیجه‌ی ضریب یک روش برای یک بازه.
class MethodFactor {
  const MethodFactor(this.factor, this.detail, {this.base, this.target});
  final double? factor;
  final String detail;

  /// مقدار شاخص (ترکیبی) سال پایه و هدف، وقتی روش شاخص‌محور است
  final double? base, target;
}

/// محاسبه‌ی ضریب تعدیل یورویی هر روش (بدون کف؛ کف در موتور اعمال می‌شود).
class MethodFactors {
  const MethodFactors(this.series,
      {required this.ppiSeries,
      required this.fxType,
      this.mix = const [],
      this.mixStrict = false,
      this.usPpiSeries = defaultUsPpiSeries});
  final SeriesLookup series;
  final String ppiSeries;

  /// سری PPI آمریکای روش M5 (پیش‌فرض پمپ 333914؛ کمپرسور هوا 333912)
  final String usPpiSeries;
  final String fxType;

  /// سبد شاخص ترکیبی (روش M7)
  final List<MixPart> mix;

  /// true = اگر یکی از شاخص‌های سبد نباشد، تعدیل انجام نمی‌شود؛ false = بازتوزیع وزن‌ها روی شاخص‌های موجود
  final bool mixStrict;

  double? _v(String code, int year, [int? month]) {
    final v = series.resolve(code, year, month: month)?.value;
    return v;
  }

  double? _ppi(int year, int? month) {
    final v = _v(ppiSeries, year, month);
    return (v != null && v > 0) ? v : null;
  }

  /// مقدار سری میلادی برای سال شمسی: ۰٫۷۹×(Y+621) + ۰٫۲۱×(Y+622)
  double? _gregBlend(String code, int jYear) {
    final a = _v(code, jYear + 621), b = _v(code, jYear + 622);
    if (a == null) return null;
    if (b == null) return a;
    return jalaliBlendWeight * a + (1 - jalaliBlendWeight) * b;
  }

  /// ترکیب سال شمسی یک سری میلادی؛ اگر یکی از دو سال نباشد null (همان قاعده‌ی بانک دیسالتر).
  double? _gregBlendStrict(String code, int jYear) {
    final a = _v(code, jYear + 621), b = _v(code, jYear + 622);
    if (a == null || b == null || a <= 0 || b <= 0) return null;
    return jalaliBlendWeight * a + (1 - jalaliBlendWeight) * b;
  }

  /// شاخص آمریکای روش M5 در سال شمسی (۰٫۷۹/۰٫۲۱ سال‌های میلادی)
  double? usIndex(int jYear) => _gregBlend(usPpiSeries, jYear);

  /// مقدار یک جزء سبد در سال شمسی
  double? mixPartValue(MixPart p, int jYear) {
    if (p.gregorian) return _gregBlendStrict(p.series, jYear);
    final v = _v(p.series, jYear);
    return (v != null && v > 0) ? v : null;
  }

  /// شاخص ترکیبی سال شمسی: Σw·I ÷ Σw روی اجزای موجود (حالت سخت‌گیرانه: همه لازم‌اند).
  double? compositeIndex(int jYear) {
    if (mix.isEmpty) return null;
    var sw = 0.0, s = 0.0;
    for (final p in mix) {
      if (p.weight <= 0) continue;
      final v = mixPartValue(p, jYear);
      if (v == null) {
        if (mixStrict) return null;
        continue;
      }
      sw += p.weight;
      s += p.weight * v;
    }
    return sw > 0 ? s / sw : null;
  }

  double? _eurUsd(int year, int? month) {
    final e = _v('FX_EUR_$fxType', year, month), u = _v('FX_USD_$fxType', year, month);
    if (e == null || u == null || u == 0) return null;
    return e / u;
  }

  MethodFactor factor(String code, int baseYear, int? baseMonth, int targetYear, int? targetMonth) {
    switch (code) {
      case 'M0':
        return const MethodFactor(1, 'بدون تعدیل: ضریب ۱');
      case 'M1':
        var k = 1.0;
        final missing = <int>[];
        for (var y = baseYear + 1; y <= targetYear - 1; y++) {
          final r = _v('INF_FX_M3', y);
          if (r == null) {
            missing.add(y);
          } else {
            k *= 1 + r;
          }
        }
        if (missing.isNotEmpty) {
          return MethodFactor(null, 'تورم ارزی سال‌های ${missing.join('، ')} موجود نیست');
        }
        if (targetYear < baseYear) {
          // تعدیل معکوس (سال هدف قبل از سال پایه)
          var inv = 1.0;
          for (var y = targetYear + 1; y <= baseYear - 1; y++) {
            final r = _v('INF_FX_M3', y);
            if (r == null) return MethodFactor(null, 'تورم ارزی سال $y موجود نیست');
            inv *= 1 + r;
          }
          return MethodFactor(1 / inv, 'معکوس Π(۱+تورم ارزی) از ${targetYear + 1} تا ${baseYear - 1}');
        }
        return MethodFactor(k, 'Π(۱+تورم ارزی مارون ۳) از ${baseYear + 1} تا ${targetYear - 1}');
      case 'M2':
        final yrs = targetYear - baseYear;
        if (baseYear == m2BaseYear && targetYear == m2TargetYear) {
          return const MethodFactor(m2PazananFactor, 'ضریب ثابت پازنان برای ۱۳۹۳ → ۱۴۰۴');
        }
        final f = math.pow(m2PazananFactor, yrs / (m2TargetYear - m2BaseYear)).toDouble();
        return MethodFactor(f, '۱٫۵۵۲۰۷۶ ^ ($yrs ÷ ۱۱) — نرخ سالانه‌ی معادل');
      case 'M5':
        final pb = _gregBlend(usPpiSeries, baseYear), pt = _gregBlend(usPpiSeries, targetYear);
        final eb = _eurUsd(baseYear, baseMonth), et = _eurUsd(targetYear, targetMonth);
        if (pb == null || pt == null) return const MethodFactor(null, 'PPI آمریکا برای این سال‌ها موجود نیست');
        if (eb == null || et == null) return const MethodFactor(null, 'نسبت یورو/دلار از جدول نرخ ارز موجود نیست');
        return MethodFactor(pt / pb * eb / et,
            'USPPI ${_s(pt)} ÷ ${_s(pb)} × یورو/دلار ${_s(eb)} ÷ ${_s(et)}', base: pb, target: pt);
      case compositeMethodCode:
        if (mix.isEmpty) return const MethodFactor(null, 'سبد شاخص ترکیبی برای این رده تعریف نشده است');
        final cb = compositeIndex(baseYear), ct = compositeIndex(targetYear);
        if (cb == null || ct == null) {
          return MethodFactor(null, 'شاخص ترکیبی سال ${cb == null ? baseYear : targetYear} موجود نیست', base: cb, target: ct);
        }
        return MethodFactor(ct / cb, 'شاخص ترکیبی ${_s(ct)} ÷ ${_s(cb)}', base: cb, target: ct);
      case 'M4':
      case 'M6':
      default:
        final a = _ppi(baseYear, baseMonth), b = _ppi(targetYear, targetMonth);
        if (a == null || b == null) return const MethodFactor(null, 'شاخص PPI موجود نیست');
        return MethodFactor(b / a, 'PPI ${_s(b)} ÷ ${_s(a)}', base: a, target: b);
    }
  }
}

String _s(double v) => v >= 100 ? v.toStringAsFixed(2) : v.toStringAsFixed(4);

/// آزمون روش‌های ریالی روی ۱۱ پکیج تزریق پازنان ۲ (فقط برای اطلاع؛ شیت Summary بخش ب).
class RialPackageResult {
  const RialPackageResult(this.code, this.nameFa, this.medianRatio, this.totalRatio);
  final String code;
  final String nameFa;

  /// میانه‌ی نسبت پیش‌بینی ÷ استعلام ریالی
  final double medianRatio;

  /// جمع پیش‌بینی ÷ جمع استعلام ریالی
  final double totalRatio;
}

const rialPackageResults = <RialPackageResult>[
  RialPackageResult('R1', 'تورم ریالی (CPI مارون ۳)', 0.462172027133676, 0.477162925071043),
  RialPackageResult('R2', 'ضریب ریالی پازنان (۱۶٫۲۶)', 0.458940756823821, 0.473826846073991),
  RialPackageResult('R3', 'مدل فلزی', 0.828995459246681, 0.855445874619527),
  RialPackageResult('R4', 'یورو × PPI × نرخ ارز (پیشنهادی)', 0.906222967965403, 0.935616992752061),
];


/// سری PPI آمریکای پیش‌فرض روش M5 (پمپ)
const defaultUsPpiSeries = 'PPI_US_333914_GREG';

/// برچسب روش برای یک رده‌ی تجهیز: در رده‌های غیرپمپ، M4/M6 با شاخص PPI همان رده و بدون کف قیمت است.
String methodLabelFor(EscalationMethod m, {required bool pump, String? ppiName, String? usPpiName}) {
  if (pump) return '${m.code} — ${m.nameFa}';
  final ppi = ppiName == null ? 'PPI منتخب رده' : 'PPI: $ppiName';
  return switch (m.code) {
    'M4' => 'M4 — $ppi',
    'M6' => 'M6 — همان M4 ($ppi)؛ کف قیمت فقط برای پمپ',
    'M5' => 'M5 — PPI آمریکا به یورو (${usPpiName ?? 'شاخص پمپ'})',
    'M7' => 'M7 — شاخص ترکیبی (سبد PPI همین رده)',
    _ => '${m.code} — ${m.nameFa}',
  };
}
