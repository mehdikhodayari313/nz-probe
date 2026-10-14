// قالب‌های واقعی MTO/PEP (ساختار کپی‌شده از فایل‌های واقعی، نام‌ها و اعداد تغییر داده شده):
//   ۱) گزارش چاپی MTO مشاور (مثل KPL): برگه‌ی هر رده، قلم چندسطری، ادغام سلول‌ها، شیت‌های نصب با وزن
//   ۲) PEP کارفرما (مثل گچساران ۴): عنوان سه‌سطری، تگ دوتکه، واحد Kg، بخش‌ها و زیرمجموعه‌ها، برق/ابزار/پایپینگ

import 'package:flutter_test/flutter_test.dart';
import 'package:price_bank/core/import/mto_importer.dart';
import 'package:price_bank/core/price_bank.dart';
import 'package:price_bank/core/xlsx/xlsx_reader.dart';

import 'support.dart';

const kplName = '99999-SMP-ME-RE-476_R03_MTO_and_Cost_Estimation_Report.xlsx';
const pepName = 'PEP-Rev.140205_Sample_4.xlsx';

MtoSheet groupOf(MtoAnalysis a, String code) => a.sheets.firstWhere((s) => s.categoryCode == code);
MtoItem itemOf(MtoAnalysis a, String tag) => a.sheets.expand((s) => s.items).firstWhere((i) => i.tag == tag);

