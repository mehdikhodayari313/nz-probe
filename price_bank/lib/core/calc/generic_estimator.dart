// تخمین قیمت تجهیزات غیرپمپ از روی همتاها با «پارامتر اندازه»ی هر رده:
//
//   CAP  ضریب هزینه‌ی همتاها:  یورو = میانگین(یورو نرمال‌شده‌ی همتا ÷ اندازه^n) × اندازه^n × ضریب پیکربندی
//   NEAR نزدیک‌ترین همتا:       یورو = یورو نرمال‌شده‌ی نزدیک‌ترین همتا × (اندازه ÷ اندازه‌ی همتا)^n × ضریب پیکربندی
//   MAN  ضریب دستی:            یورو = ضریب وارد شده × اندازه^n × ضریب پیکربندی
//
// «یورو نرمال‌شده» = یوروی تعدیل‌شده به سال هدف ÷ ضریب پیکربندی همان همتا (جنس، NACE، فشار، …).

import 'dart:math' as math;

import '../catalog/profiles.dart';
import 'estimator.dart';
import 'pump_engine.dart';

enum GenEstMethod {
  cap('ضریب هزینه‌ی همتاها', 'میانگین ضریب هزینه‌ی همه‌ی همتاها × اندازه^n — مناسب وقتی چند همتا با اندازه‌های مختلف دارید'),
  near('نزدیک‌ترین همتا', 'قیمت نزدیک‌ترین همتا از نظر اندازه، با قانون توانی مقیاس می‌شود — مناسب وقتی همتای خیلی شبیه دارید'),
  manual('ضریب دستی', 'ضریب هزینه را خودتان وارد می‌کنید (یورو به ازای اندازه^n) — مناسب وقتی همتای معتبری نیست');

  const GenEstMethod(this.titleFa, this.helpFa);
  final String titleFa;
  final String helpFa;

  static GenEstMethod byName(String? n) => GenEstMethod.values.firstWhere((m) => m.name == n, orElse: () => cap);
}

class GenericPeer {
  const GenericPeer({
    required this.itemId,
    required this.tag,
    required this.name,
    required this.project,
    required this.size,
    required this.normEur,
    required this.coef,
    this.type,
  });
  final int itemId;
  final String tag;
  final String name;
  final String project;
  final double size;
  final double normEur;
  final double coef;
  final String? type;
}

class GenericEstimate {
  /// خروجی هم‌شکل تخمین پمپ (برای نمایش یکسان)
  final EstimatorResult res = EstimatorResult();
  double? size;
  double n = 0.6;
  final Map<String, (String?, double)> factors = {}; // گروه ← (گزینه، ضریب)
  double allF = 1;
  List<GenericPeer> peers = const [];
  GenericPeer? nearest;
  GenEstMethod method = GenEstMethod.cap;
  String? note;
}

/// توان پیش‌فرض ضریب وزن: قیمت ظرف تقریباً ∝ وزن^۰٫۸
const defaultWeightExponent = 0.8;

/// «وزن ویژه» یک قلم = وزن خالی ÷ پارامتر اندازه (مثلاً kg به ازای m³ حجم ظرف).
double? weightDensity(EquipmentProfile p, Map<String, Object?> values) {
  final k = p.weightKey;
  if (k == null) return null;
  final w = values[k];
  final s = p.sizeOf(values);
  if (w is! num || w <= 0 || s == null) return null;
  return w / s;
}

/// میانه‌ی وزن ویژه‌ی اقلامی که وزن دارند؛ کمتر از دو قلم = null (ضریب وزن بی‌اثر).
double? medianWeightDensity(EquipmentProfile p, Iterable<Map<String, Object?>> items) {
  final l = [for (final v in items) if (weightDensity(p, v) case final d?) d]..sort();
  if (l.length < 2) return null;
  final m = l.length ~/ 2;
  return l.length.isOdd ? l[m] : (l[m - 1] + l[m]) / 2;
}

class GenericEstimator {
  const GenericEstimator({
    required this.profile,
    required this.factors,
    required this.n,
    this.eurRate,
    this.usdRate,
    this.weightRef,
    this.weightExp = defaultWeightExponent,
  });
  final EquipmentProfile profile;
  final FactorTable factors;
  final double n;
  final double? eurRate;
  final double? usdRate;

  /// میانه‌ی وزن ویژه‌ی رده (مرجع ضریب وزن)؛ null = ضریب وزن غیرفعال
  final double? weightRef;
  final double weightExp;

  /// ضریب وزن یک قلم: (وزن ویژه ÷ میانه‌ی رده)^m ؛ وقتی وزن یا مرجع نیست، null (بی‌اثر).
  double? weightFactor(Map<String, Object?> values) {
    final ref = weightRef;
    final d = weightDensity(profile, values);
    if (ref == null || d == null || ref <= 0 || weightExp <= 0) return null;
    return math.pow(d / ref, weightExp).toDouble();
  }

