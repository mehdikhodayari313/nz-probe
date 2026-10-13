import '../db/db.dart';

class Discipline {
  Discipline.fromRow(DbRow r)
      : code = r['code'] as String,
        nameFa = r['name_fa'] as String,
        nameEn = r['name_en'] as String?,
        enabled = (r['enabled'] as int) == 1;
  final String code;
  final String nameFa;
  final String? nameEn;
  final bool enabled;
}

class Category {
  Category.fromRow(DbRow r)
      : id = r['id'] as int,
        code = r['code'] as String,
        disciplineCode = r['discipline_code'] as String,
        parentId = r['parent_id'] as int?,
        nameFa = r['name_fa'] as String,
        nameEn = r['name_en'] as String?,
        descriptionFa = r['description_fa'] as String?,
        enabled = (r['enabled'] as int) == 1,
        escalationMethod = r['escalation_method'] as String;
  final int id;
  final String code;
  final String disciplineCode;
  final int? parentId;
  final String nameFa;
  final String? nameEn;
  final String? descriptionFa;
  final bool enabled;
  final String escalationMethod;
}

enum FieldStorage { core, spec, price, calc }

enum FieldType { text, number, enumeration }

class FieldDef {
  FieldDef.fromRow(DbRow r)
      : key = r['key'] as String,
        labelFa = r['label_fa'] as String,
        labelEn = r['label_en'] as String?,
        groupKey = r['group_key'] as String? ?? '',
        groupFa = r['group_fa'] as String? ?? '',
        storage = FieldStorage.values.byName(r['storage'] as String),
        type = switch (r['data_type'] as String) {
          'number' => FieldType.number,
          'enum' => FieldType.enumeration,
          _ => FieldType.text,
        },
        listKey = r['list_key'] as String?,
        unit = r['unit'] as String?,
        helpFa = r['help_fa'] as String?,
        sourceRef = r['source_ref'] as String?,
        sort = r['sort'] as int;

  final String key;
  final String labelFa;
  final String? labelEn;
  final String groupKey;
  final String groupFa;
  final FieldStorage storage;
  final FieldType type;
  final String? listKey;
  final String? unit;
  final String? helpFa;
  final String? sourceRef;
  final int sort;

  bool get editable => storage != FieldStorage.calc;
}

class EnumOption {
  const EnumOption(this.value, this.labelFa, this.description);
  final String value;
  final String? labelFa;
  final String? description;
}

class CatalogRepo {
  CatalogRepo(this.db);
  final Db db;

  final Map<String, List<EnumOption>> _enumCache = {};
  final Map<int, List<FieldDef>> _fieldCache = {};

  void invalidate() {
    _enumCache.clear();
    _fieldCache.clear();
  }

  List<Discipline> disciplines() =>
      [for (final r in db.query('SELECT * FROM disciplines ORDER BY sort, code')) Discipline.fromRow(r)];

  List<Category> categories() =>
      [for (final r in db.query('SELECT * FROM categories ORDER BY discipline_code, sort, id')) Category.fromRow(r)];

  Category? categoryByCode(String code) {
    final r = db.queryOne('SELECT * FROM categories WHERE code = ?', [code]);
    return r == null ? null : Category.fromRow(r);
  }

  List<FieldDef> fields(int categoryId) => _fieldCache[categoryId] ??= [
        for (final r in db.query('SELECT * FROM field_defs WHERE category_id = ? ORDER BY sort, id', [categoryId]))
          FieldDef.fromRow(r),
      ];

  List<EnumOption> options(String listKey) => _enumCache[listKey] ??= [
        for (final r in db.query(
            'SELECT value, label_fa, description FROM enum_options WHERE list_key = ? ORDER BY sort, value', [listKey]))
          EnumOption(r['value'] as String, r['label_fa'] as String?, r['description'] as String?),
      ];

  /// افزودن گزینه‌ی جدید به یک فهرست (مثلاً سرویس جدید یا کلاس متریال جدید).
  void addOption(String listKey, String value, {String? labelFa}) {
    final sort = (db.scalar('SELECT COALESCE(MAX(sort),0)+1 FROM enum_options WHERE list_key = ?', [listKey]) as int?) ?? 0;
    db.execute('INSERT OR IGNORE INTO enum_options(list_key, value, label_fa, sort) VALUES (?,?,?,?)',
        [listKey, value, labelFa, sort]);
    _enumCache.remove(listKey);
  }
}
