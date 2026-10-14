// قالب پایه‌ی رده‌های تجهیزات غیرپمپ (ظرف، مخزن، مبدل، پکیج‌ها، …).
//
// هر رده فیلدهای شناسایی، قیمت و «شرح کامل MTO» را دارد؛ مشخصات فنی هر رده هنگام ورود MTO
// از خط‌های «کلید: مقدار» شرح ساخته و به قالب اضافه می‌شوند (ظرف: ابعاد، فشار طراحی، جنس، …).
// این تابع در هر بار باز شدن برنامه اجرا می‌شود و تکرار آن بی‌اثر است.

import '../catalog/profiles.dart';
import '../db/db.dart';
import 'catalog_repo.dart';

/// رده‌هایی که از مرحله‌ی ۲ (ورود MTO) فعال می‌شوند.
const genericCategoryCodes = [
  'COMPRESSOR', 'DESALTER', 'HEATER', 'VESSEL', 'TANK', 'HEX', 'CIP', 'IGF', 'FILTER', 'FLARE', 'DEAERATOR',
  'AIR_DRYER', 'CRANE',
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
      for (final (grp, opt, v, desc) in profileFactorSeeds) {
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
  });
  _reparseExisting(db);
}

/// اقلامی که پیش از تعریف قالب‌ها وارد شده‌اند: استخراج فیلدهای ساختاریافته از «شرح کامل MTO»
/// و پاک کردن فیلدهای خام تکراری.
void _reparseExisting(Db db) {
  db.transaction(() {
    for (final p in equipmentProfiles.values) {
      final catId = db.scalar('SELECT id FROM categories WHERE code = ?', [p.code]) as int?;
      if (catId == null) continue;
      final keys = p.fields.map((f) => f.key).toSet();
      final rows = db.query(
        "SELECT i.id, i.name, v.value_text AS d FROM items i JOIN item_values v ON v.item_id = i.id "
        "WHERE i.category_id = ? AND v.field_key = 'mto_description'",
        [catId],
      );
      for (final r in rows) {
        final id = r['id'] as int;
        final has = db.scalar(
          'SELECT COUNT(*) FROM item_values WHERE item_id = ? AND field_key IN (${List.filled(keys.length, '?').join(',')})',
          [id, ...keys],
        ) as int;
        if (has > 0) continue;
        final d = parseMtoDescription(r['d'] as String? ?? '');
        final values = p.extract(d.specs, context: '${r['name']}', scope: d.scope);
        var n = 0;
        for (final e in values.entries) {
          final f = p.field(e.key);
          if (f == null) continue;
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
      db.execute(
        "DELETE FROM field_defs WHERE category_id = ? AND group_key = 'mto_specs' AND key NOT IN "
        '(SELECT DISTINCT v.field_key FROM item_values v JOIN items i ON i.id = v.item_id WHERE i.category_id = ?)',
        [catId, catId],
      );
    }
  });
}
