// محاسبات بانک قیمت دیسالتر — پیاده‌سازی دقیق Calc_Spec فایل Desalters_Price_Bank v8
// (آزمون طلایی با شیت Test_Cases همان فایل، تلورانس نسبی ۱e-۹).
//
//   GEO-1  حجم هر وسل = π/4 × (ID/1000)² × (T/T/1000) ؛ حجم کل = حجم هر وسل × تعداد وسل
//   KVA-1  kVA نصب‌شده = تعداد ترانس × kVA هر ترانس ؛ توان لازم = kVA هر ترانس ÷ کسر ظرفیت
//   FAC-2  ALL_F = TECH × MAT × NACE × SCOPE(۵ ضریب) × KVA_F ؛ STAGE_F فقط در روش A
//   NRM    یورو نرمال‌شده = یورو ÷ ALL_F (سال منبع و سال هدف)
//   ESC    تعدیل با روش رده (پیش‌فرض M7: شاخص ترکیبی ۰٫۷۰ C25.29 + ۰٫۱۵ C27.11 + ۰٫۱۵ C28.13)
//   COEF   Coef A = NormEsc ÷ STAGE_F ÷ BPD^nA ؛ Coef B = NormEsc ÷ m³^nB
//   FIT-1  نمای برازش‌شده = شیب رگرسیون ln-ln روی اقلام Include=Y (حداقل ۳ نقطه، معتبر بین ۰٫۲ و ۱٫۲)
//   EST    روش A (ظرفیت)، B (حجم)، C (نزدیک‌ترین مرجع)؛ نهایی = میانگین وزنی با وزن تعداد همتا (C وزن ۱)

import 'dart:math' as math;

import '../catalog/profiles.dart';
import 'generic_engine.dart';
import 'pump_engine.dart' show FactorTable;

/// پارامترهای بانک دیسالتر (شیت Assumptions)
class DesalterParams {
  const DesalterParams({
    this.nA = 0.6,
    this.useFittedA = false,
    this.nB = 0.6,
    this.useFittedB = false,
    this.kvaActive = false,
    this.kvaExponent = 0.3,
    this.kvaBase = 1000,
    this.finalBasis = weighted,
  });

  /// نمای ظرفیت (قیمت ∝ BPD^n) — Provisional
  final double nA;
  final bool useFittedA;

  /// نمای حجم (قیمت ∝ m³^n) — Provisional
  final double nB;
  final bool useFittedB;

  /// محرک kVA (پیش‌فرض خاموش: KVA_F = ۱)
  final bool kvaActive;
  final double kvaExponent;
  final double kvaBase;

  /// مبنای نتیجه‌ی نهایی تخمین
  final String finalBasis;

  static const weighted = 'Weighted average', simple = 'Simple average';
  static const methodA = 'Method A', methodB = 'Method B', methodC = 'Method C';
  static const finalBases = [weighted, simple, methodA, methodB, methodC];
  static const finalBasesFa = {
    weighted: 'میانگین وزنی (وزن = تعداد همتا، روش C وزن ۱)',
    simple: 'میانگین ساده‌ی روش‌ها',
    methodA: 'فقط روش A (ظرفیت)',
    methodB: 'فقط روش B (حجم)',
    methodC: 'فقط روش C (مرجع)',
  };

  /// ۱ m³/h = ۲۴ × ۶٫۲۸۹۸۱ بشکه در روز
  static const bpdPerM3h = 24 * 6.28981;

  /// محدوده‌ی معتبر نمای برازش‌شده
  static const fitMin = 0.2, fitMax = 1.2;
}

/// ضرایب پیکربندی یک قلم/تجهیز
class DesalterFactors {
  DesalterFactors(this.parts, this.kvaF);

  /// گروه ← (گزینه، ضریب) برای TECH، MAT، NACE، STAGE و ۵ گروه Scope
  final Map<String, (String?, double)> parts;
  final double kvaF;

