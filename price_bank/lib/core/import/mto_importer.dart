// ورود خودکار فایل MTO مشاور (قالب «MTO کاری با بلوک‌های استعلام» — مرجع: پازنان ۲) به دیتابیس.
//
// ساختار هر شیت تجهیز:
//   ردیف عنوان (مثلاً ۷): Item No. | Description | Qty. | GOING UNIT PRICE IRR/EUR (1404Q1) | …
//   ردیف بالای آن: «استعلام ۱»، «استعلام ۲»، … — هر بلوک: منبع، بهای واحد ریال، یورو، دلار، تاریخ مرجع
//   ستون‌های جمع‌بندی: Ref. Currency، Unit Price (Rials) و Unit Price FOB (€) = قیمت‌های بازنگری قبلی (مثلاً ۱۳۹۳)
//   ردیف‌های اقلام تا ردیف «برآورد هزینه …»
//
// هر قلم به رده‌ی مربوط (ظرف، مخزن، پکیج، …) وارد می‌شود؛ قیمت مبنای مشاور (GOING) قیمت اصلی،
// هر استعلام فروشنده یک «استعلام» جدا و قیمت بازنگری قبلی یک «برآورد» جدا ثبت می‌شود.
// خط‌های «کلید: مقدار» شرح به فیلدهای مشخصات فنی رده تبدیل می‌شوند.

import 'package:shamsi_date/shamsi_date.dart';

import '../db/db.dart';
import '../repo/audit.dart';
import '../repo/catalog_repo.dart';
import '../repo/docs_repo.dart';
import '../repo/items_repo.dart';
import '../xlsx/xlsx_reader.dart';

/// یک استعلام فروشنده برای یک قلم.
class MtoQuote {
  MtoQuote({required this.vendor, required this.currency, required this.amount, this.formula});
  final String vendor;
  final String currency; // IRR, EUR, USD
  final double amount;
  final String? formula;
  int? year;
  int? month;
  String? dateText;
  bool dateFixed = false;
}

/// یک قلم MTO.
class MtoItem {
  MtoItem(this.row, this.tag, this.description);
  final int row;
  final String tag;
  final String description;
  String get name => description.split('\n').first.trim();
  double? quantity;
  String? refCurrency;
  double? goingIrr, goingEur;
  double? oldIrr, oldEur;
  final Map<String, String> specs = {}; // برچسب ← مقدار (به ترتیب شرح)
  final List<String> scopeLines = [];
  final List<MtoQuote> quotes = [];
  final List<String> nonResponses = [];
  final List<String> warnings = [];
}

/// یک شیت تجهیز.
class MtoSheet {
  MtoSheet(this.name, this.title);
  final String name;
  final String title;
  String? categoryCode;
  bool selected = true;
  int? goingYear, goingMonth;
  int? oldYear, oldMonth;
  String goingLabel = '';
  String oldLabel = '';
  final List<MtoItem> items = [];
  int get quoteCount => items.fold(0, (s, i) => s + i.quotes.length);
  int get warningCount => items.fold(0, (s, i) => s + i.warnings.length);
}

class MtoAnalysis {
  MtoAnalysis(this.fileName);
  final String fileName;
  String format = 'unknown';
  String? docRef;
  String? revision;
  String? projectTitle;
  String? suggestedProject;
  int? issueYear, issueMonth;
  final List<MtoSheet> sheets = [];
  final List<String> skippedSheets = [];
  final List<String> warnings = [];
  bool get supported => sheets.isNotEmpty;
  int get itemCount => sheets.fold(0, (s, x) => s + x.items.length);
  int get quoteCount => sheets.fold(0, (s, x) => s + x.quoteCount);
}

class MtoImportReport {
  int items = 0, quotes = 0, estimates = 0, vendors = 0, specFields = 0, skippedDuplicates = 0;
  bool alreadyImported = false;
  final Map<String, int> perCategory = {};
  final List<String> warnings = [];
}

