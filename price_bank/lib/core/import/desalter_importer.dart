// انتقال یک‌باره‌ی بانک قیمت دیسالتر (Desalters_Price_Bank_v8.xlsx) به دیسالترهای برنامه.
//
// - هر ردیف شیت Master Database یک قلم در رده‌ی «پکیج نمک‌زدایی (دیسالتر)» می‌شود؛ شناسه‌ی پایدار = Record ID (DES-0001).
// - ستون‌ها با عنوان سرستون (ردیف ۴) شناخته می‌شوند؛ ستون‌های فرمولی (حجم، ضرایب، قیمت‌های مشتق) دوباره محاسبه می‌شوند.
// - سلول زرد = مقدار استنباطی، آبی = تبدیل ارز با نرخ بانک؛ Note سلول به عنوان شاهد همان فیلد ذخیره می‌شود.
// - فروشندگان (Vendor_Register) و استعلام‌ها (Vendor_Quotes) هم منتقل می‌شوند.
// - تصمیم‌های تأییدشده‌ی کاربر هنگام ورود اعمال و در تاریخچه ثبت می‌شوند (سال قیمت KPL-476 = ۱۳۹۴/۱۰).
// - این بانک مرجع دیسالترهاست: قلم دیسالتری که قبلاً از MTO همان پروژه وارد شده (همان تگ و همان قیمت)،
//   بایگانی می‌شود و در ورود MTO بعدی هم تکراری حساب می‌شود.

import 'dart:convert';

import '../calc/pump_engine.dart' show asText;
import '../db/db.dart';
import '../repo/audit.dart';
import '../repo/catalog_repo.dart';
import '../repo/docs_repo.dart';
import '../repo/items_repo.dart';
import '../xlsx/xlsx_reader.dart';
import 'bank_headers.dart';
import 'v8_importer.dart';

class DesalterImportReport {
  int items = 0;
  int projects = 0;
  int documents = 0;
  int vendors = 0;
  int quotes = 0;
  int inferredFlags = 0;
  int fxFlags = 0;
  int notes = 0;
  int corrections = 0;
  int archivedDuplicates = 0;
  final List<String> warnings = [];
  bool alreadyImported = false;
}

/// عنوان سرستون Master ← کلید فیلد برنامه
const desalterBankColumns = <String, String>{
  'Row': 'row_no',
  'Equipment Name': 'name',
  'Project Name': 'project',
  'Tag No.': 'tag',
  'Sub-Category': 'sub_category',
  'Desalting Technology': 'desalting_technology',
  'Shell Material': 'des_material',
  'Vessel ID (mm)': 'vessel_id_mm',
  'Vessel T/T (mm)': 'vessel_tl_mm',
  'Vessel Design Code': 'vessel_design_code',
  'IPS Standard': 'ips_standard',
  'NACE MR0175 (Y/N)': 'nace',
  'Capacity (BPD, package total)': 'capacity_bpd',
  'No. of Stages': 'no_of_stages',
  'Quantity': 'quantity',
  'Trains per Package': 'trains_per_package',
  'Vessels per Package': 'vessels_per_package',
  'Design Pressure (barg)': 'design_pressure_barg',
  'Design Temp. min (°C)': 'design_temp_min_c',
  'Design Temp. max (°C)': 'design_temp_max_c',
  'No. of Transformers': 'n_transformers',
  'Transformer Sizing (% of demand each)': 'transformer_sizing',
  'kVA per Transformer': 'kva_per_transformer',
  'Recycle Pumps (as in source)': 'recycle_pumps',
  'Capacity Basis': 'capacity_basis',
  'Cost Year (Jalali)': 'cost_year',
  'Reference Currency': 'currency',
  'Unit Price (Reference)': 'unit_price',
  'Price Basis (as stated in source)': 'price_basis',
  'Incoterm': 'incoterm',
  'Manufacturer / Supplier (as in source)': 'manufacturer',
  'Project Phase': 'project_phase',
  'Scope: Transformers': 'scope_transformers',
  'Scope: Recycle Pumps': 'scope_recycle_pumps',
  'Scope: Related Piping': 'scope_related_piping',
  'Scope: Instruments / Control': 'scope_instruments',
  'Scope: Customs & Transport': 'scope_customs_transport',
  'Source Document': 'source_document',
  'Remarks & Notes': 'remarks',
  'Include in Totals (Y/N)': 'include_in_totals',
  'Record ID': 'record_id',
};

