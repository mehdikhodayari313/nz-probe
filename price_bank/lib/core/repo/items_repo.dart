// اقلام (تجهیزات)، مقادیر مشخصات و مشاهده‌های قیمت.
//
// همه‌ی تغییرات از این کلاس عبور می‌کنند تا در تاریخچه ثبت شوند. هیچ داده‌ای پاک نمی‌شود؛
// حذف = بایگانی (status = archived) که قابل بازگرداندن است.

import 'dart:convert';

import '../db/db.dart';
import 'audit.dart';
import 'catalog_repo.dart';

class FieldMeta {
  const FieldMeta(this.flag, this.note);

  /// inferred = مقدار استنباطی؛ fx = تبدیل ارز با نرخ بانک؛ null = عادی
  final String? flag;
  final String? note;
}

class PriceObs {
  PriceObs.fromRow(DbRow r)
      : id = r['id'] as int,
        itemId = r['item_id'] as int,
        documentId = r['document_id'] as int?,
        documentTitle = r['doc_title'] as String?,
        documentFxEur = r['doc_fx_eur'] as double?,
        vendorId = r['vendor_id'] as int?,
        vendorName = r['vendor_name'] as String?,
        kind = r['kind'] as String,
        isPrimary = (r['is_primary'] as int) == 1,
        currency = r['currency'] as String?,
        amount = r['amount'] as double?,
        amountText = r['amount_text'] as String?,
        costYear = r['cost_year'] as int?,
        costYearText = r['cost_year_text'] as String?,
        costMonth = r['cost_month'] as int?,
        incoterm = r['incoterm'] as String?,
        priceBasis = r['price_basis'] as String?,
        sourceLocation = r['source_location'] as String?,
        sourceFxRate = r['source_fx_rate'] as double?,
        extra = r['extra_json'] == null ? const {} : (jsonDecode(r['extra_json'] as String) as Map<String, dynamic>),
        notes = r['notes'] as String?,
        documentHidden = (r['doc_hidden'] as int? ?? 0) == 1;

  final int id;
  final int itemId;

  /// سند این قیمت پنهان شده است (در هیچ محاسبه‌ای نیست؛ فقط در «قیمت‌ها و استعلام‌ها» دیده می‌شود)
  final bool documentHidden;
  final int? documentId;
  final String? documentTitle;
  final double? documentFxEur;
  final int? vendorId;
  final String? vendorName;
  final String kind;
  final bool isPrimary;
  final String? currency;
  final double? amount;
  final String? amountText;
  final int? costYear;
  final String? costYearText;
  final int? costMonth;
  final String? incoterm;
  final String? priceBasis;
  final String? sourceLocation;
  final double? sourceFxRate;
  final Map<String, dynamic> extra;
  final String? notes;

  /// قیمت به صورت ورودی موتور: عدد، یا متن منبع اگر عددی نبوده.
  Object? get amountValue => amount ?? amountText;
  Object? get costYearValue => costYear ?? costYearText;

  /// نرخ تسعیر مؤثر: نرخ همین قیمت، وگرنه نرخ تسعیر سند.
  double? get effectiveSourceFx => sourceFxRate ?? documentFxEur;

  String get sourceDisplay {
    final t = documentTitle ?? '';
    final l = sourceLocation ?? '';
    if (t.isEmpty) return l;
    if (l.isEmpty) return t;
    return '$t – $l';
  }
}

class ItemRecord {
  ItemRecord({
    required this.id,
    required this.categoryId,
    required this.projectId,
    required this.projectName,
    required this.tag,
    required this.name,
    required this.quantity,
    required this.include,
    required this.remarks,
    required this.legacyRef,
    required this.status,
    required this.updatedAt,
    required this.values,
    required this.meta,
    required this.observations,
    this.hiddenObservations = const [],
  });

  final int id;
  final int categoryId;
  final int? projectId;
  final String? projectName;
  final String? tag;
  final String name;
  final double? quantity;
  final bool include;
  final String? remarks;
  final String? legacyRef;
  final String status;
  final String updatedAt;
  final Map<String, Object?> values;
  final Map<String, FieldMeta> meta;
  /// قیمت‌های اسناد پیدا (مبنای همه‌ی محاسبات)
  final List<PriceObs> observations;

  /// قیمت‌های اسناد پنهان (فقط برای نمایش)
  final List<PriceObs> hiddenObservations;

