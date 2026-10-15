// محاسبات بانک قیمت کمپرسور هوا — پیاده‌سازی دقیق Calc_Spec فایل Air_Compressor_Price_Bank v8
// (آزمون طلایی با Test_Cases همان فایل، تلورانس نسبی ۱e-۹).
//
//   FAC    ALL_F = TYPE × STD × ORIGIN × DRV × ۸ ضریب Scope (گزینه‌ی ناموجود = ۱)
//   NRM    یورو نرمال‌شده‌ی هر کمپرسور = یورو ÷ تعداد کمپرسور در واحد قیمت ÷ ALL_F (سال منبع و سال هدف)
//   ESC    تعدیل با روش رده (پیش‌فرض M4 = C28.13؛ M5 = BLS 333912 آمریکا به یورو)
//   PEER   همتا = Include=Y و Use as Peer=Y و NormEsc عددی و دبی > ۰
//   FIT    n برازش‌شده = شیب ln(NormEsc) بر ln(دبی) روی همتاها (حداقل ۳ نقطه؛ معتبر بین ۰٫۲ و ۱٫۰)
//   EST    A توانی (Coef × Flow^n)، A2 ثابت + متغیر (a + b·Flow)، B یورو/کیلوگرم، C نزدیک‌ترین مرجع،
//          E بنچمارک Seider (فقط کنترل)؛ نهایی = میانگین وزنی (وزن A و B = همتا، A2 = نقاط برازش، C = ۱)

import 'dart:math' as math;

import '../catalog/profiles.dart';
import 'desalter.dart' show lnSlope;
import 'generic_engine.dart';
import 'pump_engine.dart' show FactorTable;

/// پارامترهای بانک کمپرسور (شیت Assumptions)
class CompressorParams {
  const CompressorParams({
    this.n = 0.4,
    this.useFitted = false,
    this.specificPower = 0.12,
    this.benchmarkFactor = 2.5,
    this.finalBasis = weighted,
    this.minPeers = 5,
  });

  /// نمای دبی (قیمت ∝ Nm³/h^n) — Provisional از دو رکورد گچساران
  final double n;
  final bool useFitted;

  /// توان ویژه (kW به ازای Nm³/h در ۹ تا ۱۰ barg) — فقط برای kW تخمینی و روش E
  final double specificPower;

  /// ضریب پکیج نفتی روش E (Provisional، فقط کنترل)
  final double benchmarkFactor;
  final String finalBasis;

  /// حداقل همتا پیش از هشدار
  final int minPeers;

  static const weighted = 'Weighted average', simple = 'Simple average';
  static const methodA = 'Method A', methodA2 = 'Method A2', methodB = 'Method B', methodC = 'Method C';
  static const finalBases = [weighted, simple, methodA, methodA2, methodB, methodC];
  static const finalBasesFa = {
    weighted: 'میانگین وزنی (وزن = تعداد همتا، A2 = نقاط برازش، C = ۱)',
    simple: 'میانگین ساده‌ی روش‌ها',
    methodA: 'فقط روش A (توانی)',
    methodA2: 'فقط روش A2 (ثابت + متغیر)',
    methodB: 'فقط روش B (وزن)',
    methodC: 'فقط روش C (مرجع)',
  };

  static const fitMin = 0.2, fitMax = 1.0;

  /// سال پایه‌ی بنچمارک Seider (CE 567، ۲۰۱۳) — شاخص BLS همان سال میلادی
  static const benchmarkYear = 2013;
  static const usPpiSeries = 'PPI_US_333912_GREG';
}

class CompressorFactors {
  CompressorFactors(this.parts);

  /// گروه ← (گزینه، ضریب)
  final Map<String, (String?, double)> parts;

  double _f(String g) => parts[g]?.$2 ?? 1.0;
  double get type => _f('TYPE');
  double get std => _f('STD');
  double get origin => _f('ORIGIN');
  double get driver => _f('DRV');
  double get scope => compressorScopeFields.keys.fold(1.0, (s, g) => s * _f(g));
  double get all => type * std * origin * driver * scope;
}

