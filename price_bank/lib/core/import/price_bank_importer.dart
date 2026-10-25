// ورود «بانک قیمت تجمیعی» کاربر (یک کارپوشه با یک شیت برای هر خانواده‌ی تجهیز: Pumps، Vessels، Tanks، …
// و شیت Vendor_Quotes). قالب ثابت فرض نمی‌شود:
// - شیت خانواده = شیتی که ردیف عنوانش (هر جای ۲۵ ردیف اول) نام تجهیز/تگ، قیمت واحد و سال قیمت دارد.
// - رده از کد عنوان شیت («PUMP – پمپ | …»)، نام شیت یا نام قلم.
// - ستون‌ها از عنوان به فیلدهای رده؛ ستون‌های فنی بدون فیلد با قواعد همان رده (مثل شرح MTO) خوانده می‌شوند و
//   هرچه فیلد ندارد «مشخصات فنی (از منبع)» می‌شود. ستون‌های محاسباتی بانک (قیمت تعدیل‌شده، ضرایب، نرمال‌سازی)
//   وارد نمی‌شوند؛ برنامه خودش حساب می‌کند.
// - همه‌ی استعلام‌ها (قیمت‌دار، بی‌پاسخ، انصراف) با RID به قلم وصل می‌شوند.
// - تصمیم کاربر ۱۴۰۵/۰۸/۰۳: بانک قیمت مرجع است؛ قلم تکراری (همان رده و تگ و همان قیمت) از منبع دیگر بایگانی می‌شود.

import '../catalog/profiles.dart';
import '../db/db.dart';
import '../repo/audit.dart';
import '../repo/catalog_repo.dart';
import '../repo/docs_repo.dart';
import '../repo/items_repo.dart';
import '../xlsx/xlsx_reader.dart';
import 'bank_headers.dart';
import 'mto_generic.dart' show normTag;
import 'v8_importer.dart';

class PriceBankImportReport {
  int items = 0, components = 0, quotes = 0, quotesPriced = 0, projects = 0, documents = 0;
  int archivedDuplicates = 0, skippedExisting = 0, specFields = 0;
  final Map<String, int> perCategory = {};
  final List<String> warnings = [];
}

/// عنوان‌های اصلی هر شیت خانواده
const priceBankCoreHeaders = [
  'RID', 'Equipment Name', 'Project', 'Tag No.', 'Record Type', 'Parent Package', 'Qty', 'Unit', 'Cost Year', 'Month',
  'Reference Currency', 'Unit Price (Reference)', 'IRR Part (mixed items)', 'Doc FX Rate (as in source)',
  'Price Basis (as stated in source)', 'Incoterm', 'Source Document', 'Remarks',
];

/// کد خانواده‌ی بانک ← کد رده‌ی برنامه
const _familyCategory = {
  'PUMP': 'PUMP', 'AIRCOMP': 'COMPRESSOR', 'COMPRESSOR': 'COMPRESSOR', 'AIRDRYER': 'AIR_DRYER', 'BURNPIT': 'FLARE',
  'CIP': 'CIP', 'CRANE': 'CRANE', 'DEAERATOR': 'DEAERATOR', 'DESALTER': 'DESALTER', 'FILTER': 'FILTER', 'FLARE': 'FLARE',
  'HEATER': 'HEATER', 'HEX': 'HEX', 'IGF': 'IGF', 'MISC': 'MISC_PKG', 'TANK': 'TANK', 'VESSEL': 'VESSEL',
  'VALVE': 'VALVE', 'PIPING': 'PIPE_BULK', 'ELEC': 'ELEC_EQ', 'INST': 'INST_EQ', 'HVAC': 'HVAC', 'LAB': 'LAB',
  'FIRE_SAFETY': 'FIRE_SAFETY', 'WATER_TREATMENT': 'WATER_TREAT',
};

/// ستون‌های محاسباتی بانک (برنامه خودش حساب می‌کند)
final _computed = RegExp(
    r'^(unit price (eur|usd|irr) \(source|escalated|f [a-z_ ]+$|all_f$|normalized|index (base|target)|size value|'
    r'cost coefficient|search key|key specs|qa flag|counter|شمارنده)',
    caseSensitive: false);

