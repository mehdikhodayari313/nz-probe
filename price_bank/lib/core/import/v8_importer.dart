// انتقال یک‌باره‌ی داده‌های فایل Pumps_Price_Bank_v8.xlsx به دیتابیس.
//
// - هر ردیف شیت Master Database یک قلم در رده‌ی «پمپ» می‌شود (۵۹ ستون مطابق قالب).
// - رنگ زرد پررنگ سلول = مقدار استنباطی، رنگ آبی = تبدیل ارز با نرخ بانک؛ یادداشت سلول (Note)
//   به عنوان شاهد همان فیلد ذخیره می‌شود.
// - پروژه‌ها از ستون Project Name و اسناد منبع از ستون Source Document ساخته می‌شوند.
// - فروشندگان (Vendor_Register) و استعلام‌ها (Vendor_Quotes) هم منتقل می‌شوند.
// - ورود تکراری ممکن نیست: اگر رکوردهای v8 قبلاً وارد شده باشند، کار متوقف می‌شود.

import 'dart:convert';

import '../calc/pump_engine.dart' show asText;
import '../db/db.dart';
import '../repo/audit.dart';
import '../repo/catalog_repo.dart';
import '../repo/docs_repo.dart';
import '../repo/items_repo.dart';
import '../xlsx/xlsx_reader.dart';
import 'bank_headers.dart';

class V8ImportReport {
  int items = 0;
  int projects = 0;
  int documents = 0;
  int vendors = 0;
  int quotes = 0;
  int inferredFlags = 0;
  int fxFlags = 0;
  int notes = 0;
  final List<String> warnings = [];
  bool alreadyImported = false;
}

class V8Importer {
  V8Importer(this.db, this.audit, this.catalog, this.items, this.docs);
  final Db db;
  final Audit audit;
  final CatalogRepo catalog;
  final ItemsRepo items;
  final DocsRepo docs;

  static const masterSheet = 'Master Database';
  static const _yellow = 'FFFFFF00';
  static const _blue = 'FFDDEBF7';

  /// بررسی سریع اینکه فایل واقعاً بانک قیمت v8 است.
  /// عنوان‌های اصلی شیت Master بانک پمپ (برای یافتن شیت و ردیف عنوان)
  static const _keyHeaders = [
    'Row', 'Equipment Name', 'Project Name', 'Tag No.', 'Quantity', 'Cost Year (Jalali)', 'Reference Currency',
    'Unit Price (Reference)', 'Source Document', 'Pump Type', 'Rated Flow (m³/h)', 'Differential Head (m)',
  ];

  static HeaderMap? masterHeaders(XlsxWorkbook wb, [List<String> extra = const []]) =>
      findSheetHeaders(wb, const [masterSheet, 'Master', 'Database', 'Price Bank'], {..._keyHeaders, ...extra}.toList(),
          minMatches: 3);

  /// بررسی سریع اینکه فایل واقعاً بانک قیمت v8 است.
  static String? validate(XlsxWorkbook wb) {
    final h = masterHeaders(wb);
    if (h == null) return 'جدول رکوردهای بانک (Master Database) در این فایل پیدا نشد. فایل Pumps_Price_Bank_v8.xlsx را انتخاب کنید.';
    if (!h.has('Equipment Name') && !h.has('Tag No.')) {
      return 'ستون نام تجهیز یا شماره‌ی تگ در شیت «${h.sheet.name}» پیدا نشد.';
    }
    return null;
  }

