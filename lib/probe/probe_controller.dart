import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../core/mto/mto_scan.dart';
import 'checks.dart';

/// مدیریت اجرای آزمون‌ها و ساخت گزارش. رابط کاربری فقط به این کلاس گوش می‌دهد.
class ProbeController extends ChangeNotifier {
  ProbeController() : checks = buildChecks();

  static const appVersion = '0.1.0';

  final List<ProbeCheck> checks;
  final List<FileScanReport> fileReports = [];

  bool running = false;
  bool scanningFiles = false;

  /// تأیید چشمی کاربر برای نمایش درست فارسی: null = هنوز پاسخ نداده.
  bool? fontConfirmed;

  int get passedCount => checks.where((c) => c.status == CheckStatus.passed).length;
  int get warningCount => checks.where((c) => c.status == CheckStatus.warning).length;
  int get failedCount => checks.where((c) => c.status == CheckStatus.failed).length;
  bool get finished => checks.every((c) => c.status != CheckStatus.pending && c.status != CheckStatus.running);

  CheckStatus get overall {
    if (!finished) return CheckStatus.running;
    if (failedCount > 0 || fontConfirmed == false) return CheckStatus.failed;
    if (warningCount > 0) return CheckStatus.warning;
    if (fontConfirmed == null) return CheckStatus.needsUser;
    return CheckStatus.passed;
  }

  Future<void> runAll() async {
    if (running) return;
    running = true;
    for (final c in checks) {
      c.status = CheckStatus.pending;
      c.summary = '';
      c.details = const [];
      c.elapsed = null;
    }
    notifyListeners();

    for (final c in checks) {
      c.status = CheckStatus.running;
      notifyListeners();
      final sw = Stopwatch()..start();
      try {
        final out = await c.run();
        c.status = out.status;
        c.summary = out.summary;
        c.details = out.details;
      } catch (e, st) {
        c.status = CheckStatus.failed;
        c.summary = 'خطای پیش‌بینی‌نشده';
        c.details = ['$e', ...st.toString().split('\n').take(8)];
      }
      c.elapsed = sw.elapsed;
      notifyListeners();
    }
    running = false;
    notifyListeners();
  }

  void confirmFont(bool ok) {
    fontConfirmed = ok;
    notifyListeners();
  }

  Future<void> scanFiles(List<String> paths) async {
    if (scanningFiles || paths.isEmpty) return;
    scanningFiles = true;
    notifyListeners();
    for (final p in paths) {
      final r = await scanExcelFile(p);
      fileReports.insert(0, r);
      notifyListeners();
    }
    scanningFiles = false;
    notifyListeners();
  }

  /// گزارش متنی کامل برای ارسال به واحد IT یا توسعه‌دهنده.
  String buildReport() {
    final now = Jalali.now();
    final b = StringBuffer()
      ..writeln('گزارش سنجش سازگاری — بانک قیمت نمک‌زدایی')
      ..writeln('نسخه‌ی برنامه‌ی آزمایشی: $appVersion')
      ..writeln('تاریخ: ${now.year}/${now.month}/${now.day}  ${DateTime.now().toIso8601String()}')
      ..writeln('رایانه: ${Platform.localHostname}')
      ..writeln('نتیجه‌ی کلی: ${statusLabel(overall)}')
      ..writeln('تأیید نمایش فارسی: ${fontConfirmed == null ? 'پاسخ داده نشد' : (fontConfirmed! ? 'درست' : 'نادرست')}')
      ..writeln('=' * 60);

    for (final c in checks) {
      b
        ..writeln()
        ..writeln('[${statusLabel(c.status)}] ${c.title} — ${c.summary}'
            '${c.elapsed == null ? '' : '  (${c.elapsed!.inMilliseconds}ms)'}');
      for (final line in c.details) {
        b.writeln('    $line');
      }
    }

    if (fileReports.isNotEmpty) {
      b
        ..writeln()
        ..writeln('=' * 60)
        ..writeln('فایل‌های اکسل آزمایش‌شده');
      for (final f in fileReports) {
        b
          ..writeln()
          ..writeln('• ${f.fileName}  (${(f.sizeBytes / 1024).toStringAsFixed(0)} KB، ${f.elapsed.inMilliseconds}ms)');
        if (f.error != null) {
          b.writeln('    خطا: ${f.error}');
          continue;
        }
        final r = f.result!;
        b
          ..writeln('    قالب: ${r.format.title}')
          ..writeln('    شماره‌ی سند: ${r.documentRef ?? '—'}')
          ..writeln('    شیت‌ها: ${r.sheetCount} (مخفی: ${r.hiddenSheetCount})، شیت‌های داده: ${r.dataSheets.length}')
          ..writeln('    اقلام: ${r.items.length}، مقادیر قیمت: ${r.priceValues}، سلول‌های خوانده‌شده: ${r.cellsRead}')
          ..writeln('    ایرادها: ${r.issueCount}');
        for (final i in r.issues.take(40)) {
          b.writeln('      - [${issueLabel(i.level)}] ${i.location}: ${i.message}');
        }
        if (r.issueCount > 40) b.writeln('      ... و ${r.issueCount - 40} مورد دیگر');
      }
    }
    return b.toString();
  }
}

String statusLabel(CheckStatus s) => switch (s) {
      CheckStatus.pending => 'در انتظار',
      CheckStatus.running => 'در حال اجرا',
      CheckStatus.passed => 'موفق',
      CheckStatus.warning => 'هشدار',
      CheckStatus.failed => 'ناموفق',
      CheckStatus.needsUser => 'نیاز به تأیید شما',
    };

String issueLabel(IssueLevel l) => switch (l) {
      IssueLevel.info => 'اطلاع',
      IssueLevel.warning => 'هشدار',
      IssueLevel.error => 'خطا',
    };
