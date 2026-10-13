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
  static String? validate(XlsxWorkbook wb) {
    final sh = wb.sheet(masterSheet);
    if (sh == null) return 'شیت «Master Database» در این فایل نیست. فایل Pumps_Price_Bank_v8.xlsx را انتخاب کنید.';
    if (sh.text(4, 2) != 'Equipment Name' || sh.text(4, 4) != 'Tag No.') {
      return 'ساختار ستون‌های شیت Master Database با نسخه‌ی v8 یکی نیست.';
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
    final sh = wb.sheet(masterSheet)!;
    final fields = catalog.fields(cat.id);
    final batch = Audit.newBatch();
    final projectsBefore = docs.projects().length;
    final docsBefore = docs.documents().length;
    final rowToItem = <int, int>{};

    db.transaction(() {
      for (var r = 5; r <= sh.maxRow; r++) {
        final rowNo = sh.cell(r, 1)?.number;
        if (rowNo == null) continue;
        final values = <String, Object?>{};
        final meta = <String, FieldMeta>{};
        for (final f in fields) {
          if (f.storage == FieldStorage.calc || f.sourceRef == null) continue;
          final col = columnIndex(f.sourceRef!.replaceFirst('v8 ستون ', ''));
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
    final sh = wb.sheet('Vendor_Register');
    if (sh == null) return;
    for (var r = 5; r <= sh.maxRow; r++) {
      final code = sh.text(r, 1);
      final name = sh.text(r, 2);
      if (code.isEmpty || name.isEmpty || code.startsWith('V-EX')) continue;
      final exists = db.scalar('SELECT id FROM vendors WHERE code = ? OR name = ?', [code, name]);
      if (exists != null) continue;
      db.insert(
        'INSERT INTO vendors(code, name, country, origin, avl_status, rank, types_supplied, licensor, notes, '
        'created_by, updated_by) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
        [
          code, name, _n(sh.text(r, 3)), _n(sh.text(r, 4)), _n(sh.text(r, 5)), _n(sh.text(r, 6)), _n(sh.text(r, 7)),
          _n(sh.text(r, 8)), _n(sh.text(r, 9)), audit.userId, audit.userId,
        ],
      );
      report.vendors++;
    }
  }

  void _importQuotes(XlsxWorkbook wb, V8ImportReport report, Map<int, int> rowToItem) {
    final sh = wb.sheet('Vendor_Quotes');
    if (sh == null) return;
    for (var r = 5; r <= sh.maxRow; r++) {
      final qid = sh.text(r, 1);
      if (qid.isEmpty || qid.startsWith('Q-EX')) continue;
      final masterRow = sh.cell(r, 2)?.number;
      final itemId = masterRow == null ? null : rowToItem[masterRow.toInt()];
      if (itemId == null) {
        report.warnings.add('استعلام $qid: ردیف Master «${sh.text(r, 2)}» پیدا نشد');
        continue;
      }
      final vcode = sh.text(r, 5);
      final vendorId = vcode.isEmpty ? null : db.scalar('SELECT id FROM vendors WHERE code = ?', [vcode]) as int?;
      final amount = sh.cell(r, 13)?.value;
      final year = sh.cell(r, 8)?.value;
      final extra = <String, Object?>{
        'quote_id': qid,
        'quote_ref': _n(sh.text(r, 9)),
        'validity_days': sh.cell(r, 10)?.number,
        'tbe': _n(sh.text(r, 14)),
        'delivery_weeks': sh.cell(r, 16)?.number,
        'scope_driver': _n(sh.text(r, 17)),
        'scope_baseplate': _n(sh.text(r, 18)),
        'scope_seal_system': _n(sh.text(r, 19)),
        'scope_spares': _n(sh.text(r, 20)),
        'scope_tpi': _n(sh.text(r, 21)),
      }..removeWhere((k, v) => v == null);
      db.insert(
        'INSERT INTO price_obs(item_id, vendor_id, kind, is_primary, currency, amount, amount_text, cost_year, '
        'cost_year_text, incoterm, extra_json, notes, created_by, updated_by) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          itemId, vendorId, 'quote', 0, _n(sh.text(r, 12)),
          amount is double ? amount : null, amount is double ? null : _n(asText(amount)),
          year is double ? year.toInt() : null, year is double ? null : _n(asText(year)),
          _n(sh.text(r, 11)), _jsonish(extra), _n(sh.text(r, 22)), audit.userId, audit.userId,
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