  PriceObs? get primary {
    for (final o in observations) {
      if (o.isPrimary) return o;
    }
    return observations.isEmpty ? null : observations.first;
  }

  /// مقدار یکپارچه‌ی هر فیلد (هسته، مشخصات یا قیمت) برای نمایش و جستجو.
  Object? valueOf(String key) {
    switch (key) {
      case 'tag':
        return tag;
      case 'name':
        return name;
      case 'project':
        return projectName;
      case 'quantity':
        return quantity;
      case 'remarks':
        return remarks;
      case 'include_in_totals':
        return include ? 'Y' : 'N';
      case 'v8_row':
        return legacyRef == null ? null : (double.tryParse(legacyRef!) ?? legacyRef);
      case 'cost_year':
        return primary?.costYearValue;
      case 'currency':
        return primary?.currency;
      case 'unit_price':
        return primary?.amountValue;
      case 'price_basis':
        return primary?.priceBasis;
      case 'incoterm':
        return primary?.incoterm;
      case 'source_document':
        return primary?.sourceDisplay;
    }
    return values[key];
  }
}

class ItemsRepo {
  ItemsRepo(this.db, this.audit, this.catalog);
  final Db db;
  final Audit audit;
  final CatalogRepo catalog;

  static const _obsSelect = '''
SELECT o.*, d.title AS doc_title, d.source_fx_eur AS doc_fx_eur, d.hidden AS doc_hidden, v.name AS vendor_name
FROM price_obs o
LEFT JOIN documents d ON d.id = o.document_id
LEFT JOIN vendors v ON v.id = o.vendor_id''';

  /// شرط SQL «قلم دیده می‌شود» برای جدول items با نام مستعار i: دست‌کم یک قیمت از سند پیدا دارد، یا هیچ قیمتی
  /// ندارد و سند مبدأش پنهان نیست. قلمی که همه‌ی قیمت‌هایش از اسناد پنهان است از مشاهده و محاسبات کنار می‌رود.
  static const visibleSql = '(EXISTS (SELECT 1 FROM price_obs vo LEFT JOIN documents vd ON vd.id = vo.document_id '
      'WHERE vo.item_id = i.id AND COALESCE(vd.hidden, 0) = 0) OR (NOT EXISTS (SELECT 1 FROM price_obs vo '
      'WHERE vo.item_id = i.id) AND NOT EXISTS (SELECT 1 FROM documents vd WHERE vd.id = i.source_document_id '
      'AND vd.hidden = 1)))';

  /// همه‌ی اقلام یک رده (با مقادیر و قیمت‌ها) — بارگذاری گروهی و سریع. اقلام اسناد پنهان کنار می‌روند.
  List<ItemRecord> loadCategory(int categoryId, {bool includeArchived = false}) {
    final rows = db.query(
      'SELECT i.*, p.name AS project_name FROM items i LEFT JOIN projects p ON p.id = i.project_id '
      'WHERE i.category_id = ? ${includeArchived ? '' : "AND i.status = 'active'"} AND $visibleSql ORDER BY i.id',
      [categoryId],
    );
    if (rows.isEmpty) return const [];
    final values = <int, Map<String, Object?>>{};
    for (final r in db.query(
        'SELECT v.* FROM item_values v JOIN items i ON i.id = v.item_id WHERE i.category_id = ?', [categoryId])) {
      (values[r['item_id'] as int] ??= {})[r['field_key'] as String] = r['value_num'] ?? r['value_text'];
    }
    final meta = <int, Map<String, FieldMeta>>{};
    for (final r in db.query(
        'SELECT m.* FROM field_meta m JOIN items i ON i.id = m.item_id WHERE i.category_id = ?', [categoryId])) {
      (meta[r['item_id'] as int] ??= {})[r['field_key'] as String] =
          FieldMeta(r['flag'] as String?, r['note'] as String?);
    }
    final obs = <int, List<PriceObs>>{};
    for (final r in db.query(
        '$_obsSelect JOIN items i ON i.id = o.item_id WHERE i.category_id = ? ORDER BY o.is_primary DESC, o.id',
        [categoryId])) {
      final o = PriceObs.fromRow(r);
      (obs[o.itemId] ??= []).add(o);
    }
    return [for (final r in rows) _build(r, values[r['id']] ?? {}, meta[r['id']] ?? {}, obs[r['id']] ?? [])];
  }

