// آزمون بانک کمپرسور هوا: موتور محاسبات در برابر ستون‌های فرمولی Master و Test_Cases فایل
// Air_Compressor_Price_Bank v8 (با ضرایب خود اکسل)، و سپس با تصمیم‌های کاربر (ضریب خشک‌کن ۱٫۵۳، سال KPL ۱۳۹۴/۱۰):
// ورود فایل، همه‌ی استعلام‌ها، قلم بدون قیمت خشک‌کن، شاخص BLS 333912 و روش M5 کمپرسور.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:price_bank/core/calc/compressor.dart';
import 'package:price_bank/core/calc/generic_engine.dart';
import 'package:price_bank/core/catalog/profiles.dart';
import 'package:price_bank/core/import/compressor_importer.dart';
import 'package:price_bank/core/price_bank.dart';
import 'package:price_bank/core/xlsx/xlsx_reader.dart';

import 'desalter_test.dart' show expectRel;
import 'support.dart';

const cmpPath = 'test/fixtures_private/Compressors_bank_test.xlsx';
bool get hasCmp => File(cmpPath).existsSync();

/// ضریب خشک‌کن خود اکسل (پیش از تصمیم کاربر)
const excelDryer = {'SC_DRY|Y': 1.1};

List<CompressorRecord> rawRecords(XlsxWorkbook wb) => [
      for (final r in CompressorImporter.readMaster(wb))
        CompressorRecord(
          id: r.row,
          label: '${r.values['project']} | ${r.values['tag'] ?? ''}',
          values: r.values,
          price: GenericInput(
            unitPrice: r.values['unit_price'],
            currency: r.values['currency'] as String?,
            costYear: r.values['cost_year'],
          ),
          include: r.values['include_in_totals'] != 'N',
        ),
    ];

Object? fieldOf(CompressorCalc c, String header) => switch (header) {
      'Est. Shaft Power (kW)' => c.shaftKw,
      'Standards' => c.standards,
      'Family' => c.family,
      'Unit Price EUR (source yr)' => c.eurSource,
      'Unit Price USD (source yr)' => c.usdSource,
      'Unit Price IRR (source yr)' => c.irrSource,
      'Escalated Unit Price EUR (target yr)' => c.price.eurTarget.number,
      'Escalated Unit Price USD (target yr)' => c.price.usdTarget.number,
      'Escalated Unit Price IRR (target yr)' => c.price.irrTarget.number,
      'QA Flag' => c.qaFlag,
      'TYPE_F' => c.factors.type,
      'STD_F' => c.factors.std,
      'ORIGIN_F' => c.factors.origin,
      'DRIVE_F' => c.factors.driver,
      'SCOPE_F' => c.factors.scope,
      'ALL_F' => c.factors.all,
      'Normalized EUR per compressor (base config, source yr)' => c.normEurSource,
      'Index Base' => c.indexBase,
      'Index Target' => c.indexTarget,
      'Normalized Escalated EUR per compressor' => c.normEsc,
      'Coef A (NormEsc / Flow^n)' => c.coefA,
      'Coef B (NormEsc EUR / kg)' => c.coefB,
      'Peer for fits (1/0)' => c.isPeer ? 1.0 : 0.0,
      'Fit x: Flow' => c.isPeer ? c.flow : null,
      'Fit y: NormEsc' => c.isPeer ? c.normEsc : null,
      'ln(Flow)' => c.isPeer ? math.log(c.flow!) : null,
      'ln(NormEsc)' => c.isPeer ? math.log(c.normEsc!) : null,
      _ => throw ArgumentError('ستون ناشناخته $header'),
    };

/// ورودی و خروجی مورد انتظار یک سناریوی Test_Cases (TC1..TC3)
(Map<String, Object?>, Map<String, Object?>) testCase(XlsxSheet tc, int col) {
  final inp = <String, Object?>{}, exp = <String, Object?>{};
  for (var r = 5; r <= tc.maxRow; r++) {
    final k = tc.text(r, 1);
    final kind = tc.text(r, 2);
    final v = tc.cell(r, col)?.value;
    if (kind == 'input') inp[k] = v;
    if (kind == 'expected') exp[k] = v;
  }
  return (inp, exp);
}

