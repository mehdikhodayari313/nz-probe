// موتور محاسبات قیمت پمپ.
//
// این موتور فرمول‌های شیت Master Database فایل Pumps_Price_Bank_v8 را عیناً پیاده می‌کند
// (ستون‌های K، L، AB تا AD، AG تا AI، AS تا BD) و روش M6 فایل
// Pump_Escalation_Validation را پوشش می‌دهد:
//
//   یورو(پایه)  = قیمت ÷ نرخ تسعیر منبع (یا نرخ یوروی سال پایه از جدول نرخ ارز)
//   یورو(هدف)  = MAX[ یورو(پایه) × PPI(هدف)/PPI(پایه) ، کف × PPI(هدف)/PPI(سال کف) ]
//   ریال(هدف)  = یورو(هدف) × نرخ یوروی سال هدف
//
// متن‌های خطا (مثل «(PPI/FX missing)») دقیقاً همان متن‌های v8 است تا مقایسه‌ی خودکار ممکن باشد؛
// رابط کاربری معادل فارسی آن‌ها را نشان می‌دهد.

import 'dart:math' as math;

import 'methods.dart';
import 'series.dart';

/// مقدار یک خانه‌ی محاسباتی: عدد، یا متن (پیام خطا/وضعیت)، یا خالی.
class CalcCell {
  const CalcCell.number(double this.number) : text = null;
  const CalcCell.text(String this.text) : number = null;
  const CalcCell.blank()
      : number = null,
        text = null;

  final double? number;
  final String? text;

  bool get isNumber => number != null;
  bool get isBlank => number == null && text == null;

  @override
  String toString() => number?.toString() ?? text ?? '';
}

class PumpCalcSettings {
  const PumpCalcSettings({
    required this.targetYear,
    this.targetMonth,
    this.fxType = 'V8',
    this.ppiSeries = 'PPI_EU_C2813',
    this.floorEur = 25000,
    this.floorBaseYear = 1404,
    this.costExponent = 0.6,
    this.pumpEfficiency = 0.6,
    this.eurCheckLimit = 5000000,
    this.eurTargetOverride,
    this.usdTargetOverride,
    this.method = defaultMethodCode,
    this.mix = const [],
    this.mixStrict = false,
    this.usPpiSeries = defaultUsPpiSeries,
  });

  /// سری PPI آمریکای روش M5 رده
  final String usPpiSeries;

  /// سبد شاخص ترکیبی رده (روش M7)
  final List<MixPart> mix;
  final bool mixStrict;

  /// روش تعدیل (M0، M1، M2، M4، M5، M6) — پیش‌فرض M6
  final String method;

  final int targetYear;
  final int? targetMonth;
  final String fxType;
  final String ppiSeries;
  final double floorEur;
  final int floorBaseYear;
  final double costExponent;
  final double pumpEfficiency;
  final double eurCheckLimit;
  final double? eurTargetOverride;
  final double? usdTargetOverride;

  PumpCalcSettings copyWith({double? pumpEfficiency, String? method, double? eurTargetOverride}) => PumpCalcSettings(
        targetYear: targetYear,
        targetMonth: targetMonth,
        fxType: fxType,
        ppiSeries: ppiSeries,
        floorEur: floorEur,
        floorBaseYear: floorBaseYear,
        costExponent: costExponent,
        pumpEfficiency: pumpEfficiency ?? this.pumpEfficiency,
        eurCheckLimit: eurCheckLimit,
        eurTargetOverride: eurTargetOverride ?? this.eurTargetOverride,
        usdTargetOverride: usdTargetOverride,
        method: method ?? this.method,
        mix: mix,
        mixStrict: mixStrict,
        usPpiSeries: usPpiSeries,
      );

  String get fxEurCode => 'FX_EUR_$fxType';
  String get fxUsdCode => 'FX_USD_$fxType';
}

/// جدول ضرایب نرمال‌سازی: کلید «گروه|گزینه» → ضریب مورد استفاده.
class FactorTable {
  FactorTable(this._map);
  final Map<String, double> _map;

