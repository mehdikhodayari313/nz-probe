// ورود MTO با قالب‌های متفاوت (هر مشاور، هر پروژه): تشخیص خودکار سطر عنوان و نقش ستون‌ها.
//
// نمونه‌های مرجع: گزارش چاپی MTO (KPL: هر قلم چند سطر، سلول‌های ادغام‌شده، برگه‌ی هر رده)،
// PEP کارفرما (گچساران ۴: عنوان سه‌سطری، تگ در دو ستون، واحد Kg، اقلام زیرمجموعه)، جدول‌های جمع‌بندی.
//
// برای هر شیت:
//   ۱) نوع شیت از نام و عنوانش: اقلام / نصب و اجرا (فقط برای وزن تجهیزات) / رد (جلد، جمع، خلاصه، مهندسی).
//   ۲) سطر عنوان: سطری که با سطرهای زیرعنوانش ستون «شرح» و دست‌کم دو ستون از «تگ/تعداد/قیمت» را دارد.
//   ۳) نقش هر ستون از روی عنوانش (و عنوان گروه بالای آن): تگ، شرح، تعداد، واحد، قیمت مبنا، استعلام،
//      قیمت قدیمی، ارز، تاریخ، فروشنده، وزن، مشخصه‌ی فنی، ملاحظات، جمع، … با ارز و سال هر ستون قیمت.
//   ۴) هر ستون مشخصه‌ی فنی و سطرهای ادامه‌ی شرح (قلم چندسطری) به شرح قلم اضافه می‌شود تا در قالب رده بنشیند.
//   ۵) سطرهای عنوان بخش (مثل «PUMPS» یا «CRANES») رده‌ی اقلام بعدی را تعیین می‌کنند؛ وگرنه رده از نام قلم.
// نقش ستون‌ها و رده‌ی هر قلم در پیش‌نمایش ورود قابل اصلاح است.

import '../catalog/profiles.dart';
import '../xlsx/xlsx_reader.dart';
import 'mto_importer.dart';

enum MtoColRole {
  ignore('نادیده'),
  tag('تگ / شماره'),
  desc('شرح / نام'),
  qty('تعداد / مقدار'),
  unit('واحد شمارش'),
  going('قیمت مبنا (برآورد)'),
  quote('قیمت استعلام'),
  old('قیمت قدیمی'),
  currency('ارز (هر ردیف)'),
  date('تاریخ استعلام'),
  vendor('فروشنده / سازنده'),
  weight('وزن'),
  spec('مشخصه‌ی فنی'),
  remarks('ملاحظات'),
  total('جمع ردیف (قیمت واحد = جمع ÷ تعداد وقتی قیمت واحد نیست)'),
  rate('نرخ واحد وزن/طول (× وزن یا طول)'),
  overhead('ضریب بالاسری');

  const MtoColRole(this.fa);
  final String fa;
  bool get isPrice => this == going || this == quote || this == old;
}

class MtoColumn {
  MtoColumn(this.col, this.header, this.own, this.role);
  final int col;

  /// عنوان کامل (گروه + زیرعنوان‌ها)
  final String header;

  /// پایین‌ترین عنوان اختصاصی همین ستون (برای برچسب مشخصه)
  final String own;
  MtoColRole role;
  String? currency; // IRR / EUR / USD ؛ null = از ستون ارز یا بزرگی عدد
  int? year;
  int? month;

  /// ستون‌های دیگر زیر همان عنوان ادغام‌شده (مثل تگ «DE» + «-001-A/B»)
  final List<int> extra = [];

  /// بخشی از نام قلم وقتی شرح از چند ستون ساخته شده است (مثل اقلام پایپینگ)
  bool namePart = false;

  /// بلوک استعلام (ستون‌های هم‌گروه زیر یک عنوان مثل «استعلام ۲» یا «Quotation B»)
  int? block;
  String? blockLabel;

  /// نمونه‌ی مقادیر (برای پیش‌نمایش)
  String sample = '';

  List<int> get cols => [col, ...extra];
  String get label {
    if (own.isEmpty) return header;
    // عنوان دوطبقه: «TEMP. / DESIGN (MAX)»، «PRESS. / DESIGN (BARG)» ← کمیت بالایی جزء نام است
    if (header != own && header.endsWith(own)) {
      final top = header.substring(0, header.length - own.length).trim();
      if (RegExp(r'^(temp|press|dimension|dim|duty|flow|capacity|size|weight|power|head|level)\w*\.?$', caseSensitive: false)
          .hasMatch(top)) {
        return '$top $own';
      }
    }
    return own;
  }
}

class MtoLayout {
  MtoLayout(this.sheet, this.headerRow, this.dataStart, this.columns);
  final String sheet;
  int headerRow;
  int dataStart;
  final List<MtoColumn> columns;

  /// ستون تگ فقط شماره‌ردیف است (۱، ۲، …) ← تگ = «شیت#شماره»
  bool tagIsSerial = false;

  /// جدول جمع‌بندی (بدون تگ و تعداد): پیش‌فرض وارد نمی‌شود
  bool summary = false;

  /// سال قیمت از نام شیت (مثل «p.lab.1392»)
  int? sheetYear;

  /// ستون شماره‌ردیف (۶۵، ۶۵٫۱، …) برای تشخیص پایان زیرمجموعه‌ها
  MtoColumn? serialCol;

  /// متن‌های بالای جدول (عنوان رده، «ASMARI TRAIN»، …)
  final List<String> context = [];
  final List<String> notes = [];

  /// سطرهای جمع شیت (ردیف، بزرگ‌ترین مبلغ) برای کنترل «هیچ قلمی جا نیفتاده»
  final List<(int, double)> sheetTotals = [];

  /// سطرهای بیرون از جدول که با مبلغشان قلم شدند (ردیف ← مبلغ)
  final Map<int, double> orphans = {};

  /// ارز پیش‌فرض شیت (از عنوان‌ها یا جلد)
  String? sheetCurrency;

  MtoColumn? first(MtoColRole r) => columns.where((c) => c.role == r).firstOrNull;
  Iterable<MtoColumn> all(MtoColRole r) => columns.where((c) => c.role == r);
}