/// نام شیت ← کد رده (پیشنهاد اولیه؛ در پیش‌نمایش قابل تغییر است).
const mtoSheetCategory = <String, String>{
  'DESALTER': 'DESALTER',
  'HEATER': 'HEATER',
  'VESSEL': 'VESSEL',
  'TANK': 'TANK',
  'EXCHANG': 'HEX',
  'PUMP': 'PUMP',
  'C.I.P': 'CIP',
  'CHEMICAL': 'CIP',
  'DEAERATOR': 'DEAERATOR',
  'IGF': 'IGF',
  'FILTER': 'FILTER',
  'FLARE': 'FLARE',
  'BURN PIT': 'FLARE',
  'AIR COMP': 'COMPRESSOR',
  'COMPRESSOR': 'COMPRESSOR',
  'AIR DRYER': 'AIR_DRYER',
  'DRYER': 'AIR_DRYER',
  'CRANE': 'CRANE',
};

String? suggestCategory(String sheetName) {
  final u = sheetName.toUpperCase().trim();
  // طولانی‌ترین کلید اول (مثلاً «AIR DRYER» قبل از «DRYER»)
  final keys = mtoSheetCategory.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    if (u.startsWith(k) || u.contains(k)) return mtoSheetCategory[k];
  }
  return null;
}

class MtoImporter {
  MtoImporter(this.db, this.audit, this.catalog, this.items, this.docs);
  final Db db;
  final Audit audit;
  final CatalogRepo catalog;
  final ItemsRepo items;
  final DocsRepo docs;

  /// سال و ماه پیش‌فرض قیمت‌های بازنگری قبلی وقتی در عنوان ستون نیامده (پازنان ۲: بهمن ۱۳۹۳).
  static const defaultOldYear = 1393, defaultOldMonth = 11;

  /// نرخ تسعیر پیش‌فرض قیمت‌های ریالی بازنگری قبلی (پازنان ۹۳: ۴۰٬۵۳۰٫۸ ریال/یورو).
  static const defaultOldFx = 40530.8;

  // ---------------------------------------------------------------------------
  // تحلیل فایل (بدون تغییر دیتابیس)

  static MtoAnalysis analyze(XlsxWorkbook wb, {required String fileName}) {
    final a = MtoAnalysis(fileName);
    final fm = RegExp(r'(1[34]\d\d)(\d\d)(\d\d)').firstMatch(fileName);
    if (fm != null) {
      a.issueYear = int.parse(fm.group(1)!);
      final m = int.parse(fm.group(2)!);
      if (m >= 1 && m <= 12) a.issueMonth = m;
    }
    for (final info in wb.sheets) {
      if (info.hidden) continue;
      final sh = wb.sheet(info.name);
      if (sh == null) continue;
      final hdr = _headerRow(sh);
      if (hdr == null) {
        a.skippedSheets.add(info.name);
        continue;
      }
      // اطلاعات سند از سطرهای بالای شیت
      for (var r = 1; r < hdr; r++) {
        final t = sh.text(r, 1);
        if (a.docRef == null && t.toLowerCase().startsWith('doc. ref')) {
          a.docRef = t.replaceFirst(RegExp(r'^doc\.?\s*ref\.?\s*(no\.?)?\s*[:：]?\s*', caseSensitive: false), '').trim();
          final rv = RegExp(r'-(R\d{1,3})\s*$').firstMatch(a.docRef!);
          a.revision = rv?.group(1);
        }
        if (a.projectTitle == null && t.toLowerCase().startsWith('project title')) {
          a.projectTitle = t.substring(t.indexOf(':') + 1).trim();
        }
      }
      final s = _parseSheet(sh, hdr);
      if (s.items.isEmpty) {
        a.skippedSheets.add(info.name);
        continue;
      }
      a.sheets.add(s);
    }
    if (a.sheets.isNotEmpty) a.format = 'mto_quote_blocks';
    a.suggestedProject = suggestProjectName(a.projectTitle);
    return a;
  }

  /// «Revamping of Pazanan II Desalting Unit» ← «Pazanan 2»
  static String? suggestProjectName(String? title) {
    if (title == null || title.isEmpty) return null;
    var t = title.replaceFirst(RegExp(r'^(Revamping|Reconstruction|Construction|Upgrading)\s+of\s+', caseSensitive: false), '');
    t = t.replaceFirst(RegExp(r'\s+(Desalt|Desalting|Dehydration)\b.*$', caseSensitive: false), '').trim();
    const roman = {'I': '1', 'II': '2', 'III': '3', 'IV': '4', 'V': '5'};
    t = t.replaceAllMapped(RegExp(r'\b(IV|V|I{1,3})\b'), (m) => roman[m.group(1)] ?? m.group(1)!);
    return t.isEmpty ? null : t;
  }

