// خواننده‌ی سبک و مستقل فایل‌های xlsx.
//
// فایل xlsx در واقع یک فایل zip است که داخل آن چند فایل XML قرار دارد.
// این خواننده فقط آنچه برای استخراج داده لازم است را می‌خواند:
// فهرست شیت‌ها، رشته‌های مشترک و مقدار سلول‌ها (شامل مقدار ذخیره‌شده‌ی فرمول‌ها).
// قالب‌بندی، رنگ و نمودار نادیده گرفته می‌شوند؛ به همین دلیل سریع و کم‌مصرف است.
//
// این فایل هیچ وابستگی به Flutter ندارد و در Isolate جداگانه هم قابل اجراست.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// خطای خواندن فایل اکسل (فایل خراب، رمزدار، یا قالب xls قدیمی).
class XlsxFormatException implements Exception {
  XlsxFormatException(this.message);
  final String message;
  @override
  String toString() => 'XlsxFormatException: $message';
}

/// یک سلول خوانده‌شده.
class XlsxCell {
  const XlsxCell({
    required this.row,
    required this.col,
    required this.value,
    this.formula,
    this.isError = false,
    this.fillRgb,
  });

  /// شماره‌ی ردیف (از ۱).
  final int row;

  /// شماره‌ی ستون (از ۱).
  final int col;

  /// مقدار: double، String یا bool. برای سلول فرمولی، آخرین مقدار محاسبه‌شده توسط اکسل.
  final Object? value;

  /// متن فرمول با پیشوند '=' (اگر سلول فرمولی باشد).
  final String? formula;

  /// سلول خطا دارد (#REF!، #DIV/0! و ...).
  final bool isError;

  /// رنگ پس‌زمینه‌ی سلول به صورت ARGB (مثل 'FFFFFF00' زرد) — اگر رنگ صریح داشته باشد.
  final String? fillRgb;

  bool get hasFormula => formula != null;

  /// آدرس سلول مثل "AB12".
  String get ref => '${columnName(col)}$row';

  /// مقدار به صورت متن.
  String get text {
    final v = value;
    if (v == null) return '';
    if (v is double) return formatNumber(v);
    return v.toString();
  }

  /// مقدار عددی؛ اگر سلول متنی باشد ولی محتوایش عدد باشد (مثل '43000') هم تبدیل می‌شود.
  double? get number {
    final v = value;
    if (v is double) return v;
    if (v is String) return parseLooseNumber(v);
    return null;
  }

  /// عدد به صورت متن ذخیره شده است (مثل '43000' در ستون قیمت).
  bool get isNumericText => value is String && parseLooseNumber(value! as String) != null;
}

/// اطلاعات یک شیت از روی workbook.xml.
class XlsxSheetInfo {
  const XlsxSheetInfo({required this.name, required this.hidden, required this.path});
  final String name;
  final bool hidden;
  final String path;

  /// مسیر فایل rels همین شیت (برای پیدا کردن یادداشت‌ها).
  String get relsPath {
    final i = path.lastIndexOf('/');
    return '${path.substring(0, i)}/_rels/${path.substring(i + 1)}.rels';
  }
}

/// یک شیت خوانده‌شده.
class XlsxSheet {
  XlsxSheet._(this.name, this.hidden, this._rows, this.maxRow, this.maxCol, this.cellCount, this._comments,
      [this.merges = const []]);

  /// محدوده‌های ادغام‌شده: (ردیف۱، ستون۱، ردیف۲، ستون۲)
  final List<(int, int, int, int)> merges;

  /// متن سلول؛ اگر سلول جزو محدوده‌ی ادغام‌شده باشد، متن سلول بالا-چپ همان محدوده.
  String mergedText(int row, int col) {
    final own = text(row, col);
    if (own.isNotEmpty) return own;
    for (final (r1, c1, r2, c2) in merges) {
      if (row >= r1 && row <= r2 && col >= c1 && col <= c2) return text(r1, c1);
    }
    return '';
  }

  /// محدوده‌ی ادغامی که سلول در آن است (ردیف۱، ستون۱، ردیف۲، ستون۲)
  (int, int, int, int)? mergeAt(int row, int col) {
    for (final m in merges) {
      if (row >= m.$1 && row <= m.$3 && col >= m.$2 && col <= m.$4) return m;
    }
    return null;
  }

  /// آیا سلول جزو محدوده‌ی ادغام‌شده است (به جز سلول بالا-چپ)؟
  bool isMergedTail(int row, int col) {
    for (final (r1, c1, r2, c2) in merges) {
      if (row >= r1 && row <= r2 && col >= c1 && col <= c2 && !(row == r1 && col == c1)) return true;
    }
    return false;
  }

  final String name;
  final bool hidden;
  final Map<int, Map<int, XlsxCell>> _rows;
  final int maxRow;
  final int maxCol;
  final int cellCount;
  final Map<int, String> _comments;

