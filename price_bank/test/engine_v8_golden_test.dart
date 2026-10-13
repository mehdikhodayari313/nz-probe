// آزمون طلایی: موتور محاسبات برنامه باید برای هر ۱۴۶ رکورد فایل v8 و برای تخمین‌گر و
// ماشین‌حساب M6 دقیقاً همان عددهایی را بدهد که در خود اکسل‌ها ذخیره شده است.

import 'package:flutter_test/flutter_test.dart';
import 'package:price_bank/core/calc/estimator.dart';
import 'package:price_bank/core/calc/pump_engine.dart';
import 'package:price_bank/core/calc/series.dart';
import 'package:price_bank/core/xlsx/xlsx_reader.dart';

import 'support.dart';

/// ساخت محیط محاسبه از روی خود فایل v8 (نه از داده‌های پایه‌ی برنامه).
(PumpEngine, XlsxSheet) v8Engine(XlsxWorkbook wb) {
  final series = MemorySeries();
  final fx = wb.sheet('Assumptions & FX Reference')!;
  for (var r = 5; r <= 25; r++) {
    final y = fx.cell(r, 1)?.number?.toInt();
    if (y == null) continue;
    final usd = fx.cell(r, 2)?.number, eur = fx.cell(r, 3)?.number;
    if (usd != null) series.put('FX_USD_V8', Period.year(y), usd);
    if (eur != null) series.put('FX_EUR_V8', Period.year(y), eur);
  }
  final esc = wb.sheet('Escalation_Index')!;
  for (var r = 5; r <= 25; r++) {
    final y = esc.cell(r, 1)?.number?.toInt();
    final v = esc.cell(r, 2)?.number;
    if (y != null && v != null) series.put('PPI_EU_C2813', Period.year(y), v);
  }
  final fr = wb.sheet('Factors_ROT')!;
  final factors = <String, double>{};
  for (var r = 5; r <= fr.maxRow; r++) {
    final key = fr.cell(r, 1)?.value;
    final used = fr.cell(r, 6)?.number;
    if (key is String && used != null) factors[key] = used;
  }
  final settings = PumpCalcSettings(
    targetYear: fx.at('I5')!.number!.toInt(),
    fxType: 'V8',
    ppiSeries: 'PPI_EU_C2813',
    floorEur: fx.at('I13')!.number!,
    floorBaseYear: fx.at('I14')!.number!.toInt(),
    costExponent: fx.at('I16')!.number!,
    pumpEfficiency: fx.at('I17')!.number!,
    eurTargetOverride: fx.at('I7')?.number,
    usdTargetOverride: fx.at('I10')?.number,
  );
  return (PumpEngine(series, settings, FactorTable(factors)), wb.sheet('Master Database')!);
}

/// مشخصات یک ردیف Master بر اساس قالب (کلید فیلد → ستون v8).
PumpInput rowInput(XlsxSheet md, int r, Map<String, String> specCols) {
  Object? val(String col) {
    final c = md.cell(r, columnIndex(col));
    if (c == null) return null;
    final v = c.value;
    return v is double ? v : asText(v);
  }

  return PumpInput(
    spec: {for (final e in specCols.entries) e.key: val(e.value)},
    unitPrice: val('AA'),
    currency: val('Z') as String?,
    costYear: val('Y'),
  );
}

