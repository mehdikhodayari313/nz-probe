// انعطاف خواننده‌ی بانک‌ها: فایل «به‌هم‌ریخته» (شیت تغییرنام، سرستون‌های متفاوت، ردیف عنوان جابه‌جا، ستون حذف‌شده،
// بدون App_Meta) باید همان رکوردها، قیمت‌ها، سال‌ها و استعلام‌های فایل مرجع را بدهد و ستون نبوده را گزارش کند.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:price_bank/core/import/bank_headers.dart';
import 'package:price_bank/core/import/compressor_importer.dart';
import 'package:price_bank/core/import/desalter_importer.dart';
import 'package:price_bank/core/price_bank.dart';
import 'package:price_bank/core/xlsx/xlsx_reader.dart';

import 'support.dart';

const _cmp = 'test/fixtures_private/Compressors_bank_test.xlsx';
const _des = 'test/fixtures_private/Desalters_bank_test.xlsx';

Map<String, (double?, double?, String?)> _prices(PriceBank pb, String code) {
  final cat = pb.catalog.categoryByCode(code)!;
  return {
    for (final r in pb.db.query(
        "SELECT i.legacy_ref AS ref, o.amount, o.cost_year, o.currency FROM items i "
        'JOIN price_obs o ON o.item_id = i.id AND o.is_primary = 1 WHERE i.category_id = ?',
        [cat.id]))
      r['ref'] as String: ((r['amount'] as num?)?.toDouble(), (r['cost_year'] as num?)?.toDouble(), r['currency'] as String?),
  };
}

void main() {
  test('تطبیق سرستون: عین، بدون واحد، هم‌معنی، شامل واژه‌ها', () {
    expect(coreHeader('Cost Year (Jalali)'), 'cost year');
    expect(normHeader('Capacity per Compressor (Nm³/h)'), 'capacity per compressor nm3 h');
  });

  final hasCmp = File(_cmp).existsSync() && File(_cmp.replaceFirst('.xlsx', '_messy.xlsx')).existsSync();
  test('بانک کمپرسور به‌هم‌ریخته = بانک مرجع', () {
    final wb0 = XlsxWorkbook.openFile(_cmp), wb1 = XlsxWorkbook.openFile(_cmp.replaceFirst('.xlsx', '_messy.xlsx'));
    expect(CompressorImporter.isCompressorBank(wb1), isTrue);
    expect(CompressorImporter.validate(wb1), isNull);
    final pb0 = PriceBank.memory(loadSeed()), pb1 = PriceBank.memory(loadSeed());
    final r0 = pb0.compressorImporter().run(wb0), r1 = pb1.compressorImporter().run(wb1);
    expect(r1.items, r0.items);
    expect(r1.quotes, r0.quotes);
    expect(r1.quotesPriced, r0.quotesPriced);
    expect(r1.vendors, r0.vendors);
    expect(r1.corrections, r0.corrections);
    expect(_prices(pb1, 'COMPRESSOR'), _prices(pb0, 'COMPRESSOR'));
    expect(r1.warnings.join('\n'), contains('Compressors per Price Unit'));
    // ستون تازه‌ی فایل (در قالب برنامه نیست) گم نمی‌شود
    expect(r1.warnings.join('\n'), contains('Site Altitude (m)'));
    final alt = pb1.db.scalar("SELECT COUNT(*) FROM item_values WHERE field_key = 'mto_site_altitude_m'") as int;
    expect(alt, r1.items);
    expect(r1.warnings.join('\n'), contains('Cost Year (Shamsi)'));
    pb0.close();
    pb1.close();
  }, skip: !hasCmp);

  final hasDes = File(_des).existsSync() && File(_des.replaceFirst('.xlsx', '_messy.xlsx')).existsSync();
  test('بانک دیسالتر به‌هم‌ریخته = بانک مرجع', () {
    final wb0 = XlsxWorkbook.openFile(_des), wb1 = XlsxWorkbook.openFile(_des.replaceFirst('.xlsx', '_messy.xlsx'));
    expect(CompressorImporter.isCompressorBank(wb1), isFalse);
    expect(DesalterImporter.isDesalterBank(wb1), isTrue);
    expect(DesalterImporter.validate(wb1), isNull);
    final pb0 = PriceBank.memory(loadSeed()), pb1 = PriceBank.memory(loadSeed());
    final r0 = pb0.desalterImporter().run(wb0), r1 = pb1.desalterImporter().run(wb1);
    expect(r1.items, r0.items);
    expect(r1.quotes, r0.quotes);
    expect(r1.vendors, r0.vendors);
    expect(r1.corrections, r0.corrections);
    expect(_prices(pb1, 'DESALTER'), _prices(pb0, 'DESALTER'));
    expect(r1.warnings.join('\n'), contains('No. of Transformers'));
    // ستون تازه‌ی فایل (در قالب برنامه نیست) گم نمی‌شود
    expect(r1.warnings.join('\n'), contains('Site Altitude (m)'));
    final alt = pb1.db.scalar("SELECT COUNT(*) FROM item_values WHERE field_key = 'mto_site_altitude_m'") as int;
    expect(alt, r1.items);
    pb0.close();
    pb1.close();
  }, skip: !hasDes);
}
