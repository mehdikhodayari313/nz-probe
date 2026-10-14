// آزمون ورود MTO با فایل نمونه‌ی ساختگی هم‌قالب MTO پازنان ۲
// (test/fixtures/MTO_sample_14040105.xlsx — ساختار واقعی، اعداد و نام فروشندگان ساختگی).

import 'package:flutter_test/flutter_test.dart';
import 'dart:math' as math;

import 'package:price_bank/core/calc/generic_estimator.dart';
import 'package:price_bank/core/catalog/profiles.dart';
import 'package:price_bank/core/import/mto_importer.dart';
import 'package:price_bank/core/repo/generic_templates.dart';
import 'package:price_bank/core/price_bank.dart';
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
    expect(rep.specFields, lessThan(5)); // تقریباً همه‌ی خط‌ها به فیلدهای قالب رده رفته‌اند
    expect(pb.mtoImporter().run(MtoImporter.analyze(wb, fileName: 'x.xlsx'), projectName: 'Sample').alreadyImported,
        isTrue);

    final vessel = pb.catalog.categoryByCode('VESSEL')!;
    expect(vessel.enabled, isTrue);
    expect(pb.catalog.fields(vessel.id).any((f) => f.key == 'design_pressure_barg'), isTrue);

    final rows = pb.computeCategory(vessel.id);
    expect(rows.length, 4);
    final r = rows.firstWhere((r) => r.item.tag == 'V-141');
    final p = r.item.primary!;
    expect(p.currency, 'IRR');
    expect(p.costYear, 1404);
    expect(r.item.values['design_pressure_barg'], 13.5);
    expect(r.item.values['id_mm'], 2300);
    expect(r.item.values['tl_mm'], 6900);
    expect(r.item.values['orientation'], 'Vertical');
    expect(r.item.values['material_class'], 'CS');
    expect(r.item.values['design_temp_max_c'], 85);
    expect(r.item.values['design_code'], 'ASME VIII, DIV.1 & IPS-G-ME-150');
    expect(r.size, closeTo(math.pi / 4 * 2.3 * 2.3 * 6.9 + math.pi * 2.3 * 2.3 * 2.3 / 12, 1e-9));
    expect(r.coef, isNotNull);
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

    // قالب سایر رده‌ها
    final cip = pb.computeCategory(pb.catalog.categoryByCode('CIP')!.id).first;
    expect(cip.item.values['chemical'], 'Anti Scale');
    expect(cip.item.values['injection_rate_lph'], 3);
    expect(cip.item.values['material_class'], 'SS316');
    expect(cip.size, 3);
    final hex = pb.computeCategory(pb.catalog.categoryByCode('HEX')!.id).single;
    expect(hex.item.values['hex_type'], 'Plate & Frame');
    expect(hex.item.values['duty_kw'], 3155);
    expect(hex.item.values['material_class'], 'Titanium');
    final crane = pb.computeCategory(pb.catalog.categoryByCode('CRANE')!.id).first;
    expect(crane.item.values['capacity_kg'], 5000);
    expect(crane.item.values['span_m'], 8.15);
    expect(crane.item.values['crane_type'], 'Top Running');
    final des = pb.computeCategory(pb.catalog.categoryByCode('DESALTER')!.id).single;
    expect(des.item.values['vessel_id_mm'], 3658);
    expect(des.item.values['pump_flow_m3h'], 20.2);
    expect(des.size, isNotNull);

    // تخمین: نزدیک‌ترین همتا با مشخصات خود V-141 = همان قیمت تعدیل‌شده‌ی V-141
    final vrows = pb.computeCategory(vessel.id);
    final v141 = vrows.firstWhere((x) => x.item.tag == 'V-141');
    final est = pb.genericEstimator('VESSEL');
    final peers = pb.genericPeers('VESSEL', vrows);
    expect(peers.length, 4);
    final near = est.estimate(values: v141.item.values, allPeers: peers, method: GenEstMethod.near);
    expect(near.nearest!.itemId, v141.item.id);
    expect(near.res.eurExpected, closeTo(v141.result.eurTarget.number!, 1e-6));
    final cap = est.estimate(values: v141.item.values, allPeers: peers, method: GenEstMethod.cap, quantity: 2);
    expect(cap.res.eurExpected, isNotNull);
    expect(cap.res.irrTotal, closeTo(cap.res.irrExpected! * 2, 1e-3));
    final man = est.estimate(values: v141.item.values, allPeers: peers, method: GenEstMethod.manual, manualCoef: 1000);
    expect(man.res.eurExpected, closeTo(1000 * math.pow(v141.size!, 0.6) * v141.allF, 1e-6));

    // تنظیمات رده: روش M0 فقط برای ظرف‌ها
    pb.settingsRepo.set('cat_method_VESSEL', 'M0');
    pb.invalidateCalc();
    final v0 = pb.computeCategory(vessel.id).firstWhere((x) => x.item.tag == 'V-141');
    expect(v0.result.methodCode, 'M0');
    expect(v0.result.eurTarget.number, closeTo(v0.result.eurSource.number!, 1e-9));
    expect(pb.computeCategory(pb.catalog.categoryByCode('TANK')!.id).every((x) => x.result.methodCode == 'M6'), isTrue);
    pb.close();
  });

  test('اقلام قدیمی: استخراج قالب از شرح MTO در باز شدن برنامه', () {
    final pb = PriceBank.memory(loadSeed());
    final cat = pb.catalog.categoryByCode('TANK')!;
    final (rawKey, _) = pb.catalog.ensureSpecField(cat.id, 'Roof Type');
    final id = pb.items.create(categoryId: cat.id, values: {
      'tag': 'TK-1',
      'name': 'Test Tank',
      'mto_description': 'Test Tank\nSize (D x H): 10000 x 8000 mm\nRoof Type: Cone\nMaterial (Shell/Bottom/Roof): A 283 Gr. C',
      rawKey: 'Cone',
    });
    ensureGenericTemplates(pb.db);
    pb.catalog.invalidate();
    final it = pb.items.get(id)!;
    expect(it.values['diameter_mm'], 10000);
    expect(it.values['roof_type'], 'Cone');
    expect(it.values['material_class'], 'CS');
    expect(it.values.containsKey(rawKey), isFalse);
    expect(pb.catalog.fields(cat.id).any((f) => f.key == rawKey), isFalse);
    pb.close();
  });

  test('وزن ظرف: خالی = بی‌اثر؛ با وزن دو قلم، ضریب وزن جای ضریب فشار را می‌گیرد', () {
    final pb = PriceBank.memory(loadSeed());
    pb.mtoImporter().run(MtoImporter.analyze(wb, fileName: 'x.xlsx'), projectName: 'Sample');
    final vessel = pb.catalog.categoryByCode('VESSEL')!;
    expect(pb.catalog.fields(vessel.id).any((f) => f.key == 'empty_weight_kg'), isTrue);
    final rows = pb.computeCategory(vessel.id);
    final before = {for (final r in rows) r.item.tag: r.allF};
    final a = rows.firstWhere((r) => r.item.tag == 'V-141');
    final b = rows.firstWhere((r) => r.item.tag != 'V-141' && r.size != null);

    // فقط یک قلم وزن دارد ← مرجع نیست ← بی‌اثر
    pb.items.update(a.item.id, {'empty_weight_kg': 5000});
    expect(pb.weightRefOf('VESSEL'), isNull);
    expect({for (final r in pb.computeCategory(vessel.id)) r.item.tag: r.allF}, before);

    // دو قلم وزن دارند ← ضریب وزن فعال
    pb.items.update(b.item.id, {'empty_weight_kg': 9000});
    final ref = pb.weightRefOf('VESSEL')!;
    final a2 = pb.computeCategory(vessel.id).firstWhere((r) => r.item.tag == 'V-141');
    final est = pb.genericEstimator('VESSEL');
    final (all, m) = est.configFactor(a2.item.values);
    expect(m['WEIGHT']!.$2, closeTo(math.pow(5000 / a2.size! / ref, 0.8), 1e-9));
    expect(m['PRESS']!.$2, 1.0);
    expect(a2.allF, closeTo(all, 1e-12));
    // تخمین بدون وزن ← بی‌اثر و ضریب فشار برمی‌گردد
    final noW = Map<String, Object?>.of(a2.item.values)..remove('empty_weight_kg');
    expect(est.configFactor(noW).$2['WEIGHT']!.$2, 1.0);
    expect(est.configFactor(noW).$2['PRESS']!.$1, isNot('با وزن جایگزین شد'));
    // توان وزن صفر ← وزن نادیده
    pb.settingsRepo.set('cat_wexp_VESSEL', '0');
    expect(pb.genericEstimator('VESSEL').weightFactor(a2.item.values), isNull);
    // خواندن وزن از شرح MTO
    final p = equipmentProfiles['VESSEL']!;
    expect(p.extract({'Empty Weight': '12.5 ton'})['empty_weight_kg'], 12500);
    expect(p.extract({'Weight (Empty / Operating)': '5200 / 9100 kg'})['empty_weight_kg'], 5200);
    expect(p.extract({'Operating Weight': '20000 kg'}).containsKey('empty_weight_kg'), isFalse);
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
