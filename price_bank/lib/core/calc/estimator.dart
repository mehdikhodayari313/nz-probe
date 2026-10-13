// تخمین قیمت پمپ جدید از روی رکوردهای همتا (شیت Estimator فایل v8):
//   قیمت یورو = میانگین ضریب هزینه‌ی همتاها × kWⁿ × ضریب کل پیکربندی ، حداقل برابر کف API 610
// و
// ماشین‌حساب انتقال قیمت قدیم به سال هدف (روش M6، شیت «ماشین_حساب» فایل صحت‌سنجی).

import 'dart:math' as math;

import 'pump_engine.dart';

/// یک رکورد همتا برای تخمین.
class PeerRecord {
  const PeerRecord({
    required this.itemId,
    required this.subCategory,
    required this.family,
    required this.standard,
    required this.include,
    required this.costCoef,
    this.tag = '',
    this.name = '',
  });
  final int itemId;
  final String subCategory;
  final String family;
  final String standard;
  final bool include;
  final double? costCoef;
  final String tag;
  final String name;
}

class EstimatorInput {
  const EstimatorInput({
    required this.subCategory,
    required this.matchSubCategory,
    required this.standard,
    required this.family,
    required this.spec,
    this.powerKw,
    this.capacity,
    this.head,
    this.quantity = 1,
  });
  final String subCategory;
  final bool matchSubCategory;
  final String standard;
  final String family;

  /// پارامترهای پیکربندی: material_class، seal_arrangement، api682_category، api682_plan،
  /// driver_type، nace، scope_* (همان کلیدهای قالب پمپ)
  final Map<String, Object?> spec;
  final double? powerKw;
  final double? capacity;
  final double? head;
  final double quantity;
}

class EstimatorResult {
  double? sizeKw;
  double matF = 1, sealF = 1, driveF = 1, scopeF = 1, allF = 1;
  List<PeerRecord> peers = const [];
  double? coefAvg, coefMin, coefMax;
  bool floorApplies = false;
  double? floorEur;
  double? eurExpected, eurLow, eurHigh;
  double? usdExpected;
  double? irrExpected, irrLow, irrHigh;
  double? irrTotal;
  double? eurRate, usdRate;

  int get peerCount => peers.length;
}

class PumpEstimator {
  const PumpEstimator(this.engine);
  final PumpEngine engine;

  EstimatorResult estimate(EstimatorInput inp, List<PeerRecord> all) {
    final s = engine.settings;
    final f = engine.factors;
    final r = EstimatorResult();
    final spec = inp.spec;
    String sv(String k) => asText(spec[k]);

    // توان: kW اعلام‌شده یا Q·H/(367·η)
    if (inp.powerKw != null) {
      r.sizeKw = inp.powerKw;
    } else if (inp.capacity != null && inp.head != null) {
      r.sizeKw = inp.capacity! * inp.head! / (367 * s.pumpEfficiency);
    }

    r.matF = f.get('MAT', sv('material_class'));
    r.sealF = f.get('SEAL_ARR', sv('seal_arrangement')) *
        f.get('SEAL_CAT', sv('api682_category')) *
        f.get('SEAL_PLAN', sv('api682_plan'));
    r.driveF = f.get('DRV', sv('driver_type')) * f.get('NACE', sv('nace'));
    r.scopeF = f.get('SC_DRV', sv('scope_driver')) *
        f.get('SC_BSP', sv('scope_baseplate')) *
        f.get('SC_SEAL', sv('scope_seal_support')) *
        f.get('SC_COMM', sv('scope_comm_spares')) *
        f.get('SC_2Y', sv('scope_2yr_spares')) *
        f.get('SC_TPI', sv('scope_tpi')) *
        f.get('SC_FAT', sv('scope_fat'));
    r.allF = r.matF * r.sealF * r.driveF * r.scopeF;

    // همتاها: ضریب هزینه > ۰، همان خانواده و استاندارد، شمارش در جمع‌ها، و (اختیاری) همان زیرگروه
    r.peers = [
      for (final p in all)
        if (p.costCoef != null &&
            p.costCoef! > 0 &&
            p.family == inp.family &&
            p.standard == inp.standard &&
            p.include &&
            (!inp.matchSubCategory || p.subCategory == inp.subCategory))
          p,
    ];
    if (r.peers.isNotEmpty) {
      final coefs = r.peers.map((p) => p.costCoef!).toList();
      r.coefAvg = coefs.reduce((a, b) => a + b) / coefs.length;
      r.coefMin = coefs.reduce(math.min);
      r.coefMax = coefs.reduce(math.max);
    }

    r.floorApplies = PumpEngine.floorRule(inp.standard, inp.family, sv('material_class'));
    final ppiT = engine.ppi(s.targetYear, month: s.targetMonth);
    final ppiF = engine.ppi(s.floorBaseYear);
    if (ppiT != null && ppiF != null) r.floorEur = s.floorEur * ppiT / ppiF;

    double? price(double? coef) {
      final kw = r.sizeKw;
      if (coef == null || kw == null) return null;
      final raw = coef * math.pow(kw, s.costExponent) * r.allF;
      if (r.floorApplies && r.floorEur != null) return math.max(raw, r.floorEur!);
      return raw;
    }

    r.eurExpected = price(r.coefAvg);
    r.eurLow = price(r.coefMin);
    r.eurHigh = price(r.coefMax);
    r.eurRate = engine.eurRateTarget;
    r.usdRate = engine.usdRateTarget;
    if (r.eurExpected != null && r.eurRate != null && r.usdRate != null) {
      r.usdExpected = r.eurExpected! * r.eurRate! / r.usdRate!;
    }
    if (r.eurRate != null) {
      if (r.eurExpected != null) r.irrExpected = r.eurExpected! * r.eurRate!;
      if (r.eurLow != null) r.irrLow = r.eurLow! * r.eurRate!;
      if (r.eurHigh != null) r.irrHigh = r.eurHigh! * r.eurRate!;
    }
    if (r.irrExpected != null) r.irrTotal = r.irrExpected! * inp.quantity;
    return r;
  }
}

