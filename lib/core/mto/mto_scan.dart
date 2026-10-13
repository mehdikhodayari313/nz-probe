// تشخیص قالب فایل‌های MTO/برآورد و شمارش سریع محتوای آن‌ها.
//
// در برنامه‌ی اصلی، هر قالب یک «پروفایل» کامل با استخراج مشخصات فنی و قیمت‌ها دارد.
// در این برنامه‌ی آزمایشی فقط قالب تشخیص داده می‌شود، اقلام و قیمت‌ها شمرده می‌شوند
// و ایرادهای رایج (تاریخ نامعتبر، قیمت فرمولی، عدد متنی) گزارش می‌شوند.

import '../xlsx/xlsx_reader.dart';

enum MtoFormat {
  consultantWorking('MTO کاری مشاور (با بلوک‌های استعلام)'),
  consultantReport('گزارش نهایی MTO مشاور (قالب چاپی)'),
  ownerPep('برآورد کارفرمایی کل پروژه (PEP)'),
  projectSummary('خلاصه‌ی برآورد و تعدیل پروژه'),
  unknown('قالب ناشناخته');

  const MtoFormat(this.title);
  final String title;
}

enum IssueLevel { info, warning, error }

class ScanIssue {
  const ScanIssue(this.level, this.location, this.message);
  final IssueLevel level;
  final String location; // مثل "VESSELS!AB8"
  final String message;
}

class ScannedItem {
  const ScannedItem({
    required this.sheet,
    required this.row,
    required this.tag,
    required this.name,
    this.qty,
    this.priceCount = 0,
  });
  final String sheet;
  final int row;
  final String tag;
  final String name;
  final double? qty;
  final int priceCount;
}

class MtoScanResult {
  MtoScanResult({
    required this.format,
    required this.evidence,
    required this.sheetCount,
    required this.hiddenSheetCount,
    required this.dataSheets,
    required this.items,
    required this.priceValues,
    required this.issues,
    required this.issueCount,
    required this.cellsRead,
    required this.documentRef,
  });

  final MtoFormat format;
  final List<String> evidence;
  final int sheetCount;
  final int hiddenSheetCount;
  final List<String> dataSheets;
  final List<ScannedItem> items;
  final int priceValues;

  /// حداکثر [maxIssues] مورد نگه داشته می‌شود؛ تعداد کل در [issueCount] است.
  final List<ScanIssue> issues;
  final int issueCount;
  final int cellsRead;
  final String? documentRef;

  static const maxIssues = 300;
}

/// پیمایش کامل یک کتاب کار.
MtoScanResult scanWorkbook(XlsxWorkbook wb) {
  final ctx = _ScanContext();
  final names = wb.sheets.map((s) => s.name).toSet();
  final evidence = <String>[];
  var format = MtoFormat.unknown;

  // ۱) نشانه‌های ارزان: نام شیت‌ها
  if (names.contains('P.ME') && names.any((n) => n.startsWith('EPC Summary'))) {
    format = MtoFormat.ownerPep;
    evidence.add('شیت‌های «P.ME» و «EPC Summary» وجود دارند.');
  } else if (names.any((n) => n.contains('RFCS') || n.startsWith('EPC 14'))) {
    format = MtoFormat.projectSummary;
    evidence.add('شیت خلاصه‌ی مالی (EPC/RFCS) وجود دارد.');
  }

  // ۲) نشانه‌های محتوایی: محل سرستون «Item No.»
  final dataSheets = <String>[];
  if (format == MtoFormat.unknown) {
    for (final info in wb.visibleSheets) {
      final sh = wb.sheet(info.name);
      if (sh == null) continue;
      if (sh.text(7, 1) == 'Item No.' && _rowContains(sh, 6, 'استعلام')) {
        format = MtoFormat.consultantWorking;
      } else if (sh.text(16, 1) == 'Item No.') {
        if (format == MtoFormat.unknown) format = MtoFormat.consultantReport;
      }
    }
    if (format == MtoFormat.consultantWorking) {
      evidence.add('سرستون «Item No.» در ردیف ۷ و بلوک‌های «استعلام» در ردیف ۶.');
    } else if (format == MtoFormat.consultantReport) {
      evidence.add('سرستون «Item No.» در ردیف ۱۶ (قالب چاپی صفحه‌بندی‌شده).');
    }
  }

  // ۳) شمارش محتوا بر اساس قالب
  switch (format) {
    case MtoFormat.consultantWorking:
      for (final info in wb.visibleSheets) {
        final sh = wb.sheet(info.name)!;
        if (sh.text(7, 1) == 'Item No.') {
          dataSheets.add(info.name);
          _scanWorkingSheet(sh, ctx);
        }
      }
    case MtoFormat.consultantReport:
      for (final info in wb.visibleSheets) {
        final sh = wb.sheet(info.name)!;
        if (sh.text(16, 1) == 'Item No.') {
          dataSheets.add(info.name);
          _scanReportSheet(sh, ctx);
        }
      }
    case MtoFormat.ownerPep:
      for (final n in const ['P.ME', 'P.EL', 'P.IN', 'P.PI', 'P.PL', 'P.LAB']) {
        final sh = wb.sheet(n);
        if (sh == null) continue;
        dataSheets.add(n);
        _scanTableSheet(sh, ctx);
      }
    case MtoFormat.projectSummary:
    case MtoFormat.unknown:
      for (final info in wb.visibleSheets) {
        final sh = wb.sheet(info.name);
        if (sh != null) ctx.cells += sh.cellCount;
      }
  }

  // شماره‌ی سند (برای جلوگیری از ورود تکراری در برنامه‌ی اصلی)
  final docRef = _findDocumentRef(wb);

  return MtoScanResult(
    format: format,
    evidence: evidence,
    sheetCount: wb.sheets.length,
    hiddenSheetCount: wb.sheets.where((s) => s.hidden).length,
    dataSheets: dataSheets,
    items: ctx.items,
    priceValues: ctx.prices,
    issues: ctx.issues,
    issueCount: ctx.issueCount,
    cellsRead: ctx.cells,
    documentRef: docRef,
  );
}