double? _n(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

CompressorFactors compressorFactors(Map<String, Object?> v, FactorTable t) {
  final parts = <String, (String?, double)>{};
  for (final g in compressorFactorGroups) {
    final o = compressorFactorOption(g, v);
    parts[g] = (o, o == null ? 1.0 : t.get(g, o));
  }
  return CompressorFactors(parts);
}

/// «API 618, IPS-M-PM-211» — ستون Standards
String compressorStandards(Map<String, Object?> v) {
  final parts = <String>[];
  final s = v['design_standard']?.toString() ?? '';
  final ips = v['ips_standard']?.toString() ?? '';
  if (s.isNotEmpty && s != 'Not stated') parts.add(s);
  if (ips.isNotEmpty && ips != 'None') parts.add(ips);
  return parts.isEmpty ? 'Not stated' : parts.join(', ');
}

class CompressorRecord {
  const CompressorRecord({
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

  bool get usePeer => values['use_as_peer']?.toString() != 'N';
}

/// نتیجه‌ی محاسبه‌ی یک قلم (هم‌نام ستون‌های فرمولی Master بانک کمپرسور)
class CompressorCalc {
  CompressorCalc(this.record, this.price, this.factors);
  final CompressorRecord record;
  final GenericCalcResult price;
  final CompressorFactors factors;

  double? flow, weight, perUnit, shaftKw;
  double? eurSource, usdSource, irrSource, indexBase, indexTarget;
  double? normEurSource, normEsc, coefA, coefB;
  bool isPeer = false;
  String standards = '', family = '', qaFlag = '';
  CompressorBankResult? bank;

  String? get subCategory => record.values['sub_category']?.toString();
}

class CompressorBankResult {
  CompressorBankResult(this.rows, this.fitted, this.points, this.n);
  final List<CompressorCalc> rows;

  /// n برازش‌شده (null = کمتر از ۳ نقطه)
  final double? fitted;
  final int points;

  /// n به‌کاررفته
  final double n;

  CompressorCalc? byId(int id) => rows.where((r) => r.record.id == id).firstOrNull;
  List<CompressorCalc> get peers => [for (final r in rows) if (r.isPeer) r];
}

CompressorBankResult computeCompressorBank(
  List<CompressorRecord> records, {
  required GenericEngine engine,
  required FactorTable factors,
  required CompressorParams params,
}) {
  final rows = <CompressorCalc>[];
  for (final rec in records) {
    final v = rec.values;
    final price = engine.calculate(rec.price);
    final c = CompressorCalc(rec, price, compressorFactors(v, factors));
    c.flow = _n(v['flow_m3h']);
    c.weight = _n(v['unit_weight_kg']);
    c.perUnit = _n(v['compressors_per_price_unit']);
    if ((c.flow ?? 0) > 0) c.shaftKw = c.flow! * params.specificPower;
    c.standards = compressorStandards(v);
    c.family = compressorFamily(v['compressor_type']?.toString());
    final cur = rec.price.currency, amount = _n(rec.price.unitPrice);
    c.eurSource = price.eurSource.number ?? (cur == 'EUR' ? amount : null);
    c.usdSource = price.usdSource.number ?? (cur == 'USD' ? amount : null);
    c.irrSource = price.irrSource.number ?? (cur == 'IRR' ? amount : null);
    final y = rec.price.costYear is num ? (rec.price.costYear! as num).toInt() : null;
    c.indexBase = price.indexBase ?? (y == null ? null : engine.indexAt(y));
    c.indexTarget = price.indexTarget ?? engine.indexAt(engine.settings.targetYear);
    final all = c.factors.all, pu = c.perUnit ?? 0;
    if (c.eurSource != null && pu > 0) c.normEurSource = c.eurSource! / pu / all;
    final esc = price.eurTarget.number;
    if (esc != null && pu > 0) c.normEsc = esc / pu / all;
    c.isPeer = rec.include && rec.usePeer && c.normEsc != null && (c.flow ?? 0) > 0;

    final qa = StringBuffer();
    if (amount == null) qa.write('No price; ');
    if ((c.flow ?? 0) == 0) qa.write('Capacity missing; ');
    if (v['compressor_type']?.toString() == 'Not stated') qa.write('Type missing; ');
    if (pu == 0) qa.write('Compressors per price unit missing; ');
    if (c.indexBase == null) qa.write('Base-year index missing; ');
    if (v['sub_category']?.toString() == 'CMP-CMB') qa.write('Combined with other package; ');
    if (!rec.usePeer) qa.write('Excluded from Estimator peers; ');
    if (!rec.include) qa.write('Excluded (Include=N); ');
    c.qaFlag = qa.toString();
    rows.add(c);
  }

  final pts = [for (final c in rows) if (c.isPeer) (math.log(c.flow!), math.log(c.normEsc!))];
  final fitted = lnSlope(pts);
  final n = (params.useFitted && fitted != null && fitted >= CompressorParams.fitMin && fitted <= CompressorParams.fitMax)
      ? fitted
      : params.n;
  for (final c in rows) {
    final ne = c.normEsc;
    if (ne == null) continue;
    if ((c.flow ?? 0) > 0) c.coefA = ne / math.pow(c.flow!, n);
    if ((c.weight ?? 0) > 0) c.coefB = ne / c.weight!;
  }
  final res = CompressorBankResult(rows, fitted, pts.length, n);
  for (final c in rows) {
    c.bank = res;
  }
  return res;
}

// =============================================================================
// تخمین کمپرسور / پکیج جدید

class CompressorEstimateInput {
  const CompressorEstimateInput({
    required this.values,
    this.matchSubCategory = false,
    this.referenceId,
    this.basisWeight = false,
    this.quantity = 1,
  });

  /// مشخصات تجهیز جدید با کلیدهای قالب (زیرگروه، نوع، استاندارد، مبدأ، محرک، Scope، دبی، وزن، تعداد کمپرسور)
  final Map<String, Object?> values;
  final bool matchSubCategory;
  final int? referenceId;

  /// مبنای اندازه‌ی روش C: وزن (true) یا دبی (false)
  final bool basisWeight;

  /// تعداد واحد قیمت
  final double quantity;
}

class CompressorMethodResult {
  CompressorMethodResult(this.peers, this.coefAvg, this.coefMin, this.coefMax, this.eur, this.low, this.high);
  final int peers;
  final double? coefAvg, coefMin, coefMax, eur, low, high;
  static final empty = CompressorMethodResult(0, null, null, null, null, null, null);
}

class CompressorEstimate {
  late CompressorFactors factors;
  double? flow, weight, perUnit, shaftKw;
  double n = 0.4;
  List<CompressorCalc> peers = const [];
  CompressorMethodResult a = CompressorMethodResult.empty, b = CompressorMethodResult.empty;
  int a2Points = 0;
  double? a2Slope, a2Fixed, eurA2;
  CompressorCalc? reference;
  double? referenceNormEsc, sizeRatio, eurC;
  double? hp, blsTarget, blsBase, eurE;
  double? simpleAvg, weightedAvg, finalEur;
  String finalBasis = CompressorParams.weighted;
  double? usd, irr, irrTotal, eurRate, usdRate;
  final List<String> warnings = [];

  double? spread(double? m) => (m == null || finalEur == null || finalEur == 0) ? null : m / finalEur! - 1;
}

CompressorEstimate estimateCompressor(
  CompressorEstimateInput inp,
  CompressorBankResult bank, {
  required FactorTable factors,
  required CompressorParams params,
  double? eurRate,
  double? usdRate,
  double? blsTarget,
  double? blsBase,
}) {
  final e = CompressorEstimate()
    ..n = bank.n
    ..finalBasis = params.finalBasis
    ..eurRate = eurRate
    ..usdRate = usdRate
    ..blsTarget = blsTarget
    ..blsBase = blsBase;
  final v = inp.values;
  e.factors = compressorFactors(v, factors);
  final all = e.factors.all;
  e.flow = _n(v['flow_m3h']);
  e.weight = _n(v['unit_weight_kg']);
  e.perUnit = _n(v['compressors_per_price_unit']) ?? 1;
  final pu = e.perUnit!;
  if ((e.flow ?? 0) > 0) e.shaftKw = e.flow! * params.specificPower;
  final sub = v['sub_category']?.toString();
  final allPeers = bank.peers;
  e.peers = [for (final r in allPeers) if (!inp.matchSubCategory || r.subCategory == sub) r];
  final pa = [for (final r in e.peers) if ((r.coefA ?? 0) > 0) r];
  final pb = [for (final r in e.peers) if ((r.coefB ?? 0) > 0) r];

  CompressorMethodResult method(List<double> cs, double? size, double k) {
    if (cs.isEmpty) return CompressorMethodResult.empty;
    final avg = cs.reduce((a, b) => a + b) / cs.length;
    final mn = cs.reduce(math.min), mx = cs.reduce(math.max);
    if (size == null || size <= 0) return CompressorMethodResult(cs.length, avg, mn, mx, null, null, null);
    final s = size * k;
    return CompressorMethodResult(cs.length, avg, mn, mx, avg * s, mn * s, mx * s);
  }

  e.a = method([for (final r in pa) r.coefA!], (e.flow ?? 0) > 0 ? math.pow(e.flow!, e.n).toDouble() : null, all * pu);
  e.b = method([for (final r in pb) r.coefB!], e.weight, all * pu);

  // A2: رگرسیون خطی NormEsc بر دبی روی همه‌ی همتاها (بدون فیلتر زیرگروه)
  e.a2Points = allPeers.length;
  if (e.a2Points >= 2) {
    final m = e.a2Points.toDouble();
    var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
    for (final r in allPeers) {
      sx += r.flow!;
      sy += r.normEsc!;
      sxx += r.flow! * r.flow!;
      sxy += r.flow! * r.normEsc!;
    }
    final d = m * sxx - sx * sx;
    if (d != 0) {
      e.a2Slope = (m * sxy - sx * sy) / d;
      e.a2Fixed = (sy - e.a2Slope! * sx) / m;
      if (e.a2Slope! >= 0 && (e.flow ?? 0) > 0) e.eurA2 = (e.a2Fixed! + e.a2Slope! * e.flow!) * all * pu;
    }
  }

  // C: نزدیک‌ترین مرجع
  final ref = inp.referenceId == null ? null : bank.byId(inp.referenceId!);
  e.reference = ref;
  if (ref != null) {
    e.referenceNormEsc = ref.normEsc;
    final refSize = inp.basisWeight ? ref.weight : ref.flow;
    final newSize = inp.basisWeight ? e.weight : e.flow;
    if (refSize != null && refSize != 0 && newSize != null) e.sizeRatio = newSize / refSize;
    if (e.referenceNormEsc != null && e.sizeRatio != null) {
      e.eurC = e.referenceNormEsc! * math.pow(e.sizeRatio!, inp.basisWeight ? 1 : e.n) * all * pu;
    }
  }

  // E: بنچمارک Seider (اسکرو، موتور برقی، ۱۰ تا ۷۵۰ hp) — فقط کنترل
  if (e.shaftKw != null) {
    e.hp = e.shaftKw! / 0.7457;
    if (blsTarget != null && blsBase != null && blsBase > 0 && eurRate != null && usdRate != null) {
      e.eurE = math.exp(8.2496 + 0.7243 * math.log(e.hp!)) *
          blsTarget /
          blsBase *
          params.benchmarkFactor *
          usdRate /
          eurRate *
          pu;
    }
  }

  final avail = [
    if (e.a.eur != null) (e.a.eur!, e.a.peers.toDouble()),
    if (e.eurA2 != null) (e.eurA2!, e.a2Points.toDouble()),
    if (e.b.eur != null) (e.b.eur!, e.b.peers.toDouble()),
    if (e.eurC != null) (e.eurC!, 1.0),
  ];
  if (avail.isNotEmpty) {
    e.simpleAvg = avail.fold<double>(0, (s, x) => s + x.$1) / avail.length;
    final w = avail.fold<double>(0, (s, x) => s + x.$2);
    if (w > 0) e.weightedAvg = avail.fold<double>(0, (s, x) => s + x.$1 * x.$2) / w;
  }
  e.finalEur = switch (params.finalBasis) {
    CompressorParams.simple => e.simpleAvg,
    CompressorParams.methodA => e.a.eur,
    CompressorParams.methodA2 => e.eurA2,
    CompressorParams.methodB => e.b.eur,
    CompressorParams.methodC => e.eurC,
    _ => e.weightedAvg,
  };
  if (e.finalEur != null && eurRate != null) {
    e.irr = e.finalEur! * eurRate;
    e.irrTotal = e.irr! * inp.quantity;
    if (usdRate != null) e.usd = e.finalEur! * eurRate / usdRate;
  }

  // هشدارها (همان متن شیت Estimator)
  if (e.a.peers < params.minPeers) e.warnings.add('A peers < ${params.minPeers}');
  if (e.b.peers < params.minPeers) e.warnings.add('B peers < ${params.minPeers}');
  if (pa.isNotEmpty && (e.flow ?? 0) > 0) {
    final l = [for (final r in pa) r.flow!];
    if (e.flow! < l.reduce(math.min) || e.flow! > l.reduce(math.max)) e.warnings.add('A: capacity outside peer range');
  }
  if (e.a2Slope != null && e.a2Slope! < 0) e.warnings.add('A2: negative slope – ignore A2');
  if (e.hp != null && (e.hp! < 10 || e.hp! > 750)) e.warnings.add('E: outside Seider screw range 10–750 hp');
  return e;
}

/// متن فارسی هشدارهای تخمین
String compressorWarningFa(String w) {
  if (w.startsWith('A peers <')) return 'روش A: تعداد همتا کمتر از ${w.split('<').last.trim()} است؛ نتیجه در حد AACE Class 4/5.';
  if (w.startsWith('B peers <')) return 'روش B: تعداد همتای دارای وزن کمتر از ${w.split('<').last.trim()} است.';
  return switch (w) {
    'A: capacity outside peer range' => 'روش A: دبی خارج از بازه‌ی همتاهاست (برون‌یابی).',
    'A2: negative slope – ignore A2' => 'روش A2: شیب منفی است؛ A2 کنار گذاشته شد.',
    'E: outside Seider screw range 10–750 hp' => 'روش E: توان خارج از بازه‌ی ۱۰ تا ۷۵۰ hp رابطه‌ی Seider است.',
    _ => w,
  };
}