  XlsxCell? cell(int row, int col) => _rows[row]?[col];

  /// یادداشت (Note/Comment) سلول، اگر وجود داشته باشد.
  String? comment(int row, int col) => _comments[row * 20000 + col];

  int get commentCount => _comments.length;

  /// سلول با آدرس متنی مثل "A7".
  XlsxCell? at(String ref) {
    final p = parseCellRef(ref);
    return p == null ? null : cell(p.$1, p.$2);
  }

  /// متن سلول بدون فاصله‌ی اضافه؛ سلول خالی = ''.
  String text(int row, int col) => cell(row, col)?.text.trim() ?? '';

  /// سلول‌های یک ردیف به ترتیب ستون.
  List<XlsxCell> rowCells(int row) {
    final r = _rows[row];
    if (r == null) return const [];
    final cols = r.keys.toList()..sort();
    return [for (final c in cols) r[c]!];
  }
}

/// کتاب کار اکسل.
class XlsxWorkbook {
  XlsxWorkbook._(this._archive, this.sheets, this._sharedStrings, this._xfFill);

  final Archive _archive;
  final List<XlsxSheetInfo> sheets;
  final List<String> _sharedStrings;

  /// رنگ پس‌زمینه‌ی هر سبک سلول (اندیس cellXfs) — null یعنی بدون رنگ صریح.
  final List<String?> _xfFill;
  final Map<String, XlsxSheet> _cache = {};