  /// مانند IFERROR(INDEX(...MATCH(...)),1) در اکسل: گزینه‌ی ناموجود = ۱.
  double get(String group, String option) => _map['$group|$option'] ?? 1.0;

  bool has(String group, String option) => _map.containsKey('$group|$option');

  /// نسخه‌ای با ضرایب جایگزین (کلید «گروه|گزینه») — برای تخمین موردی بدون تغییر بانک.
  FactorTable withOverrides(Map<String, double> overrides) =>
      overrides.isEmpty ? this : FactorTable({..._map, ...overrides});
}

/// ورودی محاسبه برای یک پمپ.
class PumpInput {
  const PumpInput({
    required this.spec,
    this.unitPrice,
    this.currency,
    this.costYear,
    this.costMonth,
    this.sourceFxRate,
    this.quantity,
  });

  /// مشخصات فنی: کلید فیلد ← مقدار (String یا num).
  final Map<String, Object?> spec;

  /// قیمت واحد (num)، یا متن اگر در منبع عددی نبوده.
  final Object? unitPrice;
  final String? currency;

  /// سال قیمت (int)، یا متن مثل «(Not stated)».
  final Object? costYear;
  final int? costMonth;

  /// نرخ تسعیر منبع (ریال به ازای هر یورو) — در صورت وجود، به جای جدول نرخ ارز استفاده می‌شود.
  final double? sourceFxRate;
  final double? quantity;
}

class CalcStep {
  const CalcStep(this.title, this.detail, this.result, {this.warning = false});
  final String title;
  final String detail;
  final String result;
  final bool warning;
}

class PumpCalcResult {
  PumpCalcResult();

  CalcCell sizeKw = const CalcCell.blank();
  String standards = '';
  CalcCell eurSource = const CalcCell.blank();
  CalcCell usdSource = const CalcCell.blank();
  CalcCell irrSource = const CalcCell.blank();
  CalcCell eurTarget = const CalcCell.blank();
  CalcCell usdTarget = const CalcCell.blank();
  CalcCell irrTarget = const CalcCell.blank();
  String qaFlags = '';
  double matF = 1, sealF = 1, driveF = 1, scopeF = 1, allF = 1;
  CalcCell normalizedEur = const CalcCell.blank();
  CalcCell ppiBase = const CalcCell.blank();
  CalcCell ppiTarget = const CalcCell.blank();
  bool floorApplies = false;
  CalcCell normalizedEscalatedEur = const CalcCell.blank();
  CalcCell costCoef = const CalcCell.blank();

  /// نرخ‌های استفاده‌شده (برای نمایش)
  double? eurRateTarget;
  double? usdRateTarget;
  double? baseConversionRate;
  String baseConversionSource = '';
  double? floorTargetEur;
  bool floorBinding = false;
  String methodCode = defaultMethodCode;
  double? escalationFactor;

  final List<CalcStep> steps = [];

  /// جمع ریالی برای تعداد دستگاه.
  double? totalIrr(double? quantity) =>
      irrTarget.isNumber && quantity != null ? irrTarget.number! * quantity : null;
}

/// خواندن عدد به سبک ISNUMBER اکسل (متن عددی، عدد حساب نمی‌شود).
double? asNumber(Object? v) {
  if (v is num) return v.toDouble();
  return null;
}

/// متن یک مقدار به سبک الحاق متن در اکسل (۱۱٫۰ → «11»).
String asText(Object? v) {
  if (v == null) return '';
  if (v is num) {
    final d = v.toDouble();
    if (d == d.roundToDouble() && d.abs() < 1e15) return d.toStringAsFixed(0);
    return d.toString();
  }
  return v.toString();
}

class PumpEngine {
  const PumpEngine(this.series, this.settings, this.factors);

  final SeriesLookup series;
  final PumpCalcSettings settings;
  final FactorTable factors;

  double? _fx(String code, int year, int? month) => series.resolve(code, year, month: month)?.value;

  double? get eurRateTarget =>
      settings.eurTargetOverride ?? _fx(settings.fxEurCode, settings.targetYear, settings.targetMonth);
  double? get usdRateTarget =>
      settings.usdTargetOverride ?? _fx(settings.fxUsdCode, settings.targetYear, settings.targetMonth);