void main() {
  if (!hasFixtures) {
    test('فایل‌های مرجع موجود نیست', () {}, skip: 'test/fixtures_private خالی است');
    return;
  }

  final tpl = loadJson('pump_template.json');
  final specCols = <String, String>{
    for (final f in (tpl['fields'] as List).cast<Map<String, dynamic>>())
      if (f['storage'] == 'spec') f['key'] as String: f['v8_column'] as String,
  };

  late XlsxWorkbook v8;
  late PumpEngine engine;
  late XlsxSheet md;
  setUpAll(() {
    v8 = XlsxWorkbook.openFile(v8Path);
    final e = v8Engine(v8);
    engine = e.$1;
    md = e.$2;
  });

  test('هر ۱۴۶ رکورد v8: همه‌ی ستون‌های محاسباتی برابر اکسل', () {
    final diffs = <String>[];
    var rows = 0;
    for (var r = 5; r <= md.maxRow; r++) {
      if (md.cell(r, 1)?.number == null) continue;
      rows++;
      final res = engine.calculate(rowInput(md, r, specCols));
      void chk(String col, String? d) {
        if (d != null) diffs.add('ردیف $r ستون $col: $d');
      }

      XlsxCell? c(String col) => md.cell(r, columnIndex(col));
      chk('K', compareCell(res.sizeKw, c('K')));
      chk('L', compareCell(CalcCell.text(res.standards), c('L')));
      chk('AB', compareCell(res.eurSource, c('AB')));
      chk('AC', compareCell(res.usdSource, c('AC')));
      chk('AD', compareCell(res.irrSource, c('AD')));
      chk('AG', compareCell(res.eurTarget, c('AG')));
      chk('AH', compareCell(res.usdTarget, c('AH')));
      chk('AI', compareCell(res.irrTarget, c('AI')));
      chk('AS', compareCell(res.qaFlags.isEmpty ? const CalcCell.blank() : CalcCell.text(res.qaFlags), c('AS')));
      chk('AT', compareNum(res.matF, c('AT')));
      chk('AU', compareNum(res.sealF, c('AU')));
      chk('AV', compareNum(res.driveF, c('AV')));
      chk('AW', compareNum(res.scopeF, c('AW')));
      chk('AX', compareNum(res.allF, c('AX')));
      chk('AY', compareCell(res.normalizedEur, c('AY')));
      chk('AZ', compareCell(res.ppiBase, c('AZ')));
      chk('BA', compareCell(res.ppiTarget, c('BA')));
      chk('BB', compareCell(CalcCell.text(res.floorApplies ? 'Y' : 'N'), c('BB')));
      chk('BC', compareCell(res.normalizedEscalatedEur, c('BC')));
      chk('BD', compareCell(res.costCoef, c('BD')));
    }
    expect(rows, 146);
    expectNoDiffs(diffs);
  });

  test('تخمین‌گر v8: نتیجه برابر شیت Estimator', () {
    final est = v8.sheet('Estimator')!;
    String b(int r) => asText(est.cell(r, 2)?.value);
    double? bn(int r) => est.cell(r, 2)?.number;

    final peers = <PeerRecord>[];
    for (var r = 5; r <= md.maxRow; r++) {
      if (md.cell(r, 1)?.number == null) continue;
      final res = engine.calculate(rowInput(md, r, specCols));
      peers.add(PeerRecord(
        itemId: r,
        subCategory: md.text(r, columnIndex('E')),
        family: md.text(r, columnIndex('V')),
        standard: md.text(r, columnIndex('M')),
        include: md.text(r, columnIndex('BG')) == 'Y',
        costCoef: res.costCoef.number,
      ));
    }
    final inp = EstimatorInput(
      subCategory: b(5),
      matchSubCategory: b(6) == 'Y',
      standard: b(7),
      family: b(8),
      spec: {
        'material_class': b(10),
        'seal_arrangement': b(11),
        'api682_category': b(12),
        'api682_plan': b(13),
        'driver_type': b(14),
        'nace': b(15),
        'scope_driver': b(16),
        'scope_baseplate': b(17),
        'scope_seal_support': b(18),
        'scope_comm_spares': b(19),
        'scope_2yr_spares': b(20),
        'scope_tpi': b(21),
        'scope_fat': b(22),
      },
      powerKw: bn(23),
      capacity: bn(24),
      head: bn(25),
      quantity: bn(26) ?? 1,
    );
    final r = PumpEstimator(engine).estimate(inp, peers);
    XlsxCell? f(int row) => est.cell(row, 6);
    final diffs = <String>[
      for (final (row, v) in <(int, double?)>[
        (5, r.sizeKw), (10, r.allF), (11, r.peerCount.toDouble()), (12, r.coefAvg), (13, r.coefMin),
        (14, r.coefMax), (16, r.floorEur), (18, r.eurExpected), (19, r.eurLow), (20, r.eurHigh),
        (21, r.usdExpected), (22, r.irrExpected), (23, r.irrTotal),
      ])
        if (compareNum(v, f(row)) case final d?) 'F$row: $d',
      if (f(15)?.text != (r.floorApplies ? 'Y' : 'N')) 'F15: کف قیمت',
    ];
    expectNoDiffs(diffs);
  });

  group('ماشین‌حساب M6 (فایل صحت‌سنجی)', () {
    late XlsxWorkbook val;
    late PumpEngine m6;
    setUpAll(() {
      val = XlsxWorkbook.openFile(validationPath);
      final ind = val.sheet('Indices')!;
      final series = MemorySeries();
      for (var r = 51; r <= 71; r++) {
        final y = ind.cell(r, 1)!.number!.toInt();
        series.put('PPI_EU_C2813', Period.year(y), ind.cell(r, 3)!.number!);
        series.put('FX_USD_FREE', Period.year(y), ind.cell(r, 4)!.number!);
        series.put('FX_EUR_FREE', Period.year(y), ind.cell(r, 7)!.number!);
      }
      final calc = val.sheet('ماشین_حساب')!;
      m6 = PumpEngine(
        series,
        PumpCalcSettings(
          targetYear: calc.at('D12')!.number!.toInt(),
          fxType: 'FREE',
          floorEur: val.sheet('Val_EUR_Pumps')!.at('E16')!.number!,
          floorBaseYear: 1404,
          eurTargetOverride: calc.at('D13')?.number,
        ),
        FactorTable(const {}),
      );
    });

    FloorMode mode(String s) => s == 'بله' ? FloorMode.yes : (s == 'خیر' ? FloorMode.no : FloorMode.auto);

    test('محاسبه‌ی گام‌به‌گام تک‌قلم', () {
      final c = val.sheet('ماشین_حساب')!;
      final r = PriceTransferCalculator(m6).run(TransferInput(
        basePrice: c.at('D8')!.number!,
        currency: c.at('D9')!.text,
        baseYear: c.at('D10')!.number!.toInt(),
        sourceFxRate: c.at('D11')?.number,
        isApiCentrifugal: c.at('D6')!.text == 'گریز از مرکز API 610',
        materialClass: c.at('D7')!.text,
        quantity: c.at('D14')!.number!,
        customsPercent: c.at('D15')?.number ?? 0,
        floorMode: mode(c.at('D16')!.text),
      ));
      final diffs = <String>[
        for (final (cell, v) in <(String, double?)>[
          ('D20', r.toEurRate), ('D21', r.baseEur), ('D22', r.ppiBase), ('D23', r.ppiTarget), ('D24', r.ppiFactor),
          ('D25', r.escalatedEur), ('D27', r.floorEur), ('D28', r.finalEurUnit), ('D29', r.eurRate),
          ('D30', r.irrUnitNoCustoms), ('D31', r.customsIrrUnit), ('D34', r.irrUnit), ('D35', r.irrTotal),
          ('D37', r.eurTotal), ('D38', r.usdTotal),
        ])
          if (compareNum(v, c.at(cell)) case final d?) '$cell: $d',
      ];
      expectNoDiffs(diffs);
    });

    test('جدول چندقلمی (KPL یورویی، گچساران ریالی با نرخ منبع، پازنان ریالی)', () {
      final c = val.sheet('ماشین_حساب')!;
      final diffs = <String>[];
      for (var row = 45; row <= 64; row++) {
        final price = c.cell(row, 5)?.number;
        if (price == null) continue;
        final r = PriceTransferCalculator(m6).run(TransferInput(
          basePrice: price,
          currency: c.text(row, 6),
          baseYear: c.cell(row, 7)!.number!.toInt(),
          sourceFxRate: c.cell(row, 8)?.number,
          isApiCentrifugal: c.text(row, 3) == 'گریز از مرکز API 610',
          materialClass: c.text(row, 4),
          quantity: c.cell(row, 9)?.number ?? 1,
          customsPercent: c.at('D15')?.number ?? 0,
          floorMode: mode(c.text(row, 10)),
        ));
        for (final (col, v) in <(int, double?)>[
          (11, r.baseEur), (12, r.ppiFactor), (13, r.finalEurUnit), (14, r.irrUnit), (15, r.irrTotal),
        ]) {
          final d = compareNum(v, c.cell(row, col));
          if (d != null) diffs.add('${columnName(col)}$row: $d');
        }
      }
      expectNoDiffs(diffs);
    });
  });
}
