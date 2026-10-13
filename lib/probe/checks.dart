// آزمون‌های سازگاری. هر آزمون مستقل است، خطای خودش را می‌گیرد و هرگز برنامه را از کار نمی‌اندازد.

import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:sqlite3/sqlite3.dart';

import '../core/indices/index_engine.dart';
import '../core/mto/mto_scan.dart';
import '../core/xlsx/sample_xlsx.dart';
import '../core/xlsx/xlsx_reader.dart';

enum CheckStatus { pending, running, passed, warning, failed, needsUser }

class CheckOutcome {
  CheckOutcome(this.status, this.summary, [List<String>? details]) : details = details ?? [];
  final CheckStatus status;
  final String summary;
  final List<String> details;
}

typedef CheckFn = Future<CheckOutcome> Function();

class ProbeCheck {
  ProbeCheck({required this.id, required this.title, required this.description, required this.run});
  final String id;
  final String title;
  final String description;
  final CheckFn run;

  CheckStatus status = CheckStatus.pending;
  String summary = '';
  List<String> details = const [];
  Duration? elapsed;
}

/// فهرست آزمون‌های خودکار، به ترتیب اجرا.
List<ProbeCheck> buildChecks() => [
      ProbeCheck(
        id: 'platform',
        title: 'سیستم‌عامل و محیط اجرا',
        description: 'نسخه‌ی ویندوز/اندروید، معماری پردازنده، زبان سیستم',
        run: checkPlatform,
      ),
      ProbeCheck(
        id: 'storage',
        title: 'دسترسی نوشتن روی دیسک',
        description: 'پوشه‌ی داده‌ی کاربر، پوشه‌ی اسناد و پوشه‌ی کنار برنامه (حالت قابل‌حمل)',
        run: checkStorage,
      ),
      ProbeCheck(
        id: 'sqlite',
        title: 'دیتابیس محلی SQLite',
        description: 'ساخت دیتابیس، ثبت ۲۰٬۰۰۰ رکورد، متن فارسی، بستن و باز کردن دوباره، بررسی سلامت',
        run: checkSqlite,
      ),
      ProbeCheck(
        id: 'jalali',
        title: 'تاریخ شمسی',
        description: 'تبدیل تاریخ میلادی به شمسی با نمونه‌های معلوم (نوروز ۱۴۰۳ و ۱۴۰۴)',
        run: checkJalali,
      ),
      ProbeCheck(
        id: 'indices',
        title: 'موتور شاخص‌ها و تعدیل',
        description: 'تورم تجمعی ۱۳۹۲ تا ۱۴۰۵ مطابق فایل مارون ۳، و جستجوی ماه ← فصل ← سال',
        run: checkIndexEngine,
      ),
      ProbeCheck(
        id: 'xlsx',
        title: 'خواننده‌ی اکسل (خودآزمایی)',
        description: 'خواندن یک فایل نمونه‌ی ساخته‌شده در حافظه با سه ایراد عمدی',
        run: checkXlsxReader,
      ),
    ];

// -----------------------------------------------------------------------------

Future<CheckOutcome> checkPlatform() async {
  final d = <String>[
    'سیستم‌عامل: ${Platform.operatingSystem}',
    'نسخه: ${Platform.operatingSystemVersion}',
    'Dart: ${Platform.version}',
    'تعداد هسته‌ی پردازنده: ${Platform.numberOfProcessors}',
    'زبان سیستم: ${Platform.localeName}',
    'مسیر برنامه: ${Platform.resolvedExecutable}',
  ];

  if (Platform.isWindows) {
    // نمونه: "Windows 10 Pro" 10.0 (Build 19045)
    final m = RegExp(r'Build (\d+)').firstMatch(Platform.operatingSystemVersion);
    final build = m == null ? null : int.tryParse(m.group(1)!);
    if (build != null) {
      final isServer = Platform.operatingSystemVersion.contains('Server');
      final name = isServer
          ? 'ویندوز سرور'
          : (build >= 22000 ? 'ویندوز ۱۱' : (build >= 10240 ? 'ویندوز ۱۰' : 'ویندوز قدیمی‌تر'));
      d.add('تشخیص: $name (Build $build)');
      if (build < 10240) {
        return CheckOutcome(CheckStatus.failed, 'ویندوز قدیمی‌تر از ۱۰ پشتیبانی نمی‌شود', d);
      }
      // ویندوز ۱۰ نسخه‌های خیلی قدیمی (قبل از 1809) هم ممکن است مشکل داشته باشند.
      if (build < 17763) {
        return CheckOutcome(CheckStatus.warning, 'ویندوز ۱۰ نسخه‌ی قدیمی؛ به‌روزرسانی توصیه می‌شود', d);
      }
      return CheckOutcome(CheckStatus.passed, name, d);
    }
  }
  return CheckOutcome(CheckStatus.passed, Platform.operatingSystem, d);
}

