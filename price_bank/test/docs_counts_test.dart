// بند ۲۰: حذف سند منبع، یکی شدن سند تکراری، شمارش درست اسناد؛ بند 2f: جمع گزینه‌های هر فیلتر = «همه».

import 'package:flutter_test/flutter_test.dart';
import 'package:price_bank/core/catalog/profiles.dart';
import 'package:price_bank/core/import/mto_importer.dart';
import 'package:price_bank/core/price_bank.dart';
import 'package:price_bank/core/repo/docs_repo.dart';
import 'package:price_bank/core/xlsx/xlsx_reader.dart';
import 'package:price_bank/ui/widgets/common.dart';

import 'support.dart';

void main() {
  test('یک سند با عنوان‌های کمی متفاوت', () {
    expect(DocsRepo.sameTitle('PEP-Rev 140205 Gachsaran 4.xlsx', 'PEP-Rev.140205 Gachsaran 4'), isTrue);
    expect(DocsRepo.sameTitle('PC-ME 14040105 Pazanan2', 'PC-ME 14040105 Pazanan2 Reconstruction.xlsx'), isTrue);
    expect(DocsRepo.sameTitle('91215-KPL-ME-RE-476 R03', '91215-KPL-ME-RE-476 R02'), isFalse);
    expect(DocsRepo.sameTitle('Pump list', 'Pump list 2'), isFalse); // عنوان کوتاه بدون شماره‌ی سند
  });

  test('ثبت سند تکراری یکی می‌شود؛ ادغام دیتابیس قبلی؛ شمارش بدون سند کمکی و تکرار در پروژه‌ها', () {
    final pb = PriceBank.memory(loadSeed());
    final p1 = pb.docs.ensureProject('Koopal Asmari'), p2 = pb.docs.ensureProject('Koopal Bangestan');
    final a = pb.docs.ensureDocument(projectId: p1, title: 'PEP-Rev.140205 Gachsaran 4');
    expect(pb.docs.ensureDocument(projectId: p1, title: 'PEP-Rev 140205 Gachsaran 4.xlsx'), a);
    pb.docs.ensureDocument(projectId: p1, title: '91215-KPL-ME-RE-476 R03');
    pb.docs.ensureDocument(projectId: p2, title: '91215-KPL-ME-RE-476 R03'); // همان سند در پروژه‌ی دیگر
    pb.docs.ensureDocument(projectId: p1, title: '91215-KPL-ME-RE-476 R03 — قیمت‌های بازنگری قبلی', docType: 'mto_previous');
    expect(pb.docs.documents().length, 4);
    expect(pb.docs.sourceDocumentCount(), 2);
    // دیتابیس قبلی که تکراری‌ها را جدا ثبت کرده بود
    pb.db.execute("INSERT INTO documents(project_id, title, revision) VALUES (?, 'PC-ME 14040105 Pazanan2', '')", [p2]);
    pb.db.execute("INSERT INTO documents(project_id, title, revision) VALUES (?, 'PC-ME 14040105 Pazanan2 Reconstruction.xlsx', '')", [p2]);
    expect(pb.docs.mergeDuplicateDocuments(), 1);
    expect(pb.docs.sourceDocumentCount(), 3);
    pb.close();
  });

  test('حذف سند: قیمت‌های آن و سند کمکی حذف؛ قلم بی‌قیمت حذف، قلم با قیمت دیگر می‌ماند؛ ورود دوباره ممکن', () {
    final pb = PriceBank.memory(loadSeed());
    const f = 'MTO_sample_14040105.xlsx';
    MtoAnalysis analyze() => MtoImporter.analyze(XlsxWorkbook.openFile('test/fixtures/$f'), fileName: f);
    final rep = pb.mtoImporter().run(analyze(), projectName: 'Sample', oldFx: null);
    expect(rep.items, greaterThan(10));
    final doc = pb.docs.documents().firstWhere((d) => !DocsRepo.isAuxiliary(d));
    final keep = pb.db.scalar('SELECT item_id FROM price_obs WHERE document_id = ? LIMIT 1', [doc.id]) as int;
    pb.items.addObservation(keep, kind: 'quote', currency: 'EUR', amount: 1000.0, costYear: 1404);
    final res = pb.docs.deleteDocument(doc.id, reason: 'آزمون');
    expect(res.documents, 2); // سند اصلی + «قیمت‌های بازنگری قبلی»
    expect(res.items, rep.items - 1);
    expect(pb.items.get(keep), isNotNull);
    expect(pb.docs.documents(), isEmpty);
    // همان فایل دوباره وارد می‌شود
    expect(pb.mtoImporter().run(analyze(), projectName: 'Sample', oldFx: null).items, greaterThan(10));
    pb.close();
  });

  test('2f: در هر رده و هر فیلتر، جمع گزینه‌ها و «خالی» برابر «همه» است', () {
    final pb = PriceBank.memory(loadSeed());
    for (final f in ['PEP-Rev.140205_Sample_4.xlsx', 'Estimate_sample_K.xlsx']) {
      pb.mtoImporter().run(MtoImporter.analyze(XlsxWorkbook.openFile('test/fixtures/$f'), fileName: f),
          projectName: f, oldFx: null);
    }
    var checked = 0;
    for (final e in equipmentProfiles.entries) {
      final cat = pb.catalog.categoryByCode(e.key);
      if (cat == null) continue;
      final rows = pb.computeCategory(cat.id);
      for (final fld in e.value.enumFields) {
        final (:counts, :empty) = countValues(rows, (r) => r.item.values[fld.key]?.toString() ?? '');
        expect(counts.values.fold(0, (a, b) => a + b) + empty, rows.length, reason: '${e.key}.${fld.key}');
        checked++;
      }
    }
    expect(checked, greaterThan(20));
    pb.close();
  });
}
