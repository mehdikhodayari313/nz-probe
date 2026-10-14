// آزمون ورود MTO با فایل نمونه‌ی ساختگی هم‌قالب MTO پازنان ۲
// (test/fixtures/MTO_sample_14040105.xlsx — ساختار واقعی، اعداد و نام فروشندگان ساختگی).

import 'package:flutter_test/flutter_test.dart';
import 'package:price_bank/core/import/mto_importer.dart';
import 'package:price_bank/core/price_bank.dart';
import 'package:price_bank/core/repo/catalog_repo.dart';
import 'package:price_bank/core/xlsx/xlsx_reader.dart';

import 'support.dart';

const mtoSample = 'test/fixtures/MTO_sample_14040105.xlsx';

void main() {
  late XlsxWorkbook wb;
  setUpAll(() => wb = XlsxWorkbook.openFile(mtoSample));

  test('تحلیل فایل: سند، پروژه، شیت‌ها، اقلام و استعلام‌ها', () {
    final a = MtoImporter.analyze(wb, fileName: 'MTO_sample_14040105.xlsx');
    expect(a.supported, isTrue);
    expect(a.docRef, '99999-SMP-ME-RE-001-R01');
    expect(a.revision, 'R01');
    expect(a.suggestedProject, 'Sample');
    expect(a.issueYear, 1404);
    expect(a.issueMonth, 1);
    expect(a.sheets.map((s) => s.name).toList(), ['DESALTER', 'VESSELS', 'PUMPS', 'C.I.P.', 'CRANES', 'EXCHANG.']);
    expect(a.sheets.map((s) => s.categoryCode).toList(), ['DESALTER', 'VESSEL', 'PUMP', 'CIP', 'CRANE', 'HEX']);
    expect(a.skippedSheets, containsAll(['Cover', 'Lab Equip']));
    expect(a.itemCount, 19);
    expect(a.quoteCount, 33);

    final des = a.sheets.first;
    expect(des.goingYear, 1404);
    expect(des.goingMonth, 2);
    expect(des.oldYear, 1393); // «UNIT PRICE ریال 1393Q3»
    expect(des.oldMonth, 8);
    expect(des.items.single.oldEur, isNotNull);

    final v = a.sheets[1].items.first;
    expect(v.tag, 'V-141');
    expect(v.name, 'Air Receiver');
    expect(v.specs['Design Pressure'], '13.5 Barg');
    expect(v.specs['Design Code & Standard'], 'ASME VIII, DIV.1 & IPS-G-ME-150');
    expect(v.quotes.length, 2);
    expect(v.quotes.every((q) => q.currency == 'EUR'), isTrue);
    expect(v.quotes.any((q) => q.dateFixed), isTrue); // 02/29/2025
    expect(v.quotes.map((q) => q.year).toSet(), {1403, 1404});
    expect(v.nonResponses.length, 3);
    expect(v.refCurrency, 'IRR');
    expect(v.goingIrr, isNotNull);
    expect(v.oldIrr, isNotNull);
  });

  test('ورود به دیتابیس، جلوگیری از ورود تکراری و محاسبه‌ی قیمت', () {
    final pb = PriceBank.memory(loadSeed());
    final a = MtoImporter.analyze(wb, fileName: 'MTO_sample_14040105.xlsx');
    final rep = pb.mtoImporter().run(a, projectName: 'Sample');
    expect(rep.alreadyImported, isFalse);
    expect(rep.items, 19);
    expect(rep.quotes, 33);
    expect(rep.perCategory['VESSEL'], 4);
    expect(rep.perCategory['PUMP'], 4);
    expect(rep.specFields, greaterThan(10));
    expect(pb.mtoImporter().run(MtoImporter.analyze(wb, fileName: 'x.xlsx'), projectName: 'Sample').alreadyImported,
        isTrue);

    final vessel = pb.catalog.categoryByCode('VESSEL')!;
    expect(vessel.enabled, isTrue);
    final f = pb.catalog.fields(vessel.id).firstWhere((f) => f.key == CatalogRepo.specKey('Design Pressure'));
    expect(f.labelFa, 'فشار طراحی');

    final rows = pb.computeCategory(vessel.id);
    expect(rows.length, 4);
    final r = rows.firstWhere((r) => r.item.tag == 'V-141');
    final p = r.item.primary!;
    expect(p.currency, 'IRR');
    expect(p.costYear, 1404);
    expect(r.item.values[CatalogRepo.specKey('Design Pressure')], '13.5 Barg');
    // یورو(پایه) = ریال ÷ نرخ یوروی ۱۴۰۴ جدول پیش‌فرض
    final eur1404 = pb.seriesSnapshot.resolve('FX_EUR_V8', 1404, month: 2)!.value;
    expect(r.result.eurSource.number, closeTo(p.amount! / eur1404, 1e-6));
    expect(r.result.eurTarget.isNumber, isTrue);
    expect(r.quoteCount, 2);
    expect(r.quoteEurTargets.length, 2);
    // قیمت بازنگری قبلی با نرخ تسعیر سند (۴۰٬۵۳۰٫۸)
    final old = r.item.observations.firstWhere((o) => o.costYear == 1393);
    expect(old.effectiveSourceFx, MtoImporter.defaultOldFx);

    // پمپ‌های MTO هم وارد رده‌ی پمپ شده‌اند و محاسبه می‌شوند
    final pumps = pb.computePumps().where((x) => x.item.projectName == 'Sample').toList();
    expect(pumps.length, 4);
    expect(pumps.every((x) => x.result.eurSource.isNumber), isTrue);

    // تغییر قیمت اصلی به یک استعلام
    final q = r.item.observations.firstWhere((o) => o.kind == 'quote');
    pb.items.setPrimary(r.item.id, q.id);
    expect(pb.items.get(r.item.id)!.primary!.id, q.id);
    pb.close();
  });

  test('نام پروژه از عنوان', () {
    expect(MtoImporter.suggestProjectName('Revamping of Pazanan II Desalting Unit'), 'Pazanan 2');
    expect(MtoImporter.suggestProjectName('Construction of Koopal Asmari Desalting Plant'), 'Koopal Asmari');
    expect(suggestCategory('AIR DRYER'), 'AIR_DRYER');
    expect(suggestCategory('AIR COMP.'), 'COMPRESSOR');
    expect(suggestCategory('BURN PIT'), 'FLARE');
  });
}