/// هم‌معنی‌های عنوان ستون برای فیلدهای قالب رده‌ها (کلید فیلد ← عنوان‌های رایج)
const _fieldSynonyms = <String, List<String>>{
  'id_mm': ['ID', 'Inside Diameter', 'Diameter'],
  'tl_mm': ['TL-TL', 'T/T', 'Length TL-TL'],
  'diameter_mm': ['Diameter', 'ID'],
  'height_mm': ['Height', 'Shell Height'],
  'vessel_id_mm': ['Vessel ID'],
  'vessel_tl_mm': ['Vessel TL-TL', 'Vessel T/T'],
  'shell_id_mm': ['Shell ID'],
  'shell_tl_mm': ['Shell TL-TL'],
  'driver': ['Driver Type', 'Driver'],
  'design_standard': ['Compressor Standard'],
  'plate_material': ['Plate or Tube Material', 'Plate Material', 'Tube Material'],
  'gasket_material': ['Gasket or Shell Material', 'Gasket Material'],
  'material_class': ['Material Class', 'HEX Material Class', 'API 610 Material Class'],
  'unit_weight_kg': ['Unit Weight', 'Weight per Compressor'],
  'empty_weight_kg': ['Weight', 'Empty Weight', 'Fabricated Weight'],
  'seal_arrangement': ['Seal Type or Arrangement', 'Seal Arrangement', 'Seal Type'],
  'manufacturer': ['Manufacturer or Supplier', 'Manufacturer', 'Supplier'],
  'flow_m3h': ['Capacity per Compressor', 'Inlet Flow', 'Design Flow', 'Max Flow', 'Flow'],
  'capacity_kgh': ['Capacity'],
  'duty_kw': ['Duty'],
};

/// فیلد قالب رده برای عنوان ستون بانک (null = فیلد ندارد؛ مشخصه می‌شود)
FieldDef? _fieldFor(List<FieldDef> fields, String header) {
  final nh = normHeader(header), ch = coreHeader(header);
  for (final f in fields) {
    if (f.storage == FieldStorage.calc) continue;
    final k = normHeader(f.key.replaceAll('_', ' '));
    if (k == nh || k == ch) return f;
    if ((f.labelEn ?? '').isNotEmpty && headerQuality(f.labelEn!, header) >= 70) return f;
    for (final syn in _fieldSynonyms[f.key] ?? const <String>[]) {
      if (normHeader(syn) == nh || coreHeader(syn) == ch) return f;
    }
  }
  return null;
}

class PriceBankImporter {
  PriceBankImporter(this.db, this.audit, this.catalog, this.items, this.docs);
  final Db db;
  final Audit audit;
  final CatalogRepo catalog;
  final ItemsRepo items;
  final DocsRepo docs;

  /// شیت‌های خانواده‌ی کارپوشه (شیت، نقشه‌ی عنوان، کد رده)
  static List<(XlsxSheet, HeaderMap, String?)> familySheets(XlsxWorkbook wb) {
    final out = <(XlsxSheet, HeaderMap, String?)>[];
    for (final info in wb.sheets) {
      final sh = wb.sheet(info.name);
      if (sh == null) continue;
      final h = findHeaders(sh, priceBankCoreHeaders, minMatches: 6);
      if (h == null) continue;
      if (!(h.has('Equipment Name') || h.has('Tag No.')) || !h.has('Unit Price (Reference)') || !h.has('Cost Year')) continue;
      if (!(h.has('RID') || h.has('Record Type'))) continue;
      out.add((sh, h, _categoryOf(sh, h)));
    }
    return out;
  }

  /// کارپوشه بانک قیمت تجمیعی است؟ (دست‌کم یک شیت خانواده با ستون «نوع رکورد» یا شناسه‌ی RID)
  static bool isPriceBank(XlsxWorkbook wb) => familySheets(wb).isNotEmpty;

  static String? _categoryOf(XlsxSheet sh, HeaderMap h) {
    for (var r = 1; r < h.row && r <= 3; r++) {
      final t = sh.text(r, 1).trim();
      final m = RegExp(r'^([A-Z_]{2,})\s*[–\-:|]').firstMatch(t.toUpperCase());
      if (m != null && _familyCategory[m.group(1)] != null) return _familyCategory[m.group(1)];
    }
    final n = sh.name.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    for (final e in _familyCategory.entries) {
      if (n == e.key || n == '${e.key}S' || n == '${e.key}ES') return e.value;
    }
    return suggestCategoryFromText(sh.name);
  }

