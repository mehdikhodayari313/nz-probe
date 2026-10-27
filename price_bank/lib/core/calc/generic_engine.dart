// موتور تعدیل قیمت تجهیزات غیرپمپ (ظرف، مخزن، پکیج، …).
//
// همان مسیر روش‌های تعدیل پمپ، بدون ضرایب پیکربندی و بدون کف قیمت پمپ:
//   یورو(پایه) = قیمت ÷ نرخ تسعیر منبع (یا نرخ یوروی سال قیمت از جدول نرخ ارز)
//   یورو(هدف)  = یورو(پایه) × ضریب روش (M4/M6: PPI(هدف)/PPI(پایه)؛ M0، M1، M2، M5 مطابق تعریف)
//   ریال(هدف)  = یورو(هدف) × نرخ یوروی سال هدف
// در روش M6 برای تجهیزات غیرپمپ کف قیمت تعریف نشده و با M4 یکی است.

import 'methods.dart';
import 'pump_engine.dart';
import 'series.dart';

class GenericInput {
  const GenericInput({this.unitPrice, this.currency, this.costYear, this.costMonth, this.sourceFxRate});
  final Object? unitPrice;
  final String? currency;
  final Object? costYear;
  final int? costMonth;
  final double? sourceFxRate;
}

class GenericCalcResult {
  CalcCell eurSource = const CalcCell.blank();
  CalcCell usdSource = const CalcCell.blank();
  CalcCell irrSource = const CalcCell.blank();
  CalcCell eurTarget = const CalcCell.blank();
  CalcCell usdTarget = const CalcCell.blank();
  CalcCell irrTarget = const CalcCell.blank();
  double? factor;
  String factorDetail = '';
  String methodCode = defaultMethodCode;
  double? eurRateTarget, usdRateTarget, baseRate;

  /// شاخص (ترکیبی) سال پایه و هدف در روش‌های شاخص‌محور
  double? indexBase, indexTarget;
  final List<CalcStep> steps = [];
}

class GenericEngine {
  const GenericEngine(this.series, this.settings);
  final SeriesLookup series;
  final PumpCalcSettings settings;

  double? _fx(String code, int y, int? m) => series.resolve(code, y, month: m)?.value;

  double? get eurRateTarget =>
      settings.eurTargetOverride ?? _fx(settings.fxEurCode, settings.targetYear, settings.targetMonth);
  double? get usdRateTarget =>
      settings.usdTargetOverride ?? _fx(settings.fxUsdCode, settings.targetYear, settings.targetMonth);

  /// سطح شاخص روش فعال در یک سال (M7: شاخص ترکیبی؛ M4/M6: PPI رده؛ سایر روش‌ها: null)
  double? indexAt(int year) {
    final code = methodByCode(settings.method).code;
    final mf = MethodFactors(series,
        ppiSeries: settings.ppiSeries,
        fxType: settings.fxType,
        mix: settings.mix,
        mixStrict: settings.mixStrict,
        usPpiSeries: settings.usPpiSeries);
    if (code == compositeMethodCode) return mf.compositeIndex(year);
    if (code == 'M5') return mf.usIndex(year);
    if (code == 'M4' || code == 'M6') {
      final v = series.resolve(settings.ppiSeries, year)?.value;
      return (v != null && v > 0) ? v : null;
    }
    return null;
  }