  /// ضریب کل پیکربندی برای مقادیر یک قلم.
  /// اگر ضریب وزن فعال باشد جای ضریب فشار را می‌گیرد (اثر فشار در ضخامت و وزن دیده شده است).
  (double, Map<String, (String?, double)>) configFactor(Map<String, Object?> values) {
    var all = 1.0;
    final m = <String, (String?, double)>{};
    final wf = weightFactor(values);
    for (final g in profile.factorGroups) {
      if (g == 'PRESS' && wf != null) {
        m[g] = ('با وزن جایگزین شد', 1.0);
        continue;
      }
      final opt = factorOption(g, values);
      final f = opt == null ? 1.0 : factors.get(g, opt);
      m[g] = (opt, f);
      all *= f;
    }
    if (profile.weightKey != null) {
      m['WEIGHT'] = (wf == null ? null : 'وزن ثبت‌شده', wf ?? 1.0);
      if (wf != null) all *= wf;
    }
    return (all, m);
  }

  /// همتا از روی یک قلم بانک (اندازه و یوروی تعدیل‌شده‌ی سال هدف).
  GenericPeer? peerOf({
    required int itemId,
    required String tag,
    required String name,
    required String project,
    required Map<String, Object?> values,
    required double? eurTarget,
  }) {
    final s = profile.sizeOf(values);
    if (s == null || eurTarget == null || eurTarget <= 0) return null;
    final (f, _) = configFactor(values);
    final norm = eurTarget / f;
    return GenericPeer(
      itemId: itemId,
      tag: tag,
      name: name,
      project: project,
      size: s,
      normEur: norm,
      coef: norm / math.pow(s, n),
      type: profile.typeKey == null ? null : values[profile.typeKey]?.toString(),
    );
  }

  GenericEstimate estimate({
    required Map<String, Object?> values,
    required List<GenericPeer> allPeers,
    required GenEstMethod method,
    bool sameType = false,
    double? manualCoef,
    double quantity = 1,
  }) {
    final e = GenericEstimate()
      ..n = n
      ..method = method;
    final r = e.res;
    e.size = profile.sizeOf(values);
    r.sizeKw = e.size;
    final (all, fm) = configFactor(values);
    e.allF = all;
    e.factors.addAll(fm);
    r.allF = all;

    final type = profile.typeKey == null ? null : values[profile.typeKey]?.toString();
    e.peers = [
      for (final p in allPeers)
        if (!sameType || type == null || p.type == type) p,
    ];
    r.peers = [
      for (final p in e.peers)
        PeerRecord(itemId: p.itemId, subCategory: '', family: '', standard: '', include: true, costCoef: p.coef, tag: p.tag, name: p.name),
    ];
    final s = e.size;
    if (s == null) {
      e.note = 'پارامتر اندازه (${profile.driver.labelFa}) را وارد کنید.';
      return e;
    }
    double price(double coef) => coef * math.pow(s, n) * all;

    switch (method) {
      case GenEstMethod.cap:
        if (e.peers.isEmpty) {
          e.note = 'همتای معتبری (با اندازه و قیمت) در این رده نیست؛ روش «ضریب دستی» را امتحان کنید.';
          return e;
        }
        final cs = e.peers.map((p) => p.coef).toList();
        r.coefAvg = cs.reduce((a, b) => a + b) / cs.length;
        r.coefMin = cs.reduce(math.min);
        r.coefMax = cs.reduce(math.max);
        r.eurExpected = price(r.coefAvg!);
        r.eurLow = price(r.coefMin!);
        r.eurHigh = price(r.coefMax!);
      case GenEstMethod.near:
        if (e.peers.isEmpty) {
          e.note = 'همتای معتبری در این رده نیست.';
          return e;
        }
        final sorted = [...e.peers]..sort((a, b) => (math.log(a.size / s)).abs().compareTo((math.log(b.size / s)).abs()));
        e.nearest = sorted.first;
        double scaled(GenericPeer p) => p.normEur * math.pow(s / p.size, n) * all;
        r.eurExpected = scaled(sorted.first);
        final top = sorted.take(3).map(scaled).toList();
        r.eurLow = top.reduce(math.min);
        r.eurHigh = top.reduce(math.max);
        r.coefAvg = sorted.first.coef;
        r.coefMin = sorted.take(3).map((p) => p.coef).reduce(math.min);
        r.coefMax = sorted.take(3).map((p) => p.coef).reduce(math.max);
      case GenEstMethod.manual:
        if (manualCoef == null || manualCoef <= 0) {
          e.note = 'ضریب هزینه (یورو به ازای اندازه^n) را وارد کنید.';
          return e;
        }
        r.coefAvg = r.coefMin = r.coefMax = manualCoef;
        r.eurExpected = r.eurLow = r.eurHigh = price(manualCoef);
    }
    r.eurRate = eurRate;
    r.usdRate = usdRate;
    if (r.eurExpected != null && eurRate != null && usdRate != null) r.usdExpected = r.eurExpected! * eurRate! / usdRate!;
    if (eurRate != null) {
      r.irrExpected = r.eurExpected! * eurRate!;
      r.irrLow = r.eurLow! * eurRate!;
      r.irrHigh = r.eurHigh! * eurRate!;
      r.irrTotal = r.irrExpected! * quantity;
    }
    return e;
  }
}
