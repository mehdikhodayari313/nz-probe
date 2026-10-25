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

  /// ضریب بالاسری ردیف در فایل (۰٫۳ = ۳۰٪)؛ قیمت ثبت‌شده خام (بدون بالاسری) است
  double? overhead;

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

  /// گزارش کنترل: جمع‌های شیت/جلد در برابر جمع اقلام خوانده‌شده، ضرایب (بیمه، بالاسری، …)، تاریخ فرض‌شده
  final List<String> notes = [];

  /// ضرایب یافته‌شده در شیت‌های ضریب (شیت، عنوان، مقدار)
  final List<(String, String, double)> coefficients = [];
  bool get supported => sheets.isNotEmpty;
  int get itemCount => sheets.fold(0, (s, x) => s + x.items.length);
  int get quoteCount => sheets.fold(0, (s, x) => s + x.quoteCount);
}

class MtoImportReport {
  int items = 0, quotes = 0, estimates = 0, vendors = 0, specFields = 0, skippedDuplicates = 0, weights = 0;

  /// دیسالترهایی که در بانک دیسالتر هستند و وارد نشدند (جزء skippedDuplicates)
  int skippedBankDuplicates = 0;

  /// بازنگری دیگر همان پروژه (همان رده و تگ): قیمت‌ها به همان قلم اضافه شد.
  /// [revisedNewer]: این فایل جدیدتر است → قیمت آن مبنای محاسبات شد؛ [revisedOlder]: قدیمی‌تر یا قلم بانک → فقط ثبت.
  int revisedNewer = 0, revisedOlder = 0;
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
  'MACHINER': 'SERVICES',
  'MOBILIZ': 'SERVICES',
  'MOB-DEMOB': 'SERVICES',
  'SALARY': 'SERVICES',
  'ACCOMOD': 'SERVICES',
  'ACCOMMOD': 'SERVICES',
  'CIVIL': 'SERVICES',
  'STRUCTURE': 'SERVICES',
  'تجهیز کارگاه': 'SERVICES',
  'ساختمان': 'SERVICES',
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
  'PIPE': 'PIPE_BULK',
  'FITTING': 'PIPE_BULK',
  'FITTINGS': 'PIPE_BULK',
  'EX': 'HEX',
  'HEX': 'HEX',
  'E': 'ELEC_EQ',
  'I': 'INST_EQ',
  'POWER': 'ELEC_EQ',
  'INSTRUMENT': 'INST_EQ',
  'INSTRUMENTS': 'INST_EQ',
  'CCR': 'INST_EQ',
};