// -----------------------------------------------------------------------------
// ماشین‌حساب انتقال قیمت (M6)

enum FloorMode { auto, yes, no }

class TransferInput {
  const TransferInput({
    required this.basePrice,
    required this.currency,
    required this.baseYear,
    this.baseMonth,
    this.sourceFxRate,
    this.isApiCentrifugal = true,
    this.materialClass = 'Not stated',
    this.quantity = 1,
    this.customsPercent = 0,
    this.floorMode = FloorMode.auto,
  });
  final double basePrice;
  final String currency;
  final int baseYear;
  final int? baseMonth;
  final double? sourceFxRate;
  final bool isApiCentrifugal;
  final String materialClass;
  final double quantity;

  /// هزینه‌ی گمرک، حمل و ترخیص به صورت کسر (۰٫۰۶ = ۶٪)
  final double customsPercent;
  final FloorMode floorMode;
}

class TransferResult {
  double? toEurRate;
  String toEurSource = '';
  double? baseEur;
  double? ppiBase, ppiTarget, ppiFactor;
  double? escalatedEur;
  bool floorApplies = false;
  double? floorEur;
  double? finalEurUnit;
  double? eurRate;
  double? irrUnitNoCustoms;
  double? customsIrrUnit;
  double? irrUnit;
  double? irrTotal;
  double? eurTotal;
  double? usdTotal;
  final List<String> warnings = [];
}

class PriceTransferCalculator {
  const PriceTransferCalculator(this.engine);
  final PumpEngine engine;

  TransferResult run(TransferInput i) {
    final s = engine.settings;
    final r = TransferResult();
    double? fx(String code, int y, int? m) => engine.series.resolve(code, y, month: m)?.value;

    if (i.currency == 'EUR') {
      r.toEurRate = 1;
      r.toEurSource = 'یورو';
    } else if (i.currency == 'USD') {
      final e = fx(s.fxEurCode, i.baseYear, i.baseMonth), u = fx(s.fxUsdCode, i.baseYear, i.baseMonth);
      r.toEurRate = (e != null && u != null) ? e / u : null;
      r.toEurSource = 'نسبت یورو/دلار سال ${i.baseYear}';
    } else {
      r.toEurRate = i.sourceFxRate ?? fx(s.fxEurCode, i.baseYear, i.baseMonth);
      r.toEurSource = i.sourceFxRate != null ? 'نرخ تسعیر منبع' : 'نرخ یوروی سال ${i.baseYear}';
    }
    if (r.toEurRate == null) {
      r.warnings.add('نرخ ارز سال پایه موجود نیست.');
      return r;
    }
    r.baseEur = i.basePrice / r.toEurRate!;
    r.ppiBase = engine.ppi(i.baseYear, month: i.baseMonth);
    r.ppiTarget = engine.ppi(s.targetYear, month: s.targetMonth);
    if (r.ppiBase == null || r.ppiTarget == null) {
      r.warnings.add('شاخص PPI سال پایه یا هدف موجود نیست.');
      return r;
    }
    r.ppiFactor = r.ppiTarget! / r.ppiBase!;
    r.escalatedEur = r.baseEur! * r.ppiFactor!;

    final cls = i.materialClass.toUpperCase();
    final sOrD = cls.startsWith('S-') || cls.startsWith('D-') ||
        RegExp(r'^[SD]\d').hasMatch(cls); // پشتیبانی از نگارش بدون خط تیره (D1، S6)
    r.floorApplies = switch (i.floorMode) {
      FloorMode.yes => true,
      FloorMode.no => false,
      FloorMode.auto => i.isApiCentrifugal && sOrD,
    };
    final ppiF = engine.ppi(s.floorBaseYear);
    if (ppiF != null) r.floorEur = s.floorEur * r.ppiTarget! / ppiF;
    r.finalEurUnit = (r.floorApplies && r.floorEur != null) ? math.max(r.escalatedEur!, r.floorEur!) : r.escalatedEur;

    r.eurRate = engine.eurRateTarget;
    if (r.eurRate == null) {
      r.warnings.add('نرخ یوروی سال هدف موجود نیست.');
      return r;
    }
    r.irrUnitNoCustoms = r.finalEurUnit! * r.eurRate!;
    r.customsIrrUnit = r.irrUnitNoCustoms! * i.customsPercent;
    r.irrUnit = r.irrUnitNoCustoms! + r.customsIrrUnit!;
    r.irrTotal = r.irrUnit! * i.quantity;
    r.eurTotal = r.finalEurUnit! * (1 + i.customsPercent) * i.quantity;
    final u = engine.usdRateTarget;
    if (u != null) r.usdTotal = r.eurTotal! * r.eurRate! / u;
    if (i.baseYear > s.targetYear) r.warnings.add('سال پایه بعد از سال هدف است.');
    return r;
  }
}