  static XlsxWorkbook openFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw XlsxFormatException('فایل پیدا نشد: $path');
    }
    return fromBytes(file.readAsBytesSync());
  }

  static XlsxWorkbook fromBytes(List<int> bytes) {
    // فایل xls قدیمی (قبل از ۲۰۰۷) با امضای OLE شروع می‌شود، نه zip.
    if (bytes.length >= 4 && bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0) {
      throw XlsxFormatException(
          'این فایل با قالب قدیمی xls یا رمزدار است. آن را در اکسل با قالب xlsx ذخیره کنید.');
    }
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw XlsxFormatException('فایل xlsx معتبر نیست.');
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw XlsxFormatException('فایل zip قابل باز شدن نیست: $e');
    }

    final shared = _readSharedStrings(archive);
    final sheets = _readSheetList(archive);
    return XlsxWorkbook._(archive, sheets, shared, _readStyleFills(archive));
  }

  List<XlsxSheetInfo> get visibleSheets => sheets.where((s) => !s.hidden).toList();

  bool hasSheet(String name) => sheets.any((s) => s.name == name);

  /// خواندن یک شیت با نام (نتیجه کش می‌شود).
  XlsxSheet? sheet(String name) {
    final cached = _cache[name];
    if (cached != null) return cached;
    final matches = sheets.where((s) => s.name == name);
    if (matches.isEmpty) return null;
    final parsed = _parseSheet(matches.first);
    _cache[name] = parsed;
    return parsed;
  }

  // ---------------------------------------------------------------------------

  static String? _readEntry(Archive archive, String path) {
    final f = archive.findFile(path);
    if (f == null) return null;
    final content = f.content as List<int>;
    return utf8.decode(content, allowMalformed: true);
  }

  static List<String> _readSharedStrings(Archive archive) {
    final xmlText = _readEntry(archive, 'xl/sharedStrings.xml');
    if (xmlText == null) return const [];
    final doc = XmlDocument.parse(xmlText);
    final result = <String>[];
    for (final si in _descendants(doc.rootElement, 'si')) {
      result.add(_richText(si));
    }
    return result;
  }

  /// متن یک عنصر si یا is: یا مستقیم <t> دارد یا چند تکه‌ی <r><t>.
  /// تکه‌های آوایی (rPh) کنار گذاشته می‌شوند.
  static String _richText(XmlElement el) {
    final buf = StringBuffer();
    for (final child in el.childElements) {
      final local = child.name.local;
      if (local == 't') {
        buf.write(child.innerText);
      } else if (local == 'r') {
        for (final t in child.childElements.where((e) => e.name.local == 't')) {
          buf.write(t.innerText);
        }
      }
    }
    return buf.toString();
  }

  static List<String?> _readStyleFills(Archive archive) {
    final xmlText = _readEntry(archive, 'xl/styles.xml');
    if (xmlText == null) return const [];
    final root = XmlDocument.parse(xmlText).rootElement;
    final fills = <String?>[];
    final fillsEl = root.childElements.where((e) => e.name.local == 'fills').firstOrNull;
    if (fillsEl != null) {
      for (final fill in fillsEl.childElements.where((e) => e.name.local == 'fill')) {
        String? rgb;
        final pf = fill.childElements.where((e) => e.name.local == 'patternFill').firstOrNull;
        if (pf != null && (pf.getAttribute('patternType') ?? 'none') != 'none') {
          final fg = pf.childElements.where((e) => e.name.local == 'fgColor').firstOrNull;
          rgb = fg?.getAttribute('rgb')?.toUpperCase();
        }
        fills.add(rgb);
      }
    }
    final result = <String?>[];
    final xfs = root.childElements.where((e) => e.name.local == 'cellXfs').firstOrNull;
    if (xfs != null) {
      for (final xf in xfs.childElements.where((e) => e.name.local == 'xf')) {
        final id = int.tryParse(xf.getAttribute('fillId') ?? '');
        result.add(id != null && id >= 0 && id < fills.length ? fills[id] : null);
      }
    }
    return result;
  }

  Map<int, String> _readComments(XlsxSheetInfo info) {
    final relsXml = _readEntry(_archive, info.relsPath);
    if (relsXml == null) return const {};
    String? target;
    for (final rel in _descendants(XmlDocument.parse(relsXml).rootElement, 'Relationship')) {
      if ((rel.getAttribute('Type') ?? '').endsWith('/comments')) target = rel.getAttribute('Target');
    }
    if (target == null) return const {};
    final dir = info.path.substring(0, info.path.lastIndexOf('/'));
    final xmlText = _readEntry(_archive, _resolvePath(dir, target));
    if (xmlText == null) return const {};
    final result = <int, String>{};
    for (final c in _descendants(XmlDocument.parse(xmlText).rootElement, 'comment')) {
      final pos = parseCellRef(c.getAttribute('ref') ?? '');
      if (pos == null) continue;
      final textEl = c.childElements.where((e) => e.name.local == 'text').firstOrNull;
      if (textEl == null) continue;
      result[pos.$1 * 20000 + pos.$2] = _richText(textEl).trim();
    }
    return result;
  }

  static List<XlsxSheetInfo> _readSheetList(Archive archive) {
    final wbXml = _readEntry(archive, 'xl/workbook.xml');
    if (wbXml == null) throw XlsxFormatException('workbook.xml پیدا نشد.');
    final relsXml = _readEntry(archive, 'xl/_rels/workbook.xml.rels');
    if (relsXml == null) throw XlsxFormatException('workbook.xml.rels پیدا نشد.');

    final relTargets = <String, String>{};
    for (final rel in _descendants(XmlDocument.parse(relsXml).rootElement, 'Relationship')) {
      final id = rel.getAttribute('Id');
      final target = rel.getAttribute('Target');
      if (id != null && target != null) relTargets[id] = target;
    }

    final result = <XlsxSheetInfo>[];
    for (final s in _descendants(XmlDocument.parse(wbXml).rootElement, 'sheet')) {
      final name = s.getAttribute('name') ?? '';
      final state = s.getAttribute('state');
      // صفت r:id در فضای نام relationships است؛ بر اساس نام محلی پیدا می‌شود.
      String? rid;
      for (final a in s.attributes) {
        if (a.name.local == 'id' && a.name.prefix != null) rid = a.value;
      }
      final target = rid == null ? null : relTargets[rid];
      if (target == null) continue;
      result.add(XlsxSheetInfo(
        name: name,
        hidden: state == 'hidden' || state == 'veryHidden',
        path: _resolvePath('xl', target),
      ));
    }
    return result;
  }

  /// تبدیل مسیر نسبی داخل zip به مسیر کامل.
  static String _resolvePath(String baseDir, String target) {
    if (target.startsWith('/')) return target.substring(1);
    final parts = <String>[...baseDir.split('/')];
    for (final seg in target.split('/')) {
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (seg.isNotEmpty && seg != '.') {
        parts.add(seg);
      }
    }
    return parts.join('/');
  }

  XlsxSheet _parseSheet(XlsxSheetInfo info) {
    final xmlText = _readEntry(_archive, info.path);
    if (xmlText == null) {
      throw XlsxFormatException('محتوای شیت «${info.name}» پیدا نشد (${info.path}).');
    }
    final doc = XmlDocument.parse(xmlText);
    final rows = <int, Map<int, XlsxCell>>{};
    var maxRow = 0, maxCol = 0, count = 0;

    final sheetData = _descendants(doc.rootElement, 'sheetData').firstOrNull;
    final comments = _readComments(info);
    if (sheetData == null) {
      return XlsxSheet._(info.name, info.hidden, rows, 0, 0, 0, comments);
    }

    var implicitRow = 0;
    for (final rowEl in sheetData.childElements.where((e) => e.name.local == 'row')) {
      final rAttr = int.tryParse(rowEl.getAttribute('r') ?? '');
      final rowNum = rAttr ?? implicitRow + 1;
      implicitRow = rowNum;
      var implicitCol = 0;

      for (final c in rowEl.childElements.where((e) => e.name.local == 'c')) {
        final pos = parseCellRef(c.getAttribute('r') ?? '');
        final row = pos?.$1 ?? rowNum;
        final col = pos?.$2 ?? implicitCol + 1;
        implicitCol = col;

        final cell = _parseCell(c, row, col);
        if (cell == null) continue;
        (rows[row] ??= {})[col] = cell;
        count++;
        if (row > maxRow) maxRow = row;
        if (col > maxCol) maxCol = col;
      }
    }
    final merges = <(int, int, int, int)>[];
    for (final m in _descendants(doc.rootElement, 'mergeCell')) {
      final ref = m.getAttribute('ref') ?? '';
      final parts = ref.split(':');
      if (parts.length != 2) continue;
      final a = parseCellRef(parts[0]), b = parseCellRef(parts[1]);
      if (a == null || b == null) continue;
      merges.add((a.$1, a.$2, b.$1, b.$2));
    }
    return XlsxSheet._(info.name, info.hidden, rows, maxRow, maxCol, count, comments, merges);
  }

  XlsxCell? _parseCell(XmlElement c, int row, int col) {
    final type = c.getAttribute('t');
    final styleIdx = int.tryParse(c.getAttribute('s') ?? '');
    final fill = (styleIdx != null && styleIdx >= 0 && styleIdx < _xfFill.length) ? _xfFill[styleIdx] : null;
    XmlElement? vEl, fEl, isEl;
    for (final child in c.childElements) {
      switch (child.name.local) {
        case 'v':
          vEl = child;
        case 'f':
          fEl = child;
        case 'is':
          isEl = child;
      }
    }
    final raw = vEl?.innerText;
    String? formula;
    if (fEl != null) {
      final ft = fEl.innerText.trim();
      formula = ft.isEmpty ? '=(فرمول مشترک)' : '=$ft';
    }

    Object? value;
    var isError = false;
    switch (type) {
      case 's':
        final idx = int.tryParse(raw ?? '');
        value = (idx != null && idx >= 0 && idx < _sharedStrings.length) ? _sharedStrings[idx] : null;
      case 'str':
        value = raw;
      case 'inlineStr':
        value = isEl == null ? raw : _richText(isEl);
      case 'b':
        value = raw == null ? null : raw.trim() == '1';
      case 'e':
        value = raw;
        isError = true;
      default:
        value = raw == null ? null : double.tryParse(raw.trim());
    }

    if (value == null && formula == null) return null;
    if (value is String && value.isEmpty && formula == null) return null;
    return XlsxCell(row: row, col: col, value: value, formula: formula, isError: isError, fillRgb: fill);
  }

  static Iterable<XmlElement> _descendants(XmlElement root, String local) =>
      root.descendants.whereType<XmlElement>().where((e) => e.name.local == local);
}