  V8ImportReport run(XlsxWorkbook wb, {String? fileName}) {
    final report = V8ImportReport();
    final err = validate(wb);
    if (err != null) throw FormatException(err);
    final cat = catalog.categoryByCode('PUMP')!;
    final existing =
        db.scalar('SELECT COUNT(*) FROM items WHERE category_id = ? AND legacy_ref IS NOT NULL', [cat.id]) as int;
    if (existing > 0) {
      report.alreadyImported = true;
      return report;
    }
    final fields = catalog.fields(cat.id);
    // ستون هر فیلد از عنوان سرستون (label_en)؛ اگر عنوان نبود و خانه‌ی عنوانِ ستون نسخه‌ی مرجع خالی است، همان ستون
    final labels = [
      for (final f in fields)
        if (f.storage != FieldStorage.calc && f.sourceRef != null && (f.labelEn ?? '').isNotEmpty) f.labelEn!,
    ];
    final h = masterHeaders(wb, labels)!;
    final sh = h.sheet;
    int colOf(FieldDef f) {
      final byHeader = f.labelEn == null ? null : h[f.labelEn!];
      if (byHeader != null) return byHeader;
      final legacy = columnIndex(f.sourceRef!.replaceFirst('v8 ستون ', ''));
      return sh.text(h.row, legacy).trim().isEmpty || sh.text(h.row, legacy).trim() == f.labelEn ? legacy : 0;
    }
    final fieldCols = {
      for (final f in fields)
        if (f.storage != FieldStorage.calc && f.sourceRef != null) f.key: colOf(f),
    };
    final lost = [
      for (final f in fields)
        if (fieldCols[f.key] == 0) f.labelEn ?? f.key,
    ];
    if (lost.isNotEmpty) {
      report.warnings.add('ستون‌های ${lost.map((m) => '«$m»').join('، ')} در شیت «${sh.name}» نبود؛ '
          'مقدار این فیلدها «در منبع وجود نداشت» ثبت شد.');
    }
    if (h.fuzzy.isNotEmpty) {
      report.warnings.add('عنوان‌های متفاوت با نسخه‌ی مرجع شناخته شد: '
          '${h.fuzzy.entries.map((e) => '«${e.value}» ← ${e.key}').join('، ')}');
    }
    final rowCol = h['Row'] ?? 1;
    final batch = Audit.newBatch();
    final projectsBefore = docs.projects().length;
    final docsBefore = docs.documents().length;
    final rowToItem = <int, int>{};

    db.transaction(() {
      for (var r = h.dataStart; r <= sh.maxRow; r++) {
        final rowNo = sh.cell(r, rowCol)?.number;
        if (rowNo == null) continue;
        final values = <String, Object?>{};
        final meta = <String, FieldMeta>{};
        for (final f in fields) {
          if (f.storage == FieldStorage.calc || f.sourceRef == null) continue;
          final col = fieldCols[f.key] ?? 0;
          if (col == 0) continue;
          final c = sh.cell(r, col);
          if (c != null && !c.hasFormula) {
            final v = c.value;
            values[f.key] = v is double ? v : (v == null ? null : asText(v));
          }
          final note = sh.comment(r, col);
          final fill = c?.fillRgb;
          String? flag;
          if (fill == _yellow) {
            flag = 'inferred';
            report.inferredFlags++;
          } else if (fill == _blue) {
            flag = 'fx';
            report.fxFlags++;
          }
          if (flag != null || (note != null && note.isNotEmpty)) {
            meta[f.key] = FieldMeta(flag, note);
            if (note != null && note.isNotEmpty) report.notes++;
          }
        }

        final projectName = (values['project'] as String?)?.trim();
        final projectId = (projectName == null || projectName.isEmpty) ? null : docs.ensureProject(projectName);

        // سند منبع: «File <عنوان>, <محل در سند>» یا «<عنوان> – <محل>»
        final src = (values['source_document'] as String?)?.trim() ?? '';
        int? documentId;
        String? location;
        if (src.isNotEmpty) {
          final (title, loc) = splitSourceDocument(src);
          location = loc;
          documentId = docs.ensureDocument(projectId: projectId, title: title, docType: 'v8');
        }
        values['_source_location'] = location;

        final id = items.create(
          categoryId: cat.id,
          values: values,
          projectId: projectId,
          documentId: documentId,
          reason: 'انتقال از ${fileName ?? 'v8'} (ردیف ${rowNo.toInt()})',
          meta: meta,
          batch: batch,
        );
        rowToItem[rowNo.toInt()] = id;
        report.items++;
      }

      _importVendors(wb, report);
      _importQuotes(wb, report, rowToItem);
    });

    report.projects = docs.projects().length - projectsBefore;
    report.documents = docs.documents().length - docsBefore;
    return report;
  }

  void _importVendors(XlsxWorkbook wb, V8ImportReport report) {
    report.vendors += importVendorRegister(db, audit, wb);
  }

