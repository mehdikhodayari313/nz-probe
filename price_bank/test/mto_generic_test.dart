// ورود MTO با قالب متفاوت از پازنان (فایل ساختگی: عنوان دوسطری، سلول‌های ادغام‌شده، بلوک‌های Quotation،
// عنوان بخش‌ها و ستون‌های مشخصه‌ی فنی جدا).

import 'package:flutter_test/flutter_test.dart';
import 'package:price_bank/core/catalog/profiles.dart';
import 'package:price_bank/core/import/mto_generic.dart';
import 'package:price_bank/core/import/mto_importer.dart';
import 'package:price_bank/core/price_bank.dart';
import 'package:price_bank/core/xlsx/xlsx_reader.dart';

import 'support.dart';

const genericSample = 'test/fixtures/MTO_generic_sample_14031020.xlsx';

void main() {
  late XlsxWorkbook wb;
  setUpAll(() => wb = XlsxWorkbook.openFile(genericSample));

  test('تشخیص خودکار ستون‌ها، بخش‌ها و رده‌ها', () {
    final a = MtoImporter.analyze(wb, fileName: 'MTO_generic_sample_14031020.xlsx');
    expect(a.supported, isTrue);
    expect(a.format, 'generic');
    expect(a.docRef, '12345-KPL-ME-MTO-002-R0');
    expect(a.revision, 'R0');
    expect(a.suggestedProject, 'Koopal Asmari');
    expect(a.issueYear, 1403);
    expect(a.skippedSheets, contains('Cover'));

    final l = a.layouts['Equipment List']!;
    expect(l.headerRow, 5);
    expect(l.dataStart, 7);
    MtoColumn col(String h) => l.columns.firstWhere((c) => c.header == h);
    expect(col('Tag No.').role, MtoColRole.tag);
    expect(col('ردیف').role, MtoColRole.ignore);
    expect(col('Description').role, MtoColRole.desc);
    expect(col('Qty').role, MtoColRole.qty);
    expect(col('Unit Price (EUR) 1403').role, MtoColRole.going);
    expect(col('Unit Price (EUR) 1403').currency, 'EUR');
    expect(col('Unit Price (EUR) 1403').year, 1403);
    expect(col('Total Price (EUR)').role, MtoColRole.total);
    expect(col('Quotation 1 Vendor').role, MtoColRole.vendor);
    expect(col('Quotation 1 Price (EUR)').role, MtoColRole.quote);
    expect(col('Quotation 2 Date').role, MtoColRole.date);
    expect(col('Quotation 2 Price (EUR)').block, isNot(col('Quotation 1 Price (EUR)').block));
    expect(col('Previous Estimate 1398 (IRR)').role, MtoColRole.old);
    expect(col('Previous Estimate 1398 (IRR)').year, 1398);
    expect(col('Remarks').role, MtoColRole.remarks);
    expect(col('Design Pressure (barg)').role, MtoColRole.spec);

    final cats = {for (final s in a.sheets) s.categoryCode: s.items.length};
    expect(cats, {'VESSEL': 2, 'PUMP': 1, 'TANK': 1});
    final v = a.sheets.firstWhere((s) => s.categoryCode == 'VESSEL').items.first;
    expect(v.tag, 'V-101');
    expect(v.name, 'Produced Water Degassing Drum');
    expect(v.goingEur, 52000);
    expect(v.oldIrr, 1650000000);
    expect(v.quotes.map((q) => q.vendor).toList(), ['Vendor A', 'Vendor B']);
    expect(v.quotes.first.year, 1403);
    expect(v.quotes.first.month, 8);
    expect(v.specs['Design Pressure (barg)'], '10');
  });

  test('ورود به بانک: مشخصات در فیلدهای قالب هر رده، قیمت‌ها و استعلام‌ها', () {
    final pb = PriceBank.memory(loadSeed());
    final a = MtoImporter.analyze(wb, fileName: 'MTO_generic_sample_14031020.xlsx');
    final rep = pb.mtoImporter().run(a, projectName: 'Koopal Asmari', oldFx: null);
    expect(rep.items, 4);
    expect(rep.quotes, 6);
    expect(rep.perCategory, {'VESSEL': 2, 'PUMP': 1, 'TANK': 1});

    final vessel = pb.catalog.categoryByCode('VESSEL')!;
    final v = pb.computeCategory(vessel.id).firstWhere((r) => r.item.tag == 'V-101');
    expect(v.item.values['id_mm'], 1200);
    expect(v.item.values['tl_mm'], 3500);
    expect(v.item.values['design_pressure_barg'], 10);
    expect(v.item.values['material_class'], 'CS');
    expect(v.item.primary!.currency, 'EUR');
    expect(v.item.primary!.costYear, 1403);
    expect(v.result.eurTarget.isNumber, isTrue);
    expect(v.quoteCount, 2);
    final old = v.item.observations.firstWhere((o) => o.costYear == 1398);
    expect(old.currency, 'IRR');
    final v2 = pb.computeCategory(vessel.id).firstWhere((r) => r.item.tag == 'V-102');
    expect(v2.item.values['material_class'], 'SS316');

    final tank = pb.computeCategory(pb.catalog.categoryByCode('TANK')!.id).single;
    expect(tank.item.values['diameter_mm'], 10000);
    expect(tank.item.values['height_mm'], 8000);

    // پمپ: دبی، هد، کلاس متریال و زیرگروه در فیلدهای قالب پمپ
    final p = pb.computePumps().firstWhere((r) => r.item.tag == 'P-201 A/B');
    expect(p.item.values['capacity_m3h'], 45);
    expect(p.item.values['diff_head_m'], 139.1);
    expect(p.item.values['material_class'], 'A-8');
    expect(p.item.values['sub_category'], 'ROT-CRU');
    expect(p.item.quantity, 2);
    expect(p.result.eurSource.isNumber, isTrue);

    // صحت‌سنجی روش‌ها با همین داده‌ها (قیمت ۱۳۹۸ در برابر استعلام ۱۴۰۳)
    expect(pb.backtestCategory('VESSEL').n, 1);
    pb.close();
  });

  test('اصلاح نقش ستون در پیش‌نمایش و خواندن دوباره', () {
    final a = MtoImporter.analyze(wb, fileName: 'x.xlsx');
    final l = a.layouts['Equipment List']!;
    l.columns.firstWhere((c) => c.header == 'Remarks').role = MtoColRole.spec;
    l.columns.firstWhere((c) => c.header == 'Quotation 2 Price (EUR)').role = MtoColRole.ignore;
    MtoImporter.relayout(a, 'Equipment List');
    final v = a.sheets.firstWhere((s) => s.categoryCode == 'VESSEL').items.first;
    expect(v.specs['Remarks'], 'incl. internals');
    expect(v.quotes.length, 1);
    // تعریف دستی سطر عنوان روی شیتی که جدول ندارد: بی‌اثر
    MtoImporter.relayout(a, 'Cover', headerRow: 1);
    expect(a.skippedSheets, contains('Cover'));
    expect(a.itemCount, 4);
  });

  test('تشخیص رده از متن و مشخصات پمپ', () {
    expect(suggestCategoryFromText('Pump Suction Drum'), 'VESSEL');
    expect(suggestCategoryFromText('Demulsifier Injection Pumps'), 'PUMP');
    expect(suggestCategoryFromText('Chemical Injection Package'), 'CIP');
    expect(suggestCategoryFromText('پمپ تزریق مواد شیمیایی'), 'PUMP');
    expect(suggestCategoryFromText('مخزن ذخیره‌ی آب'), 'TANK');
    expect(suggestCategoryFromText('Plate Heat Exchanger'), 'HEX');
    final s = extractPumpSpecs({
      'Type': 'Centrifugal (VS6)',
      'Rated Flow (m3/hr)': '45',
      'Differential Head (m)': '139.1',
      'Material Class(Acc. to API 610)': 'D1',
      "NACE 'MR-0175' Required": 'Yes',
      'Design Code & Standard': 'API 610 & IPS-G-PM-105',
    }, 'Off Spec. Crude Pumps');
    expect(s['pump_family'], 'Centrifugal');
    expect(s['api610_type'], 'VS6');
    expect(s['capacity_m3h'], 45);
    expect(s['material_class'], 'D-1');
    expect(s['nace'], 'Y');
    expect(s['pump_standard'], 'API 610');
    expect(s['ips_standard'], 'IPS-G-PM-105');
    expect(s['sub_category'], 'ROT-CRU');
  });
}
