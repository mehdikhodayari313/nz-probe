// قالب پایه‌ی رده‌های تجهیزات غیرپمپ (ظرف، مخزن، مبدل، پکیج‌ها، …).
//
// هر رده فیلدهای شناسایی، قیمت و «شرح کامل MTO» را دارد؛ مشخصات فنی هر رده هنگام ورود MTO
// از خط‌های «کلید: مقدار» شرح ساخته و به قالب اضافه می‌شوند (ظرف: ابعاد، فشار طراحی، جنس، …).
// این تابع در هر بار باز شدن برنامه اجرا می‌شود و تکرار آن بی‌اثر است.

import '../db/db.dart';

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
    }
  });
}
