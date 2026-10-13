// موتور شاخص‌ها: تورم ریالی و ارزی، PPI بخشی و نرخ ارز.
//
// اصل طراحی: هیچ عددی در کد ثابت نیست. همه‌ی مقادیر را کاربر وارد و ویرایش می‌کند.
// هر مقدار می‌تواند برای «سال»، «فصل» یا «ماه» شمسی ثبت شود. هنگام محاسبه اگر
// مقدار ماه موجود نباشد از فصل و سپس از سال استفاده می‌شود و سطح استفاده‌شده
// همراه نتیجه برگردانده می‌شود تا در گزارش شفاف باشد.
//
// این نسخه‌ی اولیه در برنامه‌ی آزمایشی است؛ در برنامه‌ی اصلی همین منطق
// با ذخیره در دیتابیس، تاریخچه‌ی ویرایش و نسخه‌بندی کامل می‌شود.

enum PeriodLevel {
  year('سالانه'),
  quarter('فصلی'),
  month('ماهانه');

  const PeriodLevel(this.title);
  final String title;
}

/// یک دوره‌ی زمانی شمسی: سال، یا فصل یک سال، یا ماه یک سال.
class JPeriod implements Comparable<JPeriod> {
  const JPeriod._(this.year, this.quarter, this.month);

  factory JPeriod.year(int year) => JPeriod._(year, null, null);

  factory JPeriod.quarter(int year, int quarter) {
    if (quarter < 1 || quarter > 4) throw ArgumentError('فصل باید بین ۱ و ۴ باشد: $quarter');
    return JPeriod._(year, quarter, null);
  }

  factory JPeriod.month(int year, int month) {
    if (month < 1 || month > 12) throw ArgumentError('ماه باید بین ۱ و ۱۲ باشد: $month');
    return JPeriod._(year, null, month);
  }

  /// خواندن متنی مثل "1404"، "1404Q1" یا "1404-03".
  static JPeriod? tryParse(String s) {
    final t = s.trim().toUpperCase();
    final y = RegExp(r'^(\d{4})$').firstMatch(t);
    if (y != null) return JPeriod.year(int.parse(y.group(1)!));
    final q = RegExp(r'^(\d{4})\s*Q([1-4])$').firstMatch(t);
    if (q != null) return JPeriod.quarter(int.parse(q.group(1)!), int.parse(q.group(2)!));
    final m = RegExp(r'^(\d{4})[-/](\d{1,2})$').firstMatch(t);
    if (m != null) {
      final mo = int.parse(m.group(2)!);
      if (mo >= 1 && mo <= 12) return JPeriod.month(int.parse(m.group(1)!), mo);
    }
    return null;
  }

  final int year;
  final int? quarter;
  final int? month;

  PeriodLevel get level =>
      month != null ? PeriodLevel.month : (quarter != null ? PeriodLevel.quarter : PeriodLevel.year);

  static int quarterOfMonth(int month) => (month - 1) ~/ 3 + 1;

  /// برچسب فارسی مثل «۱۴۰۴»، «فصل ۱ ۱۴۰۴»، «خرداد ۱۴۰۴».
  String get label {
    if (month != null) return '${jalaliMonthNames[month! - 1]} $year';
    if (quarter != null) return 'فصل $quarter $year';
    return '$year';
  }

  /// کلید متنی پایدار برای ذخیره در دیتابیس.
  String get key {
    if (month != null) return '$year-${month!.toString().padLeft(2, '0')}';
    if (quarter != null) return '${year}Q$quarter';
    return '$year';
  }

  @override
  bool operator ==(Object other) =>
      other is JPeriod && other.year == year && other.quarter == quarter && other.month == month;

  @override
  int get hashCode => Object.hash(year, quarter, month);

  @override
  int compareTo(JPeriod other) => key.compareTo(other.key);

  @override
  String toString() => key;
}

const jalaliMonthNames = [
  'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
];

enum SeriesKind {
  /// مقدار سطح: شاخص PPI (مثلاً 1395=100) یا نرخ ارز (ریال به ازای هر واحد).
  /// ضریب تعدیل = مقدار مقصد ÷ مقدار مبدأ.
  level('سطح شاخص / نرخ'),

  /// نرخ رشد سالانه، مثل تورم ریالی 0.373 (= ۳۷٫۳٪).
  /// ضریب تعدیل = حاصل‌ضرب (۱ + نرخ) سال‌ها.
  annualRate('نرخ رشد سالانه');

  const SeriesKind(this.title);
  final String title;
}

class IndexSeries {
  IndexSeries({required this.code, required this.title, required this.kind, this.unit = ''});

  /// کد پایدار، مثل "PPI_ME" یا "FX_EUR_IRR_NIMA".
  final String code;
  final String title;
  final SeriesKind kind;
  final String unit;
  final Map<JPeriod, double> _values = {};