Future<CheckOutcome> checkStorage() async {
  final d = <String>[];
  var status = CheckStatus.passed;

  Future<bool> tryWrite(String label, Directory dir, {required bool critical}) async {
    final probe = File('${dir.path}${Platform.pathSeparator}.nz_probe_${DateTime.now().microsecondsSinceEpoch}.tmp');
    try {
      await dir.create(recursive: true);
      final data = List<int>.generate(1024 * 1024, (i) => i % 251); // ۱ مگابایت
      await probe.writeAsBytes(data, flush: true);
      final back = await probe.readAsBytes();
      final ok = back.length == data.length && back[777] == data[777];
      await probe.delete();
      d.add('${ok ? '✔' : '✖'} $label: ${dir.path}');
      if (!ok && critical) status = CheckStatus.failed;
      return ok;
    } catch (e) {
      d.add('✖ $label: ${dir.path}\n   خطا: $e');
      if (critical) {
        status = CheckStatus.failed;
      } else if (status == CheckStatus.passed) {
        status = CheckStatus.warning;
      }
      return false;
    }
  }

  await tryWrite('پوشه‌ی داده‌ی برنامه (محل دیتابیس)', await getApplicationSupportDirectory(), critical: true);
  try {
    await tryWrite('پوشه‌ی اسناد', await getApplicationDocumentsDirectory(), critical: false);
  } catch (e) {
    d.add('– پوشه‌ی اسناد در دسترس نیست: $e');
  }

  if (Platform.isWindows) {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final ok = await tryWrite('کنار فایل برنامه (حالت قابل‌حمل)', exeDir, critical: false);
    if (!ok) {
      d.add('  ← مشکلی نیست؛ برنامه‌ی اصلی داده را در پوشه‌ی کاربر ذخیره می‌کند.');
    }
    // پوشه‌ی کاربر روی شبکه (Folder Redirection) سرعت و اطمینان دیتابیس را کم می‌کند.
    final support = (await getApplicationSupportDirectory()).path;
    if (support.startsWith(r'\\')) {
      d.add('⚠ پوشه‌ی داده‌ی کاربر روی شبکه است ($support). بهتر است دیتابیس روی دیسک محلی باشد.');
      if (status == CheckStatus.passed) status = CheckStatus.warning;
    }
  }

  final summary = switch (status) {
    CheckStatus.passed => 'نوشتن و خواندن موفق',
    CheckStatus.warning => 'کار می‌کند، با محدودیت',
    _ => 'امکان ذخیره‌ی داده وجود ندارد',
  };
  return CheckOutcome(status, summary, d);
}

