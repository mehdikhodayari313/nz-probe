// ورود MTO با قالب‌های متفاوت (هر مشاور، هر پروژه): تشخیص خودکار سطر عنوان و نقش ستون‌ها.
//
// برای هر شیت:
//   ۱) سطر عنوان: سطری که ستون «شرح» و دست‌کم دو ستون از «تگ/تعداد/قیمت» را دارد (عنوان دوسطری و
//      سلول‌های ادغام‌شده هم پشتیبانی می‌شوند).
//   ۲) نقش هر ستون از روی عنوانش: تگ، شرح، تعداد، قیمت مبنا، استعلام، قیمت قدیمی، ارز، تاریخ، فروشنده،
//      مشخصه‌ی فنی، ملاحظات، جمع (نادیده)، … — با ارز و سال هر ستون قیمت.
//   ۳) هر ستون مشخصه‌ی فنی به صورت «عنوان: مقدار» به شرح قلم اضافه می‌شود تا در قالب رده بنشیند.
//   ۴) سطرهای عنوان بخش (مثل «PUMPS») رده‌ی اقلام بعدی را تعیین می‌کنند؛ وگرنه رده از نام قلم حدس زده می‌شود.
// نقش ستون‌ها در پیش‌نمایش ورود قابل اصلاح است و با هر اصلاح، شیت دوباره خوانده می‌شود.

import 'package:shamsi_date/shamsi_date.dart';

import '../catalog/profiles.dart';
import '../xlsx/xlsx_reader.dart';
import 'mto_importer.dart';

enum MtoColRole {
  ignore('نادیده'),
  tag('تگ / شماره'),
  desc('شرح / نام'),
  qty('تعداد'),
  going('قیمت مبنا (برآورد)'),
  quote('قیمت استعلام'),
  old('قیمت قدیمی'),
  currency('ارز (هر ردیف)'),
  date('تاریخ استعلام'),
  vendor('فروشنده / سازنده'),
  spec('مشخصه‌ی فنی'),
  remarks('ملاحظات'),
  total('جمع (نادیده)');

  const MtoColRole(this.fa);
  final String fa;
  bool get isPrice => this == going || this == quote || this == old;
}

class MtoColumn {
  MtoColumn(this.col, this.header, this.role);
  final int col;
  final String header;
  MtoColRole role;
  String? currency; // IRR / EUR / USD ؛ null = از ستون ارز یا بزرگی عدد
  int? year;
  int? month;

  /// بلوک استعلام (ستون‌های هم‌گروه زیر یک عنوان مثل «استعلام ۲» یا «Quotation B»)
  int? block;
  String? blockLabel;

  /// نمونه‌ی مقادیر (برای پیش‌نمایش)
  String sample = '';
}

class MtoLayout {
  MtoLayout(this.sheet, this.headerRow, this.dataStart, this.columns);
  final String sheet;
  int headerRow;
  int dataStart;
  final List<MtoColumn> columns;

  /// ستون تگ فقط شماره‌ردیف است (۱، ۲، …) ← تگ = «شیت#شماره»
  bool tagIsSerial = false;
  final List<String> notes = [];

  MtoColumn? first(MtoColRole r) => columns.where((c) => c.role == r).firstOrNull;
  Iterable<MtoColumn> all(MtoColRole r) => columns.where((c) => c.role == r);
}