/// همه‌ی رده‌هایی که نام شیت به آن‌ها اشاره دارد، به ترتیب جای واژه («H-EX & HEATER» ← HEX، HEATER)
List<String> sheetCategoryCandidates(String sheetName) {
  var u = sheetName.toUpperCase().trim();
  final found = <(int, String)>[];
  final keys = mtoSheetCategory.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    final i = u.indexOf(k);
    if (i < 0) continue;
    found.add((i, mtoSheetCategory[k]!));
    u = u.replaceRange(i, i + k.length, ' ' * k.length); // «AIR DRYER» یک بار، نه دوباره «DRYER»
  }
  // واژه‌های کوتاه فقط وقتی نام شیت چندتکه است («E&I&C»، «P.EL»)؛ «E» تنها در نام‌های دیگر نیست
  var pos = 0;
  for (final t in u.split(RegExp(r'[.\-\s_()&,/]+'))) {
    final i = u.indexOf(t, pos);
    if (i >= 0) pos = i + t.length;
    final c = _sheetTokens[t];
    if (c == null || (t.length == 1 && !RegExp(r'^[A-Z](\s*&\s*[A-Z])+$').hasMatch(sheetName.toUpperCase().trim().split(RegExp(r'\s')).first))) {
      continue;
    }
    found.add((i < 0 ? 999 : i, c));
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  final out = <String>[];
  for (final (_, c) in found) {
    if (!out.contains(c)) out.add(c);
  }
  return out;
}

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
    _controlReport(a, wb);
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

  static String _fmt(double v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0 && s[i - 1] != '-') b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  /// گزارش کنترل «هیچ قلمی جا نیفتاده»: جمع اقلام هر شیت در برابر جمع‌های خود شیت و ارجاع‌های جلد،
  /// و ضرایب شیت‌هایی مثل «Insurance» (ضریب بیمه/بالاسری/مالیات).
  static void _controlReport(MtoAnalysis a, XlsxWorkbook wb) {
    final sums = <String, double>{};
    final sumsNoQty = <String, double>{};
    final counts = <String, int>{};
    for (final s in a.sheets) {
      final src = s.source ?? s.name;
      for (final it in s.items) {
        final u = it.goingEur ?? it.goingUsd ?? it.goingIrr;
        if (u == null) continue;
        sums[src] = (sums[src] ?? 0) + u * (it.quantity ?? 1);
        sumsNoQty[src] = (sumsNoQty[src] ?? 0) + u;
        counts[src] = (counts[src] ?? 0) + 1;
      }
    }
    // ارجاع جلد/خلاصه به شیت‌ها: «='VESSELS(SEPARATOR)'!W18»
    final refRe = RegExp(r"^=\s*'?([^'!]+?)'?!\$?[A-Z]{1,3}\$?\d+\s*$");
    final covered = <String>{};
    for (final info in wb.sheets) {
      if (!a.skippedSheets.contains(info.name)) continue;
      final sh = wb.sheet(info.name);
      if (sh == null) continue;
      for (var r = 1; r <= sh.maxRow && r <= 200; r++) {
        for (final c in sh.rowCells(r)) {
          final f = c.formula;
          if (f == null) continue;
          final m = refRe.firstMatch(f.startsWith('=') ? f : '=$f');
          if (m == null) continue;
          final target = m.group(1)!;
          final key = sums.keys.where((k) => k.trim().toLowerCase() == target.trim().toLowerCase()).firstOrNull;
          final v = c.number;
          if (v == null) continue;
          final label = [
            for (final x in sh.rowCells(r))
              if (x.col < c.col && x.value is! double && x.text.trim().isNotEmpty) x.text.trim(),
          ].lastOrNull;
          final got = key == null ? null : sums[key]!;
          if (key != null) covered.add(key);
          final diff = got == null || v == 0 ? '' : ' (اختلاف ${((got - v) / v * 100).toStringAsFixed(0)}٪)';
          a.notes.add('«${info.name}»: ${label ?? target} = ${_fmt(v)} ← شیت «$target»؛ '
              '${got == null ? 'اقلامی از این شیت خوانده نشد' : 'جمع اقلام خوانده‌شده ${_fmt(got)} (${counts[key]} قلم)$diff'}');
        }
      }
    }
    // جمع‌های داخل خود شیت (سطر SUM/NOTES) برای شیت‌هایی که جلد ارجاع نداده
    for (final e in a.layouts.entries) {
      final got = sums[e.key];
      if (got == null || covered.contains(e.key) || e.value.sheetTotals.isEmpty) continue;
      final tots = e.value.sheetTotals.map((t) => t.$2).where((v) => v >= 0.01 * got).toSet().toList()..sort();
      if (tots.isEmpty) continue;
      final orphan = e.value.orphans.values.fold(0.0, (x, y) => x + y);
      final match = tots.any((v) => (v - got).abs() <= 0.01 * v || (orphan > 0 && (v - (got - orphan)).abs() <= 0.01 * v));
      // جمع × ضریب گرد (مثل «SUM × 1.2» یا «× 1.3»): ضریب شیت
      final factors = <String>{
        for (final v in tots)
          if (v / got >= 1.01 && v / got <= 3 && ((v / got) - ((v / got) * 100).round() / 100).abs() < 0.0005)
            ((v / got) * 100).round() / 100 == ((v / got) * 10).round() / 10
                ? ((v / got)).toStringAsFixed(1)
                : ((v / got)).toStringAsFixed(2),
      };
      a.notes.add('شیت «${e.key}»: جمع اقلام خوانده‌شده ${_fmt(got)} (${counts[e.key]} قلم)؛ '
          'جمع‌های درج‌شده در شیت: ${tots.map(_fmt).join('، ')}${match || factors.isNotEmpty ? ' ✓' : ' — بررسی شود'}'
          '${factors.isEmpty ? '' : ' (جمع × ضریب ${factors.join('، ')} هم در شیت آمده است)'}');
    }
    // جمع خود شیت قیمت‌ها را بدون ضرب در تعداد جمع زده (ستون قیمت شاید مبلغ کل ردیف باشد)
    for (final e in a.layouts.entries) {
      final g = sums[e.key], n = sumsNoQty[e.key];
      if (g == null || n == null || (g - n).abs() <= 0.01 * g) continue;
      final hit = e.value.sheetTotals.any((t) => (t.$2 - n).abs() <= 0.01 * n);
      if (hit) {
        a.notes.add('شیت «${e.key}»: جمع خود شیت (${_fmt(n)}) قیمت‌ها را بدون ضرب در تعداد جمع زده است؛ '
            'اگر قیمت این شیت مبلغ کل ردیف است (نه قیمت واحد)، تعداد اقلام چندتایی را در پیش‌نمایش ۱ کنید.');
      }
    }
    for (final e in a.layouts.entries) {
      for (final n in e.value.notes.where((n) => n.contains('بیرون از ستون شرح'))) {
        a.notes.add('شیت «${e.key}»: $n');
      }
    }
    // شیت ضرایب: ستونی با عنوان ضریب/بیمه/بالاسری/مالیات و مقادیر کوچک
    final coefRe = RegExp(r'coef|ضریب|factor|insurance|بیمه|overhead|بالاسری|سربار|contingenc|tax|مالیات|vat',
        caseSensitive: false);
    for (final info in wb.sheets) {
      if (!a.skippedSheets.contains(info.name)) continue;
      final sh = wb.sheet(info.name);
      if (sh == null) continue;
      for (var r = 1; r <= sh.maxRow && r <= 40; r++) {
        for (final h in sh.rowCells(r)) {
          if (h.value is double || !coefRe.hasMatch(h.text)) continue;
          final found = <String>[];
          for (var rr = r + 1; rr <= sh.maxRow && rr <= r + 80; rr++) {
            final v = sh.cell(rr, h.col)?.number;
            if (v == null || v < 0 || v > 5) continue;
            final labels = [
              for (final x in sh.rowCells(rr))
                if (x.col < h.col && x.value is! double && x.text.trim().isNotEmpty) x.text.trim(),
            ];
            if (labels.isEmpty) continue;
            final label = labels.length > 1 ? '${labels.first} (${labels.sublist(1).join('، ')})' : labels.first;
            a.coefficients.add((info.name, label, v));
            found.add('$label: ${v.toStringAsFixed(4).replaceFirst(RegExp(r'\.?0+$'), '')}');
          }
          if (found.isNotEmpty) a.notes.add('ضرایب شیت «${info.name}» (${h.text.trim()}): ${found.join('؛ ')}');
        }
      }
    }
    // ضریب بالاسری ردیف‌ها
    final ovs = <String, Set<String>>{};
    for (final s in a.sheets) {
      for (final it in s.items) {
        if (it.overhead == null) continue;
        (ovs[s.source ?? s.name] ??= {}).add('${(it.overhead! * 100).toStringAsFixed(0)}٪');
      }
    }
    if (ovs.isNotEmpty) {
      a.notes.add('ضریب بالاسری ردیف‌ها (جدا ثبت شد و به قیمت ثبت‌شده اضافه نشده است): '
          '${ovs.entries.map((e) => '${e.key.trim()} ${e.value.join('/')}').join('؛ ')}');
    }
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
    DateTime? best, exact;
    String? bestRev;
    for (final info in wb.sheets.take(3)) {
      final sh = wb.sheet(info.name);
      if (sh == null) continue;
      for (var r = 1; r <= sh.maxRow && r <= 120; r++) {
        final cells = sh.rowCells(r);
        if (a.revision == null) {
          for (final c in cells) {
            final m = RegExp(r'^REV(?:ISION)?\.?\s*[:：]?\s*([A-Z]|\d{1,2})$', caseSensitive: false).firstMatch(c.text.trim());
            if (m != null) a.revision = m.group(1)!.toUpperCase();
          }
        }
        if (cells.isEmpty ||
            !RegExp(r'^(R(ev)?\.?\s*\d{1,2}|(R(ev)?\.?\s*)?[A-Z])$', caseSensitive: false).hasMatch(cells.first.text.trim())) {
          continue;
        }
        final rev = cells.first.text.trim().toUpperCase().replaceFirst(RegExp(r'^REV\.?\s*'), '');
        for (final c in cells.skip(1)) {
          DateTime? d;
          final m = RegExp(r'\b(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[A-Z]*\.?\s*,?\s*(\d{4})', caseSensitive: false).firstMatch(c.text);
          if (m != null) d = DateTime(int.parse(m.group(2)!), months[m.group(1)!.toUpperCase()]!, 15);
          final v = c.value;
          if (d == null && v is double && v > 30000 && v < 80000) d = DateTime(1899, 12, 30).add(Duration(days: v.floor()));
          if (d == null) continue;
          if (a.revision != null && (rev == a.revision || rev == 'R${a.revision}' || 'R$rev' == a.revision)) {
            exact = d;
            break;
          }
          if (best == null || d.isAfter(best)) {
            best = d;
            bestRev = rev;
          }
        }
      }
    }
    if (exact != null) best = exact;
    if (best == null) return;
    if (exact == null && a.revision != null && bestRev != null) {
      a.notes.add('تاریخ بازنگری ${a.revision} در جلد نیامده؛ تاریخ آخرین بازنگری دارای تاریخ ($bestRev) '
          'مبنای سال قیمت گرفته شد — بررسی شود.');
    }
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
    // سندی که پیش‌تر وارد شده ولی هیچ قلم و قیمتی ندارد (مثلاً بازنگری‌ای که همه‌ی اقلامش تکراری حساب شد) دوباره وارد می‌شود
    if (pidExisting != null &&
        db.scalar(
                'SELECT 1 FROM documents d WHERE d.project_id = ? AND d.title = ? AND d.doc_type = ? AND (EXISTS '
                '(SELECT 1 FROM price_obs o WHERE o.document_id = d.id) OR EXISTS (SELECT 1 FROM items i WHERE i.source_document_id = d.id))',
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
        'notes': ['ورود از فایل ${a.fileName}', ...a.notes].join('\n'),
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
          int? revise; // قلم موجود همین پروژه از بازنگری دیگر
          var newer = true; // این فایل جدیدتر است → قیمتش مبنا می‌شود
          // تگ تکراری در همین فایل (مثل شماره‌ردیف تکراری): با پسوند حفظ می‌شود، نه حذف
          final key = '${cat.id}|${it.tag}';
          final repeated = seenTags.contains(key);
          if (repeated) {
            var n = 2;
            while (seenTags.contains('${cat.id}|${it.tag} ($n)')) {
              n++;
            }
            it.tag = '${it.tag} ($n)';
          }
          // تکراری: همان تگ در همان پروژه و رده از ورود قبلی (مثلاً پمپ‌های v8) یا بازنگری دیگر همین MTO
          final dup = db.scalar(
              "SELECT id FROM items WHERE category_id = ? AND project_id = ? AND tag = ? AND status = 'active'",
              [cat.id, pid, it.tag]) as int?;
          if (dup != null) {
            final r = _revisionOf(dup, docId, a);
            if (r == null) {
              rep.skippedDuplicates++;
              continue;
            }
            (revise, newer) = (dup, r.$1);
            if (r.$2 != null) rep.warnings.add('${it.tag}: ${r.$2}');
          }
          // دیسالتر: بانک دیسالتر مرجع است؛ همان قلم (پایه‌ی تگ و قیمت یکسان) دوباره وارد نمی‌شود
          if (!repeated &&
              cat.code == 'DESALTER' &&
              findDesalterBankDuplicate(db, cat.id, it.tag, [it.goingEur, it.goingIrr, it.goingUsd]) != null) {
            rep.skippedDuplicates++;
            rep.skippedBankDuplicates++;
            continue;
          }
          seenTags.add('${cat.id}|${it.tag}');
          final meta = <String, FieldMeta>{};
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
            // هد از اختلاف فشار وقتی منبع هد ندارد (قاعده‌ی بانک v8: ΔP × 10.2، SG = 1، مقدار استنباطی)
            final dp = values['diff_pressure_bar'];
            if (values['diff_head_m'] == null && dp is double && dp > 0) {
              values['diff_head_m'] = double.parse((dp * 10.2).toStringAsFixed(1));
              meta['diff_head_m'] = FieldMeta('inferred',
                  'INFERRED – ${s.name} ردیف ${it.row}: Differential Pressure $dp bar → head ≈ $dp×10.2 m (SG 1.0 assumed)');
            }
            // مشخصه‌هایی که فیلد قالب پمپ ندارند هم ثبت می‌شوند (نه فقط در متن شرح)
            for (final e in pumpSpecLeftovers(it.specs)) {
              if (RegExp(r'^(section|group|price basis|overhead|unit price in source|quantity in source)\b', caseSensitive: false)
                  .hasMatch(e.key)) {
                continue;
              }
              final key = catalog.ensureSpecField(cat.id, e.key);
              if (key.$2) rep.specFields++;
              values.putIfAbsent(key.$1, () => e.value);
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
              // وزن خالی (دیسالتر هم فیلد وزن دارد، هرچند در روش بانک دیسالتر ضریب وزن ندارد)
              final wk = profile.weightKey ?? (profile.field(weightFieldKey) != null ? weightFieldKey : null);
              final w = it.weightKg ?? a.weights[normTag(it.tag)];
              if (wk != null && w != null && w > 0) {
                values.putIfAbsent(wk, () => w);
                rep.weights++;
              }
            }
            for (final e in (profile == null ? it.specs.entries.toList() : profile.leftovers(it.specs))) {
              final key = catalog.ensureSpecField(cat.id, e.key);
              if (key.$2) rep.specFields++;
              values[key.$1] = e.value;
            }
          }
          final int id;
          if (revise != null) {
            id = revise;
            _fillFromRevision(id, values, meta, it, '${a.docRef ?? a.fileName} (${s.name} ردیف ${it.row})', rep);
            newer ? rep.revisedNewer++ : rep.revisedOlder++;
          } else {
            id = items.create(
              categoryId: cat.id,
              values: values,
              meta: meta,
              projectId: pid,
              sourceDocumentId: docId,
              reason: 'ورود MTO ${a.docRef ?? a.fileName} (${s.name} ردیف ${it.row})',
              batch: batch,
            );
          }
          // قیمت بازنگری قدیمی‌تر فقط ثبت می‌شود و مبنا نمی‌شود
          var hasPrimary = !newer;
          final olderNote = newer ? '' : ' — بازنگری قدیمی‌تر یا قلم بانک (مبنا نیست)';
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
                primary: newer,
                currency: goingCurEff,
                amount: goingAmt,
                costYear: s.goingYear ?? goingYear ?? a.issueYear,
                costMonth: s.goingYear != null ? s.goingMonth : (goingYear != null ? goingMonth : a.issueMonth),
                sourceLocation: s.layout == null ? '${s.name}!E${it.row}:F${it.row}' : '${s.name} ردیف ${it.row}',
                notes: (s.layout == null
                        ? 'قیمت مبنای مشاور (GOING UNIT PRICE ${s.goingLabel})'
                        : 'قیمت مبنا/برآورد MTO${s.goingLabel.isEmpty ? '' : ' (${s.goingLabel})'}') +
                    olderNote);
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
                primary: !hasPrimary && revise == null,
                currency: cur,
                amount: amt,
                costYear: oy,
                costMonth: om,
                sourceLocation: s.name,
                notes: 'قیمت بازنگری قبلی (${s.oldLabel.isEmpty ? '$oy' : s.oldLabel})');
            hasPrimary = true;
            rep.estimates++;
          }
          if (revise != null) continue;
          rep.items++;
          rep.perCategory[cat.code] = (rep.perCategory[cat.code] ?? 0) + 1;
        }
      }
    });
    rep.vendors = (db.scalar('SELECT COUNT(*) FROM vendors') as int) - vendorsBefore;
    return rep;
  }

  /// قلم موجود [itemId] (همان پروژه، رده و تگ) و این فایل: (این فایل جدیدتر است؟, یادداشت) یا null = همان سند (تکراری).
  /// جدیدتر = تاریخ صدور دیرتر یا برابر؛ اگر تاریخ یکی معلوم نیست، فایلی که بعد وارد می‌شود جدیدتر فرض و گزارش می‌شود.
  /// قلم بانک قیمت (مرجع، تصمیم کاربر) با MTO جایگزین نمی‌شود.
  (bool, String?)? _revisionOf(int itemId, int docId, MtoAnalysis a) {
    final p = db.queryOne(
        'SELECT o.document_id, d.doc_type, d.issue_year, d.issue_month, i.legacy_ref FROM items i '
        'LEFT JOIN price_obs o ON o.item_id = i.id AND o.is_primary = 1 LEFT JOIN documents d ON d.id = o.document_id '
        'WHERE i.id = ?',
        [itemId]);
    if (p == null) return null;
    final srcDoc = db.scalar('SELECT source_document_id FROM items WHERE id = ?', [itemId]) as int?;
    if (p['document_id'] == docId || (p['document_id'] == null && srcDoc == docId)) return null;
    if (p['legacy_ref'] != null || p['doc_type'] == 'price_bank' || p['doc_type'] == 'v8') {
      return (false, 'قلم بانک قیمت است (مرجع)؛ قیمت این فایل فقط ثبت شد');
    }
    final oy = p['issue_year'] as int?, om = p['issue_month'] as int?;
    final ny = a.issueYear, nm = a.issueMonth;
    if (oy == null || ny == null) {
      return p['document_id'] == null
          ? (true, null)
          : (true, 'تاریخ بازنگری قبلی یا این فایل معلوم نیست؛ این فایل جدیدتر فرض شد و قیمتش مبنا شد');
    }
    return ((ny * 12 + (nm ?? 0)) >= (oy * 12 + (om ?? 0)), null);
  }

  /// بازنگری دیگر یک قلم: فقط فیلدهای خالی قلم پر می‌شود (مقدار موجود عوض نمی‌شود)؛ اختلاف تعداد گزارش می‌شود.
  void _fillFromRevision(int id, Map<String, Object?> values, Map<String, FieldMeta> meta, MtoItem it, String src,
      MtoImportReport rep) {
    final cur = items.get(id)!;
    final fill = <String, Object?>{};
    for (final e in values.entries) {
      if (const {'tag', 'name', 'quantity', 'remarks'}.contains(e.key)) continue;
      final v = e.value;
      if (v == null || (v is String && v.trim().isEmpty)) continue;
      final old = cur.valueOf(e.key);
      if (old == null || (old is String && old.trim().isEmpty)) fill[e.key] = v;
    }
    if (fill.isNotEmpty) {
      items.update(id, fill, reason: 'تکمیل از بازنگری $src');
      for (final k in fill.keys) {
        final m = meta[k];
        if (m != null) items.setMeta(id, k, m);
      }
    }
    final q = it.quantity;
    if (q != null && cur.quantity != null && (q - cur.quantity!).abs() > 1e-9) {
      rep.warnings.add('${it.tag}: تعداد در این فایل ${_n(q)} و در قلم موجود ${_n(cur.quantity!)} است؛ تعداد عوض نشد');
    }
  }

  static String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

}