  PriceBankImportReport run(XlsxWorkbook wb, {String? fileName}) {
    final rep = PriceBankImportReport();
    final fams = familySheets(wb);
    if (fams.isEmpty) throw const FormatException('شیت تجهیزات بانک قیمت (نام، تگ، قیمت واحد، سال قیمت) پیدا نشد.');
    final batch = Audit.newBatch();
    final projectsBefore = docs.projects().length;
    final docsBefore = docs.documents().length;
    final ridToItem = <String, int>{};
    final imported = <int>{};
    final src = fileName ?? 'بانک قیمت';

    db.transaction(() {
      for (final (sh, h, catCode0) in fams) {
        final extras = <int, String>{};
        for (var c = 1; c <= sh.maxCol && c <= 250; c++) {
          if (h.cols.values.contains(c)) continue;
          final head = sh.text(h.row, c).replaceAll('\n', ' ').trim();
          if (head.isEmpty || _computed.hasMatch(head)) continue;
          extras[c] = head;
        }
        final missing = [
          for (final m in h.missing)
            if (const {'RID', 'Project', 'Tag No.', 'Cost Year', 'Reference Currency', 'Unit Price (Reference)'}.contains(m)) m,
        ];
        if (missing.isNotEmpty) {
          rep.warnings.add('شیت «${sh.name}»: ستون‌های ${missing.map((m) => '«$m»').join('، ')} نبود؛ «در منبع وجود نداشت».');
        }
        for (var r = h.dataStart; r <= sh.maxRow; r++) {
          String t(String k) => h[k] == null ? '' : sh.text(r, h[k]!).trim();
          Object? v(String k) => h[k] == null ? null : sh.cell(r, h[k]!)?.value;
          final name = t('Equipment Name'), tag = t('Tag No.'), rid = t('RID');
          if (name.isEmpty && tag.isEmpty) continue;
          if (RegExp(r'^(total|جمع|sum)\b', caseSensitive: false).hasMatch(name)) continue;
          // رده: از شیت؛ «سایر» بر پایه‌ی نام قلم
          var code = catCode0;
          if (code == null || code == 'MISC_PKG') {
            code = serviceCategoryFromText(name) ?? priorityCategoryFromText(name) ?? suggestCategoryFromText(name) ?? code ?? 'MISC_PKG';
          }
          final cat = catalog.categoryByCode(code) ?? catalog.categoryByCode('MISC_PKG')!;
          if (!cat.enabled) db.execute('UPDATE categories SET enabled = 1 WHERE id = ?', [cat.id]);
          // قبلاً از همین بانک وارد شده است؟
          if (rid.isNotEmpty) {
            final ex = db.scalar(
                "SELECT id FROM items WHERE category_id = ? AND legacy_ref = ? AND status = 'active' AND (tag IS ? OR tag = ?)",
                [cat.id, rid, tag.isEmpty ? null : tag, tag]) as int?;
            if (ex != null) {
              ridToItem[rid] = ex;
              rep.skippedExisting++;
              continue;
            }
          }
          final fields = catalog.fields(cat.id);
          final values = <String, Object?>{
            'name': name.isEmpty ? tag : name,
            'tag': tag.isEmpty ? null : tag,
            'quantity': v('Qty') is double ? v('Qty') : null,
            'v8_row': rid.isEmpty ? null : rid,
            'cost_year': v('Cost Year'),
            'currency': t('Reference Currency').isEmpty ? null : t('Reference Currency').toUpperCase(),
            'unit_price': v('Unit Price (Reference)') is double ? v('Unit Price (Reference)') : null,
            'incoterm': t('Incoterm').isEmpty ? null : t('Incoterm'),
            'price_basis': t('Price Basis (as stated in source)').isEmpty ? null : t('Price Basis (as stated in source)'),
            'remarks': t('Remarks').isEmpty ? null : t('Remarks'),
          };
          final basis = (values['price_basis'] as String? ?? '').toLowerCase();
          values['_price_kind'] = basis.startsWith('vendor inquiry')
              ? 'other'
              : (basis.startsWith('purchase price') ? 'contract' : 'estimate');
          final fx = v('Doc FX Rate (as in source)');
          if (fx is double && fx > 0) values['_source_fx_rate'] = fx;
          // ستون‌های اضافه: اول فیلد هم‌نام رده، بعد قواعد مشخصات همان رده، بقیه «مشخصات فنی (از منبع)»
          final specs = <String, String>{};
          for (final e in {
            ...extras,
            for (final k in ['Record Type', 'Parent Package', 'Unit', 'IRR Part (mixed items)', 'Doc FX Rate (as in source)'])
              if (h[k] != null) h[k]!: k,
          }.entries) {
            final cell = sh.cell(r, e.key);
            final raw = cell?.value;
            if (raw == null || cell!.text.trim().isEmpty) continue;
            final f = _fieldFor(fields, e.value);
            if (f != null && values[f.key] == null) {
              values[f.key] = raw is double ? raw : cell.text.trim();
            } else {
              specs[e.value] = raw is double ? (raw == raw.roundToDouble() ? raw.toStringAsFixed(0) : '$raw') : cell.text.trim();
            }
          }
          final profile = equipmentProfiles[cat.code];
          if (cat.code == 'PUMP') {
            for (final e in extractPumpSpecs(specs, name).entries) {
              values.putIfAbsent(e.key, () => e.value);
            }
          } else if (profile != null) {
            for (final e in profile.extract(specs, context: name).entries) {
              values.putIfAbsent(e.key, () => e.value);
            }
          }
          final left = cat.code == 'PUMP' ? pumpSpecLeftovers(specs) : (profile?.leftovers(specs) ?? specs.entries.toList());
          for (final e in left) {
            final key = catalog.ensureSpecField(cat.id, e.key);
            if (key.$2) rep.specFields++;
            values.putIfAbsent(key.$1, () => e.value);
          }
          final irrPart = v('IRR Part (mixed items)');
          if (irrPart is double && irrPart > 0) {
            values['remarks'] = '${values['remarks'] ?? ''}\nبخش ریالی همین قلم (اقلام مختلط): $irrPart ریال'.trim();
          }
          // پروژه و سند منبع
          final project = t('Project');
          final pid = project.isEmpty ? null : docs.ensureProject(project);
          final srcDoc = t('Source Document');
          int? docId;
          if (srcDoc.isNotEmpty) {
            final (title, loc) = V8Importer.splitSourceDocument(srcDoc);
            values['_source_location'] = loc;
            docId = docs.ensureDocument(projectId: pid, title: title, docType: 'price_bank');
          }
          final id = items.create(
            categoryId: cat.id,
            values: values,
            projectId: pid,
            documentId: values['unit_price'] == null ? null : docId,
            reason: 'ورود بانک قیمت $src (${sh.name} ردیف $r${rid.isEmpty ? '' : '، $rid'})',
            batch: batch,
          );
          final month = v('Month');
          if (month is double && month >= 1 && month <= 12) {
            db.execute('UPDATE price_obs SET cost_month = ? WHERE item_id = ? AND is_primary = 1', [month.toInt(), id]);
          }
          if (rid.isNotEmpty) ridToItem[rid] = id;
          imported.add(id);
          rep.items++;
          if (values['unit_price'] == null && t('Record Type').toLowerCase().startsWith('comp')) rep.components++;
          rep.perCategory[cat.code] = (rep.perCategory[cat.code] ?? 0) + 1;
        }
      }
      _importQuotes(wb, rep, ridToItem);
      _archiveDuplicates(rep, imported, batch);
    });
    rep.projects = docs.projects().length - projectsBefore;
    rep.documents = docs.documents().length - docsBefore;
    return rep;
  }

