// دوره‌های زمانی شمسی و جستجوی مقدار شاخص با اولویت ماه ← فصل ← سال.

const jalaliMonthNames = [
  'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
];

enum PeriodLevel {
  year('سالانه'),
  quarter('فصلی'),
  month('ماهانه');

  const PeriodLevel(this.title);
  final String title;
}

/// دوره‌ی زمانی: سال، یا فصل یک سال، یا ماه یک سال.
class Period implements Comparable<Period> {
  const Period._(this.year, this.quarter, this.month);

  factory Period.year(int year) => Period._(year, null, null);

  factory Period.quarter(int year, int quarter) {
    if (quarter < 1 || quarter > 4) throw ArgumentError('فصل باید بین ۱ و ۴ باشد');
    return Period._(year, quarter, null);
  }

  factory Period.month(int year, int month) {
    if (month < 1 || month > 12) throw ArgumentError('ماه باید بین ۱ و ۱۲ باشد');
    return Period._(year, null, month);
  }

  final int year;
  final int? quarter;
  final int? month;

  PeriodLevel get level =>
      month != null ? PeriodLevel.month : (quarter != null ? PeriodLevel.quarter : PeriodLevel.year);

  static int quarterOfMonth(int month) => (month - 1) ~/ 3 + 1;

  /// کلید ذخیره: «1404»، «1404Q1»، «1404-03».
  String get key {
    if (month != null) return '$year-${month!.toString().padLeft(2, '0')}';
    if (quarter != null) return '${year}Q$quarter';
    return '$year';
  }

  String get label {
    if (month != null) return '${jalaliMonthNames[month! - 1]} $year';
    if (quarter != null) return 'فصل $quarter $year';
    return '$year';
  }

  /// خواندن «1404»، «1404Q1»، «1404 q1»، «1404-03»، «1404/3».
  static Period? tryParse(String input) {
    final t = input.trim().toUpperCase();
    final y = RegExp(r'^(\d{4})$').firstMatch(t);
    if (y != null) return Period.year(int.parse(y.group(1)!));
    final q = RegExp(r'^(\d{4})\s*Q([1-4])$').firstMatch(t);
    if (q != null) return Period.quarter(int.parse(q.group(1)!), int.parse(q.group(2)!));
    final m = RegExp(r'^(\d{4})\s*[-/]\s*(\d{1,2})$').firstMatch(t);
    if (m != null) {
      final mo = int.parse(m.group(2)!);
      if (mo >= 1 && mo <= 12) return Period.month(int.parse(m.group(1)!), mo);
    }
    return null;
  }

  /// ترتیب زمانی: سال، سپس فصل/ماه (مقدار سالانه قبل از جزئیات همان سال).
  int get _sortKey {
    if (month != null) return year * 100 + month! * 2;
    if (quarter != null) return year * 100 + (quarter! * 3) * 2 - 1;
    return year * 100;
  }

  @override
  int compareTo(Period other) => _sortKey.compareTo(other._sortKey);

  @override
  bool operator ==(Object other) =>
      other is Period && other.year == year && other.quarter == quarter && other.month == month;

  @override
  int get hashCode => Object.hash(year, quarter, month);

  @override
  String toString() => key;
}

/// مقدار پیدا شده همراه با دوره‌ای که واقعاً استفاده شد.
class Resolved {
  const Resolved(this.value, this.period);
  final double value;
  final Period period;
}

/// منبع خواندن شاخص‌ها و نرخ‌ها برای موتور محاسبات.
abstract interface class SeriesLookup {
  Resolved? resolve(String code, int year, {int? month});
}

/// پیاده‌سازی درون‌حافظه‌ای (دیتابیس آن را پر می‌کند؛ آزمون‌ها مستقیم می‌سازند).
class MemorySeries implements SeriesLookup {
  final Map<String, Map<Period, double>> _data = {};

  void put(String code, Period p, double value) => (_data[code] ??= {})[p] = value;

  Map<Period, double> series(String code) => _data[code] ?? const {};

  @override
  Resolved? resolve(String code, int year, {int? month}) {
    final s = _data[code];
    if (s == null) return null;
    if (month != null) {
      final m = s[Period.month(year, month)];
      if (m != null) return Resolved(m, Period.month(year, month));
      final qp = Period.quarter(year, Period.quarterOfMonth(month));
      final q = s[qp];
      if (q != null) return Resolved(q, qp);
    }
    final y = s[Period.year(year)];
    if (y != null) return Resolved(y, Period.year(year));
    return null;
  }
}
