// فایل برآورد «آزاد» مشاور/پیمانکار (ساختار کپی‌شده از یک برآورد واقعی، نام‌ها و اعداد تغییر داده شده؛
// tool/make_estimate_fixture.py): جلد با جمع شیت‌ها، شیت ضرایب بیمه، ۱۵ شیت با قالب‌های متفاوت (قیمت/کیلو × وزن،
// طول × قیمت/متر، فقط جمع ردیف، ستون قیمت بی‌عنوان، ردیف نصب با قیمت ۱، قلم بیرون از ستون شرح، بالاسری ۳۰/۴۰/۶۰٪).
// هیچ قلمی نباید جا بیفتد و جمع هر شیت باید با جمع‌های خود فایل بخواند؛ نسخه‌ی «فقط مقدار» (بدون فرمول) هم همین‌طور.

import 'package:flutter_test/flutter_test.dart';
import 'package:price_bank/core/import/mto_importer.dart';
import 'package:price_bank/core/price_bank.dart';
import 'package:price_bank/core/xlsx/xlsx_reader.dart';

import 'support.dart';

const k = 1.013; // ضریب ناشناس‌سازی اعداد فیکسچر

void main() {
  for (final f in ['Estimate_sample_K.xlsx', 'Estimate_sample_K_values.xlsx']) {
    group(f, () {
      late MtoAnalysis a;
      setUpAll(() => a = MtoImporter.analyze(XlsxWorkbook.openFile('test/fixtures/$f'), fileName: f));
      Iterable<MtoItem> all() => a.sheets.expand((s) => s.items);
      MtoItem named(String n) => all().firstWhere((i) => i.name.trim() == n);
      String? catOf(MtoItem it) => a.sheets.firstWhere((s) => s.items.contains(it)).categoryCode;
      int count(String sheet) => a.sheets.where((s) => s.source == sheet).fold(0, (n, s) => n + s.items.length);

      test('همه‌ی اقلام، سال سند و شیت‌های غیرقلم', () {
        expect(a.itemCount, 120);
        expect(a.skippedSheets, ['COVER', 'Insurance']);
        expect(a.revision, 'C');
        expect((a.issueYear, a.issueMonth), (1403, 11)); // FEB. 2025 (بازنگری A؛ C تاریخ ندارد)
        expect(a.notes.join('\n'), contains('تاریخ بازنگری C'));
        expect(count('VESSELS(SEPARATOR)'), 7);
        expect(count('TANKS'), 11);
        expect(count('ROTARY'), 19);
        expect(count('PIPE & FITTING & Valves'), 11);
        expect(count('Mob-Demobilization'), 12);
        expect(count('Machinery'), 13);
        expect(count('employee Salary & Accomodation '), 3);
        expect(count('Instruments , Power & CCR '), 7);
      });

      test('قیمت خام از ستون‌های گوناگون', () {
        // قیمت/کیلو × وزن (فرمول) و ضریب بالاسری جدا
        final v = all().firstWhere((i) => i.tag == 'V-120');
        expect(v.goingEur, closeTo(11000 * k, 1));
        expect(v.weightKg, closeTo(2000 * k, 1));
        expect(v.overhead, 0.3);
        // ردیف نصب: قیمت واحد «۱» و جمع ردیف ۱۵۰٬۰۰۰ ← مبلغ یکجا، رده‌ی خدمات
        final inst = a.sheets.where((s) => s.source == 'H-EX & HEATER').expand((s) => s.items).firstWhere((i) => i.name.trim() == 'Installation');
        expect(inst.goingEur, closeTo(150000 * k, 1));
        expect(inst.quantity, 1);
        expect(catOf(inst), 'SERVICES');
        // لوله: طول (m) مقدار است؛ مبلغ = جمع ردیف، یک قلم یکجا
        final pipe = named('oil line (10 inch )');
        expect(pipe.quantity, 1);
        expect(pipe.goingEur, closeTo(1447440 * k, 2));
        expect(pipe.description, contains('Length (m): ${(12000 * k).round()}'));
        expect(catOf(pipe), 'PIPE_BULK');
        // قلم بیرون از ستون شرح
        expect(named('Existing Flare move').goingEur, closeTo(1000000 * k, 1));
        // تجهیز کارگاه: ستون قیمت بی‌عنوان، «total | 1» ← مبلغ یکجا
        expect(named('ofiice building (Contractor offices)').goingEur, closeTo(250 * k, 0.5));
        expect(named('office furnish').quantity, 1);
        expect(named('office furnish').goingEur, closeTo(300000 * k, 1));
        // حقوق: «Total month» مدت است نه جمع؛ جمع ردیف (یورو) مبلغ است
        expect(named('salary').goingEur, closeTo(2028000 * k, 2));
        // پرت: قیمت ۵۰۰۰ با ۴٫۲ €/kg × ۲۰ تن نمی‌خواند
        expect(all().firstWhere((i) => i.tag == 'TK-170').warnings.join(), contains('پرت'));
      });

      test('رده‌ی هر قلم در شیت‌های چندرده‌ای', () {
        expect(catOf(all().firstWhere((i) => i.tag == 'E-101')), 'HEX');
        expect(catOf(all().firstWhere((i) => i.tag == 'H-100 A' && i.name.contains('HEATER'))), 'HEATER');
        expect(catOf(all().firstWhere((i) => i.tag == 'PK-141 A/B')), 'AIR_DRYER');
        expect(catOf(all().firstWhere((i) => i.tag == 'P-102 A/B')), 'PUMP');
        expect(catOf(named('Desalter Installation')), 'SERVICES');
        expect(catOf(named('Valves/ Control Valves')), 'VALVE');
        expect(catOf(named('Metering System')), 'INST_EQ');
        expect(catOf(named('Gas Generator')), 'ELEC_EQ');
        expect(catOf(named('HSE Equipment')), 'FIRE_SAFETY');
        expect(catOf(named('bulldozer')), 'SERVICES');
      });

      test('ورود به بانک: همه‌ی اقلام، رده‌ی خدمات، گزارش در یادداشت سند', () {
        final pb = PriceBank.memory(loadSeed());
        final rep = pb.mtoImporter().run(a, projectName: 'Sample K', oldFx: null);
        expect(rep.items, 120);
        expect(rep.perCategory['SERVICES'], greaterThanOrEqualTo(30));
        final notes = pb.db.scalar("SELECT notes FROM documents WHERE doc_type = 'mto'") as String;
        expect(notes, contains('ضرایب شیت «Insurance»'));
        final svc = pb.catalog.categoryByCode('SERVICES')!;
        expect(svc.enabled, isTrue);
        expect(pb.computeCategory(svc.id).length, rep.perCategory['SERVICES']);
        pb.close();
      });

      test('گزارش کنترل: جمع شیت‌ها و ضرایب', () {
        final n = a.notes.join('\n');
        expect(n, contains('ضرایب شیت «Insurance»'));
        expect(n, contains('Engineering (HR): 0.1667'));
        expect(n, contains('ROTARY 60٪'));
        expect(n, contains('بدون ضرب در تعداد'));
        if (f.contains('values')) {
          // بدون فرمول: جمع‌های داخل شیت‌ها (نه ارجاع جلد) کنترل می‌شود
          for (final s in ['ROTARY', 'STACK', 'H-EX & HEATER', 'PACKAGE', 'E&I&C', 'Mob-Demobilization', 'Machinery']) {
            expect(a.notes.firstWhere((x) => x.startsWith('شیت «$s»: جمع اقلام')), contains('✓'), reason: s);
          }
        } else {
          expect(n, contains('«COVER»: Salary & Accomodations'));
          expect(a.notes.firstWhere((x) => x.contains('Salary & Accomodations')), contains('اختلاف 0٪'));
        }
      });
    });
  }
}
