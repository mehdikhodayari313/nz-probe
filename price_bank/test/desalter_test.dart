// آزمون بانک دیسالتر: موتور محاسبات در برابر شیت Test_Cases فایل Desalters_Price_Bank_v8.1.xlsx
// (۲۴۳ مقدار ستون‌های فرمولی + دو سناریوی Estimator)، ورود فایل، اصلاح سال KPL، روش تعدیل مستقل هر رده،
// شاخص ترکیبی M7، تکراری MTO و استخراج مشخصات دیسالتر از شرح MTO.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:price_bank/core/calc/desalter.dart';
import 'package:price_bank/core/calc/generic_engine.dart';
import 'package:price_bank/core/calc/methods.dart';
import 'package:price_bank/core/catalog/profiles.dart';
import 'package:price_bank/core/import/desalter_importer.dart';
import 'package:price_bank/core/price_bank.dart';
import 'package:price_bank/core/xlsx/xlsx_reader.dart';

import 'support.dart';

const desPath = 'test/fixtures_private/Desalters_bank_test.xlsx';
bool get hasDes => File(desPath).existsSync();

void expectRel(Object? actual, Object? expected, String what, {double tol = 1e-9}) {
  if (expected == null || (expected is String && expected.isEmpty)) {
    expect(actual, anyOf(isNull, ''), reason: '$what: انتظار خالی');
    return;
  }
  if (expected is double) {
    expect(actual, isA<double>(), reason: '$what: انتظار $expected، محاسبه $actual');
    final a = actual! as double;
    expect((a - expected).abs() <= tol * (expected.abs() > 1 ? expected.abs() : 1), isTrue,
        reason: '$what: انتظار $expected، محاسبه $a');
    return;
  }
  expect(actual.toString(), expected.toString(), reason: what);
}

/// رکوردهای Master بدون اصلاح (همان داده‌ی اکسل)؛ شناسه = Row
List<DesalterRecord> rawRecords(XlsxWorkbook wb) => [
      for (final r in DesalterImporter.readMaster(wb))
        DesalterRecord(
          id: r.row,
          label: '${r.values['project']} | ${r.values['tag']}',
          values: r.values,
          price: GenericInput(
            unitPrice: r.values['unit_price'],
            currency: r.values['currency'] as String?,
            costYear: r.values['cost_year'],
          ),
          include: r.values['include_in_totals'] != 'N',
        ),
    ];

Object? fieldOf(DesalterCalc c, String key) => switch (key) {
      'shell_volume_per_vessel_m3' => c.volumePerVessel,
      'total_shell_volume_m3' => c.totalVolume,
      'standards' => c.standards,
      'total_installed_kva' => c.installedKva,
      'design_demand_kva_100pct' => c.demandKva,
      'unit_price_eur_source_yr' => c.eurSource,
      'unit_price_usd_source_yr' => c.usdSource,
      'unit_price_irr_source_yr' => c.irrSource,
      'escalated_unit_price_eur_target_yr' => c.price.eurTarget.number,
      'escalated_unit_price_usd_target_yr' => c.price.usdTarget.number,
      'escalated_unit_price_irr_target_yr' => c.price.irrTarget.number,
      'qa_flag' => c.qaFlag,
      'tech_f' => c.factors.tech,
      'mat_f' => c.factors.mat,
      'nace_f' => c.factors.nace,
      'scope_f' => c.factors.scope,
      'kva_f' => c.factors.kvaF,
      'all_f' => c.factors.all,
      'stage_f' => c.factors.stage,
      'normalized_eur_base_config_source_yr' => c.normEurSource,
      'index_base' => c.indexBase,
      'index_target' => c.indexTarget,
      'normalized_escalated_eur' => c.normEsc,
      'coef_a_normesc_eur_stage_f_bpd_pow_n' => c.coefA,
      'coef_b_normesc_eur_m3_pow_n' => c.coefB,
      'ln_bpd_fit' => c.lnBpd,
      'ln_normesc_stage_f_fit_a' => c.lnNormEscStage,
      'ln_m3_fit' => c.lnM3,
      'ln_normesc_fit_b' => c.lnNormEsc,
      _ => throw ArgumentError('فیلد ناشناخته $key'),
    };