  static int? _headerRow(XlsxSheet sh) {
    for (var r = 1; r <= 20 && r <= sh.maxRow; r++) {
      final a = sh.text(r, 1).toLowerCase();
      final b = sh.text(r, 2).toLowerCase();
      if (a.startsWith('item no') && b.startsWith('desc')) return r;
    }
    return null;
  }

  static (int?, int?) _yearQuarter(String header) {
    final m = RegExp(r'(1[34]\d\d)\s*Q\s*([1-4])', caseSensitive: false).firstMatch(header);
    if (m == null) {
      final y = RegExp(r'\b(1[34]\d\d)\b').firstMatch(header);
      return (y == null ? null : int.parse(y.group(1)!), null);
    }
    final q = int.parse(m.group(2)!);
    return (int.parse(m.group(1)!), q * 3 - 1); // ماه میانی فصل
  }

  static MtoSheet _parseSheet(XlsxSheet sh, int hdr) {
    final s = MtoSheet(sh.name, sh.text(hdr - 1, 1));
    s.categoryCode = suggestCategory(sh.name);

    // بلوک‌های استعلام
    final blocks = <(int, int?, int?, int?, int?)>[]; // منبع، ریال، یورو، دلار، تاریخ
    for (var c = 1; c <= sh.maxCol; c++) {
      if (!RegExp(r'^استعلام\s*\d+').hasMatch(sh.text(hdr - 1, c))) continue;
      int? irr, eur, usd, date;
      for (var k = 1; k <= 5; k++) {
        final h = sh.text(hdr, c + k);
        if (h.contains('ریال') && irr == null) {
          irr = c + k;
        } else if (h.contains('یورو') && eur == null) {
          eur = c + k;
        } else if (h.contains('دلار') && usd == null) {
          usd = c + k;
        } else if (h.contains('تاریخ') && date == null) {
          date = c + k;
        }
      }
      blocks.add((c, irr, eur, usd, date));
    }

    // ستون‌های جمع‌بندی
    int? goingIrr, goingEur, refCur, oldIrr, oldEur, newIrr, newEur;
    for (var c = 1; c <= sh.maxCol; c++) {
      final h = sh.text(hdr, c).replaceAll(RegExp(r'\s+'), ' ');
      final l = h.toLowerCase();
      final isEurHdr = h.contains('€') || l.contains('eur') || l.contains('fob');
      final isIrrHdr = l.contains('irr') || l.contains('rial') || h.contains('ریال');
      if (l.contains('going')) {
        if (isEurHdr && goingEur == null) {
          goingEur = c;
        } else if (isIrrHdr && goingIrr == null) {
          goingIrr = c;
        }
        final (y, m) = _yearQuarter(h);
        if (y != null) {
          s.goingYear = y;
          s.goingMonth = m;
          s.goingLabel = RegExp(r'1[34]\d\dQ?\d?', caseSensitive: false).firstMatch(h)?.group(0) ?? '$y';
        }
      } else if (l.contains('ref. currency') || l.contains('ref currency')) {
        refCur = c;
      } else if (l.contains('new item')) {
        if (isEurHdr) {
          newEur = c;
        } else if (isIrrHdr) {
          newIrr = c;
        }
      } else if (l.contains('unit price') && !l.contains('quoted') && !l.contains('aggregate')) {
        if (isEurHdr && !isIrrHdr && oldEur == null) {
          oldEur = c;
        } else if (isIrrHdr && oldIrr == null) {
          oldIrr = c;
        }
        final (y, m) = _yearQuarter(h);
        if (y != null) {
          s.oldYear = y;
          s.oldMonth = m;
          s.oldLabel = RegExp(r'1[34]\d\dQ?\d?', caseSensitive: false).firstMatch(h)?.group(0) ?? '$y';
        }
      }
    }

    for (var r = hdr + 1; r <= sh.maxRow; r++) {
      final tag = sh.text(r, 1);
      final desc = sh.text(r, 2);
      if (desc.startsWith('برآورد')) break;
      if (tag.isEmpty || desc.isEmpty) continue;
      final it = MtoItem(r, tag.replaceAll(RegExp(r'\s+'), ' '), desc.replaceAll('\r', ''));
      it.quantity = sh.cell(r, 3)?.number;
      if (it.quantity == null) it.warnings.add('${sh.name}!C$r: تعداد عددی نیست («${sh.text(r, 3)}»)');
      it.refCurrency = refCur == null ? null : _cur(sh.text(r, refCur));
      double? num(int? c) {
        if (c == null) return null;
        final v = sh.cell(r, c)?.number;
        return (v == null || v == 0) ? null : v;
      }

      it.goingIrr = num(goingIrr) ?? num(newIrr);
      it.goingEur = num(goingEur) ?? num(newEur);
      it.oldIrr = num(oldIrr);
      it.oldEur = num(oldEur);
      _parseDescription(it);

      for (final (src, irr, eur, usd, date) in blocks) {
        final vendor = sh.text(r, src);
        if (vendor.isEmpty) continue;
        final dateCell = date == null ? null : sh.cell(r, date);
        var any = false;
        for (final (c, cur) in [(irr, 'IRR'), (eur, 'EUR'), (usd, 'USD')]) {
          if (c == null) continue;
          final cell = sh.cell(r, c);
          final v = cell?.number;
          if (cell == null) continue;
          if (v == null || v <= 0) {
            final t = cell.text.trim();
            if (t.isNotEmpty && t != '-' && t != '0') {
              it.warnings.add('${sh.name}!${cell.ref}: قیمت غیرعددی «$t» (${_short(vendor)})');
            }
            continue;
          }
          final q = MtoQuote(vendor: vendor, currency: cur, amount: v, formula: cell.formula);
          if (cell.formula != null) {
            it.warnings.add('${sh.name}!${cell.ref}: قیمت به صورت فرمول ${cell.formula} — مبنای ضریب بررسی شود');
          }
          _applyDate(q, dateCell, it, sh.name);
          it.quotes.add(q);
          any = true;
        }
        if (!any) {
          final st = dateCell?.text.trim() ?? '';
          final l = st.toLowerCase();
          if (l.contains('no reply') || l.contains('declined') || l.contains('regret')) {
            it.nonResponses.add('$vendor: ${l.contains('declined') || l.contains('regret') ? 'انصراف' : 'بدون پاسخ'}');
          }
        }
      }
      s.items.add(it);
    }
    return s;
  }