Map<String, Object?> estimatorValues(Map<String, Object?> i) => {
      for (final k in [
        'sub_category', 'compressor_type', 'design_standard', 'supply_origin', 'driver', 'compressors_per_price_unit',
        'unit_weight_kg',
      ])
        k: i[k],
      'flow_m3h': i['capacity_nm3h'],
      'scope_dryer': i['scope_dryer'],
      'scope_receiver': i['scope_receiver'],
      'scope_filters': i['scope_filters'],
      'scope_coolers': i['scope_coolers'],
      'scope_control_panel': i['scope_control_panel'],
      'scope_spares': i['scope_spares'],
      'scope_vendor_services': i['scope_vendor_services'],
      'scope_transport': i['scope_transport'],
    };

void main() {
  test('شاخص BLS 333912، روش M5 کمپرسور و ضرایب Factors_CMP در دیتابیس تازه', () {
    final pb = PriceBank.memory(loadSeed());
    expect(pb.seriesSnapshot.resolve('PPI_US_333912_GREG', 2013)!.value, 212.4);
    expect(pb.seriesSnapshot.resolve('PPI_US_333912_GREG', 2027), isNull);
    final s = pb.settingsRepo.load();
    expect(s.methodFor('COMPRESSOR'), 'M4');
    expect(s.catUsPpi('COMPRESSOR'), 'PPI_US_333912_GREG');
    expect(s.catUsPpi('PUMP'), 'PPI_US_333914_GREG');
    // M5 کمپرسور = BLS 333912 × نسبت یورو/دلار (همان گزینه‌ی BLS اکسل)
    final e = pb.genericEngine(categoryCode: 'COMPRESSOR', method: 'M5');
    final r = e.calculate(const GenericInput(unitPrice: 100000.0, currency: 'EUR', costYear: 1392));
    const bls1404 = 0.79 * 371.2 + 0.21 * 387.3, bls1392 = 0.79 * 212.4 + 0.21 * 217.9;
    expectRel(r.eurTarget.number, 100000 * bls1404 / bls1392 * (42000 / 36300) / (695268 / 658533), 'M5 کمپرسور');
    expectRel(e.indexAt(1404), bls1404, 'شاخص M5 ۱۴۰۴');
    final (bt, bb) = pb.compressorBls(1404);
    expectRel(bt, 374.581, 'BLS ۱۴۰۴');
    expect(bb, 212.4);
    expect(pb.compressorBls(1405).$1, isNull); // ۲۰۲۷ منتشر نشده
    final f = pb.indices.factorTable(factorSetOf('COMPRESSOR'));
    expectRel(f.get('SC_DRY', 'Y') * f.get('SC_REC', 'Y') * f.get('SC_FLT', 'Y'), 1.53, 'خشک‌کن × مخزن × فیلتر');
    expect(f.get('ORIGIN', 'Domestic'), 0.6);
    expect(f.get('TYPE', 'Screw – oil-injected'), 0.55);
    expect(f.has('LUBE', 'Oil-free'), isFalse);
    pb.close();
  });

  test('استخراج مشخصات کمپرسور از شرح MTO', () {
    const desc = 'Air Compressor Package\n'
        'Type: Reciprocating, Non-Lubricated\n'
        'Normal Flow Rate (m3/hr): 300\n'
        'Discharge Pressure (barg): 9\n'
        'Design Codes & Standards: API 618, IPS-M-PM-211';
    final d = parseMtoDescription(desc);
    final v = equipmentProfiles['COMPRESSOR']!.extract(d.specs, context: d.name, scope: d.scope);
    expect(v['compressor_type'], 'Reciprocating – non-lubricated');
    expect(v['flow_m3h'], 300);
    expect(v['discharge_pressure_barg'], 9);
    expect(v['design_standard'], 'API 618');
    expect(v['ips_standard'], 'IPS-M-PM-211');
    expect(compressorTypeOf('Screw', 'Lubricated'), 'Screw – oil-injected');
    expect(compressorFamily('Screw – oil-free'), 'Positive displacement – rotary screw');
  });

  group('بانک کمپرسور هوا v8', () {
    late XlsxWorkbook wb;
    setUpAll(() {
      if (hasCmp) wb = XlsxWorkbook.openFile(cmpPath);
    });

    CompressorBankResult excelBank(PriceBank pb) => computeCompressorBank(
          rawRecords(wb),
          engine: pb.genericEngine(categoryCode: 'COMPRESSOR'),
          factors: pb.indices.factorTable(factorSetOf('COMPRESSOR')).withOverrides(excelDryer),
          params: const CompressorParams(),
        );

    test('ستون‌های فرمولی Master برابر اکسل (ضرایب اکسل، بدون اصلاح)', () {
      final pb = PriceBank.memory(loadSeed());
      final bank = excelBank(pb);
      final ex = wb.sheet('Expected')!;
      var n = 0;
      for (var r = 2; r <= ex.maxRow; r++) {
        final c = bank.byId(r + 3 - 4)!;
        for (var col = 1; col <= ex.maxCol; col++) {
          final h = ex.text(1, col);
          if (h.isEmpty) continue;
          final want = ex.cell(r, col)?.value;
          expectRel(fieldOf(c, h), want is String && want.isEmpty ? null : want, 'ردیف ${c.record.id} $h');
          n++;
        }
      }
      expect(n, 270);
      expectRel(bank.fitted, 0.343092123792752, 'n برازش‌شده');
      expect(bank.points, 4);
      pb.close();
    }, skip: !hasCmp);

    void checkTc(CompressorEstimate e, Map<String, Object?> x) {
      expectRel(e.factors.all, x['all_f'], 'ALL_F');
      expectRel(e.shaftKw, x['shaft_kw'], 'kW');
      expectRel(e.n, x['n_used'], 'n');
      expect(e.a.peers.toDouble(), x['a_peers']);
      expectRel(e.a.coefAvg, x['a_coef_avg'], 'A avg');
      expectRel(e.a.coefMin, x['a_coef_min'], 'A min');
      expectRel(e.a.coefMax, x['a_coef_max'], 'A max');
      expect(e.a2Points.toDouble(), x['a2_points']);
      expectRel(e.a2Slope, x['a2_slope_b'], 'A2 b');
      expectRel(e.a2Fixed, x['a2_fixed_a'], 'A2 a');
      expect(e.b.peers.toDouble(), x['b_peers']);
      if (x['b_coef_avg'] is double) expectRel(e.b.coefAvg, x['b_coef_avg'], 'B avg');
      expectRel(e.referenceNormEsc, x['c_ref_normesc'], 'C ref');
      expectRel(e.sizeRatio, x['c_size_ratio'], 'C ratio');
      expectRel(e.hp, x['e_hp'], 'hp');
      expectRel(e.blsTarget, x['e_bls_target'], 'BLS');
      expect(e.warnings.map((w) => '$w; ').join(), x['warnings']);
      expectRel(e.a.eur, x['a_expected'], 'A');
      expectRel(e.eurA2, x['a2_expected'], 'A2');
      expectRel(e.b.eur, x['b_expected'], 'B');
      expectRel(e.eurC, x['c_expected'], 'C');
      expectRel(e.eurE, x['e_benchmark'], 'E');
      expectRel(e.simpleAvg, x['simple_avg'], 'ساده');
      expectRel(e.weightedAvg, x['weighted_avg'], 'وزنی');
      expectRel(e.finalEur, x['final_eur'], 'نهایی');
      expectRel(e.usd, x['final_usd'], 'دلار');
      expectRel(e.irr, x['final_irr'], 'ریال');
      expectRel(e.irrTotal, x['total_irr'], 'جمع');
    }

    for (final (col, name) in [(3, 'TC1'), (4, 'TC2'), (5, 'TC3')]) {
      test('Estimator $name برابر Test_Cases (ضرایب اکسل)', () {
        final pb = PriceBank.memory(loadSeed());
        final bank = excelBank(pb);
        final (i, x) = testCase(wb.sheet('Test_Cases')!, col);
        final engine = pb.genericEngine(categoryCode: 'COMPRESSOR');
        final (bt, bb) = pb.compressorBls(1404);
        final e = estimateCompressor(
          CompressorEstimateInput(
            values: estimatorValues(i),
            matchSubCategory: i['match_sub'] == 'Y',
            referenceId: (i['ref_row']! as double).toInt(),
            basisWeight: i['ref_basis'] == 'Weight',
            quantity: i['quantity']! as double,
          ),
          bank,
          factors: pb.indices.factorTable(factorSetOf('COMPRESSOR')).withOverrides(excelDryer),
          params: const CompressorParams(),
          eurRate: engine.eurRateTarget,
          usdRate: engine.usdRateTarget,
          blsTarget: bt,
          blsBase: bb,
        );
        checkTc(e, x);
        pb.close();
      }, skip: !hasCmp);
    }

    test('ورود فایل: سال KPL ۱۳۹۴/۱۰، همه‌ی استعلام‌ها، قلم خشک‌کن، تخمین با ضریب ۱٫۵۳', () {
      final pb = PriceBank.memory(loadSeed());
      final rep = pb.compressorImporter().run(wb, fileName: 'Air_Compressor_Price_Bank_v8.xlsx');
      expect(rep.items, 10);
      expect(rep.corrections, 1);
      expect(rep.vendors, 3);
      expect(rep.quotes, 3);
      expect(rep.quotesPriced, 1);
      expect(rep.dryerLinks, 2);
      expect(pb.compressorImporter().run(wb).alreadyImported, isTrue);

      final cat = pb.catalog.categoryByCode('COMPRESSOR')!;
      final rows = pb.computeCategory(cat.id);
      GenericRow row(String ref) => rows.firstWhere((r) => r.item.legacyRef == ref);
      final kpl = row('CMP-0001');
      expect(kpl.item.primary!.costYearValue, 1394);
      expect(kpl.item.primary!.costMonth, 10);
      expect(kpl.item.meta['cost_year']?.note, contains('۱۳۹۴/۱۰'));
      expectRel(kpl.result.eurTarget.number, 912105.6094605321, 'کوپال با سال ۱۳۹۴');
      expect(kpl.cmp!.isPeer, isFalse);
      // پازنان ۲: یک قیمت + دو بی‌پاسخ
      final quotes = row('CMP-0002').item.observations.where((o) => o.kind == 'quote').toList();
      expect(quotes.length, 3);
      expect(quotes.where((o) => o.amount != null).single.amount, 97500);
      expect(quotes.where((o) => (o.notes ?? '').contains('بدون پاسخ')).length, 2);
      // پکیج کامل با ضریب ۱٫۵۳
      expectRel(row('CMP-0010').cmp!.factors.all, 0.9 * 1.53, 'ALL_F پکیج کامل');
      expectRel(row('CMP-0010').cmp!.normEsc, 200648.02840658298, 'NormEsc پکیج کامل');
      expect(row('CMP-0010').item.remarks, contains('CMP-0010-DRY'));

      // قلم بدون قیمت در رده‌ی خشک‌کن
      final dryCat = pb.catalog.categoryByCode('AIR_DRYER')!;
      final dry = pb.items.loadCategory(dryCat.id).firstWhere((it) => it.legacyRef == 'CMP-0010-DRY');
      expect(dry.primary?.amount, isNull);
      expect(dry.include, isFalse);
      expect(dry.values['flow_m3h'], 300);
      expect(dry.remarks, contains('۱٫۵۳'));
      expect(dry.remarks, contains('620,000 USD'));
      expect(dry.remarks, contains('214,771 USD')); // خشک‌کن + مخزن + فیلتر ≈ ۳۴٫۶٪

      // تخمین با تصمیم‌های کاربر (مقادیر مرجع: پیاده‌سازی مستقل Calc_Spec)
      final bank = kpl.cmp!.bank!;
      int id(String ref) => row(ref).item.id;
      const expected = {'TC1': 192643.17114489592, 'TC2': 114107.14681729909, 'TC3': 528943.3985685896};
      for (final (col, name) in [(3, 'TC1'), (4, 'TC2'), (5, 'TC3')]) {
        final (i, _) = testCase(wb.sheet('Test_Cases')!, col);
        final e = pb.estimateCompressorPackage(
          CompressorEstimateInput(
            values: estimatorValues(i),
            matchSubCategory: i['match_sub'] == 'Y',
            referenceId: id('CMP-${(i['ref_row']! as double).toInt().toString().padLeft(4, '0')}'),
            basisWeight: i['ref_basis'] == 'Weight',
            quantity: i['quantity']! as double,
          ),
          bank,
        );
        expectRel(e.finalEur, expected[name], '$name نهایی با ضریب ۱٫۵۳');
      }
      pb.close();
    }, skip: !hasCmp);
  });
}