  void _importQuotes(XlsxWorkbook wb, PriceBankImportReport rep, Map<String, int> ridToItem) {
    final t = BankTable.open(wb, const ['Vendor_Quotes', 'Vendor Quotes', 'Quotes'], const {
      'Linked RID': 1, 'Project': 2, 'Tag No.': 3, 'Family': 4, 'Vendor': 5, 'Status': 6, 'Currency': 7,
      'Quoted Unit Price': 8, 'Quote Year': 9, 'Quote Month': 10, 'Quote Date (Jalali)': 11, 'Quote Date (Gregorian)': 12,
      'Source': 13,
    });
    if (t == null || t.col('Linked RID') == 0) return;
    for (var r = t.start; r <= t.sh.maxRow; r++) {
      final rid = t.text(r, 'Linked RID').trim();
      if (rid.isEmpty) continue;
      final itemId = ridToItem[rid];
      if (itemId == null) {
        rep.warnings.add('استعلام ردیف $r: رکورد «$rid» در شیت‌های تجهیزات پیدا نشد');
        continue;
      }
      final vendor = t.text(r, 'Vendor').trim();
      final status = t.text(r, 'Status').trim();
      final amount = t.cell(r, 'Quoted Unit Price')?.value;
      final priced = amount is double;
      final year = t.cell(r, 'Quote Year')?.number, month = t.cell(r, 'Quote Month')?.number;
      final st = const {'priced': 'قیمت داده', 'no reply': 'بدون پاسخ', 'declined': 'انصراف'}[status.toLowerCase()] ?? status;
      final dateText = [t.text(r, 'Quote Date (Jalali)'), t.text(r, 'Quote Date (Gregorian)')].where((s) => s.isNotEmpty).join(' / ');
      final vid = vendor.isEmpty ? null : docs.ensureVendor(vendor);
      final exists = db.scalar(
          "SELECT 1 FROM price_obs WHERE item_id = ? AND kind = 'quote' AND vendor_id IS ? AND "
          '(amount IS ? OR amount_text IS ?) AND cost_year IS ? AND cost_month IS ?',
          [itemId, vid, priced ? amount : null, priced ? null : (st.isEmpty ? null : st), year?.toInt(), month?.toInt()]);
      if (exists != null) continue;
      items.addObservation(
        itemId,
        vendorId: vid,
        kind: 'quote',
        currency: priced ? t.text(r, 'Currency').toUpperCase() : null,
        amount: priced ? amount : (st.isEmpty ? null : st),
        costYear: year?.toInt(),
        costMonth: month?.toInt(),
        sourceLocation: t.text(r, 'Source').isEmpty ? null : t.text(r, 'Source'),
        notes: [if (st.isNotEmpty) 'وضعیت: $st', if (dateText.isNotEmpty) 'تاریخ: $dateText'].join(' — '),
      );
      rep.quotes++;
      if (priced) rep.quotesPriced++;
    }
  }

