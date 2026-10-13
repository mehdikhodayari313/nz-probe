// آزمون زنجیره‌ی کامل: دیتابیس ← داده‌های پایه ← انتقال v8 ← محاسبه ← ویرایش با تاریخچه.

import 'package:flutter_test/flutter_test.dart';
import 'package:price_bank/core/calc/series.dart';
import 'package:price_bank/core/import/v8_importer.dart';
import 'package:price_bank/core/price_bank.dart';
import 'package:price_bank/core/xlsx/xlsx_reader.dart';

import 'support.dart';

void main() {
  test('دیتابیس تازه: ساختار و داده‌های پایه', () {
    final pb = PriceBank.memory(loadSeed());
    expect(pb.db.schemaVersion, greaterThanOrEqualTo(1));
    expect(pb.catalog.fields(pb.pumpCategory.id).length, 59);
    expect(pb.catalog.options('MAT').map((o) => o.value), contains('D-2'));
    expect(pb.users.all().single.role, 'admin');
    expect(pb.catalog.disciplines().map((d) => d.code).toList(), ['MECH', 'PIPE', 'ELEC', 'INST']);
    expect(pb.indices.series().length, greaterThanOrEqualTo(20));
    expect(pb.seriesSnapshot.resolve('PPI_EU_C2813', 1393)!.value, 91.347);
    expect(pb.seriesSnapshot.resolve('FX_EUR_V8', 1404)!.value, 695268);
    expect(pb.settingsRepo.load().targetYear, 1404);
    // باز کردن دوباره نباید داده‌ی پایه را تکرار کند
    expect(pb.factorTable.get('MAT', 'D-2'), 1.9);
    pb.close();
  });

  group('انتقال v8 و محاسبه', () {
    if (!hasFixtures) {
      test('فایل مرجع نیست', () {}, skip: true);
      return;
    }
    late PriceBank pb;
    late XlsxWorkbook v8;
    setUpAll(() {
      pb = PriceBank.memory(loadSeed());
      v8 = XlsxWorkbook.openFile(v8Path);
    });
    tearDownAll(() => pb.close());

    test('انتقال: ۱۴۶ پمپ، پروژه‌ها، اسناد، برچسب‌های استنباطی', () {
      final rep = pb.v8Importer().run(v8, fileName: 'v8');
      expect(rep.alreadyImported, isFalse);
      expect(rep.items, 146);
      expect(rep.projects, greaterThanOrEqualTo(5));
      expect(rep.documents, 6); // پازنان ۲، KPL (اسمری و بنگستان)، گچساران ۴، دو CSV
      expect(rep.inferredFlags, greaterThan(100));
      expect(rep.notes, greaterThan(500));
      // ورود دوباره ممکن نیست
      expect(pb.v8Importer().run(v8).alreadyImported, isTrue);
      expect(pb.items.count(pb.pumpCategory.id), 146);
    });

    test('محاسبه از دیتابیس = عددهای اکسل (یورو و ریال تعدیل‌شده و ضریب هزینه)', () {
      final md = v8.sheet('Master Database')!;
      final byRow = <int, int>{};
      for (var r = 5; r <= md.maxRow; r++) {
        final n = md.cell(r, 1)?.number;
        if (n != null) byRow[n.toInt()] = r;
      }
      final diffs = <String>[];
      for (final row in pb.computePumps()) {
        final r = byRow[int.parse(row.item.legacyRef!)]!;
        for (final (col, cell) in [
          ('AB', row.result.eurSource),
          ('AG', row.result.eurTarget),
          ('AI', row.result.irrTarget),
          ('BD', row.result.costCoef),
        ]) {
          final d = compareCell(cell, md.cell(r, columnIndex(col)));
          if (d != null) diffs.add('ردیف $r $col: $d');
        }
      }
      expectNoDiffs(diffs);
    });

    test('ویرایش قلم: تاریخچه ثبت و محاسبه به‌روز می‌شود', () {
      final rows = pb.computePumps();
      final target = rows.firstWhere((r) => r.result.eurTarget.isNumber && r.item.primary?.currency == 'EUR');
      final before = target.result.eurTarget.number!;
      final oldYear = target.item.primary!.costYear!;
      final n = pb.items.update(target.item.id, {'cost_year': oldYear - 1}, reason: 'آزمون');
      expect(n, 1);
      final hist = pb.audit.history('item', target.item.id);
      expect(hist.first.field, 'cost_year');
      expect(hist.first.reason, 'آزمون');
      final after = pb.pumpEngine().calculate(PriceBank.inputFor(pb.items.get(target.item.id)!));
      expect(after.eurTarget.number, isNot(before));
      // تغییر بدون اختلاف، ثبت نمی‌شود
      expect(pb.items.update(target.item.id, {'cost_year': oldYear - 1}), 0);
    });

    test('نرخ تسعیر سند روی همه‌ی اقلام ریالی همان سند اثر می‌گذارد', () {
      final rows = pb.computePumps();
      final irr = rows.where((r) => r.item.primary?.currency == 'IRR' && r.item.primary?.documentId != null && r.item.primary?.amount != null).toList();
      if (irr.isEmpty) return;
      final docId = irr.first.item.primary!.documentId!;
      pb.docs.updateDocument(docId, {'source_fx_eur': 40530.8}, reason: 'نرخ تسعیر منبع');
      final again = pb.computePumps().firstWhere((r) => r.item.id == irr.first.item.id);
      final o = again.item.primary!;
      expect(again.result.eurSource.number, closeTo(o.amount! / 40530.8, 1e-6));
    });

    test('شاخص‌ها: ویرایش، ورود گروهی و جستجوی ماه ← فصل ← سال', () {
      pb.indices.upsert('FX_EUR_NIMA', Period.year(1404), 700000);
      final (n, bad) = pb.indices.importText('FX_EUR_NIMA', '1404Q2\t720000\n1404-05 730000\nبی‌معنی\n۱۴۰۵\t۹۰۰٬۰۰۰');
      expect(n, 3);
      expect(bad.length, 1);
      pb.invalidateCalc();
      final s = pb.seriesSnapshot;
      expect(s.resolve('FX_EUR_NIMA', 1404, month: 5)!.value, 730000);
      expect(s.resolve('FX_EUR_NIMA', 1404, month: 4)!.value, 720000);
      expect(s.resolve('FX_EUR_NIMA', 1404, month: 1)!.value, 700000);
      expect(s.resolve('FX_EUR_NIMA', 1405)!.value, 900000);
    });

    test('تفکیک عنوان سند از محل داخل سند', () {
      expect(V8Importer.splitSourceDocument("File PC-ME 14040105 Pazanan2 Reconstruction.xlsx, sheet 'PUMPS', spec B10"),
          ('PC-ME 14040105 Pazanan2 Reconstruction.xlsx', "sheet 'PUMPS', spec B10"));
      expect(V8Importer.splitSourceDocument('18061405_Pump_only_CSV.csv – section Pumps (row 1)'),
          ('18061405_Pump_only_CSV.csv', 'section Pumps (row 1)'));
      expect(V8Importer.splitSourceDocument('Datasheet only'), ('Datasheet only', null));
    });

    test('بایگانی و بازگرداندن قلم', () {
      final id = pb.computePumps().first.item.id;
      pb.items.archive(id, archived: true);
      expect(pb.items.count(pb.pumpCategory.id), 145);
      pb.items.archive(id, archived: false);
      expect(pb.items.count(pb.pumpCategory.id), 146);
    });
  });
}
