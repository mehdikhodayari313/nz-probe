// پر کردن دیتابیس خالی با داده‌های پایه (فقط یک بار، روی دیتابیس تازه).
// ورودی: محتوای فایل‌های assets/seed/*.json که قبلاً decode شده‌اند.

import '../calc/series.dart';
import '../db/db.dart';

class SeedData {
  const SeedData({
    required this.lists,
    required this.pumpTemplate,
    required this.factors,
    required this.indices,
    required this.settings,
  });
  final Map<String, dynamic> lists;
  final Map<String, dynamic> pumpTemplate;
  final Map<String, dynamic> factors;
  final Map<String, dynamic> indices;
  final Map<String, dynamic> settings;
}

const _disciplines = [
  ('MECH', 'مکانیک', 'Mechanical', 1),
  ('PIPE', 'پایپینگ', 'Piping', 2),
  ('ELEC', 'برق', 'Electrical', 3),
  ('INST', 'ابزار دقیق', 'Instrumentation', 4),
];

// (کد، رشته، والد، نام فارسی، نام انگلیسی، فعال، توضیح)
const _categories = [
  ('MECH_ROT', 'MECH', null, 'تجهیزات دوار', 'Rotating Equipment', true, null),
  ('PUMP', 'MECH', 'MECH_ROT', 'پمپ', 'Pumps', true,
      'پمپ‌های فرآیندی، آب، تزریق، درین، جانبی و آتش‌نشانی — ساختار ۵۹ فیلدی مطابق بانک قیمت v8'),
  ('COMPRESSOR', 'MECH', 'MECH_ROT', 'کمپرسور و پکیج هوا', 'Compressors', false, null),
  ('MECH_STAT', 'MECH', null, 'تجهیزات ثابت', 'Static Equipment', true, null),
  ('DESALTER', 'MECH', 'MECH_STAT', 'پکیج نمک‌زدایی (دیسالتر)', 'Desalting Packages', false, null),
  ('HEATER', 'MECH', 'MECH_STAT', 'گرم‌کن غیرمستقیم', 'Indirect Fired Heaters', false, null),
  ('VESSEL', 'MECH', 'MECH_STAT', 'ظرف تحت فشار', 'Pressure Vessels', false, null),
  ('TANK', 'MECH', 'MECH_STAT', 'مخزن', 'Tanks', false, null),
  ('HEX', 'MECH', 'MECH_STAT', 'مبدل حرارتی', 'Heat Exchangers', false, null),
  ('MECH_PKG', 'MECH', null, 'پکیج‌ها', 'Packages', true, null),
  ('CIP', 'MECH', 'MECH_PKG', 'پکیج تزریق مواد شیمیایی', 'Chemical Injection Packages', false, null),
  ('IGF', 'MECH', 'MECH_PKG', 'پکیج IGF', 'IGF Packages', false, null),
  ('FILTER', 'MECH', 'MECH_PKG', 'فیلتر', 'Filters', false, null),
  ('FLARE', 'MECH', 'MECH_PKG', 'فلر، استک و Burn Pit', 'Flare / Stack / Burn Pit', false, null),
  ('DEAERATOR', 'MECH', 'MECH_PKG', 'دی‌اریتور', 'Deaerators', false, null),
  ('AIR_DRYER', 'MECH', 'MECH_PKG', 'خشک‌کن هوا', 'Air Dryers', false, null),
  ('CRANE', 'MECH', 'MECH_PKG', 'جرثقیل سقفی', 'Overhead Cranes', false, null),
  ('LAB', 'MECH', 'MECH_PKG', 'تجهیزات آزمایشگاه', 'Laboratory Equipment', false, null),
  ('PIPE_BULK', 'PIPE', null, 'لوله و اتصالات (بالک)', 'Pipe & Fittings', false, null),
  ('VALVE', 'PIPE', null, 'شیرآلات', 'Valves', false, null),
  ('ELEC_EQ', 'ELEC', null, 'تجهیزات برق', 'Electrical Equipment', false, null),
  ('INST_EQ', 'INST', null, 'تجهیزات ابزار دقیق', 'Instrumentation', false, null),
];

const _ynsFa = {'Y': 'بله', 'N': 'خیر', 'Not stated': 'نامشخص'};