  double? ppi(int year, {int? month}) {
    final v = series.resolve(settings.ppiSeries, year, month: month)?.value;
    return (v != null && v > 0) ? v : null;
  }

  /// شرط کف قیمت v8: API 610، خانواده‌ی گریز از مرکز، کلاس متریال S- یا D-.
  static bool floorRule(String std, String family, String materialClass) =>
      std == 'API 610' &&
      family.startsWith('Centrifugal') &&
      (materialClass.startsWith('S-') || materialClass.startsWith('D-'));

  PumpCalcResult calculate(PumpInput inp) {
    final r = PumpCalcResult();
    final s = inp.spec;
    String sv(String k) => asText(s[k]);
    double? nv(String k) => asNumber(s[k]);
    final n = settings.costExponent;

    // ---------- K: توان مبنای اندازه
    final j = nv('power_kw'), h = nv('capacity_m3h'), i = nv('diff_head_m');
    if (j != null) {
      r.sizeKw = CalcCell.number(j);
      r.steps.add(CalcStep('توان مبنای اندازه', 'توان اعلام‌شده در منبع', _f(j, 'kW')));
    } else if (h != null && i != null) {
      final k = h * i / (367 * settings.pumpEfficiency);
      r.sizeKw = CalcCell.number(k);
      r.steps.add(CalcStep('توان مبنای اندازه (برآوردی)',
          'Q × H ÷ (367 × η) = ${_g(h)} × ${_g(i)} ÷ (367 × ${_g(settings.pumpEfficiency)})', _f(k, 'kW')));
    } else {
      r.steps.add(const CalcStep('توان مبنای اندازه', 'نه توان و نه دبی/هد در دسترس است', '—', warning: true));
    }

    // ---------- L: استانداردها
    final m = sv('pump_standard'), nIps = sv('ips_standard'), o = sv('nace');
    var st = (m == 'Not stated' || m.isEmpty) ? '' : ' + $m';
    st += (nIps == 'None' || nIps.isEmpty) ? '' : ' + $nIps';
    st += o == 'Y' ? ' + NACE MR0175' : '';
    r.standards = st.isEmpty ? 'Not stated' : st.substring(3);

    // ---------- AB / AC / AD: قیمت در سال منبع به سه ارز
    final aa = asNumber(inp.unitPrice);
    final z = inp.currency ?? '';
    final y = inp.costYear is num ? (inp.costYear! as num).toInt() : null;
    final ym = inp.costMonth;
    final eurY = y == null ? null : _fx(settings.fxEurCode, y, ym);
    final usdY = y == null ? null : _fx(settings.fxUsdCode, y, ym);

    CalcCell conv(String to) {
      if (aa == null) return const CalcCell.text('(Not stated)');
      if (y == null) return const CalcCell.text('(Cost year not stated)');
      switch (to) {
        case 'EUR':
          if (z == 'EUR') return CalcCell.number(aa);
          if (z == 'IRR') {
            final rate = inp.sourceFxRate ?? eurY;
            return rate == null ? const CalcCell.text('(FX rate missing)') : CalcCell.number(aa / rate);
          }
          if (z == 'USD') {
            if (usdY == null || eurY == null) return const CalcCell.text('(FX rate missing)');
            return CalcCell.number(aa * usdY / eurY);
          }
          return const CalcCell.text('(Currency?)');
        case 'USD':
          if (z == 'USD') return CalcCell.number(aa);
          if (z == 'IRR') {
            return usdY == null ? const CalcCell.text('(FX rate missing)') : CalcCell.number(aa / usdY);
          }
          if (z == 'EUR') {
            if (usdY == null || eurY == null) return const CalcCell.text('(FX rate missing)');
            return CalcCell.number(aa * eurY / usdY);
          }
          return const CalcCell.text('(Currency?)');
        default: // IRR
          if (z == 'IRR') return CalcCell.number(aa);
          if (z == 'USD') {
            return usdY == null ? const CalcCell.text('(FX rate missing)') : CalcCell.number(aa * usdY);
          }
          if (z == 'EUR') {
            return eurY == null ? const CalcCell.text('(FX rate missing)') : CalcCell.number(aa * eurY);
          }
          return const CalcCell.text('(Currency?)');
      }
    }

    r.eurSource = conv('EUR');
    r.usdSource = conv('USD');
    r.irrSource = conv('IRR');

    if (aa != null && y != null) {
      if (z == 'EUR') {
        r.baseConversionRate = 1;
        r.baseConversionSource = 'قیمت یورویی است';
      } else if (z == 'IRR') {
        r.baseConversionRate = inp.sourceFxRate ?? eurY;
        r.baseConversionSource = inp.sourceFxRate != null
            ? 'نرخ تسعیر منبع (سند)'
            : 'نرخ یوروی سال $y از جدول نرخ ارز «${settings.fxType}»';
      } else if (z == 'USD') {
        r.baseConversionRate = (usdY != null && eurY != null) ? eurY / usdY : null;
        r.baseConversionSource = 'نسبت یورو/دلار سال $y از جدول نرخ ارز «${settings.fxType}»';
      }
      r.steps.add(CalcStep(
        '۱. تبدیل قیمت منبع به یورو (سال $y)',
        '${_g(aa)} $z ÷ ${r.baseConversionRate == null ? '؟' : _g(r.baseConversionRate!)}  (${r.baseConversionSource})',
        r.eurSource.isNumber ? _f(r.eurSource.number!, 'EUR') : _msg(r.eurSource.text),
        warning: !r.eurSource.isNumber,
      ));
    } else {
      r.steps.add(CalcStep('۱. تبدیل قیمت منبع به یورو', aa == null ? 'قیمت عددی ثبت نشده' : 'سال قیمت ثبت نشده',
          _msg(r.eurSource.text), warning: true));
    }

    // ---------- AZ / BA: PPI
    final az = y == null ? null : ppi(y, month: ym);
    final ba = ppi(settings.targetYear, month: settings.targetMonth);
    r.ppiBase = az == null ? const CalcCell.blank() : CalcCell.number(az);
    r.ppiTarget = ba == null ? const CalcCell.blank() : CalcCell.number(ba);
    final method = methodByCode(settings.method);
    final ppiMethod = method.code == 'M4' || method.code == 'M6';
    // ضریب روش‌های غیر PPI
    MethodFactor? other;
    if (!ppiMethod && y != null) {
      other = MethodFactors(series,
              ppiSeries: settings.ppiSeries,
              fxType: settings.fxType,
              mix: settings.mix,
              mixStrict: settings.mixStrict,
              usPpiSeries: settings.usPpiSeries)
          .factor(method.code, y, ym, settings.targetYear, settings.targetMonth);
    }
    r.methodCode = method.code;
    if (ppiMethod) {
      r.escalationFactor = (az != null && ba != null) ? ba / az : null;
      r.steps.add(CalcStep(
        '۲. ضریب تعدیل PPI (روش ${method.code})',
        'PPI(${settings.targetYear}) ÷ PPI(${y ?? '؟'}) = ${ba == null ? '؟' : _g(ba)} ÷ ${az == null ? '؟' : _g(az)}',
        (az != null && ba != null) ? _g(ba / az) : 'شاخص موجود نیست',
        warning: az == null || ba == null,
      ));
    } else {
      r.escalationFactor = other?.factor;
      r.steps.add(CalcStep(
        '۲. ضریب تعدیل (روش ${method.code} — ${method.nameFa})',
        other?.detail ?? 'سال قیمت مشخص نیست',
        other?.factor == null ? 'محاسبه نشد' : _g(other!.factor!),
        warning: other?.factor == null,
      ));
    }

    // ---------- BB: کف قیمت
    final g = sv('material_class');
    final v = sv('pump_family');
    r.floorApplies = floorRule(m, v, g);

    // ---------- AG: یورو تعدیل‌شده
    final ppiFloorBase = ppi(settings.floorBaseYear);
    final excluded = z == 'EUR' && (aa ?? 0) > settings.eurCheckLimit;
    if (excluded) {
      r.eurTarget = const CalcCell.text('(Check currency – excluded)');
    } else if (r.eurSource.isNumber && (ppiMethod ? (az != null && ba != null) : other?.factor != null)) {
      final escalated = ppiMethod ? r.eurSource.number! * ba! / az! : r.eurSource.number! * other!.factor!;
      var value = escalated;
      if (!method.usesFloor) {
        r.steps.add(CalcStep('۳. کف قیمت', 'در روش ${method.code} کف قیمت اعمال نمی‌شود', '—'));
      } else if (r.floorApplies && ppiFloorBase != null && ba != null) {
        final floor = settings.floorEur * ba / ppiFloorBase;
        r.floorTargetEur = floor;
        value = math.max(escalated, floor);
        r.floorBinding = floor > escalated;
        r.steps.add(CalcStep(
          '۳. کف قیمت (API 610 گریز از مرکز، کلاس S/D)',
          '${_g(settings.floorEur)} یورو (سطح ${settings.floorBaseYear}) × PPI(${settings.targetYear}) ÷ PPI(${settings.floorBaseYear})',
          '${_f(floor, 'EUR')}${r.floorBinding ? ' ← کف اعمال شد' : ' (قیمت تعدیل‌شده بیشتر است)'}',
        ));
      } else {
        r.steps.add(CalcStep('۳. کف قیمت', r.floorApplies ? 'شاخص سال کف موجود نیست' : 'مشمول کف نیست (فقط API 610 گریز از مرکز با کلاس S/D)', '—'));
      }
      r.eurTarget = CalcCell.number(value);
    } else {
      r.eurTarget = const CalcCell.text('(PPI/FX missing)');
    }
    r.steps.add(CalcStep('۴. قیمت یورویی تعدیل‌شده (سال ${settings.targetYear})',
        excluded
            ? 'قیمت یورویی بیش از ${_g(settings.eurCheckLimit)} — احتمال اشتباه ارز؛ از محاسبه کنار گذاشته شد'
            : (method.usesFloor ? 'یورو(پایه) × ضریب تعدیل، حداقل برابر کف' : 'یورو(پایه) × ضریب تعدیل'),
        r.eurTarget.isNumber ? _f(r.eurTarget.number!, 'EUR') : _msg(r.eurTarget.text),
        warning: !r.eurTarget.isNumber));

    // ---------- AH / AI
    final eurT = eurRateTarget, usdT = usdRateTarget;
    r.eurRateTarget = eurT;
    r.usdRateTarget = usdT;
    if (r.eurTarget.isNumber && eurT != null && usdT != null) {
      r.usdTarget = CalcCell.number(r.eurTarget.number! * eurT / usdT);
    }
    if (r.eurTarget.isNumber && eurT != null) {
      r.irrTarget = CalcCell.number(r.eurTarget.number! * eurT);
    }
    r.steps.add(CalcStep(
      '۵. تبدیل به ریال با نرخ یوروی سال هدف',
      'یورو × ${eurT == null ? '؟' : _g(eurT)} (${settings.eurTargetOverride != null ? 'نرخ دستی' : 'جدول «${settings.fxType}»'})',
      r.irrTarget.isNumber ? _f(r.irrTarget.number!, 'ریال') : 'محاسبه نشد',
      warning: !r.irrTarget.isNumber,
    ));

    // ---------- AT..AX: ضرایب پیکربندی
    r.matF = factors.get('MAT', g);
    r.sealF = factors.get('SEAL_ARR', sv('seal_arrangement')) *
        factors.get('SEAL_CAT', sv('api682_category')) *
        factors.get('SEAL_PLAN', sv('api682_plan'));
    r.driveF = factors.get('DRV', sv('driver_type')) * factors.get('NACE', o);
    r.scopeF = factors.get('SC_DRV', sv('scope_driver')) *
        factors.get('SC_BSP', sv('scope_baseplate')) *
        factors.get('SC_SEAL', sv('scope_seal_support')) *
        factors.get('SC_COMM', sv('scope_comm_spares')) *
        factors.get('SC_2Y', sv('scope_2yr_spares')) *
        factors.get('SC_TPI', sv('scope_tpi')) *
        factors.get('SC_FAT', sv('scope_fat'));
    r.allF = r.matF * r.sealF * r.driveF * r.scopeF;
    r.steps.add(CalcStep(
      '۶. ضریب کل پیکربندی (نرمال‌سازی)',
      'متریال ${_g(r.matF)} × آب‌بند ${_g(r.sealF)} × محرک/NACE ${_g(r.driveF)} × Scope ${_g(r.scopeF)}',
      _g(r.allF),
    ));

    // ---------- AY / BC / BD
    if (r.eurSource.isNumber) r.normalizedEur = CalcCell.number(r.eurSource.number! / r.allF);
    if (r.eurTarget.isNumber) r.normalizedEscalatedEur = CalcCell.number(r.eurTarget.number! / r.allF);
    final kw = r.sizeKw.number;
    if (r.normalizedEscalatedEur.isNumber && kw != null && kw > 0) {
      r.costCoef = CalcCell.number(r.normalizedEscalatedEur.number! / math.pow(kw, n));
      r.steps.add(CalcStep('۷. ضریب هزینه (برای تخمین پمپ‌های جدید)',
          'یورو نرمال‌شده‌ی تعدیل‌شده ÷ kW^${_g(n)}', _g(r.costCoef.number!)));
    }

    // ---------- AS: هشدارهای کیفیت
    final qa = StringBuffer();
    if (z == 'EUR' && (aa ?? 0) > settings.eurCheckLimit) qa.write('Check currency (EUR>5M); ');
    if (aa == null) qa.write('No price; ');
    if (g == 'Not stated') qa.write('Material missing; ');
    if (sv('seal_arrangement') == 'Not stated') qa.write('Seal missing; ');
    if (!r.sizeKw.isNumber) qa.write('Size driver missing; ');
    if (az == null) qa.write('Base-year PPI missing; ');
    r.qaFlags = qa.toString();

    return r;
  }
}