  static String _short(String s) => s.length > 30 ? '${s.substring(0, 30)}…' : s;

  static String? _cur(String t) {
    final u = t.trim().toUpperCase();
    if (u.contains('EUR') || u.contains('€')) return 'EUR';
    if (u.contains('USD') || u.contains(r'$')) return 'USD';
    if (u.contains('IRR') || u.contains('RIAL') || t.contains('ریال')) return 'IRR';
    return null;
  }

  /// شرح چندخطی: خط اول نام؛ «کلید: مقدار» مشخصات؛ خط بدون «:» ادامه‌ی مقدار قبلی یا دامنه‌ی کار.
  static void _parseDescription(MtoItem it) {
    final lines = it.description.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    String? lastKey;
    for (final line in lines.skip(1)) {
      final i = line.indexOf(':');
      if (i > 0 && i < 70 && !line.startsWith('&')) {
        final k = line.substring(0, i).trim();
        final v = line.substring(i + 1).trim();
        if (v.isEmpty) {
          lastKey = k;
          it.specs[k] = '';
        } else if (it.specs.containsKey(k)) {
          it.specs[k] = '${it.specs[k]}; $v';
          lastKey = k;
        } else {
          it.specs[k] = v;
          lastKey = k;
        }
      } else if (lastKey != null) {
        it.specs[lastKey] = '${it.specs[lastKey]} $line'.trim();
      } else {
        it.scopeLines.add(line);
      }
    }
    it.specs.removeWhere((k, v) => v.isEmpty);
  }

