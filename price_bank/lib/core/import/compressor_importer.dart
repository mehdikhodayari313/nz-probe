// انتقال یک‌باره‌ی بانک قیمت کمپرسور هوا (Air_Compressor_Price_Bank_v8.xlsx) به رده‌ی کمپرسور برنامه.
//
// - هر ردیف Master Database یک قلم کمپرسور می‌شود؛ شناسه‌ی پایدار CMP-0001 (Record ID = CMP-{row:04d}).
// - ستون‌ها با عنوان سرستون (ردیف ۴) شناخته می‌شوند؛ ستون‌های فرمولی (قیمت‌های مشتق، ضرایب، Coef) دوباره محاسبه می‌شوند.
// - سلول زرد = مقدار استنباطی، آبی = نرخ/مبنای متفاوت پروژه؛ Note سلول شاهد همان فیلد است.
// - فروشندگان و همه‌ی استعلام‌ها (قیمت‌دار، بی‌پاسخ، انصراف) منتقل می‌شوند (تصمیم کاربر: مثل پمپ‌ها).
// - اصلاح تأییدشده: سال قیمت KPL-476 = ۱۳۹۴/۱۰ (مثل بانک دیسالتر).
// - پکیج کامل هوای ابزار دقیق (CMP-IAP) در رده‌ی خشک‌کن هوا هم یک قلم بدون قیمت می‌گیرد؛ قیمت تخمینی سهم خشک‌کن
//   و داستان تخمین در «ملاحظات» آن نوشته می‌شود تا هنگام ساخت بانک خشک‌کن دستی وارد شود (تصمیم کاربر ۱۴۰۵/۰۷/۲۳).

import 'dart:convert';

import '../calc/pump_engine.dart' show asText, FactorTable;
import '../catalog/profiles.dart';
import '../db/db.dart';
import '../repo/audit.dart';
import '../repo/catalog_repo.dart';
import '../repo/docs_repo.dart';
import '../repo/items_repo.dart';
import '../xlsx/xlsx_reader.dart';
import 'bank_headers.dart';
import 'desalter_importer.dart' show isKplRecord, kplCostYear, kplCostMonth, kplCorrectionNote;
import 'v8_importer.dart';

class CompressorImportReport {
  int items = 0;
  int projects = 0;
  int documents = 0;
  int vendors = 0;
  int quotes = 0;
  int quotesPriced = 0;
  int inferredFlags = 0;
  int notes = 0;
  int corrections = 0;
  int dryerLinks = 0;
  final List<String> warnings = [];
  bool alreadyImported = false;
}

/// عنوان سرستون Master ← کلید فیلد برنامه
const compressorBankColumns = <String, String>{
  'Row': 'row_no',
  'Equipment Name': 'name',
  'Project Name': 'project',
  'Tag No.': 'tag',
  'Sub-Category': 'sub_category',
  'Compressor Type': 'compressor_type',
  'Capacity per Compressor (Nm³/h)': 'flow_m3h',
  'Discharge Pressure (barg)': 'discharge_pressure_barg',
  'Flow Basis (as in source)': 'flow_basis',
  'Compressor Standard': 'design_standard',
  'IPS Standard': 'ips_standard',
  'Configuration': 'configuration',
  'Driver Type': 'driver',
  'Quantity': 'quantity',
  'Compressors per Price Unit': 'compressors_per_price_unit',
  'Unit Weight (kg)': 'unit_weight_kg',
  'Weight Basis (as in source)': 'weight_basis',
  'Dew Point (°C)': 'pressure_dew_point_c',
  'Cost Year (Jalali)': 'cost_year',
  'Reference Currency': 'currency',
  'Unit Price (Reference)': 'unit_price',
  'Price Basis (as stated in source)': 'price_basis',
  'Incoterm': 'incoterm',
  'Manufacturer / Supplier (as in source)': 'manufacturer',
  'Supply Origin': 'supply_origin',
  'Project Phase': 'project_phase',
  'Scope: Air Dryer': 'scope_dryer',
  'Scope: Air Receiver': 'scope_receiver',
  'Scope: Filter Set': 'scope_filters',
  'Scope: Inter/After-cooler': 'scope_coolers',
  'Scope: Control Panel': 'scope_control_panel',
  'Scope: Spare Parts': 'scope_spares',
  'Scope: Vendor Site Services': 'scope_vendor_services',
  'Scope: Transport to Site': 'scope_transport',
  'Use as Estimator Peer (Y/N)': 'use_as_peer',
  'Source Document': 'source_document',
  'Remarks & Notes': 'remarks',
  'Include in Totals (Y/N)': 'include_in_totals',
};