void main() {
  group('گزارش چاپی MTO (قالب KPL)', () {
    late MtoAnalysis a;
    setUpAll(() => a = MtoImporter.analyze(XlsxWorkbook.openFile('test/fixtures/$kplName'), fileName: kplName));

    test('سند، تاریخ بازنگری و پروژه', () {
      expect(a.format, 'generic');
      expect(a.docRef, '99999-SMP-ME-RE-476-R03');
      expect(a.revision, 'R03');
      expect(a.issueYear, 1394); // JAN. 2016
      expect(a.issueMonth, 10);
      expect(a.suggestedProject, 'Sample (North & South)');
      expect(a.skippedSheets, containsAll(['Cover', 'TOTAL', 'INS-VESSEL-A', 'INS-TANK-A (1)']));
      expect(a.weights['V-171'], 4000);
      expect(a.weights['V-231'], 11739);
      expect(a.weights['TK-111'], 340000);
    });

    test('اقلام چندسطری با مشخصات کامل', () {
      final vessels = a.sheets.where((s) => s.categoryCode == 'VESSEL').expand((s) => s.items).map((i) => i.tag).toSet();
      expect(vessels, containsAll(['V-171', 'V-231', 'V-181', 'V-241']));
      final v = itemOf(a, 'V-171');
      expect(v.name, 'Flare K.O. Drum');
      expect(v.quantity, 1);
      expect(v.goingIrr, 997550194);
      expect(v.specs['Size (ID x TL-TL)'], '1500 x 4500 mm');
      expect(v.specs['Design Code & Standard'], contains('IPS-G-ME-150'));
      expect(v.specs['Section'], 'NORTH TRAIN');
      expect(groupOf(a, 'VESSEL').goingYear, 1394);

      final p = itemOf(a, 'P-111 A/B/C');
      expect(p.quantity, 3);
      expect(p.goingEur, 66264);
      expect(p.specs['Rated Flow (m3/hr)'], '354');
      expect(itemOf(a, 'PK-111').specs['Vessels Dim. (ID x TL-TL)'], '4267x30480 mm');
      expect(groupOf(a, 'DESALTER').items.single.tag, 'PK-111');
      expect(groupOf(a, 'HEX').items.map((i) => i.tag), containsAll(['E-111', 'E-112']));
      expect(groupOf(a, 'HEATER').items.first.tag, 'H-111 A/B');
      expect(groupOf(a, 'TANK').items.first.tag, 'TK-111');
      expect(groupOf(a, 'COMPRESSOR').items.single.tag, 'PK-211 A/B');
      Iterable<String> tags(String code) => groupOf(a, code).items.map((i) => i.tag);
      expect(tags('AIR_DRYER'), ['PK-212']);
      expect(tags('CIP'), containsAll(['PK-250', 'PK-251']));
      expect(tags('CRANE'), containsAll(['CN-114 / CN-124', 'CN-151', 'CN-231', 'CN-251 / CN-261']));
      expect(tags('FLARE'), containsAll(['PK-171', 'ST-172', 'PK-231']));
      expect(tags('FILTER'), containsAll(['PK-132', 'F-151']));
      expect(tags('WATER_TREAT'), ['PK-152']);
      expect(tags('MISC_PKG'), ['PK-143']);
      expect(tags('DEAERATOR'), ['E-151']);
      expect(tags('IGF'), ['PK-131']);
      expect(a.skippedSheets, contains('PROC-TITLE'));
    });

    test('ورود به بانک: فیلدهای قالب، وزن از شیت نصب', () {
      final pb = PriceBank.memory(loadSeed());
      final rep = pb.mtoImporter().run(a, projectName: 'Sample', oldFx: null);
      expect(rep.items, greaterThan(10));
      final vessel = pb.catalog.categoryByCode('VESSEL')!;
      final v = pb.computeCategory(vessel.id).firstWhere((r) => r.item.tag == 'V-171');
      expect(v.item.values['id_mm'], 1500);
      expect(v.item.values['tl_mm'], 4500);
      expect(v.item.values['orientation'], 'Horizontal');
      expect(v.item.values['design_pressure_barg'], 3.5);
      expect(v.item.values['full_vacuum'], 'Y');
      expect(v.item.values['material_class'], 'CS');
      expect(v.item.values['empty_weight_kg'], 4000);
      expect(v.item.values['mto_section'], 'NORTH TRAIN');
      expect(v.item.primary!.costYear, 1394);
      expect(v.result.eurTarget.isNumber, isTrue);
      final tank = pb.computeCategory(pb.catalog.categoryByCode('TANK')!.id).firstWhere((r) => r.item.tag == 'TK-111');
      expect(tank.item.values['diameter_mm'], 25000);
      expect(tank.item.values['roof_type'], 'Dome');
      expect(tank.item.values['empty_weight_kg'], 340000);
      final hex = pb.computeCategory(pb.catalog.categoryByCode('HEX')!.id).firstWhere((r) => r.item.tag == 'E-111');
      expect(hex.item.values['duty_kw'], 6710);
      expect(hex.item.values['material_class'], 'Titanium');
      final des = pb.computeCategory(pb.catalog.categoryByCode('DESALTER')!.id).single;
      expect(des.item.values['vessel_id_mm'], 4267);
      expect(des.item.values['pump_flow_m3h'], 21);
      final pump = pb.computePumps().firstWhere((r) => r.item.tag == 'P-111 A/B/C');
      expect(pump.item.values['capacity_m3h'], 354);
      expect(pump.item.values['material_class'], 'D-1');
      expect(pump.item.values['api610_type'], 'OH2');
      pb.close();
    });
  });

  group('PEP کارفرما (قالب گچساران ۴)', () {
    late MtoAnalysis a;
    setUpAll(() => a = MtoImporter.analyze(XlsxWorkbook.openFile('test/fixtures/$pepName'), fileName: pepName));

    test('سند و شیت‌ها', () {
      expect(a.format, 'generic');
      expect(a.issueYear, 1402);
      expect(a.issueMonth, 5);
      expect(a.suggestedProject, 'Sample 4');
      expect(a.skippedSheets, containsAll(['PEP', 'EPC Summary', 'basic data', 'E.Mechanic', 'C.mECHANICAL']));
      expect(a.layouts.keys, containsAll(['P.ME', 'P.EL', 'P.IN', 'P.PI', 'P.LAB']));
      expect(a.weights['DE-001-A/B'], 90695);
      expect(a.weights['H-001-A1/A2'], 60000);
    });

    test('تگ دوتکه، واحد Kg، رده از نام و بخش', () {
      final de = itemOf(a, 'DE-001-A/B');
      expect(de.goingEur, 2823626);
      expect(de.quantity, 1);
      expect(groupOf(a, 'DESALTER').items.length, 2);
      final tk = itemOf(a, 'TK-003');
      expect(tk.quantity, 1);
      expect(tk.weightKg, 142134);
      expect(tk.goingIrr, closeTo(530386.0 * 142134, 1));
      expect(groupOf(a, 'TANK').items.map((i) => i.tag), contains('TK-003'));
      expect(groupOf(a, 'HEX').items.map((i) => i.tag), containsAll(['E-001-A/B', 'E-002-A/B']));
      expect(groupOf(a, 'HEATER').items.map((i) => i.tag).toList(), ['H-001-A1/A2', 'H-001-B1/B2']);
      expect(groupOf(a, 'VESSEL').items.map((i) => i.tag), contains('V-001-A/B'));
      expect(groupOf(a, 'PUMP').items.map((i) => i.tag), containsAll(['P-001-A/B', 'P-902']));
      expect(groupOf(a, 'CRANE').items.length, 13);
      expect(groupOf(a, 'CRANE').items.first.tag, 'CR-001');
      expect(groupOf(a, 'HVAC').items.length, greaterThanOrEqualTo(8));
      expect(groupOf(a, 'WATER_TREAT').items.length, 2);
      expect(groupOf(a, 'FIRE_SAFETY').items.length, greaterThanOrEqualTo(15));
      expect(groupOf(a, 'MISC_PKG').items.single.name, 'Pig Launcher & Receiver');
      expect(groupOf(a, 'CIP').items.map((i) => i.tag), contains('PK-501'));
      expect(groupOf(a, 'DEAERATOR').items.single.tag, 'PK-101');
      expect(groupOf(a, 'ELEC_EQ').items.first.tag, 'P.EL#1.1');
      expect(groupOf(a, 'INST_EQ').items.first.goingEur, 52603);
      expect(groupOf(a, 'PIPE_BULK').items.first.name, startsWith('StudBolt&nuts'));
      expect(groupOf(a, 'LAB').items.first.name, 'Microwave Digestion System');
      final pl = a.sheets.where((s) => s.source == 'P.PL').expand((s) => s.items).first;
      expect(pl.goingEur, isNotNull);
      expect(pl.specs['Unit'] ?? pl.description, isNotEmpty);
    });

    test('ورود به بانک: مشخصات متن آزاد، وزن، رده‌های عمومی', () {
      final pb = PriceBank.memory(loadSeed());
      final rep = pb.mtoImporter().run(a, projectName: 'Sample 4', oldFx: null);
      expect(rep.items, greaterThan(60));
      final des = pb.computeCategory(pb.catalog.categoryByCode('DESALTER')!.id).firstWhere((r) => r.item.tag == 'DE-001-A/B');
      expect(des.item.values['vessel_id_mm'], 5300);
      expect(des.item.values['vessel_tl_mm'], 18000);
      expect(des.item.values['design_pressure_barg'], 19.5);
      expect(des.item.values['empty_weight_kg'], 90695);
      expect(des.item.primary!.costYear, 1402);
      final tk = pb.computeCategory(pb.catalog.categoryByCode('TANK')!.id).firstWhere((r) => r.item.tag == 'TK-003');
      expect(tk.item.values['diameter_mm'], 25000);
      expect(tk.item.values['height_mm'], 15000);
      expect(tk.item.values['empty_weight_kg'], 142134);
      final hex = pb.computeCategory(pb.catalog.categoryByCode('HEX')!.id).firstWhere((r) => r.item.tag == 'E-001-A/B');
      expect(hex.item.values['duty_kw'], 5275);
      final pump = pb.computePumps().firstWhere((r) => r.item.tag == 'P-001-A/B');
      expect(pump.item.values['capacity_m3h'], 500);
      expect(pump.item.values['power_kw'], 216.3);
      final cip = pb.computeCategory(pb.catalog.categoryByCode('CIP')!.id).firstWhere((r) => r.item.tag == 'PK-501');
      expect(cip.item.values['injection_rate_lph'], 20);
      final elec = pb.catalog.categoryByCode('ELEC_EQ')!;
      expect(elec.enabled, isTrue);
      expect(pb.computeCategory(elec.id).first.result.eurTarget.isNumber, isTrue);
      expect(pb.bankCategories().map((c) => c.code), containsAll(['HVAC', 'FIRE_SAFETY', 'LAB', 'PIPE_BULK']));
      pb.close();
    });

    test('تغییر رده‌ی یک قلم در پیش‌نمایش', () {
      final b = MtoImporter.analyze(XlsxWorkbook.openFile('test/fixtures/$pepName'), fileName: pepName);
      final from = groupOf(b, 'MISC_PKG');
      b.moveItem(from, from.items.single, 'VESSEL');
      expect(b.sheets.where((s) => s.categoryCode == 'MISC_PKG'), isEmpty);
      expect(groupOf(b, 'VESSEL').items.map((i) => i.name), contains('Pig Launcher & Receiver'));
    });
  });
}