  ItemRecord? get(int id) {
    final r = db.queryOne(
        'SELECT i.*, p.name AS project_name FROM items i LEFT JOIN projects p ON p.id = i.project_id WHERE i.id = ?',
        [id]);
    if (r == null) return null;
    final values = {
      for (final v in db.query('SELECT * FROM item_values WHERE item_id = ?', [id]))
        v['field_key'] as String: v['value_num'] ?? v['value_text'],
    };
    final meta = {
      for (final m in db.query('SELECT * FROM field_meta WHERE item_id = ?', [id]))
        m['field_key'] as String: FieldMeta(m['flag'] as String?, m['note'] as String?),
    };
    final obs = [
      for (final o in db.query('$_obsSelect WHERE o.item_id = ? ORDER BY o.is_primary DESC, o.id', [id]))
        PriceObs.fromRow(o),
    ];
    return _build(r, values, meta, obs);
  }

  ItemRecord _build(DbRow r, Map<String, Object?> values, Map<String, FieldMeta> meta, List<PriceObs> all) {
    final obs = [for (final o in all) if (!o.documentHidden) o];
    return ItemRecord(
        id: r['id'] as int,
        categoryId: r['category_id'] as int,
        projectId: r['project_id'] as int?,
        projectName: r['project_name'] as String?,
        tag: r['tag'] as String?,
        name: r['name'] as String,
        quantity: r['quantity'] as double?,
        include: (r['include_in_totals'] as int) == 1,
        remarks: r['remarks'] as String?,
        legacyRef: r['legacy_ref'] as String?,
        status: r['status'] as String,
        updatedAt: r['updated_at'] as String,
        values: values,
        meta: meta,
        observations: obs,
        hiddenObservations: obs.length == all.length ? const [] : [for (final o in all) if (o.documentHidden) o],
      );
  }

  int count(int categoryId) =>
      db.scalar("SELECT COUNT(*) FROM items i WHERE i.category_id = ? AND i.status = 'active' AND $visibleSql",
          [categoryId]) as int;

  // ---------------------------------------------------------------------------
  // ایجاد و ویرایش