/// اصلاح تأییدشده‌ی کاربر: سال قیمت سند KPL-476 (بازنگری R03 = JAN 2016) ← ۱۳۹۴/۱۰ به جای ۱۳۹۳.
const kplCostYear = 1394, kplCostMonth = 10;
const kplCorrectionNote = 'تأیید کاربر (۱۴۰۵/۰۷/۲۳): سال قیمت KPL-476 = ۱۳۹۴/۱۰ — تاریخ بازنگری R03 = JAN 2016. '
    'مقدار فایل بانک دیسالتر: ۱۳۹۳.';

bool isKplRecord(Map<String, Object?> v) {
  final s = '${v['source_document'] ?? ''} ${v['price_basis'] ?? ''}'.toUpperCase();
  return s.contains('KPL-ME-RE-476') || s.contains('KPL-476');
}

/// پایه‌ی تگ برای تطبیق: «PK-111 (DE-111/112)» ← «PK-111»
String desalterTagBase(String? tag) {
  final t = (tag ?? '').trim().toUpperCase();
  final m = RegExp(r'^[^\s(]+').firstMatch(t);
  return m?.group(0) ?? t;
}

/// قلم بانک دیسالتر با همان پایه‌ی تگ و یکی از همین قیمت‌ها (تلورانس نسبی ۱e-۶)؛ null = تکراری نیست.
int? findDesalterBankDuplicate(Db db, int categoryId, String? tag, Iterable<double?> amounts) {
  final base = desalterTagBase(tag);
  final am = [for (final a in amounts) if (a != null && a > 0) a];
  if (base.isEmpty || am.isEmpty) return null;
  final rows = db.query(
    "SELECT i.id, i.tag, o.amount FROM items i JOIN price_obs o ON o.item_id = i.id "
    "WHERE i.category_id = ? AND i.status = 'active' AND i.legacy_ref LIKE 'DES-%' AND o.amount IS NOT NULL",
    [categoryId],
  );
  for (final r in rows) {
    if (desalterTagBase(r['tag'] as String?) != base) continue;
    final x = r['amount'] as double;
    if (am.any((a) => (a - x).abs() <= 1e-6 * x.abs())) return r['id'] as int;
  }
  return null;
}

class DesalterImporter {
  DesalterImporter(this.db, this.audit, this.catalog, this.items, this.docs);
  final Db db;
  final Audit audit;
  final CatalogRepo catalog;
  final ItemsRepo items;
  final DocsRepo docs;

  static const masterSheet = 'Master Database';
  static const _yellow = 'FFFFFF00';
  static const _blue = 'FFDDEBF7';

  /// فایل، بانک قیمت دیسالتر است؟ (App_Meta: equipment_code = DES یا عنوان شیت Master)
  static bool isDesalterBank(XlsxWorkbook wb) {
    final meta = wb.sheet('App_Meta');
    if (meta != null) {
      for (var r = 1; r <= meta.maxRow; r++) {
        if (meta.text(r, 1) == 'equipment_code') return meta.text(r, 2) == 'DES';
      }
    }
    final h = masterHeaders(wb);
    if (h == null) return false;
    for (var r = 1; r < h.row && r <= 4; r++) {
      if (h.sheet.rowCells(r).any((c) => c.text.toUpperCase().contains('DESALTER'))) return true;
    }
    return h.exact('Desalting Technology') || (h.exact('No. of Stages') && h.exact('Vessels per Package'));
  }

  /// شیت Master و ستون‌هایش (نام شیت یا ردیف عنوان عوض شده باشد هم پیدا می‌شود)
  static HeaderMap? masterHeaders(XlsxWorkbook wb) =>
      findSheetHeaders(wb, const [masterSheet, 'Master', 'Database', 'Price Bank'], desalterBankColumns.keys.toList(),
          minMatches: 4);

  static String? validate(XlsxWorkbook wb) {
    final h = masterHeaders(wb);
    if (h == null || !isDesalterBank(wb)) return 'این فایل بانک قیمت دیسالتر (Desalters_Price_Bank) نیست.';
    if (!h.has('Equipment Name') && !h.has('Tag No.')) return 'ستون نام تجهیز یا شماره‌ی تگ در شیت «${h.sheet.name}» پیدا نشد.';
    if (!h.has('Unit Price (Reference)')) return 'ستون قیمت واحد در شیت «${h.sheet.name}» پیدا نشد.';
    return null;
  }

  static List<String> headerNotes(XlsxWorkbook wb) {
    final h = masterHeaders(wb);
    return h == null ? const [] : headerReport(h, what: 'بانک دیسالتر v8');
  }