/// ورودی پیش‌فرض شیت Estimator
const estimatorValues = <String, Object?>{
  'sub_category': 'PKG-DES-2S',
  'desalting_technology': 'Electrostatic AC/DC',
  'des_material': 'CS (SA-516 Gr.70)',
  'nace': 'Y',
  'no_of_stages': '2-stage',
  'scope_transformers': 'Y',
  'scope_recycle_pumps': 'Y',
  'scope_related_piping': 'Y',
  'scope_instruments': 'Y',
  'scope_customs_transport': 'N',
  'capacity_bpd': 60000.0,
  'vessel_id_mm': 3658.0,
  'vessel_tl_mm': 16764.0,
  'vessels_per_package': 2.0,
};

void main() {
  test('شاخص ترکیبی M7 دیسالتر و سری‌های یوروستات در دیتابیس تازه', () {
    final pb = PriceBank.memory(loadSeed());
    final s = pb.settingsRepo.load();
    expect(s.methodFor('DESALTER'), 'M7');
    expect(s.methodFor('VESSEL'), 'M4');
    expect(s.catMix('DESALTER').map((p) => p.toString()).join(';'),
        'PPI_EU_C2529_GREG:0.7;PPI_EU_C2711_GREG:0.15;PPI_EU_C2813_GREG:0.15');
    expect(pb.seriesSnapshot.resolve('PPI_EU_C2529_GREG', 2025)!.value, 117.3);
    expect(pb.seriesSnapshot.resolve('PPI_EU_C2711_GREG', 2014)!.value, 95.5);
    expect(pb.seriesSnapshot.resolve('PPI_EU_C2814_GREG', 2021)!.value, 100);
    final mf = MethodFactors(pb.seriesSnapshot, ppiSeries: 'PPI_EU_C2813', fxType: 'V8', mix: s.catMix('DESALTER'));
    expectRel(mf.compositeIndex(1393), 87.2292, 'شاخص ترکیبی ۱۳۹۳');
    expectRel(mf.compositeIndex(1404), 119.088078, 'شاخص ترکیبی ۱۴۰۴');
    // سال بدون داده‌ی میلادی بعدی: null (همان قاعده‌ی بانک)
    expect(mf.compositeIndex(1406), isNull);
    // بازتوزیع وزن وقتی یک شاخص نیست؛ سخت‌گیرانه = null
    const partial = [MixPart('PPI_EU_C2529_GREG', 0.7), MixPart('NOPE_GREG', 0.3)];
    final r = MethodFactors(pb.seriesSnapshot, ppiSeries: 'x', fxType: 'V8', mix: partial);
    expectRel(r.compositeIndex(1393), 0.79 * 84.6 + 0.21 * 84.5, 'بازتوزیع وزن');
    expect(MethodFactors(pb.seriesSnapshot, ppiSeries: 'x', fxType: 'V8', mix: partial, mixStrict: true).compositeIndex(1393),
        isNull);
    // روش پمپ‌ها روی دیسالتر اثر ندارد
    pb.settingsRepo.set('escalation_method', 'M2');
    expect(pb.genericEngine(categoryCode: 'DESALTER').settings.method, 'M7');
    expect(pb.genericEngine(categoryCode: 'VESSEL').settings.method, 'M4');
    expect(pb.methodCodesFor('DESALTER'), contains('M7'));
    expect(pb.methodCodesFor('VESSEL'), isNot(contains('M7')));
    // ضرایب دیسالتر همان Factors_DES
    final f = pb.indices.factorTable(factorSetOf('DESALTER'));
    expect(f.get('SC_TRF', 'N'), 0.88);
    expect(f.get('STAGE', '1-stage'), 0.6);
    expect(f.get('PRESS', '10–20'), 1.0); // ضریب فشار در روش دیسالتر نیست
    pb.close();
  });

  test('استخراج مشخصات دیسالتر از شرح MTO', () {
    const desc = 'Desalting Package\n'
        'Type: Electrostatic - AC / DC\n'
        'Including 1st & 2nd Stage Desalters\n'
        '(W/ 3 x 50% Transformer), Recycle Pumps, Related Piping, Instruments, etc.\n'
        'Vessels Dim. (ID x TL-TL): 4267x30480 mm\n'
        'Vessels Design Pressure: 20.3 Barg\n'
        'Vessels Mat. (Shell/Heads): SA 516 Gr. 70\n'
        'Design Codes & Standards: ASME VIII, DIV.1 & IPS-G-ME-150';
    final d = parseMtoDescription(desc);
    final v = equipmentProfiles['DESALTER']!.extract(d.specs, context: d.name, scope: d.scope);
    expect(v['desalting_technology'], 'Electrostatic AC/DC');
    expect(v['no_of_stages'], '2-stage');
    expect(v['n_transformers'], 3);
    expect(v['transformer_sizing'], 0.5);
    expect(v['scope_transformers'], 'Y');
    expect(v['scope_recycle_pumps'], 'Y');
    expect(v['scope_related_piping'], 'Y');
    expect(v['scope_instruments'], 'Y');
    expect(v['des_material'], 'CS (SA-516 Gr.70)');
    expect(v['vessel_design_code'], 'ASME VIII Div.1');
    expect(v['ips_standard'], 'IPS-G-ME-150');
    expect(v['vessel_id_mm'], 4267);
    expect(v['vessel_tl_mm'], 30480);
    expect(v['design_pressure_barg'], 20.3);
    // حجم پوسته فقط با تعداد وسل
    expect(desalterShellVolume(v), isNull);
    expectRel(desalterShellVolume({...v, 'vessels_per_package': 2.0}), 871.726252950199, 'حجم کل');
  });

  group('بانک دیسالتر v8.1', () {
    late XlsxWorkbook wb;
    setUpAll(() {
      if (hasDes) wb = XlsxWorkbook.openFile(desPath);
    });

    test('ستون‌های فرمولی Master برابر Test_Cases (بدون اصلاح)', () {
      final pb = PriceBank.memory(loadSeed());
      final bank = computeDesalterBank(
        rawRecords(wb),
        engine: pb.genericEngine(categoryCode: 'DESALTER'),
        factors: pb.indices.factorTable(factorSetOf('DESALTER')),
        params: const DesalterParams(),
      );
      final tc = wb.sheet('Test_Cases')!;
      var n = 0;
      for (var r = 5; r <= tc.maxRow; r++) {
        final id = tc.text(r, 1);
        if (!id.startsWith('DES-')) continue;
        final c = bank.byId(int.parse(id.substring(4)))!;
        final key = tc.text(r, 2);
        expectRel(fieldOf(c, key), tc.cell(r, 3)?.value, '$id $key');
        n++;
      }
      expect(n, 261);
      expect(bank.fittedA, isNull); // کمتر از ۳ نقطه
      expect(bank.pointsB, 6);
      pb.close();
    }, skip: !hasDes);

    Map<String, Object?> scenario(XlsxSheet tc, String name) => {
          for (var r = 5; r <= tc.maxRow; r++)
            if (tc.text(r, 5) == name && tc.text(r, 6) == 'output') tc.text(r, 8): tc.cell(r, 9)?.value,
        };

    void checkEstimate(DesalterEstimate e, Map<String, Object?> x) {
      expectRel(e.factors.all, x['ALL_F (new)'], 'ALL_F');
      expectRel(e.factors.stage, x['STAGE_F (new)'], 'STAGE_F');
      expectRel(e.volume, x['Total shell volume new (m³)'], 'حجم');
      expect(e.a.peers.toDouble(), x['A – peers (n)']);
      expectRel(e.a.coefAvg, x['A – Coef average'], 'A avg');
      expectRel(e.a.coefMin, x['A – Coef min'], 'A min');
      expectRel(e.a.coefMax, x['A – Coef max'], 'A max');
      expect(e.b.peers.toDouble(), x['B – peers (n)']);
      expectRel(e.b.coefAvg, x['B – Coef average'], 'B avg');
      expectRel(e.b.coefMin, x['B – Coef min'], 'B min');
      expectRel(e.b.coefMax, x['B – Coef max'], 'B max');
      expect(e.reference!.record.label, x['C – reference record']);
      expectRel(e.referenceNormEsc, x['C – reference NormEsc EUR'], 'C ref');
      expectRel(e.sizeRatio, x['C – size ratio'], 'C ratio');
      expect(e.warnings.map((w) => '$w; ').join(), x['Warnings']);
      expectRel(e.a.eur, x['A – Unit price EUR expected'], 'A');
      expectRel(e.b.eur, x['B – Unit price EUR expected'], 'B');
      expectRel(e.eurC, x['C – Unit price EUR'], 'C');
      expectRel(e.simpleAvg, x['Simple average of methods (EUR)'], 'ساده');
      expectRel(e.weightedAvg, x['Weighted average (by peer count)'], 'وزنی');
      expectRel(e.finalEur, x['FINAL unit price EUR'], 'نهایی');
      expectRel(e.usd, x['Unit price USD (final)'], 'دلار');
      expectRel(e.irr, x['Unit price IRR (final)'], 'ریال');
      expectRel(e.irrTotal, x['Total IRR (× quantity)'], 'جمع');
    }

    test('Estimator: سناریوی پیش‌فرض', () {
      final pb = PriceBank.memory(loadSeed());
      final engine = pb.genericEngine(categoryCode: 'DESALTER');
      const p = DesalterParams();
      final factors = pb.indices.factorTable(factorSetOf('DESALTER'));
      final bank = computeDesalterBank(rawRecords(wb), engine: engine, factors: factors, params: p);
      final e = estimateDesalter(const DesalterEstimateInput(values: estimatorValues, referenceId: 2), bank,
          factors: factors, params: p, eurRate: engine.eurRateTarget, usdRate: engine.usdRateTarget);
      checkEstimate(e, scenario(wb.sheet('Test_Cases')!, 'default'));
      pb.close();
    }, skip: !hasDes);

    test('Estimator: سناریوی kVA فعال + n_B برازش‌شده + سال هدف ۱۴۰۵', () {
      final pb = PriceBank.memory(loadSeed());
      final engine = pb.genericEngine(categoryCode: 'DESALTER', targetYear: 1405);
      const p = DesalterParams(kvaActive: true, useFittedB: true);
      final factors = pb.indices.factorTable(factorSetOf('DESALTER'));
      final bank = computeDesalterBank(rawRecords(wb), engine: engine, factors: factors, params: p);
      expectRel(bank.nB, 0.2987279004978158, 'n_B برازش‌شده');
      final e = estimateDesalter(const DesalterEstimateInput(values: estimatorValues, referenceId: 2, demandKva: 800), bank,
          factors: factors, params: p, eurRate: engine.eurRateTarget, usdRate: engine.usdRateTarget);
      expectRel(e.factors.kvaF, 0.935248447822621, 'KVA_F');
      checkEstimate(e, scenario(wb.sheet('Test_Cases')!, 'kva_on_fitB_1405'));
      pb.close();
    }, skip: !hasDes);

    test('ورود فایل: اصلاح سال KPL، استعلام‌ها، بایگانی تکراری MTO، جلوگیری از ورود دوباره', () {
      final pb = PriceBank.memory(loadSeed());
      final cat = pb.catalog.categoryByCode('DESALTER')!;
      // دیسالتری که قبلاً از MTO کوپال وارد شده بود (همان تگ و قیمت)
      final mtoId = pb.items.create(categoryId: cat.id, values: {
        'tag': 'PK-111',
        'name': 'Desalting Package',
        'currency': 'EUR',
        'unit_price': 3500000.0,
        'cost_year': 1394.0,
      });
      final other = pb.items.create(categoryId: cat.id, values: {
        'tag': 'PK-111',
        'name': 'Other desalter',
        'currency': 'EUR',
        'unit_price': 1234567.0,
        'cost_year': 1400.0,
      });
      final rep = pb.desalterImporter().run(wb, fileName: 'Desalters_Price_Bank_v8.1.xlsx');
      expect(rep.items, 9);
      expect(rep.corrections, 2);
      expect(rep.vendors, 11);
      expect(rep.quotes, greaterThanOrEqualTo(3));
      expect(rep.archivedDuplicates, 1);
      expect(pb.items.get(mtoId)!.status, 'archived');
      expect(pb.items.get(other)!.status, 'active');
      expect(pb.desalterImporter().run(wb).alreadyImported, isTrue);

      final rows = pb.computeCategory(cat.id);
      GenericRow row(String ref) => rows.firstWhere((r) => r.item.legacyRef == ref);
      final kpl = row('DES-0001');
      expect(kpl.item.primary!.costYearValue, 1394);
      expect(kpl.item.primary!.costMonth, 10);
      expect(kpl.item.meta['cost_year']?.note, contains('۱۳۹۴/۱۰'));
      // مقادیر مرجع با سال ۱۳۹۴ (پیاده‌سازی مستقل Calc_Spec)
      expectRel(kpl.des!.indexBase, 87.1967, 'شاخص ۱۳۹۴');
      expectRel(kpl.result.eurTarget.number, 4780092.285602551, 'KPL آسماری یورو');
      expectRel(kpl.result.irrTarget.number, 3323445203226.3145, 'KPL آسماری ریال');
      expectRel(kpl.des!.usdSource, 3833830.1043219077, 'KPL دلار منبع');
      expectRel(row('DES-0002').des!.coefB, 107017.70100837915, 'KPL بنگستان Coef B');
      // سایر رکوردها بدون تغییر = Test_Cases
      expectRel(row('DES-0005').result.eurTarget.number, 3553938.97458788, 'گچساران', tol: 1e-9);
      expectRel(row('DES-0003').des!.coefB, 82678.2095016601, 'پازنان ۱۴۰۴', tol: 1e-9);
      expect(row('DES-0007').item.include, isFalse);
      expect(row('DES-0009').item.include, isFalse);
      expect(row('DES-0003').item.observations.where((o) => o.kind == 'quote').length, greaterThanOrEqualTo(2));
      expect(row('DES-0001').item.values['desalting_technology'], 'Electrostatic AC/DC');
      expect(row('DES-0005').item.values['capacity_bpd'], 80912);

      final bank = rows.first.des!.bank!;
      final e = pb.estimateDesalterPackage(
          DesalterEstimateInput(values: estimatorValues, referenceId: row('DES-0002').item.id), bank);
      expectRel(e.finalEur, 3268642.994507901, 'تخمین نهایی با سال KPL اصلاح‌شده');

      // MTO بعدی: همان دیسالتر بانک تکراری است
      expect(findDesalterBankDuplicate(pb.db, cat.id, 'PK-121', [2500000.0]), isNotNull);
      expect(findDesalterBankDuplicate(pb.db, cat.id, 'PK-121', [999.0]), isNull);
      expect(findDesalterBankDuplicate(pb.db, cat.id, 'PK-999', [2500000.0]), isNull);
      pb.close();
    }, skip: !hasDes);
  });
}
