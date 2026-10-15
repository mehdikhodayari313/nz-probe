// قالب پایه‌ی رده‌های تجهیزات غیرپمپ (ظرف، مخزن، مبدل، پکیج‌ها، …).
//
// هر رده فیلدهای شناسایی، قیمت و «شرح کامل MTO» را دارد؛ مشخصات فنی هر رده هنگام ورود MTO
// از خط‌های «کلید: مقدار» شرح ساخته و به قالب اضافه می‌شوند (ظرف: ابعاد، فشار طراحی، جنس، …).
// این تابع در هر بار باز شدن برنامه اجرا می‌شود و تکرار آن بی‌اثر است.

import '../calc/series.dart';
import '../catalog/eurostat_ppi.dart';
import '../catalog/profiles.dart';
import '../catalog/us_ppi.dart';
import '../db/db.dart';
import 'catalog_repo.dart';

/// رده‌هایی که از مرحله‌ی ۲ (ورود MTO) فعال می‌شوند.
const genericCategoryCodes = [
  'COMPRESSOR', 'DESALTER', 'HEATER', 'VESSEL', 'TANK', 'HEX', 'CIP', 'IGF', 'FILTER', 'FLARE', 'DEAERATOR',
  'AIR_DRYER', 'CRANE',
  // رده‌های عمومی (بدون قالب تخصصی): برای ورود کامل MTO و PEP (برق، ابزار دقیق، پایپینگ، آزمایشگاه، …)
  'WATER_TREAT', 'HVAC', 'FIRE_SAFETY', 'MISC_PKG', 'LAB', 'VALVE', 'PIPE_BULK', 'ELEC_EQ', 'INST_EQ',
];

/// رده‌های افزوده (برای دیتابیس‌های قدیمی که این رده‌ها را ندارند): (کد، رشته، والد، نام فارسی، نام انگلیسی)
const _extraCategories = [
  ('WATER_TREAT', 'MECH', 'MECH_PKG', 'پکیج تصفیه آب و پساب', 'Water / Waste Water Treatment'),
  ('HVAC', 'MECH', 'MECH_PKG', 'تهویه مطبوع (HVAC)', 'HVAC'),
  ('FIRE_SAFETY', 'MECH', 'MECH_PKG', 'تجهیزات ایمنی و آتش‌نشانی', 'Fire Fighting & Safety'),
  ('MISC_PKG', 'MECH', 'MECH_PKG', 'سایر پکیج‌ها و تجهیزات', 'Other Packages & Equipment'),
];

// (کلید، برچسب، گروه، نام گروه، ذخیره، نوع، فهرست، واحد، ترتیب)
const _baseFields = <(String, String, String, String, String, String, String?, String?, int)>[
  ('name', 'نام تجهیز / سرویس', 'identification', 'شناسایی', 'core', 'text', null, null, 1),
  ('project', 'پروژه', 'identification', 'شناسایی', 'core', 'text', null, null, 2),
  ('tag', 'شماره تگ', 'identification', 'شناسایی', 'core', 'text', null, null, 3),
  ('quantity', 'تعداد', 'identification', 'شناسایی', 'core', 'number', null, 'دستگاه', 4),
  ('mto_description', 'شرح کامل (از MTO)', 'description', 'شرح', 'spec', 'text', null, null, 10),
  ('cost_year', 'سال قیمت (شمسی)', 'price', 'قیمت اصلی', 'price', 'enum', 'Year', null, 900),
  ('currency', 'ارز مرجع', 'price', 'قیمت اصلی', 'price', 'enum', 'Currency', null, 901),
  ('unit_price', 'قیمت واحد (ارز مرجع)', 'price', 'قیمت اصلی', 'price', 'number', null, null, 902),
  ('remarks', 'ملاحظات', 'control', 'کنترل', 'core', 'text', null, null, 950),
  ('include_in_totals', 'شمارش در جمع‌ها', 'control', 'کنترل', 'core', 'enum', 'YN', null, 951),
];

