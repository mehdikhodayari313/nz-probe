import 'package:flutter_test/flutter_test.dart';
import 'package:price_bank/core/xlsx/xlsx_reader.dart';

import 'support.dart';

void main() {
  test('خواندن یادداشت سلول و رنگ پس‌زمینه از v8', () {
    if (!hasFixtures) return;
    final md = XlsxWorkbook.openFile(v8Path).sheet('Master Database')!;
    expect(md.comment(5, 5), startsWith('ROT-CRU'));
    expect(md.comment(4, 2), isNotNull); // راهنمای سرستون
    expect(md.commentCount, greaterThan(1000));
    var yellow = 0;
    for (var r = 5; r <= md.maxRow; r++) {
      for (final c in md.rowCells(r)) {
        if (c.fillRgb == 'FFFFFF00') yellow++;
      }
    }
    expect(yellow, greaterThan(300));
  });
}
