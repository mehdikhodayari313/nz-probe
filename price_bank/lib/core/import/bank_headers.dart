// خواندن منعطف سرستون بانک‌های قیمت (پمپ v8، دیسالتر، کمپرسور، …)
//
// فایل‌های بانک با گذر زمان عوض می‌شوند: ستون جابه‌جا می‌شود، عنوان کمی تغییر می‌کند («Cost Year (Jalali)» ←
// «Cost Year (Shamsi)» یا «Cost Year»)، ردیف عنوان پایین/بالا می‌رود، شیت تغییر نام می‌دهد یا ستونی حذف می‌شود.
// این‌جا هر عنوان مورد انتظار با چند روش (عین متن، بدون واحد پرانتزی، هم‌معنی‌ها، شامل همه‌ی واژه‌ها) پیدا می‌شود
// و ستون‌های پیدانشده فهرست می‌شوند تا در گزارش ورود بیایند (به جای خطا و توقف ورود).

import '../db/db.dart';
import '../repo/audit.dart';
import '../xlsx/xlsx_reader.dart';

/// متن عنوان برای مقایسه: حروف کوچک، ی/ک عربی، بدون علائم و فاصله‌ی اضافه
String normHeader(String s) => s
    .toLowerCase()
    .replaceAll('ي', 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll('³', '3')
    .replaceAll('²', '2')
    .replaceAll('‌', ' ')
    .replaceAll(RegExp(r'[^a-z0-9؀-ۿ]+'), ' ')
    .trim();

/// عنوان بدون واحد/توضیح پرانتزی: «Cost Year (Jalali)» ← «cost year»
String coreHeader(String s) => normHeader(s.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' '));

const _stop = {'of', 'the', 'as', 'in', 'per', 'and', 'or', 'a', 'an', 'to', 'for', 'y', 'n'};

Set<String> _tokens(String s) => coreHeader(s).split(' ').where((t) => t.isNotEmpty && !_stop.contains(t)).toSet();

/// هم‌معنی‌های رایج عنوان‌های بانک‌ها (کلید = عنوان استاندارد)
const bankHeaderSynonyms = <String, List<String>>{
  'Row': ['No', 'No.', 'Record', 'Record No', 'ردیف', 'Item', 'S/N', 'Sr'],
  'Equipment Name': ['Equipment', 'Name', 'Description', 'Service', 'Equipment Description', 'نام تجهیز', 'شرح'],
  'Project Name': ['Project', 'پروژه', 'نام پروژه'],
  'Tag No.': ['Tag', 'Tag Number', 'Item No', 'Equipment No', 'شماره تگ', 'تگ'],
  'Quantity': ['Qty', "Q'ty", 'No. of Units', 'تعداد'],
  'Cost Year (Jalali)': ['Cost Year', 'Price Year', 'Year', 'Cost Year (Shamsi)', 'Year (Jalali)', 'سال قیمت', 'سال'],
  'Reference Currency': ['Currency', 'Ref. Currency', 'ارز', 'ارز مرجع'],
  'Unit Price (Reference)': ['Unit Price', 'Price', 'Unit Cost', 'Unit Price (Ref)', 'قیمت واحد', 'قیمت'],
  'Source Document': ['Source', 'Reference Document', 'Document', 'سند منبع', 'منبع'],
  'Remarks & Notes': ['Remarks', 'Notes', 'Comments', 'ملاحظات', 'توضیحات'],
  'Include in Totals (Y/N)': ['Include in Totals', 'In Totals'],
  'Use as Estimator Peer (Y/N)': ['Use as Peer', 'Estimator Peer', 'Peer'],
  'Compressors per Price Unit': ['Units per Price', 'Compressors per Price', 'Units per Price Unit'],
  'Manufacturer / Supplier (as in source)': ['Manufacturer', 'Supplier', 'Vendor', 'Manufacturer / Supplier', 'سازنده'],
  'Price Basis (as stated in source)': ['Price Basis', 'Basis', 'مبنای قیمت'],
  'Master Row': ['Master Row No', 'Row (Master)', 'Master Database Row', 'Record Row'],
  'Quote_ID': ['Quote ID', 'Quote No', 'Quotation ID'],
  'Quoted Unit Price': ['Unit Price', 'Quoted Price', 'Offer Price', 'Price'],
  'Quote Year (Jalali)': ['Quote Year', 'Year', 'Offer Year'],
  'Vendor_ID': ['Vendor ID', 'Vendor Code', 'Supplier ID', 'Code'],
  'Vendor Name': ['Vendor', 'Supplier', 'Supplier Name', 'Manufacturer', 'نام سازنده', 'سازنده'],
  'AVL_Status': ['AVL Status', 'AVL', 'Approval Status'],
  'Vendor_Rank': ['Vendor Rank', 'Rank'],
  'Types supplied': ['Technology supplied', 'Types', 'Products', 'Scope of Supply'],
  'Licensor / OEM': ['Licensor', 'OEM'],
};

class HeaderMap {
  HeaderMap(this.sheet, this.row, this.cols, this.missing, this.fuzzy);
  final XlsxSheet sheet;