/// متن فارسی وضعیت استعلام
const _quoteStatusFa = {'Quoted': 'قیمت داده', 'No reply': 'بدون پاسخ', 'Declined': 'انصراف'};

class CompressorImporter {
  CompressorImporter(this.db, this.audit, this.catalog, this.items, this.docs);
  final Db db;
  final Audit audit;
  final CatalogRepo catalog;
  final ItemsRepo items;
  final DocsRepo docs;

  static const masterSheet = 'Master Database';
  static const _yellow = 'FFFFFF00';
  static const _blue = 'FFDDEBF7';

  /// فایل، بانک قیمت کمپرسور هوا است؟ (App_Meta: equipment_code = CMP یا عنوان شیت Master)
  static bool isCompressorBank(XlsxWorkbook wb) {
    final meta = wb.sheet('App_Meta');
    if (meta != null) {
      for (var r = 1; r <= meta.maxRow; r++) {
        if (meta.text(r, 1) == 'equipment_code') return meta.text(r, 2) == 'CMP';
      }
    }
    final h = masterHeaders(wb);
    if (h == null) return false;
    // عنوان شیت («MASTER AIR COMPRESSOR PRICE DATABASE») یا ستون‌های خاص کمپرسور
    for (var r = 1; r < h.row && r <= 4; r++) {
      if (h.sheet.rowCells(r).any((c) => c.text.toUpperCase().contains('COMPRESSOR'))) return true;
    }
    return h.exact('Compressor Type') || h.exact('Compressors per Price Unit') || h.exact('Capacity per Compressor (Nm³/h)');
  }

  /// شیت Master و ستون‌هایش (نام شیت یا ردیف عنوان عوض شده باشد هم پیدا می‌شود)
  static HeaderMap? masterHeaders(XlsxWorkbook wb) =>
      findSheetHeaders(wb, const [masterSheet, 'Master', 'Database', 'Price Bank'], compressorBankColumns.keys.toList(),
          minMatches: 4);

  static String? validate(XlsxWorkbook wb) {
    final h = masterHeaders(wb);
    if (h == null || !isCompressorBank(wb)) return 'این فایل بانک قیمت کمپرسور هوا (Air_Compressor_Price_Bank) نیست.';
    if (!h.has('Equipment Name') && !h.has('Tag No.')) return 'ستون نام تجهیز یا شماره‌ی تگ در شیت «${h.sheet.name}» پیدا نشد.';
    if (!h.has('Unit Price (Reference)')) return 'ستون قیمت واحد در شیت «${h.sheet.name}» پیدا نشد.';
    return null;
  }

  /// ستون‌هایی که پیدا نشدند یا با عنوان دیگری پیدا شدند (برای گزارش ورود)
  static List<String> headerNotes(XlsxWorkbook wb) {
    final h = masterHeaders(wb);
    return h == null ? const [] : headerReport(h, what: 'بانک کمپرسور v8');
  }

  /// خواندن رکوردهای Master (فقط سلول‌های ورودی؛ بدون اصلاح‌ها) — برای ورود و آزمون طلایی.
  static List<({int row, Map<String, Object?> values, Map<String, FieldMeta> meta})> readMaster(XlsxWorkbook wb) {
    final h = masterHeaders(wb)!;
    final sh = h.sheet;
    final cols = h.cols;
    final out = <({int row, Map<String, Object?> values, Map<String, FieldMeta> meta})>[];
    final extras = extraInputColumns(h);
    for (var r = h.dataStart; r <= sh.maxRow; r++) {
      // بدون ستون Row: شماره‌ی ردیف از جای سطر؛ سطر بی‌نام و بی‌قیمت قلم نیست
      final rowNo = cols['Row'] == null
          ? ([for (final k in ['Equipment Name', 'Tag No.', 'Unit Price (Reference)']) if (cols[k] != null) sh.text(r, cols[k]!)]
                  .any((t) => t.trim().isNotEmpty)
              ? (r - h.row).toDouble()
              : null)
          : sh.cell(r, cols['Row']!)?.number;
      if (rowNo == null) continue;
      final values = <String, Object?>{};
      final meta = <String, FieldMeta>{};
      for (final e in compressorBankColumns.entries) {
        final col = cols[e.key];
        if (col == null) continue;
        final c = sh.cell(r, col);
        if (c != null) {
          final v = c.value;
          values[e.value] = v is double ? v : (v == null ? null : asText(v).trim());
        }
        final note = sh.comment(r, col);
        final fill = c?.fillRgb;
        final flag = fill == _yellow ? 'inferred' : (fill == _blue ? 'fx' : null);
        if (flag != null || (note != null && note.isNotEmpty)) meta[e.value] = FieldMeta(flag, note);
      }
      for (final (c, head) in extras) {
        final v = sh.cell(r, c)?.value;
        if (v != null) values['x:$head'] = v is double ? v : asText(v).trim();
      }
      values.removeWhere((k, v) => v == null || (v is String && v.isEmpty));
      out.add((row: rowNo.toInt(), values: values, meta: meta));
    }
    return out;
  }

