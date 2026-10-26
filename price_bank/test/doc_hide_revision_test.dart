// بند ۱ و ۵ برنامه‌ی تغییرات: پنهان کردن سند از مشاهده و محاسبات؛ بازنگری جدیدتر MTO مبنای قیمت.

import 'package:flutter_test/flutter_test.dart';
import 'package:price_bank/core/db/migrations.dart';
import 'package:price_bank/core/import/mto_importer.dart';
import 'package:price_bank/core/price_bank.dart';
import 'package:price_bank/core/xlsx/xlsx_reader.dart';

import 'support.dart';

const _f = 'Estimate_sample_K.xlsx';

MtoAnalysis _analysis({String? docRef, int? year, int? month, double priceFactor = 1}) {
  final a = MtoImporter.analyze(XlsxWorkbook.openFile('test/fixtures/$_f'), fileName: _f);
  if (docRef != null) a.docRef = docRef;
  a.issueYear = year;
  a.issueMonth = month;
  for (final s in a.sheets) {
    for (final it in s.items) {
      if (it.goingEur != null) it.goingEur = it.goingEur! * priceFactor;
      if (it.goingIrr != null) it.goingIrr = it.goingIrr! * priceFactor;
      if (it.goingUsd != null) it.goingUsd = it.goingUsd! * priceFactor;
    }
  }
  return a;
}

void main() {
  late PriceBank pb;
  late int vessel;
  int visible() => pb.items.loadCategory(vessel).length;
  int docId(String title) => pb.db.scalar('SELECT id FROM documents WHERE title = ?', [title]) as int;
  int itemId(String tag) => pb.db.scalar('SELECT id FROM items WHERE tag = ? AND category_id = ?', [tag, vessel]) as int;

  setUp(() {
    pb = PriceBank.memory(loadSeed());
    vessel = pb.catalog.categoryByCode('VESSEL')!.id;
  });

  test('سند پنهان: اقلام و قیمت‌هایش از جدول، شمارش و محاسبات کنار می‌روند و با پیدا کردن برمی‌گردند', () {
    final a = _analysis(year: 1403, month: 5);
    pb.mtoImporter().run(a, projectName: 'Sample K', oldFx: null);
    final n = visible();
    expect(n, greaterThan(0));
    expect(pb.items.count(vessel), n);
    final d = docId(a.docRef ?? a.fileName);

    pb.docs.setHidden(d, true);
    pb.invalidateCalc();
    expect(visible(), 0);
    expect(pb.items.count(vessel), 0);
    expect(pb.computeCategory(vessel), isEmpty);
    expect(pb.docs.documents().firstWhere((x) => x.id == d).hidden, isTrue);
    expect(pb.docs.projects().single.itemCount, 0);
    // صفحه‌ی قلم هنوز باز می‌شود؛ قیمت‌ها جدا (پنهان) هستند
    final it = pb.items.get(itemId('V-120'))!;
    expect(it.observations, isEmpty);
    expect(it.hiddenObservations, isNotEmpty);

    pb.docs.setHidden(d, false);
    pb.invalidateCalc();
    expect(visible(), n);
    expect(pb.computeCategory(vessel).length, n);
  });

  test('بازنگری جدیدتر همان پروژه: قلم تکراری نمی‌شود و قیمت جدید مبنا می‌شود؛ قیمت قبلی می‌ماند', () {
    final a1 = _analysis(year: 1403, month: 5);
    final r1 = pb.mtoImporter().run(a1, projectName: 'Sample K', oldFx: null);
    final n = visible();
    final id = itemId('V-120');
    final p1 = pb.items.get(id)!.primary!;

    final r2 = pb.mtoImporter().run(_analysis(docRef: 'Sample K R02', year: 1404, month: 2, priceFactor: 1.25),
        projectName: 'Sample K', oldFx: null);
    expect(r2.items, 0);
    expect(r2.revisedNewer, r1.items);
    expect(visible(), n, reason: 'قلم دوباره ساخته نشد');
    final it = pb.items.get(id)!;
    expect(it.primary!.documentTitle, 'Sample K R02');
    expect(it.primary!.amount, closeTo(p1.amount! * 1.25, 1e-6));
    expect(it.observations.where((o) => o.id == p1.id && !o.isPrimary), hasLength(1), reason: 'قیمت قبلی نگه داشته شد');

    // تعداد بازنگری جدیدتر جایگزین می‌شود؛ بازنگری قدیمی‌تر تعداد را عوض نمی‌کند
    final a4 = _analysis(docRef: 'Sample K R03', year: 1404, month: 6);
    a4.sheets.expand((s) => s.items).firstWhere((x) => x.tag == 'V-120').quantity = 3;
    pb.mtoImporter().run(a4, projectName: 'Sample K', oldFx: null);
    expect(pb.items.get(id)!.quantity, 3);

    // بازنگری قدیمی‌تر که بعد وارد شود مبنا نمی‌شود
    final r3 = pb.mtoImporter().run(_analysis(docRef: 'Sample K R00', year: 1401, priceFactor: 0.5),
        projectName: 'Sample K', oldFx: null);
    expect(r3.revisedOlder, r1.items);
    expect(r3.revisedNewer, 0);
    expect(pb.items.get(id)!.primary!.documentTitle, 'Sample K R03');
    expect(pb.items.get(id)!.quantity, 3);

    // پنهان کردن بازنگری جدید: قیمت مبنا از سند پیدای دیگر
    pb.docs.setHidden(docId('Sample K R03'), true);
    final h = pb.items.get(id)!;
    expect(h.primary!.documentTitle, isNot('Sample K R03'));
    expect(visible(), n);
  });

  test('حذف سند: قلمی که فقط از همان سند آمده (حتی بی‌قیمت) حذف می‌شود؛ قلم دارای بازنگری دیگر می‌ماند', () {
    final a1 = _analysis(year: 1403);
    pb.mtoImporter().run(a1, projectName: 'Sample K', oldFx: null);
    pb.mtoImporter().run(_analysis(docRef: 'Sample K R02', year: 1404), projectName: 'Sample K', oldFx: null);
    final n = visible();
    pb.docs.deleteDocument(docId(a1.docRef ?? a1.fileName));
    expect(visible(), n);
    expect(pb.db.scalar('SELECT COUNT(*) FROM items WHERE source_document_id IS NULL AND project_id IS NOT NULL'), greaterThan(0));
  });

  test('مهاجرت ۳: سند مبدأ اقلام موجود از قیمت‌ها و تاریخچه‌ی ورود پر می‌شود', () {
    final a = _analysis(year: 1403);
    pb.mtoImporter().run(a, projectName: 'Sample K', oldFx: null);
    final d = docId(a.docRef ?? a.fileName);
    final total = pb.db.scalar('SELECT COUNT(*) FROM items') as int;
    pb.db.execute('UPDATE items SET source_document_id = NULL');
    final m3 = migrations.firstWhere((m) => m.version == 3);
    for (final s in m3.statements.where((s) => s.trimLeft().startsWith('UPDATE items'))) {
      pb.db.execute(s);
    }
    expect(pb.db.scalar('SELECT COUNT(*) FROM items WHERE source_document_id = ?', [d]), total,
        reason: 'اقلام بی‌قیمت هم از شرح تاریخچه');
  });
}
