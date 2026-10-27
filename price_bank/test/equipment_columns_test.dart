// بند ۲e و ۱۶ برنامه‌ی تغییرات: ظرفیت واحد پروژه (ستون و فیلتر هزار BPD) و سال قیمت در جدول همه‌ی تجهیزات.

import 'package:flutter_test/flutter_test.dart';
import 'package:price_bank/app/app_state.dart';
import 'package:price_bank/core/import/mto_importer.dart';
import 'package:price_bank/core/price_bank.dart';
import 'package:price_bank/core/xlsx/xlsx_reader.dart';
import 'package:price_bank/ui/widgets/equipment_columns.dart';

import 'support.dart';

void main() {
  test('بازه‌ی ظرفیت به هزار BPD؛ ظرفیت نامعلوم فقط وقتی بازه خالی است', () {
    expect(capacityInRange(60000, 50, 70), isTrue);
    expect(capacityInRange(60000, 61, null), isFalse);
    expect(capacityInRange(60000, null, 60), isTrue);
    expect(capacityInRange(null, null, null), isTrue);
    expect(capacityInRange(null, 10, null), isFalse);
  });

  test('ظرفیت پروژه از «پروژه‌ها و اسناد» و با ویرایش پروژه به‌روز می‌شود', () {
    final pb = PriceBank.memory(loadSeed());
    pb.mtoImporter().run(
        MtoImporter.analyze(XlsxWorkbook.openFile('test/fixtures/Estimate_sample_K.xlsx'), fileName: 'Estimate_sample_K.xlsx'),
        projectName: 'Sample K',
        oldFx: null);
    final app = AppState(pb);
    final p = pb.docs.projects().singleWhere((p) => p.name == 'Sample K');
    final item = app.allRows.firstWhere((r) => r.item.projectId == p.id).item;
    expect(app.projectCapacity(item.projectId), isNull);

    pb.docs.updateProject(p.id, {'capacity_bpd': 60000.0});
    app.dataChanged();
    expect(app.projectCapacity(item.projectId), 60000);
    expect(capacityColumn<double?>((v) => v).text(60000), '۶۰');
    expect(costYearColumn((Object? _) => item).text(null), isNotEmpty);
  });
}