  /// قلم همان رده با همان تگ و همان قیمت از منبع دیگر (MTO یا بانک‌های جدا) تکراری است ← بایگانی (بانک قیمت مرجع است)
  void _archiveDuplicates(PriceBankImportReport rep, Set<int> imported, String batch) {
    final mine = <(int, String, String, double)>[];
    for (final id in imported) {
      final r = db.queryOne(
          'SELECT i.category_id, i.tag, o.currency, o.amount FROM items i JOIN price_obs o ON o.item_id = i.id AND o.is_primary = 1 '
          'WHERE i.id = ? AND o.amount IS NOT NULL',
          [id]);
      if (r == null || r['tag'] == null) continue;
      mine.add((r['category_id'] as int, normTag(r['tag'] as String), r['currency'] as String? ?? '', (r['amount'] as num).toDouble()));
    }
    if (mine.isEmpty) return;
    final candidates = db.query(
        "SELECT i.id, i.category_id, i.tag, i.legacy_ref FROM items i WHERE i.status = 'active' AND i.tag IS NOT NULL");
    for (final c in candidates) {
      final id = c['id'] as int;
      if (imported.contains(id)) continue;
      final tag = normTag(c['tag'] as String);
      final obs = db.query('SELECT currency, amount FROM price_obs WHERE item_id = ? AND amount IS NOT NULL', [id]);
      final dup = mine.any((m) =>
          m.$1 == c['category_id'] &&
          m.$2 == tag &&
          obs.any((o) => (o['currency'] ?? '') == m.$3 && ((o['amount'] as num).toDouble() - m.$4).abs() <= 0.005 * m.$4));
      if (!dup) continue;
      items.archive(id, archived: true, reason: 'تکراری با بانک قیمت (همان تگ و قیمت) — بانک قیمت مرجع است');
      rep.archivedDuplicates++;
    }
  }
}
