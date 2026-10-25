// بانک قیمت تجمیعی کاربر (یک شیت برای هر تجهیز + Vendor_Quotes) — نسخه‌ی کوچک در fixtures_private
// (tool/make_pricebank_fixture.py) و نسخه‌ی «به‌هم‌ریخته» (tool/make_messy_pricebank_fixture.py).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:price_bank/core/import/compressor_importer.dart';
import 'package:price_bank/core/import/desalter_importer.dart';
import 'package:price_bank/core/import/price_bank_importer.dart';
import 'package:price_bank/core/price_bank.dart';
import 'package:price_bank/core/xlsx/xlsx_reader.dart';

import 'support.dart';

const _pb = 'test/fixtures_private/PriceBank_test.xlsx';
const _messy = 'test/fixtures_private/PriceBank_test_messy.xlsx';

Map<String, Object?> _values(PriceBank pb, String ref) =>
    pb.items.get(pb.db.scalar("SELECT id FROM items WHERE legacy_ref = ? AND status = 'active'", [ref]) as int)!.values;

void main() {
  final has = File(_pb).existsSync() && File(_messy).existsSync();

  test('تشخیص نوع فایل: بانک تجمیعی در برابر بانک‌های جدا', () {
    final wb = XlsxWorkbook.openFile(_pb);
    expect(PriceBankImporter.isPriceBank(wb), isTrue);
    expect(PriceBankImporter.familySheets(wb).length, 16);
    expect(CompressorImporter.isCompressorBank(wb), isFalse);
    expect(DesalterImporter.isDesalterBank(wb), isFalse);
    expect(PriceBankImporter.isPriceBank(XlsxWorkbook.openFile('test/fixtures_private/Desalters_bank_test.xlsx')), isFalse);
    expect(PriceBankImporter.isPriceBank(XlsxWorkbook.openFile('test/fixtures_private/Compressors_bank_test.xlsx')), isFalse);
  }, skip: !has);

  test('ورود: همه‌ی رکوردها، مشخصات در فیلدهای رده، استعلام‌ها، بدون تکرار در ورود دوباره', () {
    final pb = PriceBank.memory(loadSeed());
    final wb = XlsxWorkbook.openFile(_pb);
    final rep = pb.priceBankImporter().run(wb, fileName: 'PriceBank_test.xlsx');
    expect(rep.items, 168);
    expect(rep.perCategory.values.fold(0, (a, b) => a + b), 168);
    expect(rep.quotes, 47);
    expect(rep.quotesPriced, 19);
    expect(rep.components, greaterThan(0));
    // مشخصات فنی در فیلدهای قالب (نه فقط متن)
    final ves = _values(pb, 'VES-0002');
    expect([ves['id_mm'], ves['tl_mm'], ves['design_pressure_barg'], ves['orientation']], [1500, 4500, 3.5, 'Horizontal']);
    final tnk = _values(pb, 'TNK-0001');
    expect([tnk['diameter_mm'], tnk['height_mm'], tnk['roof_type']], [25000, 15000, 'Dome']);
    final pmp = _values(pb, 'PMP-0001');
    expect([pmp['capacity_m3h'], pmp['diff_head_m'], pmp['material_class']], [354, 31.2, 'D-1']);
    final cmp = _values(pb, 'CMP-0001');
    expect([cmp['flow_m3h'], cmp['unit_weight_kg'], cmp['design_standard']], [610, 2000, 'API 618']);
    expect(_values(pb, 'DES-0001')['mto_parent_package'], 'PK-111'); // جزء پکیج (برای درخت پکیج)
    // استعلام بی‌پاسخ هم ثبت می‌شود (مبلغ خالی، وضعیت در متن)
    expect(pb.db.scalar("SELECT COUNT(*) FROM price_obs WHERE kind = 'quote' AND amount IS NULL AND amount_text IS NOT NULL") as int,
        47 - 19);
    // ورود دوباره: چیزی تکرار نمی‌شود
    final rep2 = pb.priceBankImporter().run(wb);
    expect([rep2.items, rep2.skippedExisting, rep2.quotes], [0, 168, 0]);
    pb.close();
  }, skip: !has);

  test('قلم تکراری MTO (همان رده، تگ و قیمت) بایگانی می‌شود؛ بانک مرجع است', () {
    final pb = PriceBank.memory(loadSeed());
    final cat = pb.catalog.categoryByCode('VESSEL')!;
    final mto = pb.items.create(categoryId: cat.id, values: {
      'name': 'Flare KO Drum', 'tag': 'V-171', 'currency': 'IRR', 'unit_price': 800000000.0, 'cost_year': 1394.0,
    });
    final other = pb.items.create(categoryId: cat.id, values: {
      'name': 'Flare KO Drum', 'tag': 'V-171', 'currency': 'IRR', 'unit_price': 123456789.0, 'cost_year': 1400.0,
    });
    final rep = pb.priceBankImporter().run(XlsxWorkbook.openFile(_pb));
    expect(rep.archivedDuplicates, 1);
    expect(pb.items.get(mto)!.status, 'archived');
    expect(pb.items.get(other)!.status, 'active');
    pb.close();
  }, skip: !has);

  test('بانک «به‌هم‌ریخته» (نام شیت و سرستون متفاوت، ردیف عنوان پایین‌تر، ستون حذف‌شده) = بانک مرجع', () {
    final pb0 = PriceBank.memory(loadSeed()), pb1 = PriceBank.memory(loadSeed());
    final r0 = pb0.priceBankImporter().run(XlsxWorkbook.openFile(_pb));
    final r1 = pb1.priceBankImporter().run(XlsxWorkbook.openFile(_messy));
    expect([r1.items, r1.quotes, r1.quotesPriced], [r0.items, r0.quotes, r0.quotesPriced]);
    expect(r1.perCategory, r0.perCategory);
    Set<String> prices(PriceBank pb) => {
          for (final r in pb.db.query('SELECT i.legacy_ref AS ref, o.amount, o.currency, o.cost_year FROM items i '
              'JOIN price_obs o ON o.item_id = i.id AND o.is_primary = 1'))
            '${r['ref']}|${r['amount']}|${r['currency']}|${r['cost_year']}',
        };
    expect(prices(pb1), prices(pb0));
    expect(_values(pb1, 'VES-0002')['tl_mm'], 4500);
    pb0.close();
    pb1.close();
  }, skip: !has);
}