  Map<JPeriod, double> get values => Map.unmodifiable(_values);

  void set(JPeriod period, double value) {
    if (value.isNaN || value.isInfinite) throw ArgumentError('مقدار نامعتبر: $value');
    if (kind == SeriesKind.level && value <= 0) {
      throw ArgumentError('مقدار شاخص یا نرخ ارز باید مثبت باشد: $value');
    }
    if (kind == SeriesKind.annualRate && value <= -1) {
      throw ArgumentError('نرخ رشد نمی‌تواند کمتر یا مساوی ‎-100٪ باشد: $value');
    }
    _values[period] = value;
  }

  void remove(JPeriod period) => _values.remove(period);
}

/// نتیجه‌ی پیدا کردن یک مقدار، همراه با دوره‌ای که واقعاً استفاده شده.
class ResolvedValue {
  const ResolvedValue(this.value, this.usedPeriod, this.requested);
  final double value;
  final JPeriod usedPeriod;
  final JPeriod requested;

  bool get exact => usedPeriod == requested;
}

class IndexEngine {
  const IndexEngine();

  /// پیدا کردن مقدار برای یک سال (و در صورت تمایل ماه).
  /// ترتیب جستجو: ماه ← فصل همان ماه ← سال.
  ResolvedValue? resolve(IndexSeries s, int year, {int? month}) {
    final requested = month == null ? JPeriod.year(year) : JPeriod.month(year, month);
    final candidates = <JPeriod>[
      if (month != null) JPeriod.month(year, month),
      if (month != null) JPeriod.quarter(year, JPeriod.quarterOfMonth(month)),
      JPeriod.year(year),
    ];
    for (final p in candidates) {
      final v = s.values[p];
      if (v != null) return ResolvedValue(v, p, requested);
    }
    return null;
  }

  /// ضریب تعدیل یک شاخص سطح (PPI یا نرخ ارز) از یک دوره به دوره‌ی دیگر.
  EscalationResult levelFactor(
    IndexSeries s, {
    required int fromYear,
    int? fromMonth,
    required int toYear,
    int? toMonth,
  }) {
    if (s.kind != SeriesKind.level) {
      throw ArgumentError('«${s.title}» از نوع نرخ رشد است؛ از compoundFactor استفاده کنید.');
    }
    final a = resolve(s, fromYear, month: fromMonth);
    final b = resolve(s, toYear, month: toMonth);
    if (a == null || b == null) {
      return EscalationResult.incomplete([
        if (a == null) JPeriod.year(fromYear).label,
        if (b == null) JPeriod.year(toYear).label,
      ]);
    }
    return EscalationResult(b.value / a.value, [a, b]);
  }

  /// ضریب تجمعی نرخ رشد سالانه.
  ///
  /// قرارداد پیش‌فرض (includeStartYear = true) مطابق فایل مارون ۳ است:
  /// ضریب ۱۳۹۲ تا ۱۴۰۵ = (۱+r۱۳۹۲) × (۱+r۱۳۹۳) × … × (۱+r۱۴۰۵).
  EscalationResult compoundFactor(
    IndexSeries s, {
    required int fromYear,
    required int toYear,
    bool includeStartYear = true,
  }) {
    if (s.kind != SeriesKind.annualRate) {
      throw ArgumentError('«${s.title}» از نوع سطح شاخص است؛ از levelFactor استفاده کنید.');
    }
    if (toYear < fromYear) {
      final inv = compoundFactor(s, fromYear: toYear, toYear: fromYear, includeStartYear: includeStartYear);
      return inv.isComplete ? EscalationResult(1 / inv.factor!, inv.used) : inv;
    }
    var f = 1.0;
    final used = <ResolvedValue>[];
    final missing = <String>[];
    final start = includeStartYear ? fromYear : fromYear + 1;
    for (var y = start; y <= toYear; y++) {
      final r = resolve(s, y);
      if (r == null) {
        missing.add('$y');
        continue;
      }
      used.add(r);
      f *= 1 + r.value;
    }
    if (missing.isNotEmpty) return EscalationResult.incomplete(missing);
    return EscalationResult(f, used);
  }
}

class EscalationResult {
  EscalationResult(this.factor, this.used) : missing = const [];
  EscalationResult.incomplete(this.missing)
      : factor = null,
        used = const [];

  final double? factor;
  final List<ResolvedValue> used;

  /// دوره‌هایی که مقدارشان وارد نشده است.
  final List<String> missing;

  bool get isComplete => factor != null;

  /// آیا برای همه‌ی دوره‌ها مقدار دقیق (نه جایگزین سطح بالاتر) وجود داشت؟
  bool get allExact => used.every((u) => u.exact);
}