  void _importQuotes(XlsxWorkbook wb, V8ImportReport report, Map<int, int> rowToItem) {
    final t = BankTable.open(wb, const ['Vendor_Quotes', 'Vendor Quotes', 'Quotes'], const {
      'Quote_ID': 1, 'Master Row': 2, 'Vendor_ID': 5, 'Quote Year (Jalali)': 8, 'Quote Ref / Date': 9,
      'Validity (days)': 10, 'Incoterm': 11, 'Currency': 12, 'Quoted Unit Price': 13, 'TBE OK': 14,
      'Delivery (weeks)': 16, 'Sc: Driver': 17, 'Sc: Baseplate': 18, 'Sc: Seal System': 19, 'Sc: Spares': 20,
      'Sc: TPI': 21, 'Remarks': 22,
    });
    if (t == null) return;
    for (var r = t.start; r <= t.sh.maxRow; r++) {
      final qid = t.text(r, 'Quote_ID');
      if (qid.isEmpty || qid.startsWith('Q-EX')) continue;
      final masterRow = t.cell(r, 'Master Row')?.number;
      final itemId = masterRow == null ? null : rowToItem[masterRow.toInt()];
      if (itemId == null) {
        report.warnings.add('استعلام $qid: ردیف Master «${t.text(r, 'Master Row')}» پیدا نشد');
        continue;
      }
      final vcode = t.text(r, 'Vendor_ID');
      final vendorId = vcode.isEmpty ? null : db.scalar('SELECT id FROM vendors WHERE code = ?', [vcode]) as int?;
      final amount = t.cell(r, 'Quoted Unit Price')?.value;
      final year = t.cell(r, 'Quote Year (Jalali)')?.value;
      final extra = <String, Object?>{
        'quote_id': qid,
        'quote_ref': _n(t.text(r, 'Quote Ref / Date')),
        'validity_days': t.cell(r, 'Validity (days)')?.number,
        'tbe': _n(t.text(r, 'TBE OK')),
        'delivery_weeks': t.cell(r, 'Delivery (weeks)')?.number,
        'scope_driver': _n(t.text(r, 'Sc: Driver')),
        'scope_baseplate': _n(t.text(r, 'Sc: Baseplate')),
        'scope_seal_system': _n(t.text(r, 'Sc: Seal System')),
        'scope_spares': _n(t.text(r, 'Sc: Spares')),
        'scope_tpi': _n(t.text(r, 'Sc: TPI')),
      }..removeWhere((k, v) => v == null);
      db.insert(
        'INSERT INTO price_obs(item_id, vendor_id, kind, is_primary, currency, amount, amount_text, cost_year, '
        'cost_year_text, incoterm, extra_json, notes, created_by, updated_by) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          itemId, vendorId, 'quote', 0, _n(t.text(r, 'Currency')),
          amount is double ? amount : null, amount is double ? null : _n(asText(amount)),
          year is double ? year.toInt() : null, year is double ? null : _n(asText(year)),
          _n(t.text(r, 'Incoterm')), _jsonish(extra), _n(t.text(r, 'Remarks')), audit.userId, audit.userId,
        ],
      );
      report.quotes++;
    }
  }

  /// جدا کردن عنوان سند از محل داخل سند.
  /// «File PC-ME 14040105 Pazanan2 Reconstruction.xlsx, sheet 'PUMPS', spec B10» →
  /// («PC-ME 14040105 Pazanan2 Reconstruction.xlsx»، «sheet 'PUMPS', spec B10»)
  static (String, String?) splitSourceDocument(String src) {
    var head = src, rest = '';
    final dash = src.indexOf(' – ');
    if (dash > 0) {
      head = src.substring(0, dash);
      rest = src.substring(dash + 3);
    }
    final comma = head.indexOf(', ');
    if (comma > 0) {
      rest = head.substring(comma + 2) + (rest.isEmpty ? '' : ' – $rest');
      head = head.substring(0, comma);
    }
    head = head.trim();
    if (head.startsWith('File ')) head = head.substring(5).trim();
    return (head, rest.trim().isEmpty ? null : rest.trim());
  }

  static String? _n(String s) => s.trim().isEmpty ? null : s.trim();

  static String _jsonish(Map<String, Object?> m) => jsonEncode(m);
}
