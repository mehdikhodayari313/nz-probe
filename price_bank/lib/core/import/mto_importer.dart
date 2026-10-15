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

import '../catalog/profiles.dart';
import 'desalter_importer.dart' show findDesalterBankDuplicate;
import 'mto_generic.dart';
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
  String tag;
  String description;
  String get name => description.split('\n').first.trim();
  double? quantity;
  String? refCurrency;
  double? goingIrr, goingEur, goingUsd;
  double? oldIrr, oldEur, oldUsd;

  /// وزن (کیلوگرم): از واحد Kg/Ton یا ستون وزن
  double? weightKg;

  /// رده خودکار حدس زده شده (نه انتخاب کاربر)
  bool autoCategory = true;
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

  /// نام نمایشی (وقتی یک شیت به چند رده تقسیم شده: «شیت › رده»)
  String? label;
  String get display => label ?? name;

  /// شیت منبع و قالب ستون‌ها (فقط قالب‌های عمومی؛ برای اصلاح نقش ستون‌ها در پیش‌نمایش)
  String? source;
  MtoLayout? layout;
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

  /// کتاب کار (برای خواندن دوباره‌ی شیت پس از اصلاح نقش ستون‌ها)
  XlsxWorkbook? workbook;

  /// قالب ستون‌های شیت‌های غیرپازنانی: نام شیت ← قالب
  final Map<String, MtoLayout> layouts = {};

  /// شیت‌هایی که جدول اقلام در آن‌ها پیدا نشد (برای تعریف دستی سطر عنوان)
  List<String> get unreadSheets => skippedSheets;

  /// وزن تجهیزات از شیت‌های نصب و اجرا (تگ ← کیلوگرم)
  final Map<String, double> weights = {};
  final List<String> installSheets = [];

  /// رده‌ی انتخابی کاربر برای هر قلم («شیت#ردیف» ← کد رده)
  final Map<String, String?> itemCategory = {};

  /// جابه‌جایی یک قلم به رده‌ی دیگر (قالب‌های عمومی)
  void moveItem(MtoSheet from, MtoItem it, String? code) {
    if (from.source == null) return;
    itemCategory['${from.source}#${it.row}'] = code;
    MtoImporter.relayout(this, from.source!);
  }
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
  int items = 0, quotes = 0, estimates = 0, vendors = 0, specFields = 0, skippedDuplicates = 0, weights = 0;

  /// دیسالترهایی که در بانک دیسالتر هستند و وارد نشدند (جزء skippedDuplicates)
  int skippedBankDuplicates = 0;
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
  'STACK': 'FLARE',
  'R.O': 'WATER_TREAT',
  'STRIPP': 'MISC_PKG',
  'HVAC': 'HVAC',
  'LAB': 'LAB',
};

/// نام کوتاه شیت‌های PEP (مثل «P.EL»، «P.IN»): بخش نام ← رده
const _sheetTokens = <String, String>{
  'EL': 'ELEC_EQ',
  'ELEC': 'ELEC_EQ',
  'IN': 'INST_EQ',
  'INST': 'INST_EQ',
  'PI': 'PIPE_BULK',
  'PL': 'PIPE_BULK',
  'PIPING': 'PIPE_BULK',
  'LAB': 'LAB',
  'HVAC': 'HVAC',
  'VALVE': 'VALVE',
  'VALVES': 'VALVE',
};

