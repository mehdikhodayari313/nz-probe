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
  total('جمع (نادیده)');

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
  String get label => own.isNotEmpty ? own : header;
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

const _pPrice = r'price|cost|قیمت|بها|هزینه|fee|amount|estimat|برآورد|مبلغ';
const _pTotal = r'total|جمع|مبلغ کل|(^|\s)کل(\s|$)|sum\b|aggregate|تمام شده';
const _pSkipPrice = r'avg|average|میانگین|no\. of|number of|تعداد استعلام|ratio|نسبت|%|درصد';
const _pQuote = r'quot|offer|vendor price|استعلام|پیشنهاد|فروشنده|bid\b|tender';
const _pOld = r'\bold\b|previous|prev\.|قبلی|قدیم|last rev|سابق';
const _pQty = r"\bqty|quantity|q'ty|تعداد|no\.? ?of ?(units|sets|items)|مقدار";
const _pTag = r'\btag|item ?no|equipment ?(no|code)|equip\. ?no|item ?code|شماره ?تگ|شماره ?تجهیز|کد ?تجهیز|^کد$';
const _pSerial = r'^(ردیف|row|s/?n|sr\.?|no\.?|#|item|ر|رديف)$';
const _pDesc = r'desc|شرح|equipment|service|title|نام|عنوان|مشخصات کلی|name';
const _pCurrency = r'currency|ارز';
const _pDate = r'date|تاریخ';
const _pVendor = r'vendor|supplier|manufactur|maker|source|منبع|سازنده|فروشنده|تامین|تأمین|company|شرکت';
const _pRemarks = r'remark|note|comment|ملاحظات|توضیح';
const _pBlock = r'استعلام|quotation|quote|offer|vendor|پیشنهاد|bidder|supplier';
const _pWeight = r'وزن|weight';
const _pUnit = r'^(unit|uom|u\.o\.m\.?|واحد|واحد شمارش)$';

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
    if (RegExp(r'^(c\.|ins\b|ins-|install)|construction|نصب|اجرا|^cv\d').hasMatch(n)) return MtoSheetKind.install;
    for (var r = 1; r <= 15 && r <= sh.maxRow; r++) {
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
    return (m - hdr) > k ? (m - hdr) : k;
  }

  /// تشخیص قالب جدول اقلام یک شیت؛ null = جدول اقلام پیدا نشد.
  static MtoLayout? detect(XlsxSheet sh) {
    int? bestRow;
    var bestScore = 0;
    for (var r = 1; r <= 40 && r <= sh.maxRow; r++) {
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
      final score = (desc ? 3 : 0) + (tag ? 1 : 0) + (qty ? 1 : 0) + (price ? 1 : 0);
      if (desc && score >= 5 && score > bestScore) {
        bestScore = score;
        bestRow = r;
      }
    }
    if (bestRow == null) return null;
    return layoutAt(sh, bestRow);
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
          if (!sh.isMergedTail(r, c) && sh.text(r, c).isNotEmpty) _norm(sh.text(r, c)),
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
      } else if (roleOwn == MtoColRole.spec && specific.contains(roleFull)) {
        col.role = roleFull; // مثل «QUANTITY / LENGTH(M)»
      } else if (roleFull == MtoColRole.desc && parts.length > 1) {
        col.role = MtoColRole.spec;
        col.namePart = true; // زیرستون گروه «DESCRIPTION»
      } else {
        col.role = roleOwn;
      }
      if (col.role.isPrice) col.currency = currencyOf('$full ${col.blockLabel ?? ''}');
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
    final isPrice = _has(h, _pPrice);
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
    if (_has(h, _pQty) && !_has(h, _pDesc)) return MtoColRole.qty;
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
      return n == 0 ? 1 : k / n;
    }

    // شرح: طولانی‌ترین متن میان نامزدها
    final descs = l.all(MtoColRole.desc).toList();
    if (descs.length > 1) {
      descs.sort((a, b) => avgLen(b).compareTo(avgLen(a)));
      for (final d in descs.skip(1)) {
        d.role = MtoColRole.spec;
      }
    }
    // تگ: ترجیح ستون «Tag» بر «ردیف»؛ ستون «ITEM» متنی (مثل Fitting) بخشی از نام می‌شود
    final tags = l.all(MtoColRole.tag).toList();
    if (tags.length > 1) {
      tags.sort((a, b) {
        final s = _score(b.label).compareTo(_score(a.label));
        return s != 0 ? s : numericShare(b).compareTo(numericShare(a));
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
    for (final r in [MtoColRole.qty, MtoColRole.unit, MtoColRole.currency, MtoColRole.weight, MtoColRole.remarks]) {
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
    final parts = [for (final k in c.cols) if (sh.text(r, k).isNotEmpty) sh.text(r, k)];
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
    final ctxText = l.context.join(' ');
    final sheetCat = suggestCategory(sh.name) ?? (ctxText.isEmpty ? null : suggestCategoryFromText(ctxText));
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
    var curEnd = 0;
    for (var r = l.dataStart; r <= sh.maxRow; r++) {
      final d = desc == null ? '' : textOf(sh, r, desc).replaceAll('\r', '');
      final t = tag == null ? '' : textOf(sh, r, tag, tag: true);
      final np = [for (final c in nameParts) textOf(sh, r, c)].where((x) => x.isNotEmpty && x != '-').join(' ');
      final q = qty == null ? null : numOf(sh, r, qty);
      final hasPrice = prices.any((p) => (numOf(sh, r, p) ?? 0) > 0);
      if (d.isEmpty && t.isEmpty && np.isEmpty) continue;
      final first = _norm(d.isNotEmpty ? d : (np.isNotEmpty ? np : t)).toLowerCase();
      if (RegExp(r'^(جمع|total|sub.?total|grand|sum\b|برآورد هزینه|مجموع)', caseSensitive: false).hasMatch(first)) {
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
      if (q == null && !hasPrice && (t.isEmpty || (d.isEmpty && np.isEmpty) || l.tagIsSerial)) {
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
      final lines = <String>[nameLine, ...dLines.skip(head.isEmpty && np.isEmpty && dLines.isNotEmpty ? 1 : k)];
      final tagText = t.isEmpty
          ? '${sh.name}#$r'
          : (l.tagIsSerial ? '${sh.name}#${t.replaceAll(RegExp(r'\.0$'), '')}' : t.replaceAll(RegExp(r'\s+'), ' '));
      final it = MtoItem(r, tagText, '');
      final unit = unitCol == null ? '' : textOf(sh, r, unitCol).trim().toLowerCase();
      final perKg = RegExp(r'^(kg|kgs|kilo|کیلو|کیلوگرم|كيلوگرم)').hasMatch(unit);
      final perTon = RegExp(r'^(ton|tons|tonne|t|تن)$').hasMatch(unit);
      var factor = 1.0; // قیمت واحد × مقدار وقتی واحد وزنی است
      if ((perKg || perTon) && q != null) {
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
        if (v.isEmpty || v == '-' || v == '—') continue;
        lines.add('${s.label.replaceAll(':', ' ')}: ${v.replaceAll('\n', ' ')}');
      }
      for (final c in contextSpecs) {
        lines.add('Section: $c');
      }
      if (section != null) lines.add('Group: $section');
      final rowCur = curCol == null ? null : currencyOf(textOf(sh, r, curCol));
      it.refCurrency = rowCur;
      final rem = remarks == null ? '' : textOf(sh, r, remarks);
      if (rem.isNotEmpty) it.scopeLines.add(rem.replaceAll('\n', ' '));

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
      pending.add((it, lines, sectionCat));
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
        ..weightKg = it0.weightKg;
      it.quotes.addAll(it0.quotes);
      it.warnings.addAll(it0.warnings);
      it.scopeLines.addAll(it0.scopeLines);
      final dd = parseMtoDescription(it.description);
      it.specs.addAll(dd.specs);
      it.scopeLines.addAll(dd.scope);
      final key0 = '${sh.name}#${it.row}';
      final cat = overrides.containsKey(key0)
          ? overrides[key0]
          : (sheetCat ??
              priorityCategoryFromText(it.name) ??
              secCat ??
              suggestCategoryFromText(it.name) ??
              suggestCategoryFromText(it.description));
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