  static void _applyDate(MtoQuote q, XlsxCell? c, MtoItem it, String sheet) {
    if (c == null) return;
    DateTime? g;
    final v = c.value;
    if (v is double && v > 20000 && v < 80000) {
      g = DateTime(1899, 12, 30).add(Duration(days: v.floor()));
    } else {
      final t = c.text.trim();
      q.dateText = t;
      final m1 = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(t); // ماه/روز/سال
      final m2 = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
      int? y, mo, d;
      if (m1 != null) {
        mo = int.parse(m1.group(1)!);
        d = int.parse(m1.group(2)!);
        y = int.parse(m1.group(3)!);
      } else if (m2 != null) {
        y = int.parse(m2.group(1)!);
        mo = int.parse(m2.group(2)!);
        d = int.parse(m2.group(3)!);
      }
      if (y != null && mo != null && d != null && mo >= 1 && mo <= 12) {
        final last = DateTime(y, mo + 1, 0).day;
        if (d > last || d < 1) {
          it.warnings.add('$sheet!${c.ref}: تاریخ نامعتبر «$t» — آخرین روز همان ماه در نظر گرفته شد');
          d = last;
          q.dateFixed = true;
        }
        g = DateTime(y, mo, d);
      }
    }
    if (g == null) return;
    final j = Gregorian(g.year, g.month, g.day).toJalali();
    q.year = j.year;
    q.month = j.month;
  }

  // ---------------------------------------------------------------------------
  // ورود به دیتابیس