  GenericCalcResult calculate(GenericInput inp) {
    final r = GenericCalcResult();
    final aa = asNumber(inp.unitPrice);
    final z = inp.currency ?? '';
    final y = inp.costYear is num ? (inp.costYear! as num).toInt() : null;
    final ym = inp.costMonth;
    final eurY = y == null ? null : _fx(settings.fxEurCode, y, ym);
    final usdY = y == null ? null : _fx(settings.fxUsdCode, y, ym);

    if (aa == null) {
      r.eurSource = const CalcCell.text('(Not stated)');
      r.eurTarget = r.eurSource;
      r.steps.add(const CalcStep('۱. قیمت منبع', 'قیمت عددی ثبت نشده', '—', warning: true));
      return r;
    }
    if (y == null) {
      r.eurSource = const CalcCell.text('(Cost year not stated)');
      r.eurTarget = r.eurSource;
      r.steps.add(const CalcStep('۱. قیمت منبع', 'سال قیمت ثبت نشده', '—', warning: true));
      return r;
    }

    // ---------- تبدیل به یورو، دلار و ریال در سال منبع
    double? rate;
    String rateSrc;
    switch (z) {
      case 'EUR':
        rate = 1;
        rateSrc = 'قیمت یورویی است';
      case 'IRR':
        rate = inp.sourceFxRate ?? eurY;
        rateSrc = inp.sourceFxRate != null ? 'نرخ تسعیر منبع (سند)' : 'نرخ یوروی سال $y از جدول «${settings.fxTypeLabel}»';
      case 'USD':
        rate = (usdY != null && eurY != null) ? eurY / usdY : null;
        rateSrc = 'نسبت یورو/دلار سال $y';
      default:
        rate = null;
        rateSrc = 'ارز نامعتبر';
    }
    r.baseRate = rate;
    if (rate == null) {
      r.eurSource = const CalcCell.text('(FX rate missing)');
      r.eurTarget = r.eurSource;
      r.steps.add(CalcStep('۱. تبدیل به یورو (سال $y)', rateSrc, 'نرخ ارز موجود نیست', warning: true));
      return r;
    }
    final eur0 = aa / rate;
    r.eurSource = CalcCell.number(eur0);
    if (eurY != null) r.irrSource = CalcCell.number(z == 'IRR' ? aa : eur0 * eurY);
    if (eurY != null && usdY != null) r.usdSource = CalcCell.number(z == 'USD' ? aa : eur0 * eurY / usdY);
    r.steps.add(CalcStep('۱. تبدیل قیمت منبع به یورو (سال $y)', '${_g(aa)} $z ÷ ${_g(rate)}  ($rateSrc)', '${_g(eur0)} EUR'));

    // ---------- ضریب تعدیل
    final method = methodByCode(settings.method);
    r.methodCode = method.code;
    final mf = MethodFactors(series,
            ppiSeries: settings.ppiSeries,
            fxType: settings.fxType,
            mix: settings.mix,
            mixStrict: settings.mixStrict,
            usPpiSeries: settings.usPpiSeries)
        .factor(method.code, y, ym, settings.targetYear, settings.targetMonth);
    r.factor = mf.factor;
    r.indexBase = mf.base;
    r.indexTarget = mf.target;
    r.factorDetail = mf.detail;
    r.steps.add(CalcStep('۲. ضریب تعدیل (روش ${method.code} — ${method.nameFa})', mf.detail,
        mf.factor == null ? 'محاسبه نشد' : _g(mf.factor!),
        warning: mf.factor == null));
    if (mf.factor == null) {
      r.eurTarget = const CalcCell.text('(PPI/FX missing)');
      return r;
    }
    final eurT = eur0 * mf.factor!;
    r.eurTarget = CalcCell.number(eurT);
    r.steps.add(CalcStep('۳. قیمت یورویی تعدیل‌شده (سال ${settings.targetYear})',
        'یورو(پایه) × ضریب${method.usesFloor ? ' (کف قیمت فقط برای پمپ‌هاست)' : ''}', '${_g(eurT)} EUR'));

    // ---------- تبدیل به ریال و دلار سال هدف
    final eR = eurRateTarget, uR = usdRateTarget;
    r.eurRateTarget = eR;
    r.usdRateTarget = uR;
    if (eR != null) r.irrTarget = CalcCell.number(eurT * eR);
    if (eR != null && uR != null) r.usdTarget = CalcCell.number(eurT * eR / uR);
    r.steps.add(CalcStep('۴. تبدیل به ریال با نرخ یوروی سال هدف', 'یورو × ${eR == null ? '؟' : _g(eR)}',
        r.irrTarget.isNumber ? '${_g(r.irrTarget.number!)} ریال' : 'نرخ یوروی سال هدف وارد نشده',
        warning: eR == null));
    return r;
  }
}

String _g(double v) {
  final a = v.abs();
  final s = a >= 1000 ? v.toStringAsFixed(0) : (a >= 1 ? v.toStringAsFixed(4) : v.toStringAsPrecision(4));
  final t = s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : s;
  final parts = t.split('.');
  final neg = parts[0].startsWith('-');
  final ip = neg ? parts[0].substring(1) : parts[0];
  final b = StringBuffer();
  for (var i = 0; i < ip.length; i++) {
    if (i > 0 && (ip.length - i) % 3 == 0) b.write(',');
    b.write(ip[i]);
  }
  return '${neg ? '-' : ''}$b${parts.length > 1 ? '.${parts[1]}' : ''}';
}
