// آزمون روی فایل‌های واقعی پروژه‌ها.
//
// فایل‌های اکسل محرمانه‌اند و همراه کد نیستند. برای اجرای این آزمون، فایل‌ها را در
// پوشه‌ی test/fixtures کپی کنید (با هر نامی). اگر پوشه خالی باشد این آزمون رد می‌شود.
//
// اعداد مورد انتظار از خواندن مستقل همین فایل‌ها با پایتون (openpyxl) به دست آمده‌اند.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nz_probe/core/mto/mto_scan.dart';
import 'package:nz_probe/core/xlsx/xlsx_reader.dart';

/// شماره‌ی سند → (قالب، تعداد قلم، تعداد قیمت)
const _expected = <String, (MtoFormat, int, int)>{
  '91211-PZN-ME-RE-451-R02': (MtoFormat.consultantWorking, 56, 103),
  '91215-KPL-ME-RE-476-R03': (MtoFormat.consultantReport, 120, 120),
};

void main() {
  final dir = Directory('test/fixtures');
  final files = dir.existsSync()
      ? dir.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.xlsx')).toList()
      : <File>[];

  if (files.isEmpty) {
    test('فایل واقعی در test/fixtures نیست', () {}, skip: 'فایل‌ها را برای این آزمون در test/fixtures بگذارید');
    return;
  }

  for (final f in files) {
    test('خواندن ${f.uri.pathSegments.last}', () {
      final sw = Stopwatch()..start();
      final r = scanWorkbook(XlsxWorkbook.openFile(f.path));
      // ignore: avoid_print
      print('${f.uri.pathSegments.last}: ${r.format.name}, سند=${r.documentRef}, '
          'اقلام=${r.items.length}, قیمت=${r.priceValues}, ایراد=${r.issueCount}, ${sw.elapsedMilliseconds}ms');

      expect(r.format, isNot(MtoFormat.unknown), reason: 'قالب باید شناخته شود');
      final exp = _expected[r.documentRef];
      if (exp != null) {
        expect(r.format, exp.$1);
        expect(r.items.length, exp.$2);
        expect(r.priceValues, exp.$3);
      }
    });
  }
}