String _norm(String s) => s
    .replaceAll('ي', 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll('‌', ' ')
    .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

bool _has(String h, String p) => RegExp(p, caseSensitive: false).hasMatch(h);

/// خطای اکسل («#NAME?»، «#REF!»، …) مقدار نیست
bool _isXlError(String t) => RegExp(r'^#(NAME\?|REF!|VALUE!|DIV/0!|N/A|NULL!|NUM!|SPILL!|CALC!)').hasMatch(t.trim());

const _pPrice = r'price|cost|قیمت|بها|هزینه|fee|amount|estimat|برآورد|مبلغ|salary|wage|rental|حقوق|دستمزد|اجاره';
const _pTotal = r'total|جمع|مبلغ کل|(^|\s)کل(\s|$)|sum\b|aggregate|تمام شده';
const _pSkipPrice = r'avg|average|میانگین|no\. of|number of|تعداد استعلام|ratio|نسبت|%|درصد';
const _pQuote = r'quot|offer|vendor price|استعلام|پیشنهاد|فروشنده|bid\b|tender';
const _pOld = r'\bold\b|previous|prev\.|قبلی|قدیم|last rev|سابق';
const _pQty = r"\bqty|quantity|q'ty|تعداد|no\.? ?of ?(units|sets|items)|مقدار";
const _pTag = r'\btag|item ?no|equipment ?(no|code)|equip\. ?no|item ?code|شماره ?تگ|شماره ?تجهیز|کد ?تجهیز|^کد$';
const _pSerial = r'^(ردیف|row|r|s/?n|sr\.?|no\.?|#|item|ر|رديف)$';
const _pDesc = r'desc|شرح|equipment|service|title|نام|عنوان|مشخصات کلی|name';
const _pCurrency = r'currency|ارز';
const _pDate = r'date|تاریخ';
const _pVendor = r'vendor|supplier|manufactur|maker|source|منبع|سازنده|فروشنده|تامین|تأمین|company|شرکت';
const _pRemarks = r'remark|note|comment|ملاحظات|توضیح';
const _pBlock = r'استعلام|quotation|quote|offer|vendor|پیشنهاد|bidder|supplier';
const _pWeight = r'وزن|weight';
const _pUnit = r'^(unit|uom|u\.o\.m\.?|واحد|واحد شمارش)$';
const _pOverhead = r'overhead|o\.?\s?h\.?\b|بالاسری|بالا سری|سربار|mark.?up|contingenc';
const _pRate = r'/\s*(kg|kgs|ton|tonne|m|mt|meter|metre|lm|m2|m3|متر|کیلو|تن)\b|per\s*(kg|ton|tonne|m|meter|metre|m2|m3)\b|(بر|به ازای)\s*(کیلو|متر|تن)|هر\s*(کیلو|متر|تن)';
const _pNotes = r'^(notes?\b|note\s*[:：]|یادداشت|توضیحات\s*[:：]|\d+\s*-\s*[a-z.]+\s*[:：])';

String? currencyOf(String t) {
  final u = t.toUpperCase();
  if (u.contains('EUR') || t.contains('€') || t.contains('یورو')) return 'EUR';
  if (u.contains('USD') || t.contains(r'$') || t.contains('دلار') || u.contains('DOLLAR')) return 'USD';
  if (u.contains('IRR') ||
      u.contains('RIAL') ||
      RegExp(r'\bRLS\b').hasMatch(u) ||
      t.contains('ریال') ||
      t.contains('ريال') ||
      u.contains('IRT') ||
      t.contains('تومان')) {
    return 'IRR';
  }
  return null;
}

/// سال شمسی (و ماه میانی فصل) از متن: «1404Q1»، «1393»، «2015» (میلادی ← شمسی)
(int?, int?) yearOfHeader(String h) {
  final q = RegExp(r'(1[34]\d\d)\s*[-/ ]?\s*Q\s*([1-4])', caseSensitive: false).firstMatch(h);
  if (q != null) return (int.parse(q.group(1)!), int.parse(q.group(2)!) * 3 - 1);
  final j = RegExp(r'(?<!\d)(1[34]\d\d)(?![\d.])').firstMatch(h);
  if (j != null) return (int.parse(j.group(1)!), null);
  final g = RegExp(r'(?<!\d)(19[89]\d|20[0-4]\d)(?!\d)').firstMatch(h);
  if (g != null) return (int.parse(g.group(1)!) - 621, null);
  return (null, null);
}

/// تگ یکسان برای تطبیق (فاصله‌ها و حروف کوچک/بزرگ مهم نیستند)
String normTag(String t) => t.toUpperCase().replaceAll(RegExp(r'\s+'), '');

enum MtoSheetKind { items, install, skip }

class MtoGeneric {
  /// نوع شیت از نام و متن بالای آن
  static MtoSheetKind kindOf(XlsxSheet sh) {
    final n = sh.name.toLowerCase().trim();
    if (RegExp(r'cover|record|title|total|summary|خلاصه|جمع|basic ?data|inflation|^sheet\d*$|^epc|^pep$|^e\.|engineering|عملکرد|عملكرد|^rfcs|^fr\d|extra|level|index|فهرست')
        .hasMatch(n)) {
      return MtoSheetKind.skip;
    }
    if (RegExp(r'^(c\.(?!i\.?p)|ins\b|ins-|install)|construction|نصب|اجرا|^cv\d').hasMatch(n)) return MtoSheetKind.install;
    for (var r = 1; r <= 15 && r <= sh.maxRow; r++) {
      // فقط عنوان بالای جدول؛ «Desalter Installation» داخل اقلام، شیت را «نصب» نمی‌کند
      var filled = 0;
      for (var c = 1; c <= sh.maxCol && c <= 60; c++) {
        if (sh.text(r, c).isNotEmpty && !sh.isMergedTail(r, c)) filled++;
      }
      if (filled >= 4) break;
      for (var c = 1; c <= 4 && c <= sh.maxCol; c++) {
        final t = _norm(sh.text(r, c));
        if (t.length > 6 && _has(t, r'(اجرا ?و ?نصب|نصب تجهیزات|فهرست بها|installation|erection)')) {
          return MtoSheetKind.install;
        }
      }
    }
    return MtoSheetKind.items;
  }

  // ---------------------------------------------------------------------------
  // تشخیص سطر عنوان

  /// آیا سطر [r] زیرعنوان است (فقط متن‌های کوتاه، بدون عدد)؟
  static bool _headerLike(XlsxSheet sh, int r) {
    if (r > sh.maxRow) return false;
    var texts = 0, nums = 0;
    for (var c = 1; c <= sh.maxCol && c <= 120; c++) {
      final cell = sh.cell(r, c);
      if (cell == null || cell.text.trim().isEmpty) continue;
      if (cell.value is double) {
        nums++;
      } else {
        final t = cell.text.trim();
        if (t.length > 45) return false;
        texts++;
      }
    }
    return texts >= 2 && nums == 0;
  }

  /// تعداد سطرهای زیرعنوان بعد از [hdr] (۰ تا ۳)
  static int _subRows(XlsxSheet sh, int hdr) {
    var k = 0;
    while (k < 3 && _headerLike(sh, hdr + k + 1)) {
      k++;
    }
    // سطرهای خالیِ داخل ادغام عنوان (گزارش چاپی: عنوان ادغام‌شده‌ی سه‌سطری)
    var m = hdr;
    for (var c = 1; c <= sh.maxCol && c <= 120; c++) {
      final g = sh.mergeAt(hdr, c);
      if (g != null && g.$1 == hdr && g.$3 > m) m = g.$3;
    }
    // ادغام عمودی یک ستون (مثل «Total Estimation Price» تا ردیف جمع) سطرهای اقلام را عنوان نمی‌کند:
    // اولین سطری که عدد یا متن خارج از ادغام‌های عنوان دارد، شروع داده است.
    for (var rr = hdr + 1; rr <= m; rr++) {
      var data = false;
      for (var c = 1; c <= sh.maxCol && c <= 120; c++) {
        final cell = sh.cell(rr, c);
        if (cell == null || cell.text.trim().isEmpty) continue;
        final g = sh.mergeAt(rr, c);
        if (g != null && g.$1 == hdr) continue; // ادامه‌ی خود عنوان
        if (cell.value is double || !_headerLike(sh, rr)) {
          data = true;
          break;
        }
      }
      if (data) {
        m = rr - 1;
        break;
      }
    }
    return (m - hdr) > k ? (m - hdr) : k;
  }

  /// تشخیص قالب جدول اقلام یک شیت؛ null = جدول اقلام پیدا نشد.
  static MtoLayout? detect(XlsxSheet sh) {
    int? bestRow;
    var bestScore = 0;
    for (var r = 1; r <= 40 && r <= sh.maxRow; r++) {
      // خود سطر عنوان دست‌کم دو عنوان دارد (نه سطر خالی یا عنوان سراسری بالای جدول)
      var own = 0;
      for (var c = 1; c <= sh.maxCol && c <= 120; c++) {
        if (sh.text(r, c).isNotEmpty) own++;
      }
      if (own < 2) continue;
      final sub = _subRows(sh, r);
      var desc = false, tag = false, qty = false, price = false;
      for (var c = 1; c <= sh.maxCol && c <= 120; c++) {
        for (var rr = r; rr <= r + sub; rr++) {
          final h = _norm(rr == r ? sh.text(rr, c) : sh.mergedText(rr, c));
          if (h.isEmpty || h.length > 80) continue;
          final isPrice = _has(h, _pPrice);
          if (!isPrice && _has(h, _pDesc)) desc = true;
          if (!isPrice && (_has(h, _pTag) || _has(h, _pSerial))) tag = true;
          if (!isPrice && _has(h, _pQty)) qty = true;
          if (isPrice) price = true;
        }
      }
      // سرستون شرح ندارد («Instruments»، «Site Mobilization»): ستونی که زیرش متن‌های بلند است شرح است
      if (!desc && (qty || price)) desc = _textColumnBelow(sh, r + sub + 1);
      final score = (desc ? 3 : 0) + (tag ? 1 : 0) + (qty ? 1 : 0) + (price ? 1 : 0);
      if (desc && score >= 5 && score > bestScore) {
        bestScore = score;
        bestRow = r;
      }
    }
    if (bestRow == null) return null;
    return layoutAt(sh, bestRow);
  }

  /// زیر سطر [start] ستونی با متن‌های غیرعددی و نسبتاً بلند هست (نامزد ستون شرح)؟
  static bool _textColumnBelow(XlsxSheet sh, int start) {
    for (var c = 1; c <= sh.maxCol && c <= 60; c++) {
      var n = 0, len = 0;
      for (var r = start; r <= sh.maxRow && r < start + 15; r++) {
        final cell = sh.cell(r, c);
        if (cell == null || cell.value is double) continue;
        final t = cell.text.trim();
        if (t.length < 3 || RegExp(r'^[\d.,\s-]+$').hasMatch(t)) continue;
        n++;
        len += t.length;
      }
      if (n >= 2 && len / n >= 6) return true;
    }
    return false;
  }

  /// قالب با سطر عنوان مشخص (برای تعریف دستی کاربر هم استفاده می‌شود).
  static MtoLayout layoutAt(XlsxSheet sh, int hdr) {
    final sub = _subRows(sh, hdr);
    final last = hdr + sub;
    final dataStart = last + 1;

    // متن‌های بالای جدول (عنوان رده، قطار/ترین، …)
    final context = <String>[];
    for (var r = hdr - 1; r >= 1 && r >= hdr - 4; r--) {
      final texts = [
        for (var c = 1; c <= sh.maxCol && c <= 120; c++)
          if (!sh.isMergedTail(r, c) && sh.text(r, c).isNotEmpty && !_isXlError(sh.text(r, c))) _norm(sh.text(r, c)),
      ];
      if (texts.length == 1 && texts.first.length < 45 && !texts.first.contains(':')) context.insert(0, texts.first);
    }

    String? carry;
    int blockNo = 0;
    final cols = <MtoColumn>[];
    MtoColumn? prev;
    for (var c = 1; c <= sh.maxCol && c <= 120; c++) {
      // ستون دنباله‌ی عنوانی که روی همه‌ی سطرهای عنوان ادغام شده است ← بخشی از ستون قبلی
      final mg = sh.mergeAt(hdr, c);
      if (prev != null && mg != null && mg.$2 < c && mg.$1 == hdr && mg.$3 >= last && prev.cols.contains(mg.$2)) {
        prev.extra.add(c);
        continue;
      }
      final parts = <String>[];
      for (var r = hdr; r <= last; r++) {
        final t = _norm(sh.mergedText(r, c));
        if (t.isNotEmpty && (parts.isEmpty || parts.last != t)) parts.add(t);
      }
      final top = parts.isEmpty ? '' : parts.first;
      final own = parts.isEmpty ? '' : parts.last;
      // عنوان بلوک: سطر بالای عنوان (پازنان: «استعلام ۱») یا خود سطر عنوان وقتی زیرعنوان دارد («Quotation 1»)
      var g = hdr > 1 ? _norm(sh.mergedText(hdr - 1, c)) : '';
      if (g.isNotEmpty && !_has(g, _pBlock)) g = '';
      if (g.isEmpty && parts.length > 1 && _has(top, _pBlock) && !_has(top, _pPrice)) g = top;
      if (g.isNotEmpty && g != carry) {
        carry = g;
        blockNo++;
      } else if (g.isEmpty && carry != null) {
        final fits = _has(own, '$_pVendor|$_pDate|$_pPrice') || currencyOf(own) != null;
        if (!fits || _has(own, '$_pOld|$_pTotal|$_pSkipPrice') || (parts.length > 1 && !sh.isMergedTail(hdr, c))) {
          carry = null;
        }
      }
      final inBlock = carry != null;
      if (parts.isEmpty && !inBlock) {
        prev = null;
        continue;
      }
      final full = parts.join(' ');
      final col = MtoColumn(c, full.isEmpty ? (carry ?? '') : full, own, MtoColRole.ignore);
      if (inBlock) {
        col.block = blockNo;
        col.blockLabel = carry;
      }
      final roleOwn = _roleOf(own, inBlock: inBlock);
      final roleFull = _roleOf(full, inBlock: inBlock);
      const specific = {
        MtoColRole.qty, MtoColRole.unit, MtoColRole.tag, MtoColRole.date, MtoColRole.vendor,
        MtoColRole.remarks, MtoColRole.currency, MtoColRole.weight,
      };
      if (specific.contains(roleOwn)) {
        col.role = roleOwn;
      } else if (roleFull.isPrice || roleFull == MtoColRole.total) {
        col.role = roleFull;
      } else if (roleOwn.isPrice || roleOwn == MtoColRole.total) {
        col.role = roleOwn;
      } else if (roleOwn == MtoColRole.desc) {
        col.role = MtoColRole.desc;
      } else if (roleOwn == MtoColRole.spec && currencyOf(own) != null && own.length <= 12 && yearOfHeader(full).$1 != null) {
        col.role = MtoColRole.going; // «1404» / «یورو»: ستون قیمت بدون واژه‌ی «قیمت»
      } else if (roleOwn == MtoColRole.spec && specific.contains(roleFull)) {
        col.role = roleFull; // مثل «QUANTITY / LENGTH(M)»
      } else if (roleFull == MtoColRole.desc && parts.length > 1) {
        col.role = MtoColRole.spec;
        col.namePart = true; // زیرستون گروه «DESCRIPTION»
      } else {
        col.role = roleOwn;
      }
      if (col.role.isPrice || col.role == MtoColRole.rate || col.role == MtoColRole.total) {
        col.currency = currencyOf('$full ${col.blockLabel ?? ''}');
      }
      final (y, m) = yearOfHeader(full);
      col.year = y;
      col.month = m;
      cols.add(col);
      prev = col;
    }
    final l = MtoLayout(sh.name, hdr, dataStart, cols);
    l.context.addAll(context);
    l.sheetYear = yearOfHeader(sh.name).$1;
    for (final col in cols) {
      for (var r = dataStart; r <= sh.maxRow && r < dataStart + 30; r++) {
        final t = textOf(sh, r, col);
        if (t.isNotEmpty) {
          col.sample = t.length > 40 ? '${t.substring(0, 40)}…' : t.replaceAll('\n', ' ');
          break;
        }
      }
    }
    _resolve(sh, l);
    return l;
  }

  static MtoColRole _roleOf(String h, {bool inBlock = false}) {
    if (h.isEmpty) return MtoColRole.ignore;
    if (_has(h, _pOverhead) && !_has(h, r'total|جمع')) return MtoColRole.overhead;
    final isPrice = _has(h, _pPrice);
    final money = _has(h, r'price|cost|قیمت|بها|euro|\beur\b|€|ریال|ريال|تومان|usd|dollar|دلار') || currencyOf(h) != null;
    // «Estimation Length (m)» طول است نه قیمت؛ «Total Weight (kg)» وزن است نه جمع مبلغ
    if (_has(h, r'length|طول') && !money) return MtoColRole.qty;
    if (_has(h, _pWeight) && !money) {
      return _has(h, r'/\s*(m|mt|meter|metre)\b|per\s*(m|meter|metre)\b|بر متر') ? MtoColRole.spec : MtoColRole.weight;
    }
    // مدت («Total month»، «rent month»، «unit/month») مبلغ نیست
    if (_has(h, r'month|ماه|duration|مدت|\bdays?\b|روز') && !isPrice && !money) return MtoColRole.spec;
    if (isPrice && _has(h, _pRate) && !_has(h, _pTotal) && !inBlock && !_has(h, _pQuote)) return MtoColRole.rate;
    if (isPrice) {
      if (_has(h, _pSkipPrice)) return MtoColRole.ignore;
      if (_has(h, _pTotal) && !_has(h, r'unit|واحد')) return MtoColRole.total;
      if (inBlock || _has(h, _pQuote)) return MtoColRole.quote;
      if (_has(h, _pOld)) return MtoColRole.old;
      return MtoColRole.going;
    }
    if (_has(h, _pTotal)) return MtoColRole.total;
    if (inBlock && _has(h, _pVendor)) return MtoColRole.vendor;
    if (inBlock && _has(h, _pDate)) return MtoColRole.date;
    if (inBlock && currencyOf(h) != null) return MtoColRole.quote; // «ریال»، «یورو» زیر بلوک استعلام
    if (_has(h, _pQuote) && currencyOf(h) != null) return MtoColRole.quote;
    if (_has(h, _pWeight)) return MtoColRole.weight;
    if (_has(h, _pQty) && !_has(h, _pDesc) && !_has(h, r'افزایش|افزايش|کاهش|كاهش|تغییر|change|increase')) {
      return MtoColRole.qty;
    }
    if (_has(h, _pUnit)) return MtoColRole.unit;
    if (_has(h, _pCurrency)) return MtoColRole.currency;
    if (_has(h, _pRemarks)) return MtoColRole.remarks;
    if (_has(h, _pTag) && !_has(h, r'desc|شرح')) return MtoColRole.tag;
    if (_has(_norm(h).toLowerCase(), _pSerial)) return MtoColRole.tag;
    if (_has(h, _pVendor)) return MtoColRole.vendor;
    if (_has(h, _pDesc)) return MtoColRole.desc;
    if (_has(h, _pDate)) return MtoColRole.date;
    return MtoColRole.spec;
  }

  /// یکتا کردن نقش‌های تک‌ستونی و تعیین ستون شرح/تگ بهتر
  static void _resolve(XlsxSheet sh, MtoLayout l) {
    double avgLen(MtoColumn c) {
      var n = 0, s = 0;
      for (var r = l.dataStart; r <= sh.maxRow && r < l.dataStart + 80; r++) {
        final t = textOf(sh, r, c);
        if (t.isEmpty) continue;
        n++;
        s += t.length;
      }
      return n == 0 ? 0 : s / n;
    }

    double numericShare(MtoColumn c) {
      var n = 0, k = 0;
      for (var r = l.dataStart; r <= sh.maxRow && r < l.dataStart + 80; r++) {
        final t = textOf(sh, r, c);
        if (t.isEmpty) continue;
        n++;
        if (RegExp(r'^\d{1,4}(\.\d+)?$').hasMatch(t)) k++;
      }
      return n == 0 ? 0 : k / n;
    }

    // ستون‌های پر (نسبت سطرهای دارای متن)
    final numCols = [
      for (final c in l.columns)
        if (c.role.isPrice || c.role == MtoColRole.total || c.role == MtoColRole.rate || c.role == MtoColRole.qty) ...c.cols,
    ];
    double fill(MtoColumn c) {
      var n = 0, k = 0;
      for (var r = l.dataStart; r <= sh.maxRow && r < l.dataStart + 80; r++) {
        if (numCols.isEmpty
            ? !sh.rowCells(r).any((x) => x.value is double)
            : !numCols.any((k) => (sh.cell(r, k)?.number ?? 0) > 0)) {
          continue;
        }
        n++;
        if (textOf(sh, r, c).isNotEmpty) k++;
      }
      return n == 0 ? 0 : k / n;
    }

    // شرح: ستون پرتر و با متن بلندتر میان نامزدها (ستون «Description» کم‌پر مثل ملاحظات است)
    final descs = l.all(MtoColRole.desc).toList();
    if (descs.length == 1 && fill(descs.first) < 0.4) {
      final alt = [
        for (final c in l.columns)
          if (c.role == MtoColRole.spec && fill(c) >= 0.7 && avgLen(c) >= 6 && numericShare(c) < 0.3) c,
      ]..sort((a, b) => avgLen(b).compareTo(avgLen(a)));
      if (alt.isNotEmpty) {
        descs.first.role = MtoColRole.remarks;
        alt.first.role = MtoColRole.desc;
        descs
          ..clear()
          ..add(alt.first);
      }
    }
    if (descs.length > 1) {
      descs.sort((a, b) {
        // ستون پرتر برنده است («description» هر ردیف در برابر «description» توضیحی کم‌پر)
        if ((fill(a) - fill(b)).abs() >= 0.2) return fill(b).compareTo(fill(a));
        return (fill(b) * avgLen(b).clamp(0, 30)).compareTo(fill(a) * avgLen(a).clamp(0, 30));
      });
      for (final d in descs.skip(1)) {
        d.role = MtoColRole.spec;
      }
    }
    // تگ: ترجیح ستون «Tag» بر «ردیف»؛ ستون «ITEM» متنی (مثل Fitting) بخشی از نام می‌شود
    final tags = l.all(MtoColRole.tag).toList();
    if (tags.length > 1) {
      tags.sort((a, b) {
        final s = _score(b.label).compareTo(_score(a.label));
        if (s != 0) return s;
        final e = (avgLen(a) == 0 ? 1 : 0).compareTo(avgLen(b) == 0 ? 1 : 0); // ستون خالی آخر
        if (e != 0) return e;
        final n = numericShare(b).compareTo(numericShare(a));
        return n != 0 ? n : a.col.compareTo(b.col);
      });
      for (final t in tags.skip(1)) {
        if (numericShare(t) < 0.5) {
          t.role = MtoColRole.spec;
          t.namePart = l.first(MtoColRole.desc) == null;
        } else {
          t.role = MtoColRole.ignore;
          l.serialCol ??= t;
        }
      }
    }
    final tag = l.first(MtoColRole.tag);
    if (tag != null) l.tagIsSerial = numericShare(tag) > 0.8;
    if (l.tagIsSerial) l.serialCol = tag;
    // نقش‌های تک‌ستونی
    for (final r in [
      MtoColRole.qty, MtoColRole.unit, MtoColRole.currency, MtoColRole.weight, MtoColRole.remarks, MtoColRole.overhead,
    ]) {
      final list = l.all(r).toList();
      for (final x in list.skip(1)) {
        x.role = r == MtoColRole.remarks ? MtoColRole.spec : MtoColRole.ignore;
      }
    }
    // اگر شرح نیست ولی زیرستون‌های «DESCRIPTION» هست، اولی شرح است
    if (l.first(MtoColRole.desc) == null) {
      final np = l.columns.where((c) => c.namePart).toList();
      if (np.isEmpty) {
        final specs = l.all(MtoColRole.spec).toList()..sort((a, b) => avgLen(b).compareTo(avgLen(a)));
        if (specs.isNotEmpty && avgLen(specs.first) > 8) specs.first.role = MtoColRole.desc;
      }
    }
    // چند ستون «قیمت مبنا» با سال‌های مختلف: قدیمی‌ترها «قیمت قدیمی»اند
    final goings = l.all(MtoColRole.going).where((c) => c.year != null).toList();
    if (goings.length > 1) {
      final maxY = goings.map((c) => c.year!).reduce((a, b) => a > b ? a : b);
      for (final g in goings) {
        if (g.year! <= maxY - 2) g.role = MtoColRole.old;
      }
    }
    l.summary = (tag == null || l.tagIsSerial) && l.first(MtoColRole.qty) == null && l.first(MtoColRole.unit) == null;
    if (l.first(MtoColRole.desc) == null && !l.columns.any((c) => c.namePart)) {
      l.notes.add('ستون شرح پیدا نشد؛ از فهرست ستون‌ها انتخاب کنید.');
    }
    if (!l.columns.any((c) => c.role.isPrice)) l.notes.add('ستون قیمت پیدا نشد؛ از فهرست ستون‌ها انتخاب کنید.');
    if (l.summary) l.notes.add('جدول جمع‌بندی به نظر می‌رسد (بدون تگ و تعداد)؛ به طور پیش‌فرض وارد نمی‌شود.');
  }

  /// قیمت واحد نهایی هر ردیف از ستون‌های موجود؛ هیچ مبلغی بی‌صدا دور ریخته نمی‌شود:
  /// - قیمت واحد نیست ← جمع ردیف ÷ تعداد، وگرنه نرخ (هر کیلو/متر) × وزن یا طول
  /// - قیمت واحد × تعداد با جمع ردیف نمی‌خواند (مثل «Installation»: قیمت ۱، جمع ۱۵۰٬۰۰۰) ← جمع ردیف، یکجا
  /// - مقدار طول (m) یا وزن (kg) است ← یک قلم یکجا با مبلغ جمع ردیف
  /// - ضریب بالاسری ردیف (۰٫۳، ۳۰ یا مبلغ بالاسری) جدا ثبت می‌شود؛ قیمت ثبت‌شده خام است
  static void _reconcile(XlsxSheet sh, MtoLayout l, int r, MtoItem it, List<String> lines,
      {required List<MtoColumn> rates,
      required List<MtoColumn> totals,
      required MtoColumn? overheadCol,
      required String? rowCur,
      required double factor,
      required bool qtyKg,
      required bool qtyLen,
      required double? qtyRaw}) {
    String fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    // جمع ردیف: ستون ارزدار مقدم (مبلغ خام، نه «Total+Overheads»)
    final ranked = [...totals]..sort((a, b) => (a.currency == null ? 1 : 0).compareTo(b.currency == null ? 1 : 0));
    final totCol = ranked.where((c) => (numOf(sh, r, c) ?? 0) > 0).firstOrNull;
    final rowTot = l.orphans[r] ?? (totCol == null ? null : numOf(sh, r, totCol));
    final totCur = totCol?.currency ?? totals.map((c) => c.currency).whereType<String>().firstOrNull ?? rowCur;
    // ضریب بالاسری
    double? ovF;
    if (overheadCol != null && l.orphans[r] == null) {
      final ov = numOf(sh, r, overheadCol);
      if (ov != null && ov > 0) {
        final hp = RegExp(r'(\d+(?:\.\d+)?)\s*%').firstMatch(overheadCol.header);
        final pct = hp == null ? null : double.parse(hp.group(1)!) / 100;
        if (ov <= 1) {
          ovF = ov;
        } else if (pct != null && (ov / 100 - pct).abs() < 1e-9) {
          ovF = pct;
        } else if (rowTot != null && ov < rowTot) {
          ovF = ov / rowTot; // مبلغ بالاسری
        } else if (ov <= 100) {
          ovF = ov / 100;
        }
      }
    }
    void setGoing(double v, String? c) {
      c ??= l.sheetCurrency ?? (v >= 5e6 ? 'IRR' : 'EUR');
      it.goingEur = c == 'EUR' ? v : null;
      it.goingIrr = c == 'IRR' ? v : null;
      it.goingUsd = c == 'USD' ? v : null;
    }

    void asLot(double amount, String? c, String basis) {
      if (qtyRaw != null && qtyRaw != 1 && !qtyKg) lines.add('${qtyLen ? 'Length (m)' : 'Quantity in source'}: ${fmt(qtyRaw)}');
      it.quantity = 1;
      setGoing(amount, c);
      lines.add('Price basis: $basis');
    }

    final unit0 = it.goingEur ?? it.goingUsd ?? it.goingIrr;
    final unitCur = it.goingEur != null ? 'EUR' : (it.goingUsd != null ? 'USD' : (it.goingIrr != null ? 'IRR' : null));
    final qn = (it.quantity ?? 1) > 0 ? (it.quantity ?? 1) : 1.0;
    if (unit0 != null) {
      final sameCur = totCur == null || unitCur == null || totCur == unitCur;
      if (rowTot != null && sameCur && factor == 1 && !qtyKg) {
        final exp = unit0 * (qtyLen ? (qtyRaw ?? 1) : qn);
        final ratio = rowTot / exp;
        final withOv = ovF != null && (ratio - (1 + ovF)).abs() < 0.01;
        if (qtyLen && (ratio - 1).abs() <= 0.02) {
          asLot(rowTot, totCur ?? unitCur, 'جمع ردیف (طول × قیمت هر متر)');
        } else if ((ratio - 1).abs() > 0.02 && !withOv && unit0 > 1 && ratio >= 0.5 && ratio <= 2 && qtyRaw != null) {
          // اختلاف کم: قیمت واحد × تعداد می‌ماند، فقط هشدار
          it.warnings.add('${sh.name}!ردیف $r: قیمت واحد ${fmt(unit0)} × تعداد ${fmt(qn)} = ${fmt(exp)} '
              'با جمع ردیف ${fmt(rowTot)} نمی‌خواند — بررسی شود');
        } else if ((ratio - 1).abs() > 0.02 && !withOv) {
          if (unit0 > 1) {
            it.warnings.add('${sh.name}!ردیف $r: قیمت واحد ${fmt(unit0)} × تعداد ${fmt(qn)} = ${fmt(exp)} '
                'با جمع ردیف ${fmt(rowTot)} نمی‌خواند؛ جمع ردیف به‌عنوان مبلغ یکجا ثبت شد');
            lines.add('Unit price in source: ${fmt(unit0)}');
          }
          asLot(rowTot, totCur ?? unitCur, 'جمع ردیف');
        }
      } else if (qtyLen && qtyRaw != null && qtyRaw > 0) {
        asLot(unit0 * qtyRaw, unitCur, 'طول × قیمت هر متر');
      }
    } else if (rowTot != null) {
      if (qtyLen || qtyKg) {
        asLot(rowTot, totCur, 'جمع ردیف');
      } else {
        final u = rowTot / qn;
        if (qn > 1 && u <= 1) {
          asLot(rowTot, totCur, 'جمع ردیف'); // «office furnish | 300000 | total | 1»
        } else {
          setGoing(u, totCur);
          lines.add('Price basis: ${qn == 1 ? 'جمع ردیف' : 'جمع ردیف ÷ تعداد'}');
        }
      }
    } else {
      for (final rc in rates) {
        final v = numOf(sh, r, rc);
        if (v == null || v <= 0) continue;
        final perLen = _has(rc.header, r'/\s*(m|mt|meter|metre|lm)\b|per\s*(m|meter|metre)\b|متر');
        final w = it.weightKg;
        if (perLen && qtyLen && qtyRaw != null && qtyRaw > 0) {
          asLot(v * qtyRaw, rc.currency ?? rowCur, 'نرخ هر متر × طول');
          break;
        }
        if (!perLen && w != null && w > 0) {
          setGoing(v * w, rc.currency ?? rowCur);
          lines.add('Price basis: نرخ هر کیلو × وزن (${fmt(v)} × ${fmt(w)})');
          break;
        }
      }
    }
    // کنترل پرت: قیمت واحد با نرخ هر کیلو × وزن همان ردیف خیلی فاصله دارد (مثل ۵٬۰۰۰ در برابر ۴٫۲ × ۲۰٬۰۰۰)
    final u1 = it.goingEur ?? it.goingUsd ?? it.goingIrr;
    final w = it.weightKg;
    if (u1 != null && w != null && w > 0 && it.quantity == 1) {
      for (final rc in rates) {
        if (_has(rc.header, r'/\s*(m|mt|meter|metre|lm)\b|per\s*(m|meter|metre)\b|متر')) continue;
        final v = numOf(sh, r, rc);
        if (v == null || v <= 0) continue;
        final byRate = v * w;
        if (u1 / byRate > 3 || byRate / u1 > 3) {
          it.warnings.add('${sh.name}!ردیف $r: قیمت ${fmt(u1)} با نرخ ${fmt(v)} × وزن ${fmt(w)} kg = ${fmt(byRate)} '
              'نمی‌خواند (پرت؟) — قیمت فایل ثبت شد، بررسی شود');
        }
        break;
      }
    }
    if (ovF != null) {
      it.overhead = ovF;
      final pc = ovF * 100;
      lines.add('Overhead: ${pc.toStringAsFixed((pc - pc.round()).abs() < 0.05 ? 0 : 1)}%');
    }
  }

  /// پکیج مستقل در شیت ظروف/مخازن («AIR DRYER PACKAGE»، «WALNUT FILTER») رده‌ی خودش را دارد
  static String? _packageOverride(String? sheetCat, String name) {
    if (sheetCat != 'VESSEL' && sheetCat != 'TANK') return null;
    final s = suggestCategoryFromText(name);
    const own = {'AIR_DRYER', 'FILTER', 'COMPRESSOR', 'PUMP', 'CIP', 'DEAERATOR', 'IGF', 'DESALTER'};
    return s != null && own.contains(s) ? s : null;
  }

  static int _score(String h) {
    final l = h.toLowerCase();
    if (_has(l, r'\btag|شماره ?تگ')) return 5;
    if (_has(l, r'equip|تجهیز')) return 4;
    if (_has(l, r'item ?no')) return 3;
    if (_has(l, r'code|کد')) return 2;
    return 0;
  }

  // ---------------------------------------------------------------------------
  // خواندن مقادیر

  /// متن یک ستون (با ستون‌های ادغام‌شده‌ی همراهش)
  static String textOf(XlsxSheet sh, int r, MtoColumn c, {bool tag = false}) {
    final parts = [for (final k in c.cols) if (sh.text(r, k).isNotEmpty && !_isXlError(sh.text(r, k))) sh.text(r, k)];
    if (parts.isEmpty) return '';
    if (!tag) return parts.join(' ');
    // تگ دوتکه: «DE» + «-001-A/B» ← «DE-001-A/B»؛ «CR» + «001» ← «CR-001»
    var s = parts.first;
    for (final p in parts.skip(1)) {
      s = (s.endsWith('-') || p.startsWith('-')) ? '$s$p' : '$s-$p';
    }
    return s;
  }

  static double? numOf(XlsxSheet sh, int r, MtoColumn c) {
    for (final k in c.cols) {
      final v = sh.cell(r, k)?.number;
      if (v != null) return v;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // خواندن اقلام

  /// خواندن اقلام با قالب [l]؛ اقلام هر رده در یک گروه (MtoSheet) جدا.
  /// [overrides]: رده‌ی انتخابی کاربر برای هر قلم («شیت#ردیف» ← کد رده)
  static List<MtoSheet> parse(XlsxSheet sh, MtoLayout l, {int? defaultYear, Map<String, String?> overrides = const {}}) {
    final desc = l.first(MtoColRole.desc);
    final nameParts = l.columns.where((c) => c.namePart).toList();
    if (desc == null && nameParts.isEmpty) return const [];
    final tag = l.first(MtoColRole.tag);
    final qty = l.first(MtoColRole.qty);
    final unitCol = l.first(MtoColRole.unit);
    final curCol = l.first(MtoColRole.currency);
    final weightCol = l.first(MtoColRole.weight);
    final remarks = l.first(MtoColRole.remarks);
    final specs = l.all(MtoColRole.spec).toList();
    final prices = l.columns.where((c) => c.role.isPrice).toList();
    final rates = l.all(MtoColRole.rate).toList();
    final totals = l.all(MtoColRole.total).toList();
    final overheadCol = l.first(MtoColRole.overhead);
    final usedCols = {for (final c in l.columns) ...c.cols};
    final freeNext = qty == null || usedCols.contains(qty.cols.last + 1) ? null : qty.cols.last + 1;
    // ستون تعداد با واحد وزنی/طولی در سرستون: «QTY (kg)»، «Estimation Length (m)»
    final qtyKg = qty != null && _has(qty.header, r'\(\s*(kg|kgs|ton|tonne|کیلو|تن)\s*\)|\bkg\b');
    final qtyTon = qty != null && _has(qty.header, r'\(\s*(ton|tonne|تن)\s*\)');
    final qtyLen = qty != null && _has(qty.header, r'length|طول|\(\s*m\s*\)|\bmeter|متر');
    // ستون‌های عددی که ممکن است جمع شیت را داشته باشند
    final moneyCols = [...prices, ...totals, ...rates, if (overheadCol != null) overheadCol];
    bool sumFormula(int r) => [
          for (final c in moneyCols)
            for (final k in c.cols) sh.cell(r, k)?.formula ?? '',
        ].any((f) => RegExp(r'^=?\s*SUM\s*\(', caseSensitive: false).hasMatch(f.trim()));
    void addTotals(int r) {
      for (final c in moneyCols) {
        for (final k in c.cols) {
          final v = sh.cell(r, k)?.number;
          if (v != null && v >= 1) l.sheetTotals.add((r, v));
        }
      }
    }
    double rowMax(int r) => [
          for (final c in moneyCols)
            for (final k in c.cols) sh.cell(r, k)?.number ?? 0,
        ].fold(0.0, (a, b) => b > a ? b : a);
    // رده‌ی شیت: عنوان بالای جدول (مثل «IGF PACKAGES») بر نام کوتاه شیت (مثل «IWWTP-A») مقدم است
    final ctxCat = [for (final c in l.context) suggestCategory(c) ?? suggestCategoryFromText(c)].whereType<String>().firstOrNull;
    // نام شیت با چند رده («H-EX & HEATER»، «PIPE & FITTING & Valves»، «E&I&C»): رده‌ی هر قلم از نام خودش، میان همین نامزدها
    final cands = sheetCategoryCandidates(sh.name);
    final sheetCat = ctxCat ?? (cands.length == 1 ? cands.first : null);
    String? fromCands(String text) {
      if (cands.length < 2) return null;
      final s = suggestCategoryFromText(text);
      return s ?? cands.first;
    }
    final contextSpecs = [
      for (final c in l.context)
        if (suggestCategory(c) == null && suggestCategoryFromText(c) == null) c,
    ];
    final baseYear = l.sheetYear ?? defaultYear;
    final goingYear = prices.where((c) => c.role == MtoColRole.going && c.year != null).map((c) => c.year).firstOrNull;
    final goingMonth = prices.where((c) => c.role == MtoColRole.going && c.year != null).map((c) => c.month).firstOrNull;
    final oldCol = prices.where((c) => c.role == MtoColRole.old && c.year != null).firstOrNull;

    final pending = <(MtoItem, List<String>, String?)>[]; // قلم، سطرهای شرح، رده‌ی بخش
    String? section;
    String? sectionCat;
    String? sectionSerial;
    final serialCol = l.serialCol;
    String serialOf(int r) {
      if (serialCol == null) return '';
      final v = sh.cell(r, serialCol.col)?.value;
      if (v is double) return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
      return sh.text(r, serialCol.col);
    }

    MtoItem? cur;
    List<String>? curLines;
    final usedTags = <String>{};
    var curEnd = 0;
    // جمع جاری ستون‌های مبلغ از آخرین سطر جمع: سطر جمعِ بدون فرمول (فایل «فقط مقدار») هم شناخته شود
    final moneyKeys = {for (final c in moneyCols) ...c.cols};
    final runSum = <int, double>{};
    var runCount = 0;
    bool looksLikeSum(int r) {
      if (runCount < 2) return false;
      for (final k in moneyKeys) {
        final v = sh.cell(r, k)?.number;
        final s0 = runSum[k] ?? 0;
        if (v != null && v > 0 && s0 > 0 && (v - s0).abs() <= 0.005 * v) return true;
      }
      return false;
    }
    void resetSum() {
      runSum.clear();
      runCount = 0;
    }
    for (var r = l.dataStart; r <= sh.maxRow; r++) {
      var d = desc == null ? '' : textOf(sh, r, desc).replaceAll('\r', '');
      final t = tag == null ? '' : textOf(sh, r, tag, tag: true);
      final np = [for (final c in nameParts) textOf(sh, r, c)].where((x) => x.isNotEmpty && x != '-').join(' ');
      final q = qty == null ? null : numOf(sh, r, qty);
      var hasPrice = [...prices, ...rates, ...totals].any((p) => (numOf(sh, r, p) ?? 0) > 0);
      // سطر جمع: فرمول SUM در ستون‌های مبلغ و بدون شرح (مثل «Installation Included» + جمع ستون)
      if (d.isEmpty && np.isEmpty && sumFormula(r)) {
        addTotals(r);
        resetSum();
        cur = null;
        continue;
      }
      // سطر جمع بدون فرمول: مبلغ برابر جمع اقلام قبلی و بدون تعداد (مثل «Installation Included | 258,500»)
      if (q == null && looksLikeSum(r) && (d.isEmpty || _has(d, r'included|total|جمع|sum\b'))) {
        addTotals(r);
        resetSum();
        cur = null;
        continue;
      }
      // ردیفی که فقط شماره‌ی ردیف دارد (مثل «15 | | 2,247,050» = جمع × ۱٫۳) قلم نیست
      if (d.isEmpty && np.isEmpty && (t.isEmpty || l.tagIsSerial)) {
        // متن و مبلغ بیرون از ستون شرح (مثل «Existing Flare move» = ۱٬۰۰۰٬۰۰۰): قلم جدا با هشدار، نه حذف بی‌صدا
        final texts = [
          for (final x in sh.rowCells(r))
            if (x.value is! double && x.text.trim().length >= 4 && !RegExp(r'^[\d.,\s%-]+$').hasMatch(x.text.trim())) x.text.trim(),
        ];
        final amount = [for (final x in sh.rowCells(r)) if (x.formula == null) x.number ?? 0].fold(0.0, (a, b) => b > a ? b : a);
        if (texts.length == 1 && amount >= 1000 && !_has(texts.first, '$_pNotes|^(جمع|total|sum\b)')) {
          d = texts.first;
          l.notes.add('ردیف $r: «${texts.first}» با مبلغ ${amount.toStringAsFixed(0)} بیرون از ستون شرح بود؛ به‌عنوان قلم جدا خوانده شد.');
          l.orphans[r] = amount;
          hasPrice = true;
        } else {
          if (amount > 0 && texts.isEmpty) rowMax(r) > 0 ? addTotals(r) : l.sheetTotals.add((r, amount));
          continue;
        }
      }
      final first = _norm(d.isNotEmpty ? d : (np.isNotEmpty ? np : t)).toLowerCase();
      if (RegExp(r'^(جمع|total|sub.?total|grand|sum\b|برآورد هزینه|مجموع)', caseSensitive: false).hasMatch(first) ||
          _has(first, _pNotes)) {
        addTotals(r);
        cur = null;
        continue;
      }
      // ادامه‌ی شرح قلم چندسطری (گزارش چاپی)
      final isTagRow = t.isNotEmpty;
      if (cur != null && !isTagRow && q == null && !hasPrice && d.isNotEmpty) {
        final spec = d.contains(':') || d.startsWith('&') || d.startsWith('(');
        if (r <= curEnd || spec) {
          curLines!.add(d);
          continue;
        }
      }
      // سطر عنوان بخش: فقط متن، بدون تعداد و قیمت
      // ردیف مادر زیرمجموعه («65 | CRANES | طبق لیست زیر» و بعد 65.1، 65.2، …) قلم نیست، حتی اگر مبلغ جمع داشته باشد
      final serNow = serialOf(r);
      final parentOfNext = serNow.isNotEmpty && r < sh.maxRow && serialOf(r + 1).startsWith('$serNow.');
      if ((q == null && !hasPrice && (t.isEmpty || (d.isEmpty && np.isEmpty) || l.tagIsSerial)) ||
          (parentOfNext && q == null && (t.isEmpty || l.tagIsSerial))) {
        final txt = d.isNotEmpty ? d : (np.isNotEmpty ? np : t);
        if (txt.length < 80) {
          section = _norm(txt);
          sectionCat = suggestCategory(section) ?? suggestCategoryFromText(section);
          sectionSerial = serialOf(r);
        }
        cur = null;
        continue;
      }
      // پایان زیرمجموعه‌ی بخش: ردیف ۶۸ بعد از ۶۷٫۱، ۶۷٫۲، …
      final ser = serialOf(r);
      if (sectionSerial != null && sectionSerial.isNotEmpty && ser.isNotEmpty && !ser.startsWith('$sectionSerial.')) {
        section = null;
        sectionCat = null;
        sectionSerial = null;
      }

      // سطرهای اول شرح تا اولین «کلید: مقدار» = نام (شکست خط داخل سلول برای جا شدن متن است)
      final dLines = [for (final x in d.split('\n')) if (x.trim().isNotEmpty && x.trim() != '-') x.trim()];
      var k = 0;
      final head = <String>[];
      while (k < dLines.length && !dLines[k].contains(':') && !dLines[k].startsWith('&')) {
        head.add(dLines[k]);
        k++;
      }
      final nameLine = head.isNotEmpty ? head.join(' ') : (np.isNotEmpty ? np : (dLines.isNotEmpty ? dLines.first : t));
      // نام کوتاه برای شرح‌های بسیار بلند (متن کامل در شرح قلم می‌ماند)
      var shortName = nameLine;
      if (nameLine.length > 90) {
        final cut = nameLine.indexOf(RegExp(r'[,،.;]\s'), 25);
        shortName = (cut > 0 && cut <= 90) ? nameLine.substring(0, cut) : '${nameLine.substring(0, nameLine.lastIndexOf(' ', 88).clamp(30, 88))}…';
      }
      final lines = <String>[
        shortName,
        if (shortName != nameLine) nameLine,
        ...dLines.skip(head.isEmpty && np.isEmpty && dLines.isNotEmpty ? 1 : k),
      ];
      final tagText = t.isEmpty
          ? '${sh.name}#$r'
          : (l.tagIsSerial ? '${sh.name}#${t.replaceAll(RegExp(r'\.0$'), '')}' : t.replaceAll(RegExp(r'\s+'), ' '));
      var uniqueTag = tagText;
      for (var n = 2; usedTags.contains(uniqueTag); n++) {
        uniqueTag = '$tagText ($n)';
      }
      usedTags.add(uniqueTag);
      final it = MtoItem(r, uniqueTag, '');
      var unit = unitCol == null ? '' : textOf(sh, r, unitCol).trim().toLowerCase();
      // ستون واحدِ بی‌عنوان کنار تعداد («QTY | m2 | 250»)
      if (unitCol == null && qty != null && freeNext != null) {
        final t = sh.text(r, freeNext).trim();
        if (t.isNotEmpty && t.length <= 14 && sh.cell(r, freeNext)?.value is! double && !RegExp(r'\d{3,}').hasMatch(t)) {
          unit = t.toLowerCase();
        }
      }
      final perKg = RegExp(r'^(kg|kgs|kilo|کیلو|کیلوگرم|كيلوگرم)').hasMatch(unit);
      final perTon = RegExp(r'^(ton|tons|tonne|t|تن)$').hasMatch(unit);
      var factor = 1.0; // قیمت واحد × مقدار وقتی واحد وزنی است
      if ((qtyKg || qtyTon) && q != null) {
        // «QTY (kg)»: مقدار، وزن است؛ قیمت از نرخ هر کیلو × وزن یا جمع ردیف
        it.weightKg = q * (qtyTon ? 1000 : 1);
        it.quantity = 1;
        lines.add('Weight (kg): ${it.weightKg!.toStringAsFixed(0)}');
      } else if ((perKg || perTon) && q != null) {
        it.weightKg = q * (perTon ? 1000 : 1);
        it.quantity = 1;
        factor = q;
        lines.add('Weight (kg): ${it.weightKg!.toStringAsFixed(0)}');
      } else {
        it.quantity = q;
        if (unit.isNotEmpty && !RegExp(r'^(no\.?|nos\.?|set|sets|ea|each|عدد|دستگاه|pc|pcs|item|a lot|lot|unit)$').hasMatch(unit)) {
          lines.add('Unit: $unit');
        }
      }
      if (qtyLen && it.quantity != null && !(qtyKg || qtyTon)) lines.add('Unit: m');
      if (it.quantity == null) {
        it.warnings.add('${sh.name}!ردیف $r: تعداد عددی نیست — ۱ در نظر گرفته شد');
        it.quantity = 1;
      }
      if (weightCol != null) {
        final w = numOf(sh, r, weightCol);
        if (w != null && w > 0) it.weightKg ??= w * (_has(weightCol.header, r'ton|تن') ? 1000 : 1);
      }
      for (final s in [...nameParts, ...specs]) {
        if (identical(s, desc)) continue;
        final v = textOf(sh, r, s);
        if (v.isEmpty || RegExp(r'^[-—_.\s]+$').hasMatch(v)) continue; // «_» و «-» یعنی خالی
        lines.add('${s.label.replaceAll(':', ' ')}: ${v.replaceAll('\n', ' ')}');
      }
      for (final c in contextSpecs) {
        lines.add('Section: $c');
      }
      if (section != null) lines.add('Group: $section');
      final rowCur = curCol == null ? null : currencyOf(textOf(sh, r, curCol));
      it.refCurrency = rowCur;
      final rem = remarks == null ? '' : textOf(sh, r, remarks);
      // ملاحظات عددی (مثل قیمت دیگر در ستون REMARKS) دامنه‌ی تأمین نیست؛ به‌عنوان مشخصه نگه داشته می‌شود
      if (rem.isNotEmpty) {
        if (RegExp(r'^-?[\d,]+(\.\d+)?$').hasMatch(rem.trim())) {
          lines.add('${remarks!.label}: ${rem.trim()}');
        } else {
          it.scopeLines.add(rem.replaceAll('\n', ' '));
        }
      }

      for (final p in prices) {
        final v0 = numOf(sh, r, p);
        if (v0 == null || v0 <= 0) continue;
        final v = v0 * factor;
        var cur0 = p.currency ?? rowCur;
        if (cur0 == null) {
          cur0 = v0 >= 5e6 ? 'IRR' : 'EUR';
          it.warnings.add('${sh.name}!ردیف $r: ارز ستون «${p.label}» مشخص نبود؛ از بزرگی عدد «$cur0» فرض شد');
        }
        switch (p.role) {
          case MtoColRole.going:
            if (cur0 == 'IRR') it.goingIrr ??= v;
            if (cur0 == 'EUR') it.goingEur ??= v;
            if (cur0 == 'USD') it.goingUsd ??= v;
          case MtoColRole.old:
            if (cur0 == 'IRR') it.oldIrr ??= v;
            if (cur0 == 'EUR') it.oldEur ??= v;
            if (cur0 == 'USD') it.oldUsd ??= v;
          case MtoColRole.quote:
            final vendorCol = l.columns
                .where((c) => c.role == MtoColRole.vendor && (p.block == null ? c.block == null : c.block == p.block))
                .firstOrNull;
            final dateCol =
                l.columns.where((c) => c.role == MtoColRole.date && (p.block == null || c.block == p.block)).firstOrNull;
            final vendor = vendorCol == null ? '' : textOf(sh, r, vendorCol);
            final qv = MtoQuote(
              vendor: vendor.isNotEmpty ? vendor : (p.blockLabel ?? p.label),
              currency: cur0,
              amount: v,
              formula: sh.cell(r, p.col)?.formula,
            );
            if (dateCol != null) MtoImporter.applyQuoteDate(qv, sh.cell(r, dateCol.col), it, sh.name);
            qv.year ??= p.year ?? baseYear;
            qv.month ??= p.month;
            it.quotes.add(qv);
          default:
            break;
        }
      }
      _reconcile(sh, l, r, it, lines,
          rates: rates, totals: totals, overheadCol: overheadCol, rowCur: rowCur, factor: factor,
          qtyKg: qtyKg || qtyTon, qtyLen: qtyLen, qtyRaw: q);
      pending.add((it, lines, sectionCat));
      for (final k in moneyKeys) {
        final v = sh.cell(r, k)?.number;
        if (v != null && v > 0) runSum[k] = (runSum[k] ?? 0) + v;
      }
      runCount++;
      cur = it;
      curLines = lines;
      curEnd = r;
      for (final c in [if (tag != null) tag, if (qty != null) qty, if (desc != null) desc]) {
        final m = sh.mergeAt(r, c.col);
        if (m != null && m.$3 > curEnd) curEnd = m.$3;
      }
    }

    // ساخت شرح نهایی و گروه‌بندی بر اساس رده
    final groups = <String, MtoSheet>{};
    for (final (it0, lines, secCat) in pending) {
      final it = MtoItem(it0.row, it0.tag, lines.join('\n'))
        ..quantity = it0.quantity
        ..refCurrency = it0.refCurrency
        ..goingIrr = it0.goingIrr
        ..goingEur = it0.goingEur
        ..goingUsd = it0.goingUsd
        ..oldIrr = it0.oldIrr
        ..oldEur = it0.oldEur
        ..oldUsd = it0.oldUsd
        ..weightKg = it0.weightKg
        ..overhead = it0.overhead;
      it.quotes.addAll(it0.quotes);
      it.warnings.addAll(it0.warnings);
      it.scopeLines.addAll(it0.scopeLines);
      final dd = parseMtoDescription(it.description);
      it.specs.addAll(dd.specs);
      it.scopeLines.addAll(dd.scope);
      final key0 = '${sh.name}#${it.row}';
      final cat = overrides.containsKey(key0)
          ? overrides[key0]
          : (serviceCategoryFromText(it.name) ??
              _packageOverride(sheetCat, it.name) ??
              sheetCat ??
              priorityCategoryFromText(it.name) ??
              (secCat == null ? fromCands(it.name) : null) ??
              secCat ??
              suggestCategoryFromText(it.name) ??
              suggestCategoryFromText(it.description) ??
              (l.summary ? null : 'MISC_PKG')); // نامشخص ← «سایر پکیج‌ها و تجهیزات» (در پیش‌نمایش قابل تغییر)
      it.autoCategory = !overrides.containsKey(key0);
      final key = cat ?? '?';
      final g = groups[key] ??= (MtoSheet(sh.name, l.context.isEmpty ? sh.name : l.context.join(' · '))
        ..categoryCode = cat
        ..source = sh.name
        ..layout = l
        ..selected = cat != null && !l.summary
        ..goingYear = goingYear ?? baseYear
        ..goingMonth = goingYear == null ? null : goingMonth
        ..goingLabel = goingYear == null ? (l.sheetYear == null ? '' : '${l.sheetYear}') : '$goingYear'
        ..oldYear = oldCol?.year
        ..oldMonth = oldCol?.month
        ..oldLabel = oldCol?.year == null ? '' : '${oldCol!.year}');
      g.items.add(it);
    }
    final list = groups.values.toList();
    if (list.length > 1) {
      for (final g in list) {
        g.label = '${sh.name} › ${g.categoryCode ?? 'رده نامشخص'}';
      }
    }
    return list;
  }

  /// صفحه‌ی ادامه‌ی گزارش چاپی (بدون سطر عنوان): متن ستون شرح به شرح [last] اضافه می‌شود.
  static bool appendContinuation(XlsxSheet sh, MtoItem last, MtoLayout prev) {
    final desc = prev.first(MtoColRole.desc);
    if (desc == null) return false;
    var cont = false;
    for (var r = 1; r <= 25 && r <= sh.maxRow; r++) {
      for (var c = 1; c <= 6 && c <= sh.maxCol; c++) {
        if (_has(sh.text(r, c), r"cont'?d|continued|ادامه")) cont = true;
      }
    }
    if (!cont) return false;
    final lines = <String>[];
    for (var r = 1; r <= sh.maxRow; r++) {
      final t = textOf(sh, r, desc).trim();
      if (t.isEmpty) continue;
      if (_has(t, r'^(total|جمع)')) break;
      lines.add(t);
    }
    if (lines.isEmpty) return false;
    last.description = '${last.description}\n${lines.join('\n')}';
    final dd = parseMtoDescription(last.description);
    last.specs
      ..clear()
      ..addAll(dd.specs);
    return true;
  }

  // ---------------------------------------------------------------------------
  // شیت‌های نصب و اجرا: وزن هر تجهیز (کیلوگرم) از ستون «وزن واحد» یا مقدار با واحد Kg/Ton

  static Map<String, double> weightsFrom(XlsxSheet sh) {
    final out = <String, double>{};
    final l = detect(sh);
    if (l == null) return out;
    final tag = l.first(MtoColRole.tag);
    if (tag == null || l.tagIsSerial) return out;
    final qty = l.first(MtoColRole.qty);
    final unit = l.first(MtoColRole.unit);
    final w = l.first(MtoColRole.weight);
    String? curTag;
    for (var r = l.dataStart; r <= sh.maxRow; r++) {
      final t = textOf(sh, r, tag, tag: true);
      if (t.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(t)) {
        curTag = normTag(t);
        final wv = w == null ? null : numOf(sh, r, w);
        if (wv != null && wv > 0) {
          final u = unit == null ? '' : textOf(sh, r, unit).trim().toLowerCase();
          final ton = _has(w!.header, r'ton|تن') || RegExp(r'^(ton|tons|tonne|t|تن)$').hasMatch(u);
          out[curTag] = wv * (ton ? 1000 : 1);
          continue;
        }
      } else if (t.isNotEmpty) {
        curTag = null;
      }
      if (curTag == null || qty == null || unit == null) continue;
      final u = textOf(sh, r, unit).trim().toLowerCase();
      final q = numOf(sh, r, qty);
      if (q == null || q <= 0) continue;
      final kg = RegExp(r'^(kg|kgs|کیلو)').hasMatch(u)
          ? q
          : (RegExp(r'^(ton|tons|tonne|t|تن)$').hasMatch(u) ? q * 1000 : null);
      if (kg == null) continue;
      // سطر خود تجهیز یا بزرگ‌ترین سطر زیرمجموعه (بارگیری/حمل کل مصالح)
      if ((out[curTag] ?? 0) < kg) out[curTag] = kg;
    }
    return out;
  }
}