// -----------------------------------------------------------------------------
// توابع کمکی

/// "AB" → 28
int columnIndex(String letters) {
  var n = 0;
  for (final ch in letters.toUpperCase().codeUnits) {
    if (ch < 65 || ch > 90) return 0;
    n = n * 26 + (ch - 64);
  }
  return n;
}

/// 28 → "AB"
String columnName(int index) {
  var n = index;
  final buf = <int>[];
  while (n > 0) {
    final rem = (n - 1) % 26;
    buf.insert(0, 65 + rem);
    n = (n - 1) ~/ 26;
  }
  return String.fromCharCodes(buf);
}

final _refPattern = RegExp(r'^\$?([A-Za-z]{1,3})\$?(\d+)$');

/// "AB12" → (12, 28)
(int, int)? parseCellRef(String ref) {
  final m = _refPattern.firstMatch(ref.trim());
  if (m == null) return null;
  final row = int.parse(m.group(2)!);
  final col = columnIndex(m.group(1)!);
  if (row <= 0 || col <= 0) return null;
  return (row, col);
}

/// تبدیل متن به عدد با تحمل ویرگول هزارگان، ارقام فارسی/عربی و فاصله.
double? parseLooseNumber(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  const ar = '٠١٢٣٤٥٦٧٨٩';
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    final i = fa.indexOf(ch);
    final j = ar.indexOf(ch);
    if (i >= 0) {
      buf.write(i);
    } else if (j >= 0) {
      buf.write(j);
    } else if (ch == ',' || ch == '٬' || ch == ' ' || ch == ' ') {
      // جداکننده‌ی هزارگان
    } else if (ch == '٫') {
      buf.write('.');
    } else {
      buf.write(ch);
    }
  }
  s = buf.toString();
  if (!RegExp(r'^[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$').hasMatch(s)) return null;
  return double.tryParse(s);
}

/// نمایش عدد بدون ".0" اضافه.
String formatNumber(double v) {
  if (v.isNaN || v.isInfinite) return v.toString();
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toStringAsFixed(0);
  return v.toString();
}