  /// [oldYear]/[oldMonth]: سال قیمت‌های بازنگری قبلی وقتی در عنوان ستون نیامده.
  /// [oldFx]: نرخ تسعیر قیمت‌های ریالی بازنگری قبلی (ریال/یورو).
  MtoImportReport run(
    MtoAnalysis a, {
    required String projectName,
    int oldYear = defaultOldYear,
    int? oldMonth = defaultOldMonth,
    double? oldFx = defaultOldFx,
  }) {
    final rep = MtoImportReport();
    final project = projectName.trim();
    if (project.isEmpty) throw ArgumentError('نام پروژه خالی است');
    final title = a.docRef ?? a.fileName;
    final pidExisting = db.scalar('SELECT id FROM projects WHERE name = ?', [project]) as int?;
    if (pidExisting != null &&
        db.scalar('SELECT 1 FROM documents WHERE project_id = ? AND title = ? AND doc_type = ?',
                [pidExisting, title, 'mto']) !=
            null) {
      rep.alreadyImported = true;
      return rep;
    }
    final vendorsBefore = db.scalar('SELECT COUNT(*) FROM vendors') as int;
    final batch = Audit.newBatch();

    db.transaction(() {
      final pid = docs.ensureProject(project);
      final docId = docs.ensureDocument(projectId: pid, title: title, revision: '', docType: 'mto');
      docs.updateDocument(docId, {
        'doc_ref': a.docRef,
        'issue_year': a.issueYear,
        'issue_month': a.issueMonth,
        'notes': 'ورود از فایل ${a.fileName}',
      });
      int? oldDocId;
      int oldDoc() => oldDocId ??= () {
            final id = docs.ensureDocument(
                projectId: pid, title: '$title — قیمت‌های بازنگری قبلی', revision: '', docType: 'mto_previous');
            docs.updateDocument(id, {
              'issue_year': oldYear,
              'issue_month': oldMonth,
              'source_fx_eur': oldFx,
              'notes': 'ستون‌های Unit Price (Rials / FOB €) فایل ${a.fileName}',
            });
            return id;
          }();

      for (final s in a.sheets.where((s) => s.selected && s.categoryCode != null)) {
        final cat = catalog.categoryByCode(s.categoryCode!);
        if (cat == null) {
          rep.warnings.add('رده‌ی ${s.categoryCode} برای شیت ${s.name} پیدا نشد');
          continue;
        }
        final isPump = cat.code == 'PUMP';
        for (final it in s.items) {
          // تکراری: همان تگ در همان پروژه و رده
          final dup = db.scalar(
              "SELECT id FROM items WHERE category_id = ? AND project_id = ? AND tag = ? AND status = 'active'",
              [cat.id, pid, it.tag]);
          if (dup != null) {
            rep.skippedDuplicates++;
            continue;
          }
          final values = <String, Object?>{
            'tag': it.tag,
            'name': it.name,
            'quantity': it.quantity,
            'remarks': [
              if (it.scopeLines.isNotEmpty) it.scopeLines.join(' '),
              if (it.nonResponses.isNotEmpty) 'استعلام‌های بی‌نتیجه: ${it.nonResponses.join('، ')}',
            ].join(' | '),
          };
          if (isPump) {
            values['remarks'] = '${it.description}${values['remarks'] == '' ? '' : '\n${values['remarks']}'}';
          } else {
            values['mto_description'] = it.description;
            for (final e in it.specs.entries) {
              final key = catalog.ensureSpecField(cat.id, e.key);
              if (key.$2) rep.specFields++;
              values[key.$1] = e.value;
            }
          }
          final id = items.create(
            categoryId: cat.id,
            values: values,
            projectId: pid,
            reason: 'ورود MTO ${a.docRef ?? a.fileName} (${s.name} ردیف ${it.row})',
            batch: batch,
          );
          var hasPrimary = false;
          // ۱) قیمت مبنای مشاور
          String? goingCurEff;
          double? goingAmt;
          if (it.refCurrency == 'EUR' && it.goingEur != null) {
            (goingCurEff, goingAmt) = ('EUR', it.goingEur);
          } else if (it.refCurrency == 'IRR' && it.goingIrr != null) {
            (goingCurEff, goingAmt) = ('IRR', it.goingIrr);
          } else if (it.goingEur != null) {
            (goingCurEff, goingAmt) = ('EUR', it.goingEur);
          } else if (it.goingIrr != null) {
            (goingCurEff, goingAmt) = ('IRR', it.goingIrr);
          }
          if (goingAmt != null) {
            items.addObservation(id,
                documentId: docId,
                kind: 'estimate',
                primary: true,
                currency: goingCurEff,
                amount: goingAmt,
                costYear: s.goingYear ?? a.issueYear,
                costMonth: s.goingMonth,
                sourceLocation: '${s.name}!E${it.row}:F${it.row}',
                notes: 'قیمت مبنای مشاور (GOING UNIT PRICE ${s.goingLabel})');
            hasPrimary = true;
            rep.estimates++;
          }
          // ۲) استعلام‌ها
          for (final q in it.quotes) {
            final vid = docs.ensureVendor(q.vendor);
            items.addObservation(id,
                documentId: docId,
                vendorId: vid,
                kind: 'quote',
                primary: !hasPrimary,
                currency: q.currency,
                amount: q.amount,
                costYear: q.year ?? s.goingYear ?? a.issueYear,
                costYearText: q.year == null ? q.dateText : null,
                costMonth: q.month,
                sourceLocation: s.name,
                notes: [
                  if (q.formula != null) 'فرمول منبع: ${q.formula}',
                  if (q.dateFixed) 'تاریخ اصلاح‌شده (${q.dateText})',
                ].join(' · '));
            hasPrimary = true;
            rep.quotes++;
          }
          // ۳) قیمت بازنگری قبلی
          final oy = s.oldYear ?? oldYear;
          final om = s.oldYear == null ? oldMonth : s.oldMonth;
          for (final (amt, cur) in [(it.oldIrr, 'IRR'), (it.oldEur, 'EUR')]) {
            if (amt == null) continue;
            items.addObservation(id,
                documentId: oldDoc(),
                kind: 'estimate',
                primary: !hasPrimary,
                currency: cur,
                amount: amt,
                costYear: oy,
                costMonth: om,
                sourceLocation: s.name,
                notes: 'قیمت بازنگری قبلی (${s.oldLabel.isEmpty ? '$oy' : s.oldLabel})');
            hasPrimary = true;
            rep.estimates++;
          }
          rep.items++;
          rep.perCategory[cat.code] = (rep.perCategory[cat.code] ?? 0) + 1;
        }
      }
    });
    rep.vendors = (db.scalar('SELECT COUNT(*) FROM vendors') as int) - vendorsBefore;
    return rep;
  }

}