  /// خواندن رکوردهای Master (فقط سلول‌های ورودی؛ بدون اصلاح‌ها) — برای ورود و آزمون طلایی.
  static List<({int row, Map<String, Object?> values, Map<String, FieldMeta> meta})> readMaster(XlsxWorkbook wb) {
    final h = masterHeaders(wb)!;
    final sh = h.sheet;
    final cols = h.cols;
    final out = <({int row, Map<String, Object?> values, Map<String, FieldMeta> meta})>[];
    for (var r = h.dataStart; r <= sh.maxRow; r++) {
      final rowNo = cols['Row'] == null
          ? ([for (final k in ['Equipment Name', 'Tag No.', 'Unit Price (Reference)']) if (cols[k] != null) sh.text(r, cols[k]!)]
                  .any((t) => t.trim().isNotEmpty)
              ? (r - h.row).toDouble()
              : null)
          : sh.cell(r, cols['Row']!)?.number;
      if (rowNo == null) continue;
      final values = <String, Object?>{};
      final meta = <String, FieldMeta>{};
      for (final e in desalterBankColumns.entries) {
        final col = cols[e.key];
        if (col == null) continue;
        final c = sh.cell(r, col);
        // همه‌ی ستون‌های نگاشت‌شده ورودی‌اند؛ مقدار مشتق (مثل ظرفیت گچساران از m³/h) با مقدار ذخیره‌شده خوانده می‌شود
        if (c != null) {
          final v = c.value;
          values[e.value] = v is double ? v : (v == null ? null : asText(v).trim());
        }
        final note = sh.comment(r, col);
        final fill = c?.fillRgb;
        final flag = fill == _yellow ? 'inferred' : (fill == _blue ? 'fx' : null);
        if (flag != null || (note != null && note.isNotEmpty)) meta[e.value] = FieldMeta(flag, note);
      }
      values.removeWhere((k, v) => v == null || (v is String && v.isEmpty));
      out.add((row: rowNo.toInt(), values: values, meta: meta));
    }
    return out;
  }

  DesalterImportReport run(XlsxWorkbook wb, {String? fileName}) {
    final report = DesalterImportReport();
    final err = validate(wb);
    if (err != null) throw FormatException(err);
    report.warnings.addAll(headerNotes(wb));
    final missing = masterHeaders(wb)!.missing;
    final cat = catalog.categoryByCode('DESALTER')!;
    final existing = db.scalar(
        "SELECT COUNT(*) FROM items WHERE category_id = ? AND legacy_ref LIKE 'DES-%'", [cat.id]) as int;
    if (existing > 0) {
      report.alreadyImported = true;
      return report;
    }
    final batch = Audit.newBatch();
    final projectsBefore = docs.projects().length;
    final docsBefore = docs.documents().length;
    final rowToItem = <int, int>{};
    final src = fileName ?? 'بانک دیسالتر';

    db.transaction(() {
      for (final rec in readMaster(wb)) {
        final values = {...rec.values};
        final meta = {...rec.meta};
        for (final m in meta.values) {
          if (m.flag == 'inferred') report.inferredFlags++;
          if (m.flag == 'fx') report.fxFlags++;
          if (m.note != null && m.note!.isNotEmpty) report.notes++;
        }
        final recordId = (values.remove('record_id') as String?) ?? 'DES-${rec.row.toString().padLeft(4, '0')}';
        values.remove('row_no');
        values['v8_row'] = recordId;
        markMissingFields(values, missing);

        // اصلاح تأییدشده: سال قیمت KPL
        final kpl = isKplRecord(values) && values['cost_year'] is double && (values['cost_year'] as double) != kplCostYear;
        if (kpl) {
          values['cost_year'] = kplCostYear.toDouble();
          meta['cost_year'] = FieldMeta('inferred', kplCorrectionNote);
          report.corrections++;
        }

        // نوع قیمت اصلی
        final basis = (values['price_basis'] as String? ?? '').toLowerCase();
        values['_price_kind'] = basis.startsWith('vendor inquiry')
            ? 'other'
            : (basis.startsWith('purchase price') ? 'contract' : 'estimate');

        final projectName = (values['project'] as String?)?.trim();
        final projectId = (projectName == null || projectName.isEmpty) ? null : docs.ensureProject(projectName);
        final srcDoc = (values['source_document'] as String?)?.trim() ?? '';
        int? documentId;
        if (srcDoc.isNotEmpty) {
          final (title, loc) = V8Importer.splitSourceDocument(srcDoc);
          values['_source_location'] = loc;
          documentId = docs.ensureDocument(projectId: projectId, title: title, docType: 'v8');
        }

        final id = items.create(
          categoryId: cat.id,
          values: values,
          projectId: projectId,
          documentId: documentId,
          reason: 'انتقال از $src (ردیف ${rec.row}، $recordId)',
          meta: meta,
          batch: batch,
        );
        if (kpl) {
          db.execute('UPDATE price_obs SET cost_month = ? WHERE item_id = ? AND is_primary = 1', [kplCostMonth, id]);
          audit.log(
              entity: 'item', entityId: id, field: 'cost_year', oldValue: 1393, newValue: '$kplCostYear/$kplCostMonth',
              reason: kplCorrectionNote, batch: batch);
        }
        rowToItem[rec.row] = id;
        report.items++;
      }
      _importVendors(wb, report);
      _importQuotes(wb, report, rowToItem);
      _archiveMtoDuplicates(cat.id, report, batch);
    });

    report.projects = docs.projects().length - projectsBefore;
    report.documents = docs.documents().length - docsBefore;
    return report;
  }