void seedDatabase(Db db, SeedData seed) {
  if ((db.scalar('SELECT COUNT(*) FROM users') as int) > 0) return; // قبلاً پر شده

  db.transaction(() {
    db.execute("INSERT INTO app_meta(key, value) VALUES('seeded_at', ?)", [nowIso()]);

    // کاربر پیش‌فرض
    final admin = db.insert(
        "INSERT INTO users(username, display_name, role) VALUES('admin', 'مدیر سیستم', 'admin')");

    for (final (code, fa, en, sort) in _disciplines) {
      db.execute('INSERT INTO disciplines(code, name_fa, name_en, sort) VALUES (?,?,?,?)', [code, fa, en, sort]);
      db.execute(
          'INSERT INTO user_scopes(user_id, discipline_code, can_view, can_edit, can_approve) VALUES (?,?,1,1,1)',
          [admin, code]);
    }

    final catIds = <String, int>{};
    var sort = 0;
    for (final (code, disc, parent, fa, en, enabled, desc) in _categories) {
      catIds[code] = db.insert(
        'INSERT INTO categories(code, discipline_code, parent_id, name_fa, name_en, description_fa, sort, enabled) '
        'VALUES (?,?,?,?,?,?,?,?)',
        [code, disc, parent == null ? null : catIds[parent], fa, en, desc, sort++, enabled ? 1 : 0],
      );
    }

    // قالب فیلدهای پمپ
    final pumpId = catIds['PUMP']!;
    for (final f in (seed.pumpTemplate['fields'] as List).cast<Map<String, dynamic>>()) {
      db.execute(
        'INSERT INTO field_defs(category_id, key, label_fa, label_en, group_key, group_fa, storage, data_type, '
        'list_key, unit, help_fa, source_ref, sort) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          pumpId, f['key'], f['label_fa'], f['label_en'], f['group'], f['group_fa'], f['storage'], f['type'],
          f['list'], f['unit'], f['help_fa'], 'v8 ستون ${f['v8_column']}', f['sort'],
        ],
      );
    }

    // فهرست‌ها
    final lists = (seed.lists['lists'] as Map<String, dynamic>);
    final subcats = (seed.lists['subcategories'] as Map<String, dynamic>);
    final refs = (seed.lists['reference_tables'] as Map<String, dynamic>);
    final matDesc = {for (final r in (refs['material_classes'] as List)) (r as List)[0]: '${r[1]} / ${r[2]} — ${r[4]}'};
    final typeDesc = {for (final r in (refs['api610_types'] as List)) (r as List)[0]: '${r[1]} — ${r[2]}'};
    final incoDesc = {for (final r in (refs['incoterms'] as List)) (r as List)[0]: '${r[2]}'};
    lists.forEach((key, values) {
      var i = 0;
      for (final v in (values as List).map((e) => e.toString())) {
        String? label;
        String? desc;
        if (key == 'YN' || key == 'YNS') label = _ynsFa[v];
        if (key == 'SubCat' && subcats[v] != null) {
          final m = subcats[v] as Map<String, dynamic>;
          label = m['name_en'] as String?;
          desc = m['desc_fa'] as String?;
        }
        if (key == 'MAT') desc = matDesc[v]?.toString();
        if (key == 'API610') desc = typeDesc[v]?.toString();
        if (key == 'Incoterm') desc = incoDesc[v]?.toString();
        db.execute('INSERT OR IGNORE INTO enum_options(list_key, value, label_fa, description, sort) VALUES (?,?,?,?,?)',
            [key, v, label, desc, i++]);
      }
    });

    // ضرایب
    final setCode = seed.factors['set'] as String;
    for (final f in (seed.factors['factors'] as List).cast<Map<String, dynamic>>()) {
      db.execute(
        'INSERT INTO factors(set_code, grp, option, provisional, calibrated, description) VALUES (?,?,?,?,?,?)',
        [setCode, f['group'], f['option'], (f['provisional'] as num).toDouble(), (f['calibrated'] as num?)?.toDouble(),
          f['description']],
      );
    }

    // شاخص‌ها
    var sSort = 0;
    for (final s in (seed.indices['series'] as List).cast<Map<String, dynamic>>()) {
      db.execute(
        'INSERT INTO index_series(code, name_fa, name_en, kind, grp, unit, base, source, calendar, sort) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [s['code'], s['name_fa'], s['name_en'], s['kind'], s['group'], s['unit'], s['base'], s['source'],
          s['calendar'], sSort++],
      );
    }
    for (final v in (seed.indices['values'] as List).cast<Map<String, dynamic>>()) {
      final p = Period.tryParse(v['period'] as String);
      if (p == null) continue;
      db.execute(
        'INSERT OR REPLACE INTO index_values(series_code, period_key, year, quarter, month, value, status, source) '
        'VALUES (?,?,?,?,?,?,?,?)',
        [v['series'], p.key, p.year, p.quarter, p.month, (v['value'] as num).toDouble(), v['status'], v['source']],
      );
    }

    // تنظیمات و انواع نرخ ارز
    var fSort = 0;
    for (final t in (seed.settings['fx_rate_types'] as List).cast<Map<String, dynamic>>()) {
      db.execute('INSERT INTO fx_rate_types(code, name_fa, sort) VALUES (?,?,?)', [t['code'], t['name_fa'], fSort++]);
    }
    seed.settings.forEach((k, v) {
      if (v is List || v is Map) return;
      db.execute('INSERT OR REPLACE INTO settings(key, value) VALUES (?, ?)', [k, v.toString()]);
    });
  });
}
