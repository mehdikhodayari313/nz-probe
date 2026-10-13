import 'package:flutter_test/flutter_test.dart';
import 'package:nz_probe/core/indices/index_engine.dart';

void main() {
  const engine = IndexEngine();

  // شیت Inflation فایل مارون ۳ (۱۴۰۵/۰۳/۱۰)
  const rial = {
    1392: 0.37, 1393: 0.156, 1394: 0.119, 1395: 0.09, 1396: 0.096, 1397: 0.312, 1398: 0.412,
    1399: 0.47, 1400: 0.462, 1401: 0.465, 1402: 0.5, 1403: 0.4, 1404: 0.6, 1405: 0.2,
  };

  IndexSeries rialSeries() {
    final s = IndexSeries(code: 'INF_IRR', title: 'تورم ریالی', kind: SeriesKind.annualRate);
    rial.forEach((y, r) => s.set(JPeriod.year(y), r));
    return s;
  }

  group('تورم تجمعی', () {
    test('۱۳۹۲ تا ۱۴۰۵ دقیقاً برابر سلول C17 اکسل', () {
      final f = engine.compoundFactor(rialSeries(), fromYear: 1392, toYear: 1405);
      expect(f.isComplete, isTrue);
      expect(f.factor, closeTo(49.789403941690125, 1e-9));
      expect(f.used.length, 14);
    });

    test('بدون احتساب سال شروع', () {
      final f = engine.compoundFactor(rialSeries(), fromYear: 1392, toYear: 1405, includeStartYear: false);
      expect(f.factor, closeTo(49.789403941690125 / 1.37, 1e-9));
    });

    test('جهت معکوس = معکوس ضریب', () {
      final a = engine.compoundFactor(rialSeries(), fromYear: 1400, toYear: 1404).factor!;
      final b = engine.compoundFactor(rialSeries(), fromYear: 1404, toYear: 1400).factor!;
      expect(a * b, closeTo(1, 1e-12));
    });

    test('سال بدون داده عدد ساختگی تولید نمی‌کند', () {
      final f = engine.compoundFactor(rialSeries(), fromYear: 1389, toYear: 1393);
      expect(f.isComplete, isFalse);
      expect(f.factor, isNull);
      expect(f.missing, containsAll(['1389', '1390', '1391']));
    });
  });

  group('شاخص سطح با دقت سال/فصل/ماه', () {
    late IndexSeries ppi;
    setUp(() {
      ppi = IndexSeries(code: 'PPI', title: 'PPI', kind: SeriesKind.level)
        ..set(JPeriod.year(1403), 100)
        ..set(JPeriod.year(1404), 112)
        ..set(JPeriod.quarter(1404, 1), 110)
        ..set(JPeriod.month(1404, 3), 115);
    });

    test('مقدار ماهانه اولویت دارد', () {
      final r = engine.resolve(ppi, 1404, month: 3)!;
      expect(r.value, 115);
      expect(r.exact, isTrue);
    });

    test('نبود ماه → فصل', () {
      final r = engine.resolve(ppi, 1404, month: 1)!;
      expect(r.value, 110);
      expect(r.usedPeriod, JPeriod.quarter(1404, 1));
      expect(r.exact, isFalse);
    });

    test('نبود فصل → سال', () {
      expect(engine.resolve(ppi, 1404, month: 12)!.value, 112);
    });

    test('ضریب تعدیل', () {
      final f = engine.levelFactor(ppi, fromYear: 1403, toYear: 1404, toMonth: 3);
      expect(f.factor, closeTo(1.15, 1e-12));
      // ۱۴۰۳ سالانه خواسته و سالانه پیدا شد؛ خرداد ۱۴۰۴ ماهانه خواسته و ماهانه پیدا شد.
      expect(f.allExact, isTrue);
      final g = engine.levelFactor(ppi, fromYear: 1403, toYear: 1404, toMonth: 2);
      expect(g.factor, closeTo(1.10, 1e-12));
      expect(g.allExact, isFalse); // اردیبهشت از مقدار فصلی پر شد
    });

    test('ویرایش مقدار', () {
      ppi.set(JPeriod.month(1404, 3), 120);
      expect(engine.resolve(ppi, 1404, month: 3)!.value, 120);
      ppi.remove(JPeriod.month(1404, 3));
      expect(engine.resolve(ppi, 1404, month: 3)!.value, 110);
    });

    test('مقادیر نامعتبر رد می‌شوند', () {
      expect(() => ppi.set(JPeriod.year(1405), 0), throwsArgumentError);
      expect(() => ppi.set(JPeriod.year(1405), double.nan), throwsArgumentError);
      expect(() => JPeriod.month(1404, 13), throwsArgumentError);
      expect(() => engine.compoundFactor(ppi, fromYear: 1403, toYear: 1404), throwsArgumentError);
    });
  });

  group('JPeriod', () {
    test('خواندن متن', () {
      expect(JPeriod.tryParse('1404'), JPeriod.year(1404));
      expect(JPeriod.tryParse('1404Q1'), JPeriod.quarter(1404, 1));
      expect(JPeriod.tryParse('1404 q2'), JPeriod.quarter(1404, 2));
      expect(JPeriod.tryParse('1404-03'), JPeriod.month(1404, 3));
      expect(JPeriod.tryParse('1404/3'), JPeriod.month(1404, 3));
      expect(JPeriod.tryParse('1404-13'), isNull);
      expect(JPeriod.tryParse('abc'), isNull);
    });

    test('کلید و برچسب', () {
      expect(JPeriod.month(1404, 3).key, '1404-03');
      expect(JPeriod.quarter(1404, 1).key, '1404Q1');
      expect(JPeriod.month(1404, 3).label, 'خرداد 1404');
    });
  });
}