  /// دیسالترهای واردشده از MTO که همان قلم بانک‌اند (همان پایه‌ی تگ و همان قیمت) بایگانی می‌شوند.
  void _archiveMtoDuplicates(int catId, DesalterImportReport report, String batch) {
    final rows = db.query(
      "SELECT i.id, i.tag FROM items i WHERE i.category_id = ? AND i.status = 'active' "
      "AND (i.legacy_ref IS NULL OR i.legacy_ref NOT LIKE 'DES-%')",
      [catId],
    );
    for (final r in rows) {
      final id = r['id'] as int;
      final amounts = [
        for (final o in db.query('SELECT amount FROM price_obs WHERE item_id = ? AND amount IS NOT NULL', [id]))
          o['amount'] as double,
      ];
      final dup = findDesalterBankDuplicate(db, catId, r['tag'] as String?, amounts);
      if (dup == null) continue;
      final ref = db.scalar('SELECT legacy_ref FROM items WHERE id = ?', [dup]);
      items.archive(id, archived: true, reason: 'تکراری با بانک دیسالتر ($ref) — بانک دیسالتر مرجع است');
      report.archivedDuplicates++;
    }
  }

  void _importVendors(XlsxWorkbook wb, DesalterImportReport report) {
    report.vendors += importVendorRegister(db, audit, wb);
  }

  void _importQuotes(XlsxWorkbook wb, DesalterImportReport report, Map<int, int> rowToItem) {
    final t = BankTable.open(wb, const ['Vendor_Quotes', 'Vendor Quotes', 'Quotes'], const {
      'Quote_ID': 1, 'Master Row': 2, 'Vendor_ID': 5, 'Quote Year (Jalali)': 8, 'Quote Ref / Date': 9,
      'Validity (days)': 10, 'Incoterm': 11, 'Currency': 12, 'Quoted Unit Price': 13, 'TBE OK': 14,
      'Delivery (weeks)': 16, 'Sc: Transformers': 17, 'Sc: Recycle Pumps': 18, 'Sc: Piping': 19, 'Sc: Instruments': 20,
      'Remarks': 21,
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
        'scope_transformers': _n(t.text(r, 'Sc: Transformers')),
        'scope_recycle_pumps': _n(t.text(r, 'Sc: Recycle Pumps')),
        'scope_piping': _n(t.text(r, 'Sc: Piping')),
        'scope_instruments': _n(t.text(r, 'Sc: Instruments')),
      }..removeWhere((k, v) => v == null);
      db.insert(
        'INSERT INTO price_obs(item_id, vendor_id, kind, is_primary, currency, amount, amount_text, cost_year, '
        'cost_year_text, incoterm, extra_json, notes, created_by, updated_by) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          itemId, vendorId, 'quote', 0, _n(t.text(r, 'Currency')),
          amount is double ? amount : null, amount is double ? null : _n(asText(amount)),
          year is double ? year.toInt() : null, year is double ? null : _n(asText(year)),
          _n(t.text(r, 'Incoterm')), jsonEncode(extra), _n(t.text(r, 'Remarks')), audit.userId, audit.userId,
        ],
      );
      report.quotes++;
    }
  }

  static String? _n(String s) => s.trim().isEmpty ? null : s.trim();
}