String _norm(String s) => s
    .replaceAll('ي', 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

bool _has(String h, String p) => RegExp(p, caseSensitive: false).hasMatch(h);

const _pPrice = r'price|cost|قیمت|بها|fee|amount|estimat|برآورد|مبلغ';
const _pTotal = r'total|جمع|مبلغ کل|sum\b|aggregate';
const _pSkipPrice = r'avg|average|میانگین|no\. of|number of|تعداد استعلام|ratio|نسبت|%|درصد';
const _pQuote = r'quot|offer|vendor price|استعلام|پیشنهاد|فروشنده|bid\b|tender';
const _pOld = r'\bold\b|previous|prev\.|قبلی|قدیم|last rev|سابق';
const _pQty = r"\bqty|quantity|q'ty|تعداد|no\.? ?of ?(units|sets|items)|مقدار|\bnos?\b|\bset\b";
const _pTag = r'\btag|item ?no|equipment ?(no|code)|equip\. ?no|item ?code|شماره ?تگ|شماره ?تجهیز|کد ?تجهیز|^کد$';
const _pSerial = r'^(ردیف|row|s/?n|sr\.?|no\.?|#|item|ر)$';
const _pDesc = r'desc|شرح|equipment|service|title|نام|عنوان|مشخصات کلی|item description|name';
const _pCurrency = r'currency|ارز';
const _pDate = r'date|تاریخ';
const _pVendor = r'vendor|supplier|manufactur|maker|source|منبع|سازنده|فروشنده|تامین|تأمین|company|شرکت';
const _pRemarks = r'remark|note|comment|ملاحظات|توضیح';
const _pBlock = r'استعلام|quotation|quote|offer|vendor|پیشنهاد|bidder|supplier';

String? currencyOf(String t) {
  final u = t.toUpperCase();
  if (u.contains('EUR') || t.contains('€') || t.contains('یورو')) return 'EUR';
  if (u.contains('USD') || t.contains(r'$') || t.contains('دلار') || u.contains('DOLLAR')) return 'USD';
  if (u.contains('IRR') || u.contains('RIAL') || t.contains('ریال') || u.contains('IRT') || t.contains('تومان')) return 'IRR';
  return null;
}

/// سال شمسی (و ماه میانی فصل) از عنوان ستون: «1404Q1»، «1393»، «2015» (میلادی ← شمسی)
(int?, int?) yearOfHeader(String h) {
  final q = RegExp(r'(1[34]\d\d)\s*[-/ ]?\s*Q\s*([1-4])', caseSensitive: false).firstMatch(h);
  if (q != null) return (int.parse(q.group(1)!), int.parse(q.group(2)!) * 3 - 1);
  final j = RegExp(r'(?<!\d)(1[34]\d\d)(?!\d)').firstMatch(h);
  if (j != null) return (int.parse(j.group(1)!), null);
  final g = RegExp(r'(?<!\d)(19[89]\d|20[0-4]\d)(?!\d)').firstMatch(h);
  if (g != null) return (int.parse(g.group(1)!) - 621, null);
  return (null, null);
}

class MtoGeneric {
  /// تشخیص قالب جدول اقلام یک شیت؛ null = جدول اقلام پیدا نشد.
  static MtoLayout? detect(XlsxSheet sh) {
    int? bestRow;
    var bestScore = 0;
    for (var r = 1; r <= 40 && r <= sh.maxRow; r++) {
      var desc = false, tag = false, qty = false, price = false;
      for (var c = 1; c <= sh.maxCol && c <= 80; c++) {
        final h = _norm(sh.text(r, c));
        if (h.isEmpty || h.length > 80) continue;
        final isPrice = _has(h, _pPrice);
        if (!isPrice && _has(h, _pDesc)) desc = true;
        if (!isPrice && (_has(h, _pTag) || _has(h, _pSerial))) tag = true;
        if (!isPrice && _has(h, _pQty)) qty = true;
        if (isPrice) price = true;
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
    // سطر زیرعنوان: متنی، بدون عدد، با واژه‌های ارز/منبع/تاریخ
    var sub = false;
    if (hdr + 1 <= sh.maxRow) {
      var texts = 0, nums = 0, hints = 0;
      for (var c = 1; c <= sh.maxCol && c <= 80; c++) {
        final cell = sh.cell(hdr + 1, c);
        if (cell == null || cell.text.trim().isEmpty) continue;
        if (cell.number != null && cell.value is double) {
          nums++;
        } else {
          texts++;
          final t = _norm(cell.text);
          if (currencyOf(t) != null || _has(t, '$_pVendor|$_pDate|$_pPrice|unit|واحد')) hints++;
        }
      }
      sub = texts >= 2 && nums == 0 && hints >= 1;
    }
    final dataStart = hdr + (sub ? 2 : 1);

    // برچسب گروه بالای عنوان (مثل «استعلام ۱» یا «Quotation A») که برای ستون‌های بلوک ادامه می‌یابد
    final groupRow = hdr - 1;
    String? carry;
    int blockNo = 0;
    final cols = <MtoColumn>[];
    for (var c = 1; c <= sh.maxCol && c <= 120; c++) {
      final top = _norm(sh.mergedText(hdr, c));
      final bottom = sub ? _norm(sh.text(hdr + 1, c)) : '';
      // عنوان بلوک: سطر بالای عنوان (پازنان: «استعلام ۱») یا خود سطر عنوان وقتی زیرعنوان دارد («Quotation 1» ادغام‌شده)
      var g = groupRow >= 1 ? _norm(sh.mergedText(groupRow, c)) : '';
      if (g.isEmpty && sub && bottom.isNotEmpty && _has(top, _pBlock) && !_has(top, _pPrice)) g = top;
      if (g.isNotEmpty && _has(g, _pBlock) && g != carry) {
        carry = g;
        blockNo++;
      } else if (g.isNotEmpty && !_has(g, _pBlock)) {
        carry = null;
      } else if (g.isEmpty && sub && top.isNotEmpty && !sh.isMergedTail(hdr, c)) {
        carry = null; // ستون مستقل بعد از بلوک ادغام‌شده
      }
      final header = [top, if (bottom.isNotEmpty && bottom != top) bottom].join(' ').trim();
      // پایان بلوک: ستونی که نه فروشنده/تاریخ/ارز/قیمت است، یا قیمت قدیمی/جمع/میانگین است
      if (carry != null && g.isEmpty) {
        final own = bottom.isNotEmpty ? bottom : top;
        final fits = _has(own, '$_pVendor|$_pDate|$_pPrice') || currencyOf(own) != null;
        if (!fits || _has(own, '$_pOld|$_pTotal|$_pSkipPrice')) carry = null;
      }
      final inBlock = carry != null;
      if (header.isEmpty && !inBlock) continue;
      final col = MtoColumn(c, header.isEmpty ? (carry ?? '') : header, MtoColRole.ignore);
      if (inBlock) {
        col.block = blockNo;
        col.blockLabel = carry;
      }
      col.role = _roleOf(col.header, inBlock: inBlock);
      final cur = currencyOf('${col.header} ${col.blockLabel ?? ''}');
      if (col.role.isPrice) col.currency = cur;
      final (y, m) = yearOfHeader(col.header);
      col.year = y;
      col.month = m;
      // نمونه‌ی مقدار
      for (var r = dataStart; r <= sh.maxRow && r < dataStart + 30; r++) {
        final t = sh.text(r, c);
        if (t.isNotEmpty) {
          col.sample = t.length > 40 ? '${t.substring(0, 40)}…' : t.replaceAll('\n', ' ');
          break;
        }
      }
      cols.add(col);
    }
    final l = MtoLayout(sh.name, hdr, dataStart, cols);
    _resolve(sh, l);
    return l;
  }

  static MtoColRole _roleOf(String h, {bool inBlock = false}) {
    if (h.isEmpty) return MtoColRole.ignore;
    if (_has(h, _pPrice)) {
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
    if (_has(h, _pQty) && !_has(h, _pDesc)) return MtoColRole.qty;
    if (_has(h, _pCurrency)) return MtoColRole.currency;
    if (_has(h, _pRemarks)) return MtoColRole.remarks;
    if (_has(h, _pTag) && !_has(h, r'desc|شرح')) return MtoColRole.tag;
    if (_has(_norm(h).toLowerCase(), _pSerial)) return MtoColRole.tag;
    if (_has(h, _pVendor)) return MtoColRole.vendor;
    if (_has(h, _pDesc)) return MtoColRole.desc;
    if (_has(h, _pDate)) return MtoColRole.date;
    if (_has(h, r'^(unit|uom|واحد)$')) return MtoColRole.ignore;
    return MtoColRole.spec;
  }

  /// یکتا کردن نقش‌های تک‌ستونی و تعیین ستون شرح/تگ بهتر
  static void _resolve(XlsxSheet sh, MtoLayout l) {
    double avgLen(int c) {
      var n = 0, s = 0;
      for (var r = l.dataStart; r <= sh.maxRow && r < l.dataStart + 60; r++) {
        final t = sh.text(r, c);
        if (t.isEmpty) continue;
        n++;
        s += t.length;
      }
      return n == 0 ? 0 : s / n;
    }

    // شرح: طولانی‌ترین متن میان نامزدها
    final descs = l.all(MtoColRole.desc).toList();
    if (descs.length > 1) {
      descs.sort((a, b) => avgLen(b.col).compareTo(avgLen(a.col)));
      for (final d in descs.skip(1)) {
        d.role = MtoColRole.spec;
      }
    }
    // تگ: ترجیح ستون «Tag» بر «ردیف»
    final tags = l.all(MtoColRole.tag).toList();
    if (tags.length > 1) {
      tags.sort((a, b) => _score(b.header).compareTo(_score(a.header)));
      for (final t in tags.skip(1)) {
        t.role = MtoColRole.ignore;
      }
    }
    final tag = l.first(MtoColRole.tag);
    if (tag != null) {
      var serial = 0, total = 0;
      for (var r = l.dataStart; r <= sh.maxRow && r < l.dataStart + 60; r++) {
        final t = sh.text(r, tag.col);
        if (t.isEmpty) continue;
        total++;
        if (RegExp(r'^\d{1,4}(\.\d+)?$').hasMatch(t)) serial++;
      }
      l.tagIsSerial = total > 0 && serial / total > 0.8;
    }
    // تعداد و ارز ردیف: فقط یکی
    for (final r in [MtoColRole.qty, MtoColRole.currency, MtoColRole.remarks]) {
      final list = l.all(r).toList();
      for (final x in list.skip(1)) {
        x.role = r == MtoColRole.remarks ? MtoColRole.spec : MtoColRole.ignore;
      }
    }
    // اگر چند ستون «قیمت مبنا» با سال‌های مختلف هست، قدیمی‌ترها «قیمت قدیمی»اند
    final goings = l.all(MtoColRole.going).where((c) => c.year != null).toList();
    if (goings.length > 1) {
      final maxY = goings.map((c) => c.year!).reduce((a, b) => a > b ? a : b);
      for (final g in goings) {
        if (g.year! <= maxY - 2) g.role = MtoColRole.old;
      }
    }
    if (l.first(MtoColRole.desc) == null) l.notes.add('ستون شرح پیدا نشد؛ از فهرست ستون‌ها انتخاب کنید.');
    if (!l.columns.any((c) => c.role.isPrice)) l.notes.add('ستون قیمت پیدا نشد؛ از فهرست ستون‌ها انتخاب کنید.');
  }

  static int _score(String h) {
    final l = h.toLowerCase();
    if (_has(l, r'\btag|شماره ?تگ')) return 5;
    if (_has(l, r'equip|تجهیز')) return 4;
    if (_has(l, r'item ?no')) return 3;
    if (_has(l, r'code|کد')) return 2;
    return 0;
  }

  /// خواندن اقلام با قالب [l]؛ اقلام هر رده در یک گروه (MtoSheet) جدا.
  static List<MtoSheet> parse(XlsxSheet sh, MtoLayout l, {int? defaultYear}) {
    final desc = l.first(MtoColRole.desc);
    if (desc == null) return const [];
    final tag = l.first(MtoColRole.tag);
    final qty = l.first(MtoColRole.qty);
    final curCol = l.first(MtoColRole.currency);
    final remarks = l.first(MtoColRole.remarks);
    final specs = l.all(MtoColRole.spec).toList();
    final prices = l.columns.where((c) => c.role.isPrice).toList();
    final sheetCat = suggestCategory(sh.name);
    final goingYear = prices.where((c) => c.role == MtoColRole.going && c.year != null).map((c) => c.year).firstOrNull;
    final goingMonth = prices.where((c) => c.role == MtoColRole.going && c.year != null).map((c) => c.month).firstOrNull;
    final oldCol = prices.where((c) => c.role == MtoColRole.old && c.year != null).firstOrNull;

    final groups = <String, MtoSheet>{};
    String? section;
    String? sectionCat;
    for (var r = l.dataStart; r <= sh.maxRow; r++) {
      final d = sh.text(r, desc.col).replaceAll('\r', '');
      final t = tag == null ? '' : sh.text(r, tag.col);
      final q = qty == null ? null : sh.cell(r, qty.col)?.number;
      final hasPrice = prices.any((p) => (sh.cell(r, p.col)?.number ?? 0) > 0);
      final first = _norm(d.isNotEmpty ? d : t).toLowerCase();
      if (d.isEmpty && t.isEmpty) continue;
      if (RegExp(r'^(جمع|total|sub.?total|grand|sum\b|برآورد هزینه|مجموع)', caseSensitive: false).hasMatch(first)) continue;
      // سطر عنوان بخش: فقط یک متن، بدون تعداد و قیمت
      if (q == null && !hasPrice && (t.isEmpty || d.isEmpty)) {
        final txt = d.isNotEmpty ? d : t;
        if (txt.length < 80) {
          section = _norm(txt);
          sectionCat = suggestCategory(section) ?? suggestCategoryFromText(section);
        }
        continue;
      }

      // شرح کامل: متن شرح + ستون‌های مشخصه به صورت «عنوان: مقدار»
      final lines = <String>[d.isEmpty ? t : d];
      for (final s in specs) {
        final v = sh.text(r, s.col);
        if (v.isEmpty || v == '-' || v == '—') continue;
        lines.add('${s.header.replaceAll(':', ' ')}: ${v.replaceAll('\n', ' ')}');
      }
      final fullDesc = lines.join('\n');
      final tagText = t.isEmpty
          ? '${sh.name}#$r'
          : (l.tagIsSerial ? '${sh.name}#${t.replaceAll(RegExp(r'\.0$'), '')}' : t.replaceAll(RegExp(r'\s+'), ' '));
      final it = MtoItem(r, tagText, fullDesc);
      it.quantity = q;
      if (q == null) it.warnings.add('${sh.name}!ردیف $r: تعداد عددی نیست — ۱ در نظر گرفته می‌شود');
      it.quantity ??= 1;
      final rowCur = curCol == null ? null : currencyOf(sh.text(r, curCol.col));
      it.refCurrency = rowCur;
      final rem = remarks == null ? '' : sh.text(r, remarks.col);
      if (rem.isNotEmpty) it.scopeLines.add(rem.replaceAll('\n', ' '));
      final dd = parseMtoDescription(fullDesc);
      it.specs.addAll(dd.specs);
      it.scopeLines.addAll(dd.scope);

      for (final p in prices) {
        final cell = sh.cell(r, p.col);
        final v = cell?.number;
        if (cell == null || v == null || v <= 0) continue;
        var cur = p.currency ?? rowCur;
        if (cur == null) {
          cur = v >= 5e6 ? 'IRR' : 'EUR';
          it.warnings.add('${sh.name}!${cell.ref}: ارز مشخص نبود؛ از بزرگی عدد «$cur» فرض شد');
        }
        switch (p.role) {
          case MtoColRole.going:
            if (cur == 'IRR') it.goingIrr ??= v;
            if (cur == 'EUR') it.goingEur ??= v;
            if (cur == 'USD') it.goingUsd ??= v;
          case MtoColRole.old:
            if (cur == 'IRR') it.oldIrr ??= v;
            if (cur == 'EUR') it.oldEur ??= v;
            if (cur == 'USD') it.oldUsd ??= v;
          case MtoColRole.quote:
            final vendorCol = l.columns
                .where((c) => c.role == MtoColRole.vendor && (p.block == null ? c.block == null : c.block == p.block))
                .firstOrNull;
            final dateCol =
                l.columns.where((c) => c.role == MtoColRole.date && (p.block == null || c.block == p.block)).firstOrNull;
            final vendor = (vendorCol == null ? '' : sh.text(r, vendorCol.col));
            final qv = MtoQuote(
              vendor: vendor.isNotEmpty ? vendor : (p.blockLabel ?? p.header),
              currency: cur,
              amount: v,
              formula: cell.formula,
            );
            if (dateCol != null) MtoImporter.applyQuoteDate(qv, sh.cell(r, dateCol.col), it, sh.name);
            qv.year ??= p.year;
            qv.month ??= p.month;
            it.quotes.add(qv);
          default:
            break;
        }
      }
      // رده: شیت ← بخش ← نام قلم
      final cat = sheetCat ?? sectionCat ?? suggestCategoryFromText(it.name);
      final key = cat ?? '?';
      final g = groups[key] ??= (MtoSheet(sh.name, section ?? sh.name)
        ..categoryCode = cat
        ..source = sh.name
        ..layout = l
        ..goingYear = goingYear ?? defaultYear
        ..goingMonth = goingMonth
        ..goingLabel = goingYear == null ? '' : '$goingYear'
        ..oldYear = oldCol?.year
        ..oldMonth = oldCol?.month
        ..oldLabel = oldCol?.year == null ? '' : '${oldCol!.year}');
      g.items.add(it);
    }
    final list = groups.values.toList();
    if (list.length > 1) {
      for (final g in list) {
        g.label = '${sh.name} › ${g.categoryCode == null ? 'رده نامشخص' : g.categoryCode!}';
      }
    }
    return list;
  }

  /// تاریخ میلادی → سال/ماه شمسی (کمکی)
  static (int, int) jalali(DateTime g) {
    final j = Gregorian(g.year, g.month, g.day).toJalali();
    return (j.year, j.month);
  }
}
