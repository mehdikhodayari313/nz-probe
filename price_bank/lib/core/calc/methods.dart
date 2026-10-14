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

EscalationMethod methodByCode(String? code) =>
    escalationMethods.firstWhere((m) => m.code == code && m.selectable,
        orElse: () => escalationMethods.firstWhere((m) => m.code == defaultMethodCode));

/// نتیجه‌ی ضریب یک روش برای یک بازه.
class MethodFactor {
  const MethodFactor(this.factor, this.detail);
  final double? factor;
  final String detail;
}

/// محاسبه‌ی ضریب تعدیل یورویی هر روش (بدون کف؛ کف در موتور اعمال می‌شود).
class MethodFactors {
  const MethodFactors(this.series, {required this.ppiSeries, required this.fxType});
  final SeriesLookup series;
  final String ppiSeries;
  final String fxType;

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
        final pb = _gregBlend('PPI_US_333914_GREG', baseYear), pt = _gregBlend('PPI_US_333914_GREG', targetYear);
        final eb = _eurUsd(baseYear, baseMonth), et = _eurUsd(targetYear, targetMonth);
        if (pb == null || pt == null) return const MethodFactor(null, 'PPI پمپ آمریکا برای این سال‌ها موجود نیست');
        if (eb == null || et == null) return const MethodFactor(null, 'نسبت یورو/دلار از جدول نرخ ارز موجود نیست');
        return MethodFactor(pt / pb * eb / et,
            'USPPI ${_s(pt)} ÷ ${_s(pb)} × یورو/دلار ${_s(eb)} ÷ ${_s(et)}');
      case 'M4':
      case 'M6':
      default:
        final a = _ppi(baseYear, baseMonth), b = _ppi(targetYear, targetMonth);
        if (a == null || b == null) return const MethodFactor(null, 'شاخص PPI موجود نیست');
        return MethodFactor(b / a, 'PPI ${_s(b)} ÷ ${_s(a)}');
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


/// برچسب روش برای یک رده‌ی تجهیز: در رده‌های غیرپمپ، M4/M6 با شاخص PPI همان رده و بدون کف قیمت است.
String methodLabelFor(EscalationMethod m, {required bool pump, String? ppiName}) {
  if (pump) return '${m.code} — ${m.nameFa}';
  final ppi = ppiName == null ? 'PPI منتخب رده' : 'PPI: $ppiName';
  return switch (m.code) {
    'M4' => 'M4 — $ppi',
    'M6' => 'M6 — همان M4 ($ppi)؛ کف قیمت فقط برای پمپ',
    'M5' => 'M5 — PPI پمپ آمریکا به یورو (شاخص پمپ)',
    _ => '${m.code} — ${m.nameFa}',
  };
}