void ensureGenericTemplates(Db db) {
  db.transaction(() {
    for (final (code, disc, parent, fa, en) in _extraCategories) {
      if (db.scalar('SELECT id FROM categories WHERE code = ?', [code]) != null) continue;
      final pid = db.scalar('SELECT id FROM categories WHERE code = ?', [parent]) as int?;
      final sort = (db.scalar('SELECT COALESCE(MAX(sort), 0) + 1 FROM categories') as int?) ?? 0;
      db.execute(
        'INSERT INTO categories(code, discipline_code, parent_id, name_fa, name_en, sort, enabled) VALUES (?,?,?,?,?,?,1)',
        [code, disc, pid, fa, en, sort],
      );
    }
    for (final code in genericCategoryCodes) {
      final id = db.scalar('SELECT id FROM categories WHERE code = ?', [code]) as int?;
      if (id == null) continue;
      db.execute('UPDATE categories SET enabled = 1 WHERE id = ? AND enabled = 0', [id]);
      for (final (key, label, grp, grpFa, storage, type, list, unit, sort) in _baseFields) {
        db.execute(
          'INSERT OR IGNORE INTO field_defs(category_id, key, label_fa, group_key, group_fa, storage, data_type, '
          'list_key, unit, sort) VALUES (?,?,?,?,?,?,?,?,?,?)',
          [id, key, label, grp, grpFa, storage, type, list, unit, sort],
        );
      }
      // قالب تخصصی رده
      final p = equipmentProfiles[code];
      if (p == null) continue;
      for (var i = 0; i < p.fields.length; i++) {
        final f = p.fields[i];
        db.execute(
          'INSERT OR IGNORE INTO field_defs(category_id, key, label_fa, label_en, group_key, group_fa, storage, data_type, '
          "list_key, unit, help_fa, source_ref, sort) VALUES (?,?,?,?,?,?,'spec',?,?,?,?,'قالب رده',?)",
          [id, f.key, f.labelFa, f.labelEn, f.group, profileGroupFa[f.group] ?? f.group, f.type, f.list, f.unit, f.help,
            profileGroupSort(f.group) + i],
        );
      }
      for (final (grp, opt, v, desc) in p.factorSeeds ?? profileFactorSeeds) {
        if (!p.factorGroups.contains(grp)) continue;
        db.execute(
          'INSERT OR IGNORE INTO factors(set_code, grp, option, provisional, description) VALUES (?,?,?,?,?)',
          [factorSetOf(code), grp, opt, v, 'اولیه (قضاوت مهندسی) | $desc'],
        );
      }
    }
    for (final e in profileLists.entries) {
      var i = 0;
      for (final (v, label) in e.value) {
        db.execute('INSERT OR IGNORE INTO enum_options(list_key, value, label_fa, sort) VALUES (?,?,?,?)',
            [e.key, v, label, i++]);
      }
    }
    _cleanupDesalterFactors(db);
    _cleanupCompressorFactors(db);
    _ensurePpiSeries(db);
  });
  _reparseExisting(db);
  _reparseMtoPumps(db);
}

/// ضرایب اولیه‌ی قدیمی دیسالتر (فشار و کلاس‌های جنس عمومی) که در روش بانک دیسالتر به کار نمی‌روند؛
/// فقط ضرایب کالیبره‌نشده حذف می‌شوند.
void _cleanupDesalterFactors(Db db) {
  final set = factorSetOf('DESALTER');
  final groups = desalterFactorGroups.map((g) => "'$g'").join(',');
  final mats = desalterLists['DES_MAT']!.map((e) => "'${e.$1}'").join(',');
  db.execute(
    'DELETE FROM factors WHERE set_code = ? AND calibrated IS NULL AND '
    "(grp NOT IN ($groups) OR (grp = 'MAT' AND option NOT IN ($mats)))",
    [set],
  );
}

/// ضرایب اولیه‌ی قدیمی کمپرسور (روغن‌کاری LUBE، جنس، NACE) که در روش بانک کمپرسور به کار نمی‌روند؛
/// فقط ضرایب کالیبره‌نشده حذف می‌شوند.
void _cleanupCompressorFactors(Db db) {
  final groups = compressorFactorGroups.map((g) => "'$g'").join(',');
  db.execute('DELETE FROM factors WHERE set_code = ? AND calibrated IS NULL AND grp NOT IN ($groups)',
      [factorSetOf('COMPRESSOR')]);
}