// -----------------------------------------------------------------------------
// قالب‌بندی متن گام‌ها

String _g(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) return _group(v.toStringAsFixed(0));
  final a = v.abs();
  final s = a >= 1000 ? v.toStringAsFixed(0) : (a >= 1 ? v.toStringAsFixed(4) : v.toStringAsPrecision(4));
  return _group(s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : s);
}

String _group(String s) {
  final neg = s.startsWith('-');
  final body = neg ? s.substring(1) : s;
  final parts = body.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  return '${neg ? '-' : ''}$buf${parts.length > 1 ? '.${parts[1]}' : ''}';
}

String _f(double v, String unit) => '${_g(v)} $unit';

/// معادل فارسی پیام‌های v8.
String _msg(String? code) => calcMessageFa(code);

String calcMessageFa(String? code) => switch (code) {
      null => '—',
      '(Not stated)' => 'قیمت ثبت نشده',
      '(Cost year not stated)' => 'سال قیمت مشخص نیست',
      '(FX rate missing)' => 'نرخ ارز سال قیمت موجود نیست',
      '(Currency?)' => 'ارز نامعتبر',
      '(Check currency – excluded)' => 'ارز مشکوک — کنار گذاشته شد',
      '(PPI/FX missing)' => 'شاخص PPI یا نرخ ارز موجود نیست',
      _ => code,
    };

/// معادل فارسی هشدارهای کیفیت.
List<String> qaFlagsFa(String flags) => [
      for (final f in flags.split(';').map((e) => e.trim()).where((e) => e.isNotEmpty))
        switch (f) {
          'Check currency (EUR>5M)' => 'ارز مشکوک (یورو بیش از ۵ میلیون)',
          'No price' => 'بدون قیمت',
          'Material missing' => 'کلاس متریال نامشخص',
          'Seal missing' => 'آب‌بند نامشخص',
          'Size driver missing' => 'توان / دبی و هد نامشخص',
          'Base-year PPI missing' => 'PPI سال پایه موجود نیست',
          _ => f,
        },
    ];