  CompressorImportReport run(XlsxWorkbook wb, {String? fileName}) {
    final report = CompressorImportReport();
    final err = validate(wb);
    if (err != null) throw FormatException(err);
    report.warnings.addAll(headerNotes(wb));
    final missing = masterHeaders(wb)!.missing;
    final cat = catalog.categoryByCode('COMPRESSOR')!;
    final existing = db.scalar(
        "SELECT COUNT(*) FROM items WHERE category_id = ? AND legacy_ref LIKE 'CMP-%'", [cat.id]) as int;
    if (existing > 0) {
      report.alreadyImported = true;
      return report;
    }
    final batch = Audit.newBatch();
    final projectsBefore = docs.projects().length;
    final docsBefore = docs.documents().length;
    final rowToItem = <int, int>{};
    final extraAdded = <String>{};
    final src = fileName ?? 'بانک کمپرسور هوا';
    final iap = <({String ref, Map<String, Object?> values, int? projectId, int? documentId, int itemId})>[];

    db.transaction(() {
      for (final rec in readMaster(wb)) {
        final values = {...rec.values};
        final meta = {...rec.meta};
        for (final m in meta.values) {
          if (m.flag == 'inferred') report.inferredFlags++;
          if (m.note != null && m.note!.isNotEmpty) report.notes++;
        }
        final recordId = 'CMP-${rec.row.toString().padLeft(4, '0')}';
        markMissingFields(values, missing);
        values.remove('row_no');
        values['v8_row'] = recordId;

        final kpl = isKplRecord(values) && values['cost_year'] is double && (values['cost_year'] as double) != kplCostYear;
        final oldYear = values['cost_year'];
        if (kpl) {
          values['cost_year'] = kplCostYear.toDouble();
          meta['cost_year'] = FieldMeta('inferred', '$kplCorrectionNote (بانک کمپرسور هم ۱۳۹۳ نوشته بود.)');
          report.corrections++;
        }

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
        if (values['sub_category'] == 'CMP-IAP') {
          values['remarks'] = '${values['remarks'] ?? ''}\nدر بانک خشک‌کن هوا هم دیده می‌شود: قلم $recordId-DRY (بدون قیمت).'.trim();
        }

        extraAdded.addAll(storeExtraColumns(values, (l) => catalog.ensureSpecField(cat.id, l)));
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
              entity: 'item', entityId: id, field: 'cost_year', oldValue: oldYear, newValue: '$kplCostYear/$kplCostMonth',
              reason: kplCorrectionNote, batch: batch);
        }
        rowToItem[rec.row] = id;
        if (values['sub_category'] == 'CMP-IAP') {
          iap.add((ref: recordId, values: values, projectId: projectId, documentId: documentId, itemId: id));
        }
        report.items++;
      }
      _importVendors(wb, report);
      _importQuotes(wb, report, rowToItem);
      for (final p in iap) {
        _addDryerLink(p.ref, p.values, p.projectId, p.documentId, batch);
        report.dryerLinks++;
      }
    });

    if (extraAdded.isNotEmpty) {
      report.warnings.add('ستون‌های اضافه‌ی فایل (${extraAdded.map((e) => '«$e»').join('، ')}) در قالب برنامه نبودند؛ '
          'به‌صورت «مشخصات فنی (از منبع)» ثبت شدند.');
    }
    report.projects = docs.projects().length - projectsBefore;
    report.documents = docs.documents().length - docsBefore;
    return report;
  }

  /// قلم بدون قیمت در رده‌ی خشک‌کن هوا برای پکیج کامل IA/PA؛ برآورد سهم خشک‌کن و داستان آن در «ملاحظات».
  void _addDryerLink(String ref, Map<String, Object?> v, int? projectId, int? documentId, String batch) {
    final dryer = catalog.categoryByCode('AIR_DRYER');
    if (dryer == null) return;
    final f = FactorTable(_factorMap(factorSetOf('COMPRESSOR')));
    final note = compressorDryerShareNote(ref, v, f);
    items.create(
      categoryId: dryer.id,
      values: {
        'name': 'خشک‌کن هوا — بخشی از ${v['name'] ?? 'پکیج کامل هوای ابزار دقیق'}',
        'tag': v['tag'],
        'quantity': 1.0,
        'flow_m3h': v['flow_m3h'],
        'scope': 'جزئی از پکیج کامل $ref (کمپرسورها + خشک‌کن + فیلترها + مخازن در یک قیمت)',
        'include_in_totals': 'N',
        'remarks': note,
        'v8_row': '$ref-DRY',
      },
      projectId: projectId,
      reason: 'پکیج کامل IA/PA بانک کمپرسور ($ref) — قیمت خالی برای ورود دستی (تصمیم کاربر ۱۴۰۵/۰۷/۲۳)',
      batch: batch,
    );
  }

  Map<String, double> _factorMap(String set) => {
        for (final r in db.query('SELECT grp, option, COALESCE(calibrated, provisional) AS v FROM factors WHERE set_code = ?', [set]))
          '${r['grp']}|${r['option']}': (r['v'] as num).toDouble(),
      };

  void _importVendors(XlsxWorkbook wb, CompressorImportReport report) {
    report.vendors += importVendorRegister(db, audit, wb, licensorCol: 0, notesCol: 8);
  }

  /// همه‌ی استعلام‌ها، حتی بی‌پاسخ و انصراف (مبلغ خالی، وضعیت در یادداشت).
  void _importQuotes(XlsxWorkbook wb, CompressorImportReport report, Map<int, int> rowToItem) {
    final t = BankTable.open(wb, const ['Vendor_Quotes', 'Vendor Quotes', 'Quotes'], const {
      'Quote_ID': 1, 'Master Row': 2, 'Vendor_ID': 5, 'Quote Status': 8, 'Quote Year (Jalali)': 9, 'Quote Ref / Date': 10,
      'Validity (days)': 11, 'Incoterm': 12, 'Currency': 13, 'Quoted Unit Price': 14, 'Quoted Total': 15,
      'Units Quoted': 16, 'TBE OK': 17, 'Delivery (weeks)': 19, 'Sc: Dryer': 20, 'Sc: Spares': 21, 'Remarks': 22,
    });
    if (t == null) return;
    final sh = t.sh;
    int c(String h) => t.col(h);
    for (var r = t.start; r <= sh.maxRow; r++) {
      final qid = sh.text(r, c('Quote_ID'));
      if (qid.isEmpty || qid.startsWith('Q-EX')) continue;
      final masterRow = sh.cell(r, c('Master Row'))?.number;
      final itemId = masterRow == null ? null : rowToItem[masterRow.toInt()];
      if (itemId == null) {
        report.warnings.add('استعلام $qid: ردیف Master «${sh.text(r, c('Master Row'))}» پیدا نشد');
        continue;
      }
      final vcode = sh.text(r, c('Vendor_ID'));
      final vendorId = vcode.isEmpty ? null : db.scalar('SELECT id FROM vendors WHERE code = ?', [vcode]) as int?;
      final status = sh.text(r, c('Quote Status'));
      final amount = sh.cell(r, c('Quoted Unit Price'))?.value;
      final year = sh.cell(r, c('Quote Year (Jalali)'))?.value;
      final extra = <String, Object?>{
        'quote_id': qid,
        'quote_status': _n(status),
        'quote_ref': _n(sh.text(r, c('Quote Ref / Date'))),
        'validity_days': sh.cell(r, c('Validity (days)'))?.number,
        'quoted_total': sh.cell(r, c('Quoted Total'))?.number,
        'units_quoted': sh.cell(r, c('Units Quoted'))?.number,
        'tbe': _n(sh.text(r, c('TBE OK'))),
        'delivery_weeks': sh.cell(r, c('Delivery (weeks)'))?.number,
        'scope_dryer': _n(sh.text(r, c('Sc: Dryer'))),
        'scope_spares': _n(sh.text(r, c('Sc: Spares'))),
      }..removeWhere((k, v) => v == null);
      final remarks = _n(sh.text(r, c('Remarks')));
      final st = _quoteStatusFa[status] ?? status;
      final notes = [if (st.isNotEmpty) 'وضعیت: $st', if (remarks != null) remarks].join(' — ');
      final priced = amount is double;
      db.insert(
        'INSERT INTO price_obs(item_id, vendor_id, kind, is_primary, currency, amount, amount_text, cost_year, '
        'cost_year_text, incoterm, extra_json, notes, created_by, updated_by) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          itemId, vendorId, 'quote', 0, priced ? _n(sh.text(r, c('Currency'))) : null,
          priced ? amount : null, priced ? null : (st.isEmpty ? null : st),
          year is double ? year.toInt() : null, year is double ? null : _n(asText(year)),
          _n(sh.text(r, c('Incoterm'))), jsonEncode(extra), notes.isEmpty ? null : notes, audit.userId, audit.userId,
        ],
      );
      report.quotes++;
      if (priced) report.quotesPriced++;
    }
  }

  static String? _n(String s) => s.trim().isEmpty ? null : s.trim();
}