/// سری‌های PPI یوروستات (C25.29، C27.11 و شاخص‌های اجزای پکیج‌ها) برای روش شاخص ترکیبی.
/// مقادیر موجود (و ویرایش‌های کاربر) دست نمی‌خورند؛ فقط سال‌های ناموجود اضافه می‌شوند.
void _ensurePpiSeries(Db db) {
  var sort = (db.scalar('SELECT COALESCE(MAX(sort), 0) FROM index_series') as int?) ?? 0;
  for (final s in blsPpiSeeds) {
    if (db.scalar('SELECT 1 FROM index_series WHERE code = ?', [s.code]) == null) {
      db.execute(
        'INSERT INTO index_series(code, name_fa, name_en, kind, grp, unit, base, source, calendar, sort) '
        "VALUES (?,?,?,'level','ppi_world','Jun1984=100','Jun1984=100',?,'gregorian',?)",
        [s.code, s.nameFa, s.nameEn, 'US BLS PCU333912333912 via FRED، میانگین سالانه (دریافت ۱۴۰۵/۰۷/۲۳)', ++sort],
      );
    }
    for (final (y, v, st) in s.values) {
      final p = Period.tryParse('$y')!;
      db.execute(
        'INSERT OR IGNORE INTO index_values(series_code, period_key, year, quarter, month, value, status, source) '
        'VALUES (?,?,?,?,?,?,?,?)',
        [s.code, p.key, p.year, p.quarter, p.month, v, st == 'partial' ? 'forecast' : st,
          st == 'partial' ? 'BLS: میانگین ژانویه تا اوت ۲۰۲۶ (ناقص)' : 'BLS / FRED میانگین سالانه'],
      );
    }
  }
  for (final s in eurostatPpiSeeds) {
    if (db.scalar('SELECT 1 FROM index_series WHERE code = ?', [s.code]) == null) {
      db.execute(
        'INSERT INTO index_series(code, name_fa, name_en, kind, grp, unit, base, source, calendar, sort) '
        "VALUES (?,?,?,'level','ppi_world','2021=100','2021=100',?,'gregorian',?)",
        [s.code, s.nameFa, s.nameEn, 'Eurostat sts_inppd_a, NACE ${s.nace}, EA20 (دریافت ۱۴۰۵/۰۷/۲۳)', ++sort],
      );
    }
    for (final (y, v, st) in s.values) {
      final p = Period.tryParse('$y')!;
      db.execute(
        'INSERT OR IGNORE INTO index_values(series_code, period_key, year, quarter, month, value, status, source) '
        'VALUES (?,?,?,?,?,?,?,?)',
        [s.code, p.key, p.year, p.quarter, p.month, v, st,
          st == 'forecast' ? 'پیش‌بینی: رشد ۲٪ سالانه' : 'Eurostat sts_inppd_a${st == 'imputed' ? ' (imputed)' : ''}'],
      );
    }
  }
}

/// پمپ‌هایی که پیش از این نسخه از MTO وارد شده‌اند (شرح فقط در «ملاحظات»):
/// دبی، هد، فشار رانش، کلاس متریال، استاندارد، … از شرح به فیلدهای قالب پمپ منتقل می‌شود.
void _reparseMtoPumps(Db db) {
  final catId = db.scalar("SELECT id FROM categories WHERE code = 'PUMP'") as int?;
  if (catId == null) return;
  final rows = db.query(
    "SELECT i.id, i.name, i.remarks FROM items i WHERE i.category_id = ? AND i.remarks LIKE '%:%' "
    "AND EXISTS (SELECT 1 FROM price_obs o JOIN documents d ON d.id = o.document_id "
    "            WHERE o.item_id = i.id AND d.doc_type = 'mto') "
    "AND NOT EXISTS (SELECT 1 FROM item_values v WHERE v.item_id = i.id AND v.field_key = 'capacity_m3h')",
    [catId],
  );
  if (rows.isEmpty) return;
  db.transaction(() {
    for (final r in rows) {
      final id = r['id'] as int;
      final d = parseMtoDescription(r['remarks'] as String? ?? '');
      final values = extractPumpSpecs(d.specs, r['name'] as String? ?? '');
      var n = 0;
      for (final e in values.entries) {
        final v = e.value;
        db.execute(
          'INSERT OR IGNORE INTO item_values(item_id, field_key, value_text, value_num) VALUES (?,?,?,?)',
          [id, e.key, v is num ? null : v.toString(), v is num ? v.toDouble() : null],
        );
        n++;
      }
      if (n > 0) {
        db.execute(
          'INSERT INTO audit_log(ts, entity, entity_id, field, new_value, reason) VALUES (?,?,?,?,?,?)',
          [nowIso(), 'item', '$id', 'مشخصات', '$n فیلد', 'استخراج خودکار مشخصات پمپ از شرح MTO'],
        );
      }
    }
  });
}