  /// ردیف عنوان
  final int row;

  /// عنوان استاندارد ← شماره‌ی ستون
  final Map<String, int> cols;

  /// عنوان‌های مورد انتظار که پیدا نشدند
  final List<String> missing;

  /// عنوان‌هایی که با متن متفاوت پیدا شدند (استاندارد ← متن فایل)
  final Map<String, String> fuzzy;

  int get dataStart => row + 1;
  int? operator [](String h) => cols[h];
  bool has(String h) => cols.containsKey(h);

  /// عنوان با متن عین نسخه‌ی مرجع پیدا شد (برای تشخیص نوع بانک)
  bool exact(String h) => cols.containsKey(h) && !fuzzy.containsKey(h);
}

/// کیفیت تطبیق عنوان فایل با عنوان مورد انتظار (۰ = نه)
int _quality(String want, String got, List<String> syn) {
  if (got.trim().isEmpty) return 0;
  final nw = normHeader(want), ng = normHeader(got);
  if (nw == ng) return 100;
  final cw = coreHeader(want), cg = coreHeader(got);
  if (cw.isNotEmpty && cw == cg) return 90;
  for (final s in syn) {
    if (normHeader(s) == ng || (coreHeader(s).isNotEmpty && coreHeader(s) == cg)) return 80;
  }
  final tw = _tokens(want), tg = _tokens(got);
  if (tw.length >= 2 && tg.containsAll(tw)) return 70 - (tg.length - tw.length).clamp(0, 20);
  for (final s in syn) {
    final ts = _tokens(s);
    if (ts.length >= 2 && tg.containsAll(ts)) return 55 - (tg.length - ts.length).clamp(0, 20);
  }
  // عنوان فایل بخشی از عنوان مورد انتظار است («Capacity per Compressor» در برابر «Capacity per Compressor (Nm³/h)»)
  if (tg.length >= 2 && tw.containsAll(tg)) return 50;
  return 0;
}

/// نگاشت عنوان‌های مورد انتظار در یک ردیف (هر ستون فقط یک بار، بهترین تطبیق اول)
(Map<String, int>, Map<String, String>) _matchRow(XlsxSheet sh, int r, List<String> expected) {
  final cands = <(int q, String want, int col, String got)>[];
  for (var c = 1; c <= sh.maxCol && c <= 250; c++) {
    final got = sh.text(r, c).replaceAll('\n', ' ').trim();
    if (got.isEmpty || sh.cell(r, c)?.value is double) continue;
    for (final w in expected) {
      final q = _quality(w, got, bankHeaderSynonyms[w] ?? const []);
      if (q > 0) cands.add((q, w, c, got));
    }
  }
  cands.sort((a, b) => b.$1 != a.$1 ? b.$1.compareTo(a.$1) : a.$3.compareTo(b.$3));
  final cols = <String, int>{}, fuzzy = <String, String>{};
  final used = <int>{};
  for (final (q, w, c, got) in cands) {
    if (cols.containsKey(w) || used.contains(c)) continue;
    cols[w] = c;
    used.add(c);
    if (q < 100) fuzzy[w] = got;
  }
  return (cols, fuzzy);
}

/// ردیف عنوان (در ۲۵ ردیف اول) با بیشترین عنوان‌های پیدا‌شده
HeaderMap? findHeaders(XlsxSheet sh, List<String> expected, {int maxRow = 25, int minMatches = 2}) {
  HeaderMap? best;
  for (var r = 1; r <= sh.maxRow && r <= maxRow; r++) {
    final (cols, fuzzy) = _matchRow(sh, r, expected);
    if (cols.length < minMatches) continue;
    if (best == null || cols.length > best.cols.length) {
      best = HeaderMap(sh, r, cols, [for (final w in expected) if (!cols.containsKey(w)) w], fuzzy);
    }
  }
  return best;
}

/// شیت مناسب: نام پیشنهادی (بدون حساسیت به حروف/فاصله) وگرنه شیتی که بیشترین عنوان را دارد
HeaderMap? findSheetHeaders(XlsxWorkbook wb, List<String> names, List<String> expected, {int minMatches = 3}) {
  final want = names.map(normHeader).toSet();
  for (final info in wb.sheets) {
    if (!want.contains(normHeader(info.name))) continue;
    final sh = wb.sheet(info.name);
    if (sh == null) continue;
    final h = findHeaders(sh, expected, minMatches: minMatches);
    if (h != null) return h;
  }
  HeaderMap? best;
  for (final info in wb.sheets) {
    final sh = wb.sheet(info.name);
    if (sh == null) continue;
    final h = findHeaders(sh, expected, minMatches: minMatches);
    if (h != null && (best == null || h.cols.length > best.cols.length)) best = h;
  }
  return best;
}