String _g(double v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// برآورد سهم خشک‌کن از قیمت پکیج کامل IA/PA (برای قلم بدون قیمت رده‌ی خشک‌کن) با داستان تخمین.
String compressorDryerShareNote(String ref, Map<String, Object?> v, FactorTable f) {
  final dry = f.get('SC_DRY', 'Y'), rec = f.get('SC_REC', 'Y'), flt = f.get('SC_FLT', 'Y');
  final set = dry * rec * flt;
  final shareSet = 1 - 1 / set;
  final shareDry = (dry - 1) / set;
  final p = v['unit_price'] is num ? (v['unit_price']! as num).toDouble() : null;
  final cur = v['currency']?.toString() ?? '';
  final y = v['cost_year'] is num ? (v['cost_year']! as num).toInt().toString() : '—';
  String pct(double x) => (x * 100).toStringAsFixed(1);
  final money = p == null
      ? 'قیمت پکیج در منبع نیست.'
      : 'قیمت کل پکیج ${_g(p)} $cur (سال $y) ← خشک‌کن + مخزن + فیلتر ≈ ${_g(p * shareSet)} $cur؛ '
          'خشک‌کن تنها ≈ ${_g(p * shareDry)} $cur.';
  return 'قیمت این قلم عمداً خالی است تا هنگام ساخت بانک خشک‌کن دستی وارد شود (تصمیم کاربر ۱۴۰۵/۰۷/۲۳).\n'
      'منبع: پکیج کامل هوای ابزار دقیق و سرویس $ref در بانک کمپرسور — ${v['configuration'] ?? ''} '
      '${v['compressor_type'] ?? ''}، دبی هر کمپرسور ${v['flow_m3h'] ?? '—'} Nm³/h، نقطه‌ی شبنم '
      '${v['pressure_dew_point_c'] ?? '—'} °C؛ کمپرسورها، خشک‌کن، فیلترها و مخازن در یک قیمت.\n'
      'داستان تخمین: پکیج کامل به ازای هر کمپرسور (تعدیل‌شده به ۱۴۰۴ با C28.13) ≈ ۲۷۶ هزار یورو و پکیج کمپرسور تنهای '
      'گچساران ۴ در همان دبی (۳۰۰ Nm³/h) ≈ ۲۰۰ هزار یورو است (نسبت ۱٫۳۸). با ضریب اسکرو بدون روغن ۰٫۹، ضریب دامنه‌ی '
      '«خشک‌کن + مخزن + فیلتر» ≈ ۱٫۵۳ به دست آمد (ضریب اکسل ۱٫۱۸ بود). ضریب‌ها: خشک‌کن ${dry.toStringAsFixed(3)} × '
      'مخزن ${rec.toStringAsFixed(2)} × فیلتر ${flt.toStringAsFixed(2)} = ${set.toStringAsFixed(2)}.\n'
      'سهم خشک‌کن + مخزن + فیلتر = ۱ − ۱/${set.toStringAsFixed(2)} ≈ ${pct(shareSet)}٪؛ '
      'سهم خشک‌کن تنها = (${dry.toStringAsFixed(3)} − ۱)/${set.toStringAsFixed(2)} ≈ ${pct(shareDry)}٪.\n'
      '$money\n'
      'وضعیت: Provisional — فقط با یک پکیج کامل و دو رکورد گچساران؛ با قیمت واقعی خشک‌کن کالیبره شود.';
}