/// اقلامی که پیش از تعریف قالب‌ها وارد شده‌اند: استخراج فیلدهای ساختاریافته از «شرح کامل MTO»
/// و پاک کردن فیلدهای خام تکراری.
void _reparseExisting(Db db) {
  db.transaction(() {
    for (final p in equipmentProfiles.values) {
      final catId = db.scalar('SELECT id FROM categories WHERE code = ?', [p.code]) as int?;
      if (catId == null) continue;
      final keys = p.fields.map((f) => f.key).toSet();
      // فیلدهای تازه‌ی قالب فقط یک بار (پس از تغییر قالب) برای اقلام قبلی پر می‌شوند؛
      // به این ترتیب مقداری که کاربر عمداً پاک کرده دوباره برنمی‌گردد.
      final sigKey = 'profile_fields_${p.code}';
      final stored = (db.scalar('SELECT value FROM app_meta WHERE key = ?', [sigKey]) as String?)?.split(',').toSet();
      final sig = (keys.toList()..sort()).join(',');
      final newKeys = stored == null ? keys : keys.difference(stored);
      final rows = db.query(
        "SELECT i.id, i.name, v.value_text AS d FROM items i JOIN item_values v ON v.item_id = i.id "
        "WHERE i.category_id = ? AND v.field_key = 'mto_description'",
        [catId],
      );
      for (final r in rows) {
        final id = r['id'] as int;
        final existing = {
          for (final x in db.query(
            'SELECT field_key FROM item_values WHERE item_id = ? AND field_key IN (${List.filled(keys.length, '?').join(',')})',
            [id, ...keys],
          ))
            x['field_key'] as String,
        };
        if (existing.isNotEmpty && newKeys.isEmpty) continue;
        final d = parseMtoDescription(r['d'] as String? ?? '');
        final values = p.extract(d.specs, context: '${r['name']}', scope: d.scope);
        // فقط فیلدهایی که هنوز مقدار ندارند (فیلدهای تازه‌ی قالب)؛ ویرایش‌های کاربر دست نمی‌خورد
        var n = 0;
        for (final e in values.entries) {
          final f = p.field(e.key);
          if (f == null || existing.contains(f.key) || (existing.isNotEmpty && !newKeys.contains(f.key))) continue;
          final v = e.value;
          db.execute(
            'INSERT OR IGNORE INTO item_values(item_id, field_key, value_text, value_num) VALUES (?,?,?,?)',
            [id, f.key, f.type == 'number' ? null : v.toString(), f.type == 'number' ? (v as num).toDouble() : null],
          );
          n++;
        }
        if (n > 0) {
          db.execute(
            'INSERT INTO audit_log(ts, entity, entity_id, field, new_value, reason) VALUES (?,?,?,?,?,?)',
            [nowIso(), 'item', '$id', 'مشخصات', '$n فیلد', 'استخراج خودکار از شرح MTO (قالب رده)'],
          );
        }
        // فیلدهای خام MTO که حالا در قالب رده هستند، تکراری‌اند
        for (final label in d.specs.keys.where(p.maps)) {
          db.execute('DELETE FROM item_values WHERE item_id = ? AND field_key = ?', [id, CatalogRepo.specKey(label)]);
        }
      }
      db.execute('INSERT OR REPLACE INTO app_meta(key, value) VALUES (?, ?)', [sigKey, sig]);
      db.execute(
        "DELETE FROM field_defs WHERE category_id = ? AND group_key = 'mto_specs' AND key NOT IN "
        '(SELECT DISTINCT v.field_key FROM item_values v JOIN items i ON i.id = v.item_id WHERE i.category_id = ?)',
        [catId, catId],
      );
    }
  });
}