  /// ساخت قلم جدید. [values] شامل همه‌ی فیلدهای قالب (هسته، مشخصات، قیمت) است.
  int create({
    required int categoryId,
    required Map<String, Object?> values,
    int? projectId,
    int? documentId,
    int? sourceDocumentId,
    String? reason,
    Map<String, FieldMeta> meta = const {},
    String? batch,
  }) {
    return db.transaction(() {
      final now = nowIso();
      final uid = audit.userId;
      final id = db.insert(
        'INSERT INTO items(category_id, project_id, tag, name, quantity, include_in_totals, remarks, legacy_ref, '
        'source_document_id, created_at, created_by, updated_at, updated_by) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          categoryId, projectId, _txt(values['tag']), _txt(values['name']) ?? '(بدون نام)', _num(values['quantity']),
          _txt(values['include_in_totals']) == 'N' ? 0 : 1, _txt(values['remarks']), _txt(values['v8_row']),
          sourceDocumentId ?? documentId, now, uid, now, uid,
        ],
      );
      final fields = catalog.fields(categoryId);
      for (final f in fields.where((f) => f.storage == FieldStorage.spec)) {
        final v = values[f.key];
        if (v == null || (v is String && v.isEmpty)) continue;
        _putValue(id, f, v);
      }
      // قیمت اولیه
      final hasPrice = ['unit_price', 'currency', 'cost_year', 'incoterm', 'price_basis']
          .any((k) => values[k] != null && values[k].toString().isNotEmpty);
      if (hasPrice || documentId != null) {
        _insertObs(id, {
          'document_id': documentId,
          'kind': values['_price_kind'] ?? 'estimate',
          'is_primary': 1,
          'currency': _txt(values['currency']),
          'amount': values['unit_price'],
          'cost_year': values['cost_year'],
          'incoterm': _txt(values['incoterm']),
          'price_basis': _txt(values['price_basis']),
          'source_location': _txt(values['_source_location']),
          'source_fx_rate': _num(values['_source_fx_rate']),
        });
      }
      meta.forEach((k, m) => setMeta(id, k, m, log: false));
      audit.log(entity: 'item', entityId: id, field: '*', newValue: 'ایجاد', reason: reason, batch: batch);
      return id;
    });
  }

  void _putValue(int itemId, FieldDef f, Object v) {
    double? n;
    String? t;
    if (f.type == FieldType.number) {
      n = _num(v);
      if (n == null) t = v.toString();
    } else {
      t = _txt(v);
    }
    db.execute(
      'INSERT INTO item_values(item_id, field_key, value_text, value_num) VALUES (?,?,?,?) '
      'ON CONFLICT(item_id, field_key) DO UPDATE SET value_text = excluded.value_text, value_num = excluded.value_num',
      [itemId, f.key, t, n],
    );
  }

  int _insertObs(int itemId, Map<String, Object?> o) {
    final amount = o['amount'];
    final year = o['cost_year'];
    final now = nowIso();
    return db.insert(
      'INSERT INTO price_obs(item_id, document_id, vendor_id, kind, is_primary, currency, amount, amount_text, '
      'cost_year, cost_year_text, cost_month, incoterm, price_basis, source_location, source_fx_rate, extra_json, '
      'notes, created_at, created_by, updated_at, updated_by) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        itemId, o['document_id'], o['vendor_id'], o['kind'] ?? 'estimate', o['is_primary'] ?? 0, o['currency'],
        _num(amount), _num(amount) == null ? _txt(amount) : null,
        _num(year)?.toInt(), _num(year) == null ? _txt(year) : null, o['cost_month'],
        o['incoterm'], o['price_basis'], o['source_location'], o['source_fx_rate'],
        o['extra'] == null ? null : jsonEncode(o['extra']), o['notes'], now, audit.userId, now, audit.userId,
      ],
    );
  }

  /// افزودن یک مشاهده‌ی قیمت (استعلام، برآورد، …) به قلم. اگر [primary] باشد، قیمت اصلی محاسبه می‌شود.
  int addObservation(
    int itemId, {
    int? documentId,
    int? vendorId,
    String kind = 'estimate',
    bool primary = false,
    String? currency,
    Object? amount,
    Object? costYear,
    String? costYearText,
    int? costMonth,
    String? sourceLocation,
    double? sourceFxRate,
    String? notes,
  }) {
    return db.transaction(() {
      if (primary) db.execute('UPDATE price_obs SET is_primary = 0 WHERE item_id = ?', [itemId]);
      return _insertObs(itemId, {
        'document_id': documentId,
        'vendor_id': vendorId,
        'kind': kind,
        'is_primary': primary ? 1 : 0,
        'currency': currency,
        'amount': amount,
        'cost_year': costYear ?? costYearText,
        'cost_month': costMonth,
        'source_location': sourceLocation,
        'source_fx_rate': sourceFxRate,
        'notes': (notes == null || notes.isEmpty) ? null : notes,
      });
    });
  }

  /// انتخاب یک مشاهده‌ی قیمت به عنوان قیمت اصلی قلم (مبنای تعدیل).
  void setPrimary(int itemId, int obsId, {String? reason}) {
    final old = db.scalar('SELECT id FROM price_obs WHERE item_id = ? AND is_primary = 1', [itemId]);
    if (old == obsId) return;
    db.transaction(() {
      db.execute('UPDATE price_obs SET is_primary = CASE WHEN id = ? THEN 1 ELSE 0 END WHERE item_id = ?', [obsId, itemId]);
      audit.log(entity: 'item', entityId: itemId, field: 'قیمت اصلی', oldValue: old, newValue: obsId, reason: reason);
    });
  }

  /// ویرایش چند فیلد یک قلم؛ فقط فیلدهای تغییرکرده ذخیره و در تاریخچه ثبت می‌شوند.
  /// برمی‌گرداند: تعداد فیلدهای تغییرکرده.
  int update(int itemId, Map<String, Object?> changes, {String? reason}) {
    final item = get(itemId);
    if (item == null) throw StateError('قلم $itemId پیدا نشد');
    final fields = {for (final f in catalog.fields(item.categoryId)) f.key: f};
    final batch = Audit.newBatch();
    var changed = 0;

    db.transaction(() {
      final obs = item.primary;
      for (final e in changes.entries) {
        final key = e.key;
        final newV = _normalize(e.value);
        final oldV = _normalize(item.valueOf(key));
        if (_same(oldV, newV)) continue;
        changed++;
        final f = fields[key];
        switch (key) {
          case 'tag':
          case 'name':
          case 'remarks':
            db.execute('UPDATE items SET $key = ? WHERE id = ?', [key == 'name' ? (newV ?? '') : _txt(newV), itemId]);
          case 'quantity':
            db.execute('UPDATE items SET quantity = ? WHERE id = ?', [_num(newV), itemId]);
          case 'include_in_totals':
            db.execute('UPDATE items SET include_in_totals = ? WHERE id = ?', [_txt(newV) == 'N' ? 0 : 1, itemId]);
          case 'project':
            final pid = newV == null ? null : _projectId(newV.toString());
            db.execute('UPDATE items SET project_id = ? WHERE id = ?', [pid, itemId]);
          case 'cost_year':
          case 'currency':
          case 'unit_price':
          case 'incoterm':
          case 'price_basis':
            final oid = obs?.id ?? _insertObs(itemId, {'is_primary': 1});
            final col = switch (key) {
              'cost_year' => 'cost_year',
              'currency' => 'currency',
              'unit_price' => 'amount',
              'incoterm' => 'incoterm',
              _ => 'price_basis',
            };
            if (col == 'amount') {
              db.execute('UPDATE price_obs SET amount = ?, amount_text = ? WHERE id = ?',
                  [_num(newV), _num(newV) == null ? _txt(newV) : null, oid]);
            } else if (col == 'cost_year') {
              db.execute('UPDATE price_obs SET cost_year = ?, cost_year_text = ? WHERE id = ?',
                  [_num(newV)?.toInt(), _num(newV) == null ? _txt(newV) : null, oid]);
            } else {
              db.execute('UPDATE price_obs SET $col = ? WHERE id = ?', [_txt(newV), oid]);
            }
            db.execute('UPDATE price_obs SET updated_at = ?, updated_by = ? WHERE id = ?', [nowIso(), audit.userId, oid]);
          default:
            if (f == null || f.storage != FieldStorage.spec) {
              changed--;
              continue;
            }
            if (newV == null) {
              db.execute('DELETE FROM item_values WHERE item_id = ? AND field_key = ?', [itemId, key]);
            } else {
              _putValue(itemId, f, newV);
            }
        }
        // مقدار جدید کاربر دیگر «استنباطی» نیست
        db.execute("DELETE FROM field_meta WHERE item_id = ? AND field_key = ? AND flag = 'inferred'", [itemId, key]);
        audit.log(
            entity: 'item', entityId: itemId, field: key, oldValue: oldV, newValue: newV, reason: reason, batch: batch);
      }
      if (changed > 0) {
        db.execute('UPDATE items SET updated_at = ?, updated_by = ? WHERE id = ?', [nowIso(), audit.userId, itemId]);
      }
    });
    return changed;
  }

  void setMeta(int itemId, String key, FieldMeta m, {bool log = true}) {
    db.execute(
      'INSERT INTO field_meta(item_id, field_key, flag, note) VALUES (?,?,?,?) '
      'ON CONFLICT(item_id, field_key) DO UPDATE SET flag = excluded.flag, note = excluded.note',
      [itemId, key, m.flag, m.note],
    );
    if (log) audit.log(entity: 'item', entityId: itemId, field: '$key (یادداشت)', newValue: m.note);
  }

  void archive(int itemId, {required bool archived, String? reason}) {
    db.execute('UPDATE items SET status = ?, updated_at = ?, updated_by = ? WHERE id = ?',
        [archived ? 'archived' : 'active', nowIso(), audit.userId, itemId]);
    audit.log(
        entity: 'item', entityId: itemId, field: 'status', newValue: archived ? 'بایگانی' : 'فعال', reason: reason);
  }

  int? _projectId(String name) {
    if (name.trim().isEmpty) return null;
    final id = db.scalar('SELECT id FROM projects WHERE name = ?', [name]) as int?;
    if (id != null) return id;
    return db.insert('INSERT INTO projects(name, created_by, updated_by) VALUES (?,?,?)',
        [name, audit.userId, audit.userId]);
  }

  // ---------------------------------------------------------------------------

  static Object? _normalize(Object? v) {
    if (v == null) return null;
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }
    if (v is num) return v.toDouble();
    return v;
  }

  static bool _same(Object? a, Object? b) {
    if (a is double && b is double) return (a - b).abs() <= 1e-12 * (a.abs() + b.abs() + 1);
    return a?.toString() == b?.toString();
  }

  static String? _txt(Object? v) {
    if (v == null) return null;
    if (v is double && v == v.roundToDouble() && v.abs() < 1e15) return v.toStringAsFixed(0);
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static double? _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '').trim());
    return null;
  }
}