/// متن گزارش ستون‌های پیدانشده/تقریبی
List<String> headerReport(HeaderMap h, {String what = 'بانک'}) => [
      if (h.missing.isNotEmpty)
        'ستون‌های ${h.missing.map((m) => '«$m»').join('، ')} در شیت «${h.sheet.name}» نبود؛ '
            'مقدار این فیلدها «در منبع وجود نداشت» ثبت شد.',
      if (h.fuzzy.isNotEmpty)
        'عنوان‌های متفاوت با نسخه‌ی مرجع ($what) شناخته شد: '
            '${h.fuzzy.entries.map((e) => '«${e.value}» ← ${e.key}').join('، ')}',
    ];

/// جدول یک شیت بانک با ستون‌های شناخته‌شده از عنوان؛ اگر عنوان پیدا نشد، شماره‌ی ستون نسخه‌ی مرجع (فقط وقتی
/// عنوان آن خانه خالی است یا ردیف عنوان اصلاً پیدا نشد).
class BankTable {
  BankTable._(this.sh, this.h, this.fallback);
  final XlsxSheet sh;
  final HeaderMap? h;
  final Map<String, int> fallback;

  /// [names]: نام‌های شیت (اولی نام نسخه‌ی مرجع)؛ [columns]: عنوان ← شماره‌ی ستون در نسخه‌ی مرجع
  static BankTable? open(XlsxWorkbook wb, List<String> names, Map<String, int> columns, {int minMatches = 2}) {
    final want = names.map(normHeader).toSet();
    final expected = columns.keys.toList();
    for (final info in wb.sheets) {
      if (!want.contains(normHeader(info.name))) continue;
      final sh = wb.sheet(info.name);
      if (sh != null) return BankTable._(sh, findHeaders(sh, expected, minMatches: minMatches), columns);
    }
    final h = findSheetHeaders(wb, const [], expected, minMatches: (expected.length / 2).ceil().clamp(2, 6));
    return h == null ? null : BankTable._(h.sheet, h, columns);
  }

  int get start => h?.dataStart ?? 5;

  int col(String name) {
    final c = h?[name];
    if (c != null) return c;
    final f = fallback[name] ?? 0;
    if (h == null || f == 0) return f;
    return sh.text(h!.row, f).trim().isEmpty ? f : 0;
  }

  String text(int r, String name) {
    final c = col(name);
    return c == 0 ? '' : sh.text(r, c);
  }

  XlsxCell? cell(int r, String name) {
    final c = col(name);
    return c == 0 ? null : sh.cell(r, c);
  }
}

/// فیلدهای اصلی که ستونشان در فایل نبود: «در منبع وجود نداشت» در ملاحظات قلم (مقدار عددی ساختگی ثبت نمی‌شود)
void markMissingFields(Map<String, Object?> values, List<String> missing) {
  const essential = {
    'Cost Year (Jalali)': 'سال قیمت',
    'Reference Currency': 'ارز مرجع',
    'Unit Price (Reference)': 'قیمت واحد',
    'Quantity': 'تعداد',
    'Project Name': 'پروژه',
    'Tag No.': 'شماره تگ',
  };
  final lost = [for (final m in missing) if (essential[m] != null) essential[m]!];
  if (lost.isEmpty) return;
  values['remarks'] = '${values['remarks'] ?? ''}\n${lost.join('، ')}: در منبع وجود نداشت'.trim();
}

/// شیت Vendor_Register (هر سه بانک): ستون‌ها از عنوان؛ ردیف نمونه (V-EX…) و فروشنده‌ی تکراری وارد نمی‌شود.
/// [licensorCol]/[notesCol]: شماره‌ی ستون در نسخه‌ی مرجع (۰ = ندارد)
int importVendorRegister(Db db, Audit audit, XlsxWorkbook wb, {int licensorCol = 8, int notesCol = 9}) {
  final t = BankTable.open(wb, const ['Vendor_Register', 'Vendor Register', 'Vendors', 'Vendor List'], {
    'Vendor_ID': 1,
    'Vendor Name': 2,
    'Country': 3,
    'Origin': 4,
    'AVL_Status': 5,
    'Vendor_Rank': 6,
    'Types supplied': 7,
    'Licensor / OEM': licensorCol,
    'Notes': notesCol,
  });
  if (t == null) return 0;
  String? n(String s) => s.trim().isEmpty ? null : s.trim();
  var count = 0;
  for (var r = t.start; r <= t.sh.maxRow; r++) {
    final code = t.text(r, 'Vendor_ID').trim();
    final name = t.text(r, 'Vendor Name').trim();
    if (code.isEmpty || name.isEmpty || code.startsWith('V-EX')) continue;
    if (db.scalar('SELECT id FROM vendors WHERE code = ? OR name = ?', [code, name]) != null) continue;
    db.insert(
      'INSERT INTO vendors(code, name, country, origin, avl_status, rank, types_supplied, licensor, notes, '
      'created_by, updated_by) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
      [
        code, name, n(t.text(r, 'Country')), n(t.text(r, 'Origin')), n(t.text(r, 'AVL_Status')),
        n(t.text(r, 'Vendor_Rank')), n(t.text(r, 'Types supplied')), n(t.text(r, 'Licensor / OEM')),
        n(t.text(r, 'Notes')), audit.userId, audit.userId,
      ],
    );
    count++;
  }
  return count;
}