// -----------------------------------------------------------------------------

class _ScanContext {
  final items = <ScannedItem>[];
  final issues = <ScanIssue>[];
  var issueCount = 0;
  var prices = 0;
  var cells = 0;

  void issue(IssueLevel level, String sheet, int row, int col, String msg) {
    issueCount++;
    if (issues.length < MtoScanResult.maxIssues) {
      issues.add(ScanIssue(level, '$sheet!${columnName(col)}$row', msg));
    }
  }
}

bool _rowContains(XlsxSheet sh, int row, String needle) =>
    sh.rowCells(row).any((c) => c.text.contains(needle));

/// قالب کاری مشاور (مثل پازنان ۲): هر تجهیز یک ردیف، استعلام‌ها در بلوک‌های ۵ ستونی:
/// منبع | ریال | یورو | دلار | تاریخ مرجع
void _scanWorkingSheet(XlsxSheet sh, _ScanContext ctx) {
  ctx.cells += sh.cellCount;
  final blocks = [
    for (final c in sh.rowCells(6))
      if (c.text.contains('استعلام')) c.col,
  ];
  for (var r = 8; r <= sh.maxRow; r++) {
    final desc = sh.text(r, 2);
    if (desc.startsWith('برآورد')) break; // ردیف جمع
    final tag = sh.text(r, 1);
    if (tag.isEmpty || desc.isEmpty) continue;

    var priceCount = 0;
    for (final c0 in blocks) {
      for (var off = 1; off <= 3; off++) {
        final cell = sh.cell(r, c0 + off);
        if (cell == null) continue;
        final n = cell.number;
        if (n == null) {
          if (cell.text.trim().isNotEmpty) {
            ctx.issue(IssueLevel.warning, sh.name, r, c0 + off, 'قیمت غیرعددی: «${cell.text}»');
          }
          continue;
        }
        priceCount++;
        if (cell.hasFormula) {
          ctx.issue(IssueLevel.warning, sh.name, r, c0 + off,
              'قیمت به صورت فرمول وارد شده (${cell.formula}) — مبنای ضریب بررسی شود');
        } else if (cell.isNumericText) {
          ctx.issue(IssueLevel.info, sh.name, r, c0 + off, 'عدد به صورت متن ذخیره شده و تبدیل شد');
        }
      }
      _checkDate(sh, r, c0 + 4, ctx);
    }
    ctx.prices += priceCount;
    ctx.items.add(ScannedItem(
      sheet: sh.name,
      row: r,
      tag: tag,
      name: desc.split('\n').first.trim(),
      qty: sh.cell(r, 3)?.number,
      priceCount: priceCount,
    ));
  }
}

/// قالب چاپی مشاور (مثل KPL): ردیف تجهیز + چند ردیف ادامه‌ی شرح در زیر آن.
void _scanReportSheet(XlsxSheet sh, _ScanContext ctx) {
  ctx.cells += sh.cellCount;
  int? descCol, qtyCol, rialCol, euroCol;
  for (final c in sh.rowCells(16)) {
    final h = c.text.replaceAll('\n', ' ').trim();
    if (h.startsWith('Description')) descCol = c.col;
    if (h.startsWith('Qty')) qtyCol = c.col;
    // هر دو سرستون با «Unit Price» شروع می‌شوند؛ واحد پول باید جداگانه تشخیص داده شود.
    if (h.startsWith('Unit Price') && h.contains('Rial')) rialCol = c.col;
    if (h.startsWith('Unit Price') && h.contains('Euro')) euroCol = c.col;
  }
  if (descCol == null) {
    ctx.issue(IssueLevel.error, sh.name, 16, 1, 'ستون Description پیدا نشد');
    return;
  }
  for (var r = 17; r <= sh.maxRow; r++) {
    final tag = sh.text(r, 1);
    final desc = sh.text(r, descCol);
    if (tag.isEmpty || desc.isEmpty) continue;
    if (tag.toUpperCase().contains('TRAIN')) continue;
    var priceCount = 0;
    for (final pc in [rialCol, euroCol]) {
      if (pc == null) continue;
      final n = sh.cell(r, pc)?.number;
      if (n != null && n > 0) priceCount++;
    }
    ctx.prices += priceCount;
    ctx.items.add(ScannedItem(
      sheet: sh.name,
      row: r,
      tag: tag,
      name: desc.split('\n').first.trim(),
      qty: qtyCol == null ? null : sh.cell(r, qtyCol)?.number,
      priceCount: priceCount,
    ));
  }
}