Future<CheckOutcome> checkSqlite() async {
  final d = <String>[];
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final path = '${dir.path}${Platform.pathSeparator}nz_probe_test.db';
  for (final suffix in ['', '-wal', '-shm']) {
    final f = File('$path$suffix');
    if (f.existsSync()) f.deleteSync();
  }

  d.add('نسخه‌ی SQLite: ${sqlite3.version.libVersion}');
  d.add('مسیر آزمایشی: $path');

  final sw = Stopwatch()..start();
  var db = sqlite3.open(path);
  try {
    final mode = db.select('PRAGMA journal_mode=WAL;').rows.first.first;
    d.add('حالت ژورنال: $mode');
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('''
      CREATE TABLE index_series(
        code TEXT PRIMARY KEY,
        title TEXT NOT NULL
      );
      CREATE TABLE index_value(
        series_code TEXT NOT NULL REFERENCES index_series(code),
        period_key TEXT NOT NULL,
        value REAL NOT NULL,
        PRIMARY KEY(series_code, period_key)
      );
    ''');
    db.execute("INSERT INTO index_series VALUES ('INF_IRR', 'تورم ریالی')");

    // ۲۰٬۰۰۰ رکورد در یک تراکنش: معادل چند سال داده‌ی ماهانه برای صدها شاخص
    final insert = db.prepare('INSERT INTO index_value VALUES (?, ?, ?)');
    final rnd = Random(42);
    var expectedSum = 0.0;
    db.execute('BEGIN');
    for (var i = 0; i < 20000; i++) {
      final v = (rnd.nextInt(100000) / 100.0);
      expectedSum += v;
      insert.execute(['INF_IRR', 'K$i', v]);
    }
    db.execute('COMMIT');
    insert.dispose();
    final tInsert = sw.elapsedMilliseconds;
    d.add('ثبت ۲۰٬۰۰۰ رکورد: $tInsert میلی‌ثانیه');

    final row = db.select('SELECT COUNT(*) AS n, SUM(value) AS s FROM index_value').first;
    final n = row['n'] as int;
    final s = (row['s'] as num).toDouble();
    if (n != 20000 || (s - expectedSum).abs() > 1e-6) {
      return CheckOutcome(CheckStatus.failed, 'داده‌ی ثبت‌شده با داده‌ی خوانده‌شده یکی نیست', d);
    }

    // بستن و باز کردن دوباره: داده باید ماندگار باشد
    db.dispose();
    db = sqlite3.open(path);
    final title = db.select("SELECT title FROM index_series WHERE code='INF_IRR'").first['title'];
    if (title != 'تورم ریالی') {
      return CheckOutcome(CheckStatus.failed, 'متن فارسی درست ذخیره نشد: $title', d);
    }
    d.add('متن فارسی پس از باز کردن دوباره: «$title» ✔');

    final integrity = db.select('PRAGMA integrity_check').rows.first.first;
    d.add('بررسی سلامت: $integrity');
    if (integrity != 'ok') {
      return CheckOutcome(CheckStatus.failed, 'بررسی سلامت دیتابیس ناموفق', d);
    }
    d.add('زمان کل: ${sw.elapsedMilliseconds} میلی‌ثانیه');
  } finally {
    db.dispose();
    for (final suffix in ['', '-wal', '-shm']) {
      try {
        final f = File('$path$suffix');
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  final ms = sw.elapsedMilliseconds;
  return CheckOutcome(
    ms < 5000 ? CheckStatus.passed : CheckStatus.warning,
    ms < 5000 ? 'کار می‌کند' : 'کار می‌کند ولی کند است — احتمالاً آنتی‌ویروس',
    d,
  );
}

Future<CheckOutcome> checkJalali() async {
  final d = <String>[];
  final samples = <(DateTime, String)>[
    (DateTime(2024, 3, 20), '1403/1/1'),
    (DateTime(2025, 3, 21), '1404/1/1'),
    (DateTime(2025, 2, 15), '1403/11/27'),
  ];
  var ok = true;
  for (final (g, expected) in samples) {
    final j = Jalali.fromDateTime(g);
    final got = '${j.year}/${j.month}/${j.day}';
    final pass = got == expected;
    ok &= pass;
    d.add('${pass ? '✔' : '✖'} ${g.year}-${g.month}-${g.day} → $got (انتظار: $expected)');
  }
  final today = Jalali.now();
  final todayStr = '${today.year}/${today.month.toString().padLeft(2, '0')}/${today.day.toString().padLeft(2, '0')}';
  d.add('امروز: $todayStr');
  return CheckOutcome(ok ? CheckStatus.passed : CheckStatus.failed, ok ? 'امروز $todayStr' : 'تبدیل تاریخ نادرست', d);
}

Future<CheckOutcome> checkIndexEngine() async {
  final d = <String>[];
  const engine = IndexEngine();
  var ok = true;

  // نرخ‌های تورم دقیقاً مطابق شیت Inflation فایل مارون ۳
  const rial = {
    1392: 0.37, 1393: 0.156, 1394: 0.119, 1395: 0.09, 1396: 0.096, 1397: 0.312, 1398: 0.412,
    1399: 0.47, 1400: 0.462, 1401: 0.465, 1402: 0.5, 1403: 0.4, 1404: 0.6, 1405: 0.2,
  };
  const fx = {
    1392: 0.02, 1393: 0.02, 1394: 0.02, 1395: 0.02, 1396: 0.02, 1397: 0.02, 1398: 0.02,
    1399: 0.05, 1400: 0.05, 1401: 0.049, 1402: 0.04, 1403: 0.04, 1404: 0.04, 1405: 0.01,
  };
  final infRial = IndexSeries(code: 'INF_IRR', title: 'تورم ریالی', kind: SeriesKind.annualRate);
  final infFx = IndexSeries(code: 'INF_FX', title: 'تورم ارزی', kind: SeriesKind.annualRate);
  rial.forEach((y, r) => infRial.set(JPeriod.year(y), r));
  fx.forEach((y, r) => infFx.set(JPeriod.year(y), r));

  void expectClose(String label, double? got, double expected) {
    final pass = got != null && (got - expected).abs() < 1e-9 * max(1.0, expected.abs());
    ok &= pass;
    d.add('${pass ? '✔' : '✖'} $label = ${got ?? '—'} (مرجع اکسل: $expected)');
  }

  expectClose('ضریب تورم ریالی ۱۳۹۲→۱۴۰۵',
      engine.compoundFactor(infRial, fromYear: 1392, toYear: 1405).factor, 49.789403941690125);
  expectClose('ضریب تورم ارزی ۱۳۹۲→۱۴۰۵',
      engine.compoundFactor(infFx, fromYear: 1392, toYear: 1405).factor, 1.5093038516721788);

  // شاخص سطح با دقت‌های مختلف: سال، فصل، ماه
  final ppi = IndexSeries(code: 'PPI_TEST', title: 'PPI آزمایشی', kind: SeriesKind.level);
  ppi.set(JPeriod.year(1403), 100);
  ppi.set(JPeriod.year(1404), 112);
  ppi.set(JPeriod.quarter(1404, 1), 110);
  ppi.set(JPeriod.month(1404, 3), 115);

  void expectResolve(String label, int y, int? m, double value, PeriodLevel level) {
    final r = engine.resolve(ppi, y, month: m);
    final pass = r != null && r.value == value && r.usedPeriod.level == level;
    ok &= pass;
    d.add('${pass ? '✔' : '✖'} $label → ${r?.value ?? '—'} از سطح ${r?.usedPeriod.level.title ?? '—'}');
  }

  expectResolve('خرداد ۱۴۰۴ (مقدار ماهانه دارد)', 1404, 3, 115, PeriodLevel.month);
  expectResolve('اردیبهشت ۱۴۰۴ (فقط فصل ۱ دارد)', 1404, 2, 110, PeriodLevel.quarter);
  expectResolve('مهر ۱۴۰۴ (فقط سالانه دارد)', 1404, 7, 112, PeriodLevel.year);

  final f = engine.levelFactor(ppi, fromYear: 1403, toYear: 1404, toMonth: 3);
  expectClose('ضریب PPI از ۱۴۰۳ تا خرداد ۱۴۰۴', f.factor, 1.15);

  final missing = engine.compoundFactor(infRial, fromYear: 1390, toYear: 1393);
  final pass = !missing.isComplete && missing.missing.contains('1390');
  ok &= pass;
  d.add('${pass ? '✔' : '✖'} سال بدون داده (۱۳۹۰) به‌درستی گزارش شد و عدد ساختگی تولید نشد');

  return CheckOutcome(ok ? CheckStatus.passed : CheckStatus.failed,
      ok ? 'نتایج دقیقاً با اکسل یکسان است' : 'اختلاف با مرجع اکسل', d);
}

Future<CheckOutcome> checkXlsxReader() async {
  final d = <String>[];
  final result = await Isolate.run(() => scanWorkbook(XlsxWorkbook.fromBytes(buildSampleXlsx())));
  var ok = true;
  void expect(String label, Object got, Object expected) {
    final pass = got == expected;
    ok &= pass;
    d.add('${pass ? '✔' : '✖'} $label: $got (انتظار: $expected)');
  }

  expect('قالب', result.format.title, MtoFormat.consultantWorking.title);
  expect('تعداد شیت (شامل مخفی)', result.sheetCount, 2);
  expect('شیت مخفی', result.hiddenSheetCount, 1);
  expect('تعداد قلم', result.items.length, 1);
  expect('تعداد قیمت', result.priceValues, 2);
  expect('تعداد ایراد', result.issueCount, 3);
  if (result.items.isNotEmpty) {
    expect('تگ', result.items.first.tag, 'P-101 A/B');
    expect('نام (خط اول شرح)', result.items.first.name, 'پمپ آزمایشی');
  }
  for (final i in result.issues) {
    d.add('   • ${i.location}: ${i.message}');
  }
  return CheckOutcome(ok ? CheckStatus.passed : CheckStatus.failed,
      ok ? 'خواندن و تشخیص ایرادها درست است' : 'خروجی خواننده با انتظار یکی نیست', d);
}

// -----------------------------------------------------------------------------
// خواندن فایل واقعی انتخاب‌شده توسط کاربر

class FileScanReport {
  FileScanReport({required this.path, this.result, this.error, required this.elapsed, required this.sizeBytes});
  final String path;
  final MtoScanResult? result;
  final String? error;
  final Duration elapsed;
  final int sizeBytes;

  String get fileName => path.split(RegExp(r'[\\/]')).last;
}

Future<FileScanReport> scanExcelFile(String path) async {
  final sw = Stopwatch()..start();
  var size = 0;
  try {
    size = await File(path).length();
    // پردازش در Isolate جدا تا رابط کاربری هنگام خواندن فایل‌های بزرگ قفل نشود.
    final result = await Isolate.run(() => scanWorkbook(XlsxWorkbook.openFile(path)));
    return FileScanReport(path: path, result: result, elapsed: sw.elapsed, sizeBytes: size);
  } on XlsxFormatException catch (e) {
    return FileScanReport(path: path, error: e.message, elapsed: sw.elapsed, sizeBytes: size);
  } catch (e) {
    return FileScanReport(path: path, error: '$e', elapsed: sw.elapsed, sizeBytes: size);
  }
}
