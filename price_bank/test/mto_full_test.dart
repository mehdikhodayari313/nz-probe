// آزمون کامل روی ساختار کامل سه فایل واقعی (همه‌ی شیت‌ها؛ نام پروژه‌ها عوض و اعداد تصادفی شده‌اند):
// گزارش MTO چاپی (KPL)، PEP کارفرما (گچساران ۴) و برآورد به‌روزرسانی (مارون ۳).
// خلاصه‌ی خوانده‌شده چاپ می‌شود تا رفتار روی فایل کامل دیده شود.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:price_bank/core/import/mto_importer.dart';
import 'package:price_bank/core/price_bank.dart';
import 'package:price_bank/core/xlsx/xlsx_reader.dart';

import 'support.dart';

MtoAnalysis load(String name) {
  final sw = Stopwatch()..start();
  final a = MtoImporter.analyze(XlsxWorkbook.openFile('test/fixtures/full/$name'), fileName: name);
  debugPrint('### $name: ${sw.elapsedMilliseconds} ms · قالب ${a.format} · سند ${a.docRef} · '
      'تاریخ ${a.issueYear}/${a.issueMonth} · پروژه ${a.suggestedProject} · وزن ${a.weights.length} تگ');
  for (final s in a.sheets) {
    final its = s.items;
    debugPrint('  ${s.display.padRight(32)} ${(s.categoryCode ?? '?').padRight(11)} ${its.length.toString().padLeft(4)} قلم'
        ' · ${s.selected ? 'انتخاب' : 'بدون تیک'} · سال ${s.goingYear} · '
        '${its.take(3).map((i) => '${i.tag}=${i.name}').join(' | ')}');
  }
  debugPrint('  رد/نصب: ${a.skippedSheets.join('، ')}');
  return a;
}

void report(PriceBank pb, MtoImportReport rep) {
  debugPrint('  ورود: ${rep.items} قلم · ${rep.quotes} استعلام · ${rep.estimates} برآورد · وزن ${rep.weights} · '
      'تکراری ${rep.skippedDuplicates} · ${rep.perCategory}');
}

void main() {
  test('MTO چاپی کامل (KPL)', () {
    final a = load('99999-SMP-ME-RE-476_R03_MTO_full.xlsx');
    expect(a.issueYear, 1394);
    expect(a.itemCount, greaterThan(100));
    expect(a.sheets.where((s) => s.categoryCode == null), isEmpty);
    final pb = PriceBank.memory(loadSeed());
    final rep = pb.mtoImporter().run(a, projectName: 'Sample', oldFx: null);
    report(pb, rep);
    expect(rep.items, greaterThan(100));
    expect(rep.weights, greaterThan(10));
    pb.close();
  });

  test('PEP کامل (گچساران ۴)', () {
    final a = load('PEP-Rev.140205_Sample_4_full.xlsx');
    expect(a.issueYear, 1402);
    expect(a.sheets.where((s) => s.categoryCode == 'PIPE_BULK').expand((s) => s.items).length, greaterThan(500));
    final pb = PriceBank.memory(loadSeed());
    final rep = pb.mtoImporter().run(a, projectName: 'Sample 4', oldFx: null);
    report(pb, rep);
    expect(rep.items, greaterThan(600));
    pb.close();
  });

  test('برآورد به‌روزرسانی (مارون ۳)', () {
    final a = load('Sample_M3_14050310.xlsx');
    final lab = a.sheets.where((s) => s.categoryCode == 'LAB').toList();
    expect(lab, isNotEmpty);
    expect(lab.first.goingYear, 1392);
    final pb = PriceBank.memory(loadSeed());
    final rep = pb.mtoImporter().run(a, projectName: 'Sample M3', oldFx: null);
    report(pb, rep);
    pb.close();
  });
}
