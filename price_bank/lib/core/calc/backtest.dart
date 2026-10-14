// صحت‌سنجی روش‌های تعدیل با داده‌های خود بانک (برای هر رده‌ی تجهیز):
//
// برای هر قلمی که هم «قیمت قدیمی» (مثلاً بازنگری ۱۳۹۳) و هم «استعلام جدید» دارد:
//   واقعی  = میانگین یوروی استعلام‌های جدیدترین سال استعلام (هر استعلام با نرخ ارز تاریخ خودش)
//   برآورد = قیمت قدیمی که با هر روش به همان سال استعلام تعدیل شده است
//   خطا    = برآورد ÷ واقعی − ۱
// همان روش فایل صحت‌سنجی پمپ‌ها (۱۴ پمپ پازنان ۲)، اما خودکار و برای همه‌ی رده‌ها.

import 'dart:math' as math;

import '../repo/items_repo.dart';
import 'methods.dart';

class BacktestPair {
  BacktestPair({
    required this.item,
    required this.oldYear,
    required this.quoteYear,
    required this.quoteCount,
    required this.actualEur,
  });
  final ItemRecord item;
  final int oldYear;
  final int quoteYear;
  final int quoteCount;
  final double actualEur;

  /// برآورد یورویی هر روش (کد روش ← یورو)
  final Map<String, double> predEur = {};

  double? ratio(String code) => predEur[code] == null ? null : predEur[code]! / actualEur;
}

class BacktestResult {
  BacktestResult(this.pairs, this.methods);
  final List<BacktestPair> pairs;
  final List<String> methods;

  int get n => pairs.length;

  /// آمار هر روش؛ اگر هیچ جفتی نباشد null
  MethodStats? stats(String code) {
    final e = [for (final p in pairs) if (p.ratio(code) case final r?) r - 1];
    if (e.isEmpty) return null;
    double median(List<double> l) {
      final s = [...l]..sort();
      final m = s.length ~/ 2;
      return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
    }

    final abs = e.map((x) => x.abs()).toList();
    final pred = pairs.where((p) => p.predEur[code] != null);
    final sp = pred.fold<double>(0, (a, p) => a + p.predEur[code]!);
    final sa = pred.fold<double>(0, (a, p) => a + p.actualEur);
    return MethodStats(
      bias: median(e),
      mdape: median(abs),
      mape: abs.reduce((a, b) => a + b) / abs.length,
      within25: abs.where((x) => x < 0.25).length,
      totalRatio: sa <= 0 ? double.nan : sp / sa,
    );
  }

  /// روش با کمترین خطای میانه
  String? get best {
    String? b;
    double? v;
    for (final m in methods) {
      final s = stats(m);
      if (s == null) continue;
      if (v == null || s.mdape < v) {
        v = s.mdape;
        b = m;
      }
    }
    return b;
  }
}

/// انتخاب جفت (قیمت قدیمی، استعلام‌های جدید) برای یک قلم؛ فاصله‌ی دست‌کم [minGap] سال.
({PriceObs old, List<PriceObs> quotes, int year})? backtestPairOf(ItemRecord it, {int minGap = 2}) {
  final quotes = it.observations.where((o) => o.kind == 'quote' && o.costYear != null && o.amount != null).toList();
  if (quotes.isEmpty) return null;
  final qy = quotes.map((o) => o.costYear!).reduce(math.max);
  final latest = quotes.where((o) => o.costYear == qy).toList();
  final olds = it.observations
      .where((o) => o.kind != 'quote' && o.costYear != null && o.amount != null && o.costYear! <= qy - minGap)
      .toList()
    ..sort((a, b) => a.costYear!.compareTo(b.costYear!));
  if (olds.isEmpty) return null;
  return (old: olds.first, quotes: latest, year: qy);
}