String? suggestCategory(String sheetName) {
  final u = sheetName.toUpperCase().trim();
  // طولانی‌ترین کلید اول (مثلاً «AIR DRYER» قبل از «DRYER»)
  final keys = mtoSheetCategory.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    if (u.startsWith(k) || u.contains(k)) return mtoSheetCategory[k];
  }
  for (final t in u.split(RegExp(r'[.\-\s_()&,]+'))) {
    if (_sheetTokens[t] case final c?) return c;
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
    final a = MtoAnalysis(fileName)..workbook = wb;
    final fm = RegExp(r'(1[34]\d\d)(\d\d)(\d\d)').firstMatch(fileName);
    if (fm != null) {
      a.issueYear = int.parse(fm.group(1)!);
      final m = int.parse(fm.group(2)!);
      if (m >= 1 && m <= 12) a.issueMonth = m;
    }
    (MtoItem, MtoLayout)? lastGeneric;
    for (final info in wb.sheets) {
      if (info.hidden) continue;
      final sh = wb.sheet(info.name);
      if (sh == null) continue;
      final hdr = _headerRow(sh);
      if (hdr == null) {
        // قالب‌های دیگر: نوع شیت، سپس تشخیص خودکار سطر عنوان و نقش ستون‌ها
        final kind = MtoGeneric.kindOf(sh);
        if (kind == MtoSheetKind.install) {
          final w = MtoGeneric.weightsFrom(sh);
          if (w.isNotEmpty) a.installSheets.add(info.name);
          for (final e in w.entries) {
            a.weights.putIfAbsent(e.key, () => e.value);
          }
          a.skippedSheets.add(info.name);
          continue;
        }
        if (kind == MtoSheetKind.skip) {
          _docInfo(a, sh, 40);
          a.skippedSheets.add(info.name);
          continue;
        }
        final l = MtoGeneric.detect(sh);
        // صفحه‌ی ادامه («… (Cont'd)»): سطرهای شرح به آخرین قلم صفحه‌ی قبل اضافه می‌شود
        final lg = lastGeneric;
        if (l == null && lg != null && MtoGeneric.appendContinuation(sh, lg.$1, lg.$2)) {
          a.skippedSheets.add(info.name);
          continue;
        }
        final groups =
            l == null ? const <MtoSheet>[] : MtoGeneric.parse(sh, l, defaultYear: a.issueYear, overrides: a.itemCategory);
        if (l == null || groups.isEmpty || groups.every((g) => g.items.isEmpty)) {
          a.skippedSheets.add(info.name);
          continue;
        }
        _docInfo(a, sh, l.headerRow);
        a.layouts[info.name] = l;
        a.sheets.addAll(groups);
        final lastIt = groups.expand((g) => g.items).fold<MtoItem?>(null, (m, i) => m == null || i.row > m.row ? i : m);
        if (lastIt != null) lastGeneric = (lastIt, l);
        continue;
      }
      _docInfo(a, sh, hdr);
      final s = _parseSheet(sh, hdr);
      if (s.items.isEmpty) {
        a.skippedSheets.add(info.name);
        continue;
      }
      a.sheets.add(s);
    }
    if (a.sheets.isNotEmpty) a.format = a.layouts.isEmpty ? 'mto_quote_blocks' : 'generic';
    a.suggestedProject = suggestProjectName(a.projectTitle);
    _fileInfo(a, wb);
    // سال پیش‌فرض قیمت‌های بدون سال (تاریخ سند) برای گروه‌هایی که پیش از یافتن تاریخ خوانده شدند
    for (final s in a.sheets) {
      if (s.layout != null && s.goingYear == null) s.goingYear = s.layout!.sheetYear ?? a.issueYear;
      for (final it in s.items) {
        for (final q in it.quotes) {
          q.year ??= s.goingYear;
        }
      }
    }
    return a;
  }

  /// شماره‌ی سند و عنوان پروژه از سطرهای بالای جدول (هر ستونی از ۱ تا ۶)
  static void _docInfo(MtoAnalysis a, XlsxSheet sh, int hdr) {
    for (var r = 1; r < hdr && r <= sh.maxRow; r++) {
      for (var c = 1; c <= 60 && c <= sh.maxCol; c++) {
        final t = sh.text(r, c);
        if (t.isEmpty) continue;
        final l = t.toLowerCase();
        if (a.docRef == null &&
            RegExp(r'^(doc\.?\s*(ref|no)|document\s*(no|number|ref)|شماره\s*(سند|مدرک))', caseSensitive: false).hasMatch(l)) {
          var v = t.replaceFirst(
              RegExp(r'^(doc\.?\s*(ref|no)\.?|document\s*(no|number|ref)\.?|شماره\s*(سند|مدرک))\s*(no\.?)?\s*[:：]?\s*',
                  caseSensitive: false),
              '');
          v = v.trim();
          if (v.isEmpty && c + 1 <= sh.maxCol) v = sh.text(r, c + 1);
          if (v.isNotEmpty) {
            a.docRef = v;
            a.revision = RegExp(r'-(R\d{1,3})\s*$').firstMatch(v)?.group(1);
          }
        }
        if (a.projectTitle == null && RegExp(r'^(project\s*(title|name)?|نام\s*پروژه|عنوان\s*پروژه|پروژه)\s*[:：]', caseSensitive: false).hasMatch(l)) {
          a.projectTitle = t.substring(t.indexOf(RegExp(r'[:：]')) + 1).trim();
        }
        // «… for Construct New KOOPAL (ASMARI & BANGESTAN) Desalting Unit» یا «… نمک‌زدایی مارون ۳ بنگستان»
        if (a.projectTitle == null &&
            RegExp(r'(construct\w*|revamp\w*|upgrad\w*)\s.*desalt', caseSensitive: false).hasMatch(t.replaceAll('\n', ' '))) {
          a.projectTitle = t.replaceAll('\n', ' ').trim();
        }
        if (a.projectTitle == null && RegExp(r'نمک\s*\u200c?\s*زدایی\s+\S').hasMatch(t) && t.length < 120) {
          a.projectTitle = t.trim();
        }
      }
    }
  }

  /// خواندن دوباره‌ی یک شیت پس از اصلاح نقش ستون‌ها (یا تعریف دستی سطر عنوان) در پیش‌نمایش.
  static void relayout(MtoAnalysis a, String sheet, {int? headerRow}) {
    final sh = a.workbook?.sheet(sheet);
    if (sh == null) return;
    var l = a.layouts[sheet];
    if (headerRow != null || l == null) {
      l = MtoGeneric.layoutAt(sh, headerRow ?? 1);
      a.layouts[sheet] = l;
    }
    // انتخاب‌های کاربر (تیک و رده) برای همان رده‌ها حفظ می‌شود
    final prev = {for (final s in a.sheets.where((s) => s.source == sheet)) s.categoryCode: s.selected};
    final idx = a.sheets.indexWhere((s) => s.source == sheet);
    a.sheets.removeWhere((s) => s.source == sheet);
    final groups = MtoGeneric.parse(sh, l, defaultYear: a.issueYear, overrides: a.itemCategory);
    for (final g in groups) {
      g.selected = prev[g.categoryCode] ?? g.selected;
    }
    a.sheets.insertAll(idx < 0 ? a.sheets.length : idx, groups);
    a.skippedSheets.remove(sheet);
    if (groups.isEmpty && !a.skippedSheets.contains(sheet)) a.skippedSheets.add(sheet);
    if (a.sheets.isNotEmpty && a.format == 'unknown') a.format = 'generic';
  }

  /// اطلاعات از نام فایل و جدول بازنگری جلد: شماره‌ی سند، بازنگری، تاریخ، نام پروژه
  static void _fileInfo(MtoAnalysis a, XlsxWorkbook wb) {
    final f = a.fileName;
    final ref = RegExp(r'(\d{3,6}-[A-Z0-9]{2,6}-[A-Z]{2}-[A-Z]{2}-\d{2,4})[ _-]?(R\d{1,2})?', caseSensitive: false).firstMatch(f);
    if (a.docRef == null && ref != null) {
      a.docRef = ref.group(2) == null ? ref.group(1) : '${ref.group(1)}-${ref.group(2)}';
      a.revision ??= ref.group(2)?.toUpperCase();
    }
    if (a.issueYear == null) {
      final ym = RegExp(r'(?<!\d)(1[34]\d\d)(0[1-9]|1[0-2])(?!\d)').firstMatch(f);
      if (ym != null) {
        a.issueYear = int.parse(ym.group(1)!);
        a.issueMonth = int.parse(ym.group(2)!);
      }
    }
    if (a.issueYear == null) _revisionDate(a, wb);
    if (a.suggestedProject == null) {
      // «PEP-Rev.140205 … Gachsaran_4» ← «Gachsaran 4»
      const stop = {'PEP', 'REV', 'MTO', 'AND', 'COST', 'ESTIMATION', 'REPORT', 'XLSX', 'XLS', 'BASIC', 'FEED', 'RE', 'ME', 'R'};
      final words = [
        for (final m in RegExp(r'[A-Za-z]{3,}(?:[ _-]?\d{1,2}(?!\d))?').allMatches(f.replaceAll(RegExp(r'\.xls[xm]?$'), '')))
          m.group(0)!.replaceAll('_', ' '),
      ].where((w) => !stop.contains(w.split(RegExp(r'[ _-]')).first.toUpperCase()) && !RegExp(r'^R\d').hasMatch(w)).toList();
      if (words.isNotEmpty) {
        final w = words.first;
        a.suggestedProject = w == w.toUpperCase() && w.length > 4 ? '${w[0]}${w.substring(1).toLowerCase()}' : w;
      }
    }
  }

  /// تاریخ بازنگری سند از جدول «REV. / DATE» برگه‌ی جلد (مثل R03 · JAN. 2016 ← ۱۳۹۴/۱۰)
  static void _revisionDate(MtoAnalysis a, XlsxWorkbook wb) {
    const months = {'JAN': 1, 'FEB': 2, 'MAR': 3, 'APR': 4, 'MAY': 5, 'JUN': 6, 'JUL': 7, 'AUG': 8, 'SEP': 9, 'OCT': 10, 'NOV': 11, 'DEC': 12};
    DateTime? best;
    for (final info in wb.sheets.take(3)) {
      final sh = wb.sheet(info.name);
      if (sh == null) continue;
      for (var r = 1; r <= sh.maxRow && r <= 120; r++) {
        final cells = sh.rowCells(r);
        if (cells.isEmpty || !RegExp(r'^R(ev)?\.?\s*\d{1,2}$', caseSensitive: false).hasMatch(cells.first.text.trim())) continue;
        final rev = cells.first.text.trim().toUpperCase();
        for (final c in cells.skip(1)) {
          DateTime? d;
          final m = RegExp(r'\b(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[A-Z]*\.?\s*,?\s*(\d{4})', caseSensitive: false).firstMatch(c.text);
          if (m != null) d = DateTime(int.parse(m.group(2)!), months[m.group(1)!.toUpperCase()]!, 15);
          final v = c.value;
          if (d == null && v is double && v > 30000 && v < 80000) d = DateTime(1899, 12, 30).add(Duration(days: v.floor()));
          if (d == null) continue;
          if (a.revision != null && rev == a.revision) {
            best = d;
            break;
          }
          if (a.revision == null && (best == null || d.isAfter(best))) best = d;
        }
      }
    }
    if (best == null) return;
    final j = Gregorian(best.year, best.month, best.day).toJalali();
    a.issueYear = j.year;
    a.issueMonth = j.month;
  }

  /// «Revamping of Pazanan II Desalting Unit» ← «Pazanan 2»
  static String? suggestProjectName(String? title) {
    if (title == null || title.isEmpty) return null;
    final fa = RegExp(r'نمک\s*\u200c?\s*زدایی\s+(.{2,40})$').firstMatch(title.trim());
    if (fa != null) return fa.group(1)!.trim();
    final m = RegExp(r'(?:for\s+)?(?:construct\w*|revamp\w*|upgrad\w*)\s+(?:of\s+)?(?:new\s+)?(.+?)\s+(?:desalt|dehydrat)',
            caseSensitive: false)
        .firstMatch(title.replaceAll('\n', ' '));
    var t = m != null
        ? m.group(1)!
        : title.replaceFirst(RegExp(r'^(Revamping|Reconstruction|Construction|Upgrading)\s+of\s+', caseSensitive: false), '');
    // «KOOPAL (ASMARI & BANGESTAN)» ← «Koopal (Asmari & Bangestan)»
    if (t == t.toUpperCase()) {
      t = t.toLowerCase().replaceAllMapped(RegExp(r'(^|[\s(])([a-z])'), (x) => '${x.group(1)}${x.group(2)!.toUpperCase()}');
    }
    t = t.replaceFirst(RegExp(r'\s+(Desalt|Desalting|Dehydration)\b.*$', caseSensitive: false), '').trim();
    const roman = {'I': '1', 'II': '2', 'III': '3', 'IV': '4', 'V': '5'};
    t = t.replaceAllMapped(RegExp(r'\b(IV|V|I{1,3})\b'), (x) => roman[x.group(1)] ?? x.group(1)!);
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
          applyQuoteDate(q, dateCell, it, sh.name);
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

  static void _parseDescription(MtoItem it) {
    final d = parseMtoDescription(it.description);
    it.specs.addAll(d.specs);
    it.scopeLines.addAll(d.scope);
  }

  static void applyQuoteDate(MtoQuote q, XlsxCell? c, MtoItem it, String sheet) {
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
    int? goingYear,
    int? goingMonth,
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

      final seenTags = <String>{};
      for (final s in a.sheets.where((s) => s.selected && s.categoryCode != null)) {
        final cat = catalog.categoryByCode(s.categoryCode!);
        if (cat == null) {
          rep.warnings.add('رده‌ی ${s.categoryCode} برای شیت ${s.name} پیدا نشد');
          continue;
        }
        final isPump = cat.code == 'PUMP';
        for (final it in s.items) {
          // تگ تکراری در همین فایل (مثل شماره‌ردیف تکراری): با پسوند حفظ می‌شود، نه حذف
          final key = '${cat.id}|${it.tag}';
          if (seenTags.contains(key)) {
            var n = 2;
            while (seenTags.contains('${cat.id}|${it.tag} ($n)')) {
              n++;
            }
            it.tag = '${it.tag} ($n)';
          } else {
            // تکراری: همان تگ در همان پروژه و رده از ورود قبلی (مثلاً پمپ‌های v8)
            final dup = db.scalar(
                "SELECT id FROM items WHERE category_id = ? AND project_id = ? AND tag = ? AND status = 'active'",
                [cat.id, pid, it.tag]);
            if (dup != null) {
              rep.skippedDuplicates++;
              continue;
            }
            // دیسالتر: بانک دیسالتر مرجع است؛ همان قلم (پایه‌ی تگ و قیمت یکسان) دوباره وارد نمی‌شود
            if (cat.code == 'DESALTER' &&
                findDesalterBankDuplicate(db, cat.id, it.tag, [it.goingEur, it.goingIrr, it.goingUsd]) != null) {
              rep.skippedDuplicates++;
              rep.skippedBankDuplicates++;
              continue;
            }
          }
          seenTags.add('${cat.id}|${it.tag}');
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
            // دبی، هد، فشار رانش، کلاس متریال، استاندارد، … در فیلدهای قالب پمپ
            for (final e in {...extractFreeSpecs(it.description, 'PUMP'), ...extractPumpSpecs(it.specs, it.name)}.entries) {
              values.putIfAbsent(e.key, () => e.value);
            }
          } else {
            values['mto_description'] = it.description;
            final profile = equipmentProfiles[cat.code];
            if (profile != null) {
              // فیلدهای ساختاریافته‌ی قالب رده (ابعاد، فشار، جنس، …)
              values.addAll(profile.extract(it.specs, context: '${it.name}\n${s.title}', scope: it.scopeLines));
              // مشخصات متن آزاد («536 m3/hr, 19.5 bar D.P., ID=5300 mm») برای فیلدهای هنوز خالی
              for (final e in extractFreeSpecs(it.description, cat.code).entries) {
                if (profile.field(e.key) != null) values.putIfAbsent(e.key, () => e.value);
              }
              // وزن: از MTO (واحد Kg/Ton) یا شیت‌های نصب و اجرا (همان تگ)
              final wk = profile.weightKey;
              final w = it.weightKg ?? a.weights[normTag(it.tag)];
              if (wk != null && w != null && w > 0) {
                values.putIfAbsent(wk, () => w);
                rep.weights++;
              }
            }
            for (final e in it.specs.entries) {
              if (profile != null && profile.maps(e.key)) continue;
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
          } else if (it.refCurrency == 'USD' && it.goingUsd != null) {
            (goingCurEff, goingAmt) = ('USD', it.goingUsd);
          } else if (it.goingEur != null) {
            (goingCurEff, goingAmt) = ('EUR', it.goingEur);
          } else if (it.goingIrr != null) {
            (goingCurEff, goingAmt) = ('IRR', it.goingIrr);
          } else if (it.goingUsd != null) {
            (goingCurEff, goingAmt) = ('USD', it.goingUsd);
          }
          if (goingAmt != null) {
            items.addObservation(id,
                documentId: docId,
                kind: 'estimate',
                primary: true,
                currency: goingCurEff,
                amount: goingAmt,
                costYear: s.goingYear ?? goingYear ?? a.issueYear,
                costMonth: s.goingYear != null ? s.goingMonth : (goingYear != null ? goingMonth : a.issueMonth),
                sourceLocation: s.layout == null ? '${s.name}!E${it.row}:F${it.row}' : '${s.name} ردیف ${it.row}',
                notes: s.layout == null
                    ? 'قیمت مبنای مشاور (GOING UNIT PRICE ${s.goingLabel})'
                    : 'قیمت مبنا/برآورد MTO${s.goingLabel.isEmpty ? '' : ' (${s.goingLabel})'}');
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
                costYear: q.year ?? s.goingYear ?? goingYear ?? a.issueYear,
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
          for (final (amt, cur) in [(it.oldIrr, 'IRR'), (it.oldEur, 'EUR'), (it.oldUsd, 'USD')]) {
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