/// جدول‌های ساده‌ی برآورد کارفرمایی (مثل P.ME گچساران ۴): هر ردیفی که شماره‌ی ردیف
/// و شرح داشته باشد یک قلم است.
void _scanTableSheet(XlsxSheet sh, _ScanContext ctx) {
  ctx.cells += sh.cellCount;

  // ستون شرح از روی سرستون‌های ردیف ۱ تا ۳ پیدا می‌شود (ستون اول همیشه شماره‌ی ردیف است).
  int? nameCol;
  for (final key in const ['SERVICE', 'ITEM', 'DESCRIPTION']) {
    for (var r = 1; r <= 3 && nameCol == null; r++) {
      for (final c in sh.rowCells(r)) {
        if (c.col > 1 && c.text.trim().toUpperCase() == key) {
          nameCol = c.col;
          break;
        }
      }
    }
    if (nameCol != null) break;
  }

  for (var r = 4; r <= sh.maxRow; r++) {
    final no = sh.text(r, 1);
    if (no.isEmpty || parseLooseNumber(no) == null) continue;

    var name = nameCol == null ? '' : sh.text(r, nameCol);
    if (name.isEmpty) {
      for (final c in sh.rowCells(r)) {
        if (c.col > 1 && c.value is String && c.text.trim().length > 2) {
          name = c.text;
          break;
        }
      }
    }
    name = name.split('\n').first.trim();
    if (name.isEmpty) continue;

    // ردیف‌های عنوان گروه (مثل «1 SWITCHGEAR») عدد ندارند و شمرده نمی‌شوند.
    final startCol = nameCol ?? 2;
    var values = 0;
    for (final c in sh.rowCells(r)) {
      final n = c.number;
      if (c.col > startCol && c.value is double && n != null && n > 0) values++;
    }
    if (values == 0) continue;
    ctx.prices += values;
    ctx.items.add(ScannedItem(sheet: sh.name, row: r, tag: no, name: name, priceCount: values));
  }
}

final _usDate = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$');

/// تاریخ‌هایی که به صورت متن m/d/yyyy وارد شده‌اند باید واقعاً وجود داشته باشند
/// (مثلاً 2/29/2025 وجود ندارد چون ۲۰۲۵ کبیسه نیست).
void _checkDate(XlsxSheet sh, int row, int col, _ScanContext ctx) {
  final cell = sh.cell(row, col);
  if (cell == null || cell.value is! String) return;
  final m = _usDate.firstMatch(cell.text.trim());
  if (m == null) return;
  final mo = int.parse(m.group(1)!), d = int.parse(m.group(2)!), y = int.parse(m.group(3)!);
  if (!isValidGregorian(y, mo, d)) {
    ctx.issue(IssueLevel.error, sh.name, row, col, 'تاریخ نامعتبر «${cell.text}» (چنین روزی وجود ندارد)');
  }
}

bool isValidGregorian(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1) return false;
  final dt = DateTime.utc(y, m, d);
  return dt.year == y && dt.month == m && dt.day == d;
}

final _docRefPattern = RegExp(r'\b\d{5}-[A-Z]{2,4}-[A-Z]{2}-[A-Z]{2}-\d{3}(-R\d{2})?\b');

String? _findDocumentRef(XlsxWorkbook wb) {
  for (final info in wb.visibleSheets.take(6)) {
    final sh = wb.sheet(info.name);
    if (sh == null) continue;
    for (var r = 1; r <= 12 && r <= sh.maxRow; r++) {
      for (final c in sh.rowCells(r)) {
        final m = _docRefPattern.firstMatch(c.text);
        if (m != null) return m.group(0);
      }
    }
    // قالب چاپی: اجزای شماره‌ی سند در ردیف ۱۱ زیر عنوان‌های Proj./Loc./Disc./Type/Seq./Rev.
    if (sh.text(10, 14) == 'Proj.') {
      final parts = [
        for (final c in sh.rowCells(11))
          if (c.col >= 14 && c.text.trim().isNotEmpty) c.text.trim(),
      ];
      if (parts.length >= 5) return parts.join('-');
    }
  }
  return null;
}