  double _f(String g) => parts[g]?.$2 ?? 1.0;
  double get tech => _f('TECH');
  double get mat => _f('MAT');
  double get nace => _f('NACE');
  double get stage => _f('STAGE');
  double get scope => desalterScopeFields.keys.fold(1.0, (s, g) => s * _f(g));
  double get all => tech * mat * nace * scope * kvaF;
}

double? _n(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

/// توان لازم (kVA ۱۰۰٪) = kVA هر ترانس ÷ کسر ظرفیت هر ترانس
double? desalterDemandKva(Map<String, Object?> v) {
  final kva = _n(v['kva_per_transformer']), sz = _n(v['transformer_sizing']);
  if (kva == null || sz == null || sz <= 0) return null;
  return kva / sz;
}

/// ضریب محرک kVA: (توان لازم ÷ مبنا)^m وقتی فعال است؛ وگرنه ۱
double desalterKvaFactor(double? demandKva, DesalterParams p) {
  if (!p.kvaActive || demandKva == null || demandKva <= 0 || p.kvaBase <= 0) return 1.0;
  return math.pow(demandKva / p.kvaBase, p.kvaExponent).toDouble();
}

DesalterFactors desalterFactors(Map<String, Object?> v, FactorTable t, DesalterParams p, {double? demandKva}) {
  final parts = <String, (String?, double)>{};
  for (final g in desalterFactorGroups) {
    final o = desalterFactorOption(g, v);
    parts[g] = (o, o == null ? 1.0 : t.get(g, o));
  }
  return DesalterFactors(parts, desalterKvaFactor(demandKva ?? desalterDemandKva(v), p));
}

/// «ASME VIII Div.1, IPS-G-ME-150, NACE MR0175» — ستون Standards
String desalterStandards(Map<String, Object?> v) {
  final parts = <String>[];
  final code = v['vessel_design_code']?.toString() ?? '';
  final ips = v['ips_standard']?.toString() ?? '';
  if (code.isNotEmpty && code != 'Not stated') parts.add(code);
  if (ips.isNotEmpty && ips != 'None') parts.add(ips);
  if (v['nace']?.toString() == 'Y') parts.add('NACE MR0175');
  return parts.isEmpty ? 'Not stated' : parts.join(', ');
}

/// ورودی محاسبه‌ی یک قلم بانک
class DesalterRecord {
  const DesalterRecord({
    required this.id,
    required this.label,
    required this.values,
    required this.price,
    this.include = true,
  });
  final int id;

  /// «پروژه | تگ»
  final String label;
  final Map<String, Object?> values;
  final GenericInput price;
  final bool include;
}

/// نتیجه‌ی محاسبه‌ی یک قلم (هم‌نام ستون‌های فرمولی Master بانک دیسالتر)
class DesalterCalc {
  DesalterCalc(this.record, this.price, this.factors);
  final DesalterRecord record;
  final GenericCalcResult price;
  final DesalterFactors factors;

  double? volumePerVessel, totalVolume, installedKva, demandKva, bpd;
  double? eurSource, normEurSource, normEsc, coefA, coefB;
  double? lnBpd, lnNormEscStage, lnM3, lnNormEsc;
  String standards = '';
  String qaFlag = '';

  /// نتیجه‌ی کل بانک (نمای برازش‌شده و نمای به‌کاررفته)
  DesalterBankResult? bank;

  double? usdSource, irrSource, indexBase, indexTarget;

  double? get eurTarget => price.eurTarget.number;
  String? get subCategory => record.values['sub_category']?.toString();
}

class DesalterBankResult {
  DesalterBankResult(this.rows, this.fittedA, this.fittedB, this.pointsA, this.pointsB, this.nA, this.nB);
  final List<DesalterCalc> rows;

  /// نمای برازش‌شده از داده‌ی بانک (null = کمتر از ۳ نقطه)
  final double? fittedA, fittedB;
  final int pointsA, pointsB;

  /// نمای به‌کاررفته
  final double nA, nB;

  DesalterCalc? byId(int id) => rows.where((r) => r.record.id == id).firstOrNull;
}

/// شیب رگرسیون خطی (n·Σxy − Σx·Σy) ÷ (n·Σx² − (Σx)²) ؛ کمتر از ۳ نقطه یا بدون پراکندگی = null
double? lnSlope(List<(double, double)> pts) {
  final n = pts.length;
  if (n < 3) return null;
  var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
  for (final (x, y) in pts) {
    sx += x;
    sy += y;
    sxx += x * x;
    sxy += x * y;
  }
  final d = n * sxx - sx * sx;
  if (d == 0) return null;
  return (n * sxy - sx * sy) / d;
}

double _usedExponent(double? fitted, bool useFitted, double provisional) =>
    (useFitted && fitted != null && fitted >= DesalterParams.fitMin && fitted <= DesalterParams.fitMax)
        ? fitted
        : provisional;

/// محاسبه‌ی همه‌ی اقلام بانک دیسالتر با موتور تعدیل [engine] (روش و سبد شاخص رده).
DesalterBankResult computeDesalterBank(
  List<DesalterRecord> records, {
  required GenericEngine engine,
  required FactorTable factors,
  required DesalterParams params,
}) {
  final rows = <DesalterCalc>[];
  for (final rec in records) {
    final v = rec.values;
    final price = engine.calculate(rec.price);
    final c = DesalterCalc(rec, price, desalterFactors(v, factors, params));
    c.volumePerVessel = desalterVesselVolume(v);
    c.totalVolume = desalterShellVolume(v);
    final nTrf = _n(v['n_transformers']), kva = _n(v['kva_per_transformer']);
    c.installedKva = (nTrf != null && kva != null) ? nTrf * kva : null;
    c.demandKva = desalterDemandKva(v);
    c.bpd = _n(v['capacity_bpd']);
    c.standards = desalterStandards(v);
    // معادل سال منبع: قیمتی که به همان ارز است، حتی بدون سال قیمت همان قیمت است (FX-2)
    final cur = rec.price.currency, amount = _n(rec.price.unitPrice);
    c.eurSource = price.eurSource.number ?? (cur == 'EUR' ? amount : null);
    c.usdSource = price.usdSource.number ?? (cur == 'USD' ? amount : null);
    c.irrSource = price.irrSource.number ?? (cur == 'IRR' ? amount : null);
    final y = rec.price.costYear is num ? (rec.price.costYear! as num).toInt() : null;
    c.indexBase = price.indexBase ?? (y == null ? null : engine.indexAt(y));
    c.indexTarget = price.indexTarget ?? engine.indexAt(engine.settings.targetYear);
    final all = c.factors.all;
    if (c.eurSource != null) c.normEurSource = c.eurSource! / all;
    final esc = price.eurTarget.number;
    if (esc != null) c.normEsc = esc / all;

    final qa = StringBuffer();
    if (_n(rec.price.unitPrice) == null) qa.write('No price; ');
    if ((c.bpd ?? 0) == 0) qa.write('Capacity missing; ');
    if ((c.totalVolume ?? 0) == 0) qa.write('Dimensions missing; ');
    if (v['des_material']?.toString() == 'Not stated') qa.write('Material missing; ');
    if (c.indexBase == null) qa.write('Base-year index missing; ');
    if (v['sub_category']?.toString() == 'PKG-DES-AGG') qa.write('Aggregate item; ');
    if (params.kvaActive && (c.demandKva ?? 0) == 0) qa.write('kVA missing (driver active); ');
    if (!rec.include) qa.write('Excluded (Include=N); ');
    c.qaFlag = qa.toString();
    rows.add(c);
  }

  // FIT-1: نمای برازش‌شده
  final ptsA = <(double, double)>[], ptsB = <(double, double)>[];
  for (final c in rows) {
    final ne = c.normEsc;
    if (!c.record.include || ne == null || ne <= 0) continue;
    if ((c.bpd ?? 0) > 0) {
      c.lnBpd = math.log(c.bpd!);
      c.lnNormEscStage = math.log(ne / c.factors.stage);
      ptsA.add((c.lnBpd!, c.lnNormEscStage!));
    }
    if ((c.totalVolume ?? 0) > 0) {
      c.lnM3 = math.log(c.totalVolume!);
      c.lnNormEsc = math.log(ne);
      ptsB.add((c.lnM3!, c.lnNormEsc!));
    }
  }
  final fa = lnSlope(ptsA), fb = lnSlope(ptsB);
  final nA = _usedExponent(fa, params.useFittedA, params.nA);
  final nB = _usedExponent(fb, params.useFittedB, params.nB);
  for (final c in rows) {
    final ne = c.normEsc;
    if (ne == null) continue;
    if ((c.bpd ?? 0) > 0) c.coefA = ne / c.factors.stage / math.pow(c.bpd!, nA);
    if ((c.totalVolume ?? 0) > 0) c.coefB = ne / math.pow(c.totalVolume!, nB);
  }
  final res = DesalterBankResult(rows, fa, fb, ptsA.length, ptsB.length, nA, nB);
  for (final c in rows) {
    c.bank = res;
  }
  return res;
}

// =============================================================================
// تخمین پکیج دیسالتر جدید

class DesalterEstimateInput {
  const DesalterEstimateInput({
    required this.values,
    this.demandKva,
    this.matchSubCategory = false,
    this.referenceId,
    this.basisCapacity = false,
    this.quantity = 1,
  });

  /// مشخصات تجهیز جدید با همان کلیدهای قالب (فناوری، متریال، NACE، مرحله، Scope، ظرفیت، ابعاد، تعداد وسل)
  final Map<String, Object?> values;
  final double? demandKva;

  /// فقط همتاهای هم‌زیرگروه
  final bool matchSubCategory;

  /// قلم مرجع روش C
  final int? referenceId;

  /// مبنای اندازه‌ی روش C: ظرفیت (true) یا حجم (false)
  final bool basisCapacity;
  final double quantity;
}

class DesalterMethodResult {
  DesalterMethodResult(this.peers, this.coefAvg, this.coefMin, this.coefMax, this.eur, this.low, this.high);
  final int peers;
  final double? coefAvg, coefMin, coefMax, eur, low, high;
}

class DesalterEstimate {
  late DesalterFactors factors;
  double? volume, bpd;
  double nA = 0.6, nB = 0.6;
  bool kvaOn = false;
  double kvaExponent = 0.3;
  List<DesalterCalc> peers = const [];
  DesalterMethodResult a = DesalterMethodResult(0, null, null, null, null, null, null);
  DesalterMethodResult b = DesalterMethodResult(0, null, null, null, null, null, null);
  DesalterCalc? reference;
  double? referenceNormEsc, sizeRatio, eurC;
  double? simpleAvg, weightedAvg, finalEur;
  String finalBasis = DesalterParams.weighted;
  double? usd, irr, irrTotal, eurRate, usdRate;
  final List<String> warnings = [];

  /// اختلاف هر روش با نتیجه‌ی نهایی
  double? spread(double? m) => (m == null || finalEur == null || finalEur == 0) ? null : m / finalEur! - 1;
}

DesalterEstimate estimateDesalter(
  DesalterEstimateInput inp,
  DesalterBankResult bank, {
  required FactorTable factors,
  required DesalterParams params,
  double? eurRate,
  double? usdRate,
}) {
  final e = DesalterEstimate()
    ..nA = bank.nA
    ..nB = bank.nB
    ..kvaOn = params.kvaActive
    ..kvaExponent = params.kvaExponent
    ..finalBasis = params.finalBasis
    ..eurRate = eurRate
    ..usdRate = usdRate;
  final v = inp.values;
  e.factors = desalterFactors(v, factors, params, demandKva: inp.demandKva);
  final all = e.factors.all, st = e.factors.stage;
  e.volume = desalterShellVolume(v);
  e.bpd = _n(v['capacity_bpd']);
  final sub = v['sub_category']?.toString();
  e.peers = [
    for (final r in bank.rows)
      if (r.record.include && (!inp.matchSubCategory || r.subCategory == sub)) r,
  ];
  final pa = [for (final r in e.peers) if ((r.coefA ?? 0) > 0) r];
  final pb = [for (final r in e.peers) if ((r.coefB ?? 0) > 0) r];

  DesalterMethodResult method(List<double> cs, double? size, double n, double k) {
    if (cs.isEmpty) return DesalterMethodResult(0, null, null, null, null, null, null);
    final avg = cs.reduce((a, b) => a + b) / cs.length;
    final mn = cs.reduce(math.min), mx = cs.reduce(math.max);
    if (size == null || size <= 0) return DesalterMethodResult(cs.length, avg, mn, mx, null, null, null);
    final s = math.pow(size, n) * k;
    return DesalterMethodResult(cs.length, avg, mn, mx, avg * s, mn * s, mx * s);
  }

  e.a = method([for (final r in pa) r.coefA!], e.bpd, e.nA, all * st);
  e.b = method([for (final r in pb) r.coefB!], e.volume, e.nB, all);

  // روش C: نزدیک‌ترین مرجع (قلم انتخابی)
  final ref = inp.referenceId == null ? null : bank.byId(inp.referenceId!);
  e.reference = ref;
  if (ref != null) {
    e.referenceNormEsc = ref.normEsc;
    final refSize = inp.basisCapacity ? ref.bpd : ref.totalVolume;
    final newSize = inp.basisCapacity ? e.bpd : e.volume;
    if (refSize != null && refSize != 0 && newSize != null) e.sizeRatio = newSize / refSize;
    if (e.referenceNormEsc != null && e.sizeRatio != null) {
      e.eurC = e.referenceNormEsc! *
          math.pow(e.sizeRatio!, inp.basisCapacity ? e.nA : e.nB) *
          all *
          (inp.basisCapacity ? st / ref.factors.stage : 1);
    }
  }

  final avail = [
    if (e.a.eur != null) (e.a.eur!, e.a.peers.toDouble()),
    if (e.b.eur != null) (e.b.eur!, e.b.peers.toDouble()),
    if (e.eurC != null) (e.eurC!, 1.0),
  ];
  if (avail.isNotEmpty) {
    e.simpleAvg = avail.fold<double>(0, (s, x) => s + x.$1) / avail.length;
    final w = avail.fold<double>(0, (s, x) => s + x.$2);
    e.weightedAvg = avail.fold<double>(0, (s, x) => s + x.$1 * x.$2) / w;
  }
  e.finalEur = switch (params.finalBasis) {
    DesalterParams.simple => e.simpleAvg,
    DesalterParams.methodA => e.a.eur,
    DesalterParams.methodB => e.b.eur,
    DesalterParams.methodC => e.eurC,
    _ => e.weightedAvg,
  };
  if (e.finalEur != null && eurRate != null) {
    e.irr = e.finalEur! * eurRate;
    e.irrTotal = e.irr! * inp.quantity;
    if (usdRate != null) e.usd = e.finalEur! * eurRate / usdRate;
  }

  // هشدارها
  if (e.a.peers < 5 && e.b.peers < 5) e.warnings.add('Peers < 5 in both methods');
  if (pa.isNotEmpty && e.bpd != null) {
    final l = [for (final r in pa) r.bpd!];
    if (e.bpd! < l.reduce(math.min) || e.bpd! > l.reduce(math.max)) e.warnings.add('A: capacity outside peer range');
  }
  if (pb.isNotEmpty && e.volume != null) {
    final l = [for (final r in pb) r.totalVolume!];
    if (e.volume! < l.reduce(math.min) || e.volume! > l.reduce(math.max)) e.warnings.add('B: volume outside peer range');
  }
  return e;
}

/// متن فارسی هشدارهای تخمین
const desalterWarningFa = {
  'Peers < 5 in both methods': 'تعداد همتا در هر دو روش A و B کمتر از ۵ است؛ نتیجه را با احتیاط به کار ببرید.',
  'A: capacity outside peer range': 'روش A: ظرفیت خارج از بازه‌ی همتاهاست (برون‌یابی).',
  'B: volume outside peer range': 'روش B: حجم خارج از بازه‌ی همتاهاست (برون‌یابی).',
};
