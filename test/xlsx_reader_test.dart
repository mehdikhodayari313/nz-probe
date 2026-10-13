import 'package:flutter_test/flutter_test.dart';
import 'package:nz_probe/core/mto/mto_scan.dart';
import 'package:nz_probe/core/xlsx/sample_xlsx.dart';
import 'package:nz_probe/core/xlsx/xlsx_reader.dart';

void main() {
  group('توابع کمکی', () {
    test('تبدیل حروف ستون به شماره و برعکس', () {
      expect(columnIndex('A'), 1);
      expect(columnIndex('Z'), 26);
      expect(columnIndex('AA'), 27);
      expect(columnIndex('AU'), 47);
      expect(columnIndex('XFD'), 16384);
      for (final n in [1, 26, 27, 52, 53, 702, 703, 16384]) {
        expect(columnIndex(columnName(n)), n);
      }
    });

    test('خواندن آدرس سلول', () {
      expect(parseCellRef('AB12'), (12, 28));
      expect(parseCellRef(r'$C$5'), (5, 3));
      expect(parseCellRef('12AB'), isNull);
      expect(parseCellRef(''), isNull);
    });

    test('عدد متنی با ویرگول و ارقام فارسی', () {
      expect(parseLooseNumber('43000'), 43000);
      expect(parseLooseNumber('43,000'), 43000);
      expect(parseLooseNumber('۴۳٬۰۰۰'), 43000);
      expect(parseLooseNumber('۳۱٫۲'), 31.2);
      expect(parseLooseNumber(' -1.5e3 '), -1500);
      expect(parseLooseNumber('declined'), isNull);
      expect(parseLooseNumber('no reply'), isNull);
      expect(parseLooseNumber(''), isNull);
    });

    test('اعتبار تاریخ میلادی', () {
      expect(isValidGregorian(2025, 2, 29), isFalse); // ۲۰۲۵ کبیسه نیست
      expect(isValidGregorian(2024, 2, 29), isTrue);
      expect(isValidGregorian(2025, 13, 1), isFalse);
    });
  });

  group('خواننده‌ی xlsx روی فایل نمونه', () {
    late XlsxWorkbook wb;
    setUp(() => wb = XlsxWorkbook.fromBytes(buildSampleXlsx()));

    test('فهرست شیت‌ها و شیت مخفی', () {
      expect(wb.sheets.map((s) => s.name).toList(), ['PUMPS', 'Hidden']);
      expect(wb.sheets[1].hidden, isTrue);
      expect(wb.visibleSheets.length, 1);
    });

    test('مسیر مطلق در rels (/xl/worksheets/...) هم خوانده می‌شود', () {
      expect(wb.sheet('Hidden')!.cell(1, 1)!.number, 1);
    });

    test('rich text، فرمول و inlineStr', () {
      final sh = wb.sheet('PUMPS')!;
      expect(sh.text(7, 1), 'Item No.'); // دو تکه‌ی rich text
      final j8 = sh.at('J8')!;
      expect(j8.hasFormula, isTrue);
      expect(j8.formula, '=4*1000');
      expect(j8.number, 4000);
      final k8 = sh.at('K8')!;
      expect(k8.value, '43000');
      expect(k8.isNumericText, isTrue);
      expect(k8.number, 43000);
      expect(sh.text(8, 2).split('\n').first, 'پمپ آزمایشی');
      expect(sh.maxRow, 9);
    });

    test('پیمایش قالب کاری مشاور', () {
      final r = scanWorkbook(wb);
      expect(r.format, MtoFormat.consultantWorking);
      expect(r.items.length, 1);
      expect(r.items.single.tag, 'P-101 A/B');
      expect(r.items.single.qty, 2);
      expect(r.priceValues, 2);
      expect(r.issueCount, 3);
      expect(r.issues.where((i) => i.level == IssueLevel.error).single.location, 'PUMPS!M8');
    });
  });

  group('فایل نامعتبر', () {
    test('فایل xls قدیمی پیام روشن می‌دهد', () {
      expect(
        () => XlsxWorkbook.fromBytes([0xD0, 0xCF, 0x11, 0xE0, 0, 0, 0, 0]),
        throwsA(isA<XlsxFormatException>().having((e) => e.message, 'message', contains('xls'))),
      );
    });

    test('بایت‌های تصادفی', () {
      expect(() => XlsxWorkbook.fromBytes([1, 2, 3, 4, 5]), throwsA(isA<XlsxFormatException>()));
    });
  });
}
