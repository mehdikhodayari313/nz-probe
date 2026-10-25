// پروژه‌ها، اسناد منبع و فروشندگان.
// ویرایش یک سند (مثلاً نرخ تسعیر منبع) بلافاصله روی محاسبه‌ی همه‌ی اقلام آن سند اثر می‌گذارد،
// چون محاسبات همیشه از داده‌ی زنده خوانده می‌شوند.

import '../db/db.dart';
import 'audit.dart';

class Project {
  Project.fromRow(DbRow r)
      : id = r['id'] as int,
        name = r['name'] as String,
        nameFa = r['name_fa'] as String?,
        capacityBpd = r['capacity_bpd'] as double?,
        location = r['location'] as String?,
        notes = r['notes'] as String?,
        itemCount = (r['item_count'] as int?) ?? 0;
  final int id;
  final String name;
  final String? nameFa;
  final double? capacityBpd;
  final String? location;
  final String? notes;
  final int itemCount;
}

class SourceDocument {
  SourceDocument.fromRow(DbRow r)
      : id = r['id'] as int,
        projectId = r['project_id'] as int?,
        projectName = r['project_name'] as String?,
        title = r['title'] as String,
        docRef = r['doc_ref'] as String?,
        revision = r['revision'] as String? ?? '',
        docType = r['doc_type'] as String?,
        issueYear = r['issue_year'] as int?,
        issueMonth = r['issue_month'] as int?,
        sourceFxEur = r['source_fx_eur'] as double?,
        sourceFxUsd = r['source_fx_usd'] as double?,
        fxRateType = r['fx_rate_type'] as String?,
        consultant = r['consultant'] as String?,
        notes = r['notes'] as String?,
        priceCount = (r['price_count'] as int?) ?? 0;
  final int id;
  final int? projectId;
  final String? projectName;
  final String title;
  final String? docRef;
  final String revision;
  final String? docType;
  final int? issueYear;
  final int? issueMonth;
  final double? sourceFxEur;
  final double? sourceFxUsd;
  final String? fxRateType;
  final String? consultant;
  final String? notes;
  final int priceCount;
}

class DocsRepo {
  DocsRepo(this.db, this.audit);
  final Db db;
  final Audit audit;

  List<Project> projects() => [
        for (final r in db.query('SELECT p.*, (SELECT COUNT(*) FROM items i WHERE i.project_id = p.id '
            "AND i.status = 'active') AS item_count FROM projects p ORDER BY p.name"))
          Project.fromRow(r),
      ];

  int ensureProject(String name) {
    final id = db.scalar('SELECT id FROM projects WHERE name = ?', [name]) as int?;
    if (id != null) return id;
    final nid = db.insert('INSERT INTO projects(name, created_by, updated_by) VALUES (?,?,?)',
        [name, audit.userId, audit.userId]);
    audit.log(entity: 'project', entityId: nid, field: '*', newValue: name);
    return nid;
  }

  List<SourceDocument> documents({int? projectId}) => [
        for (final r in db.query(
          'SELECT d.*, p.name AS project_name, (SELECT COUNT(*) FROM price_obs o WHERE o.document_id = d.id) AS price_count '
          'FROM documents d LEFT JOIN projects p ON p.id = d.project_id '
          '${projectId == null ? '' : 'WHERE d.project_id = ?'} ORDER BY p.name, d.title',
          [if (projectId != null) projectId],
        ))
          SourceDocument.fromRow(r),
      ];

  /// عنوان سند برای تشخیص یکسانی: «PEP-Rev.140205 Gachsaran 4.xlsx» ≡ «PEP-Rev 140205 Gachsaran 4»
  static String normTitle(String t) => t
      .toLowerCase()
      .replaceAll(RegExp(r'\.(xlsx|xlsm|xls|csv|pdf|docx?)\b'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), ' ')
      .trim();

  /// دو عنوان یک سندند؟ برابر پس از یکسان‌سازی، یا یکی ادامه‌ی دیگری با دست‌کم سه واژه و یک عدد
  /// («PC-ME 14040105 Pazanan2» و «PC-ME 14040105 Pazanan2 Reconstruction.xlsx»)
  static bool sameTitle(String a, String b) {
    final x = normTitle(a), y = normTitle(b);
    if (x.isEmpty || y.isEmpty) return false;
    if (x == y) return true;
    final (s, l) = x.length <= y.length ? (x, y) : (y, x);
    return l.startsWith('$s ') && s.split(' ').length >= 3 && RegExp(r'\d{3,}').hasMatch(s);
  }

  /// سند کمکی (قیمت‌های بازنگری قبلی) جزء سند اصلی است و جدا شمرده نمی‌شود
  static bool isAuxiliary(SourceDocument d) => d.docType == 'mto_previous';

  /// تعداد اسناد منبع واقعی: بدون سند کمکی و بدون تکرار یک سند در چند پروژه
  int sourceDocumentCount() {
    final seen = <String>[];
    for (final d in documents()) {
      if (isAuxiliary(d)) continue;
      if (!seen.any((t) => sameTitle(t, d.title))) seen.add(d.title);
    }
    return seen.length;
  }

  int ensureDocument({int? projectId, required String title, String revision = '', String? docType}) {
    final id = db.scalar(
      'SELECT id FROM documents WHERE project_id IS ? AND title = ? AND revision = ?',
      [projectId, title, revision],
    ) as int?;
    if (id != null) return id;
    // همان سند با عنوان کمی متفاوت (پسوند فایل، نقطه/خط تیره، عنوان کوتاه‌تر)
    for (final r in db.query('SELECT id, title, revision, doc_type FROM documents WHERE project_id IS ?', [projectId])) {
      if ((r['doc_type'] == 'mto_previous') != (docType == 'mto_previous')) continue;
      final rv = r['revision'] as String? ?? '';
      if ((rv == revision || rv.isEmpty || revision.isEmpty) && sameTitle(r['title'] as String, title)) return r['id'] as int;
    }
    final nid = db.insert(
      'INSERT INTO documents(project_id, title, revision, doc_type, created_by, updated_by) VALUES (?,?,?,?,?,?)',
      [projectId, title, revision, docType, audit.userId, audit.userId],
    );
    audit.log(entity: 'document', entityId: nid, field: '*', newValue: title);
    return nid;
  }

  static const documentFields = {
    'title': 'عنوان',
    'doc_ref': 'شماره‌ی سند',
    'revision': 'بازنگری',
    'doc_type': 'نوع سند',
    'issue_year': 'سال صدور',
    'issue_month': 'ماه صدور',
    'source_fx_eur': 'نرخ تسعیر منبع (ریال/یورو)',
    'source_fx_usd': 'نرخ تسعیر منبع (ریال/دلار)',
    'fx_rate_type': 'نوع نرخ ارز سند',
    'consultant': 'مشاور / تهیه‌کننده',
    'notes': 'یادداشت',
  };

  static const projectFields = {
    'name': 'نام پروژه',
    'name_fa': 'نام فارسی',
    'capacity_bpd': 'ظرفیت (بشکه در روز)',
    'location': 'محل',
    'notes': 'یادداشت',
  };

  void updateDocument(int id, Map<String, Object?> changes, {String? reason}) =>
      _update('documents', 'document', id, changes, documentFields.keys.toSet(), reason);

  void updateProject(int id, Map<String, Object?> changes, {String? reason}) =>
      _update('projects', 'project', id, changes, projectFields.keys.toSet(), reason);

  void _update(String table, String entity, int id, Map<String, Object?> changes, Set<String> allowed, String? reason) {
    final old = db.queryOne('SELECT * FROM $table WHERE id = ?', [id]);
    if (old == null) return;
    final batch = Audit.newBatch();
    db.transaction(() {
      var n = 0;
      for (final e in changes.entries) {
        if (!allowed.contains(e.key)) continue;
        final nv = (e.value is String && (e.value! as String).trim().isEmpty) ? null : e.value;
        if (old[e.key]?.toString() == nv?.toString()) continue;
        db.execute('UPDATE $table SET ${e.key} = ? WHERE id = ?', [nv, id]);
        audit.log(entity: entity, entityId: id, field: e.key, oldValue: old[e.key], newValue: nv, reason: reason,
            batch: batch);
        n++;
      }
      if (n > 0) {
        db.execute('UPDATE $table SET updated_at = ?, updated_by = ? WHERE id = ?', [nowIso(), audit.userId, id]);
      }
    });
  }

  /// اصلاح گروهی سال قیمت همه‌ی قیمت‌های یک سند (وقتی بعداً معلوم شود سال اشتباه بوده).
  int setCostYearForDocument(int documentId, int year, {int? month, String? reason}) {
    final rows = db.query('SELECT id, item_id, cost_year, cost_year_text FROM price_obs WHERE document_id = ?', [documentId]);
    final batch = Audit.newBatch();
    db.transaction(() {
      for (final r in rows) {
        db.execute(
          'UPDATE price_obs SET cost_year = ?, cost_year_text = NULL, cost_month = ?, updated_at = ?, updated_by = ? WHERE id = ?',
          [year, month, nowIso(), audit.userId, r['id']],
        );
        audit.log(
          entity: 'item',
          entityId: r['item_id'],
          field: 'cost_year',
          oldValue: r['cost_year'] ?? r['cost_year_text'],
          newValue: month == null ? year : '$year-$month',
          reason: reason ?? 'اصلاح گروهی سال قیمت سند',
          batch: batch,
        );
      }
    });
    return rows.length;
  }

  // ---------------------------------------------------------------------------
  // فروشندگان

  /// حذف کامل یک پروژه: اقلام آن (با مقادیر، برچسب‌ها و قیمت‌ها)، اسناد آن و خود پروژه.
  /// قیمت‌های اقلام پروژه‌های دیگر که به اسناد این پروژه ارجاع داشتند، فقط از سند جدا می‌شوند.
  /// همه‌چیز در تاریخچه ثبت می‌شود. قبل از صدا زدن، از دیتابیس پشتیبان بگیرید.
  ({int items, int documents}) deleteProject(int id, {String? reason}) {
    final row = db.queryOne('SELECT name FROM projects WHERE id = ?', [id]);
    if (row == null) return (items: 0, documents: 0);
    final batch = Audit.newBatch();
    return db.transaction(() {
      final nItems = db.scalar('SELECT COUNT(*) FROM items WHERE project_id = ?', [id]) as int;
      final nDocs = db.scalar('SELECT COUNT(*) FROM documents WHERE project_id = ?', [id]) as int;
      db.execute(
        'UPDATE price_obs SET document_id = NULL WHERE document_id IN (SELECT id FROM documents WHERE project_id = ?) '
        'AND item_id NOT IN (SELECT id FROM items WHERE project_id = ?)',
        [id, id],
      );
      for (final it in db.query('SELECT id, tag, name FROM items WHERE project_id = ?', [id])) {
        audit.log(entity: 'item', entityId: it['id'], field: 'delete',
            oldValue: '${it['tag'] ?? ''} ${it['name']}'.trim(), reason: reason ?? 'حذف پروژه', batch: batch);
      }
      db.execute('DELETE FROM items WHERE project_id = ?', [id]);
      db.execute('DELETE FROM documents WHERE project_id = ?', [id]);
      db.execute('DELETE FROM projects WHERE id = ?', [id]);
      audit.log(entity: 'project', entityId: id, field: 'delete',
          oldValue: '${row['name']} ($nItems قلم، $nDocs سند)', reason: reason, batch: batch);
      return (items: nItems, documents: nDocs);
    });
  }

  /// حذف یک سند منبع: قیمت‌های آن سند (و سند کمکی «قیمت‌های بازنگری قبلی» آن) حذف می‌شود؛ قلمی که دیگر هیچ قیمتی
  /// ندارد و فقط از همین سند آمده بود هم حذف می‌شود. همه در تاریخچه. قبل از صدا زدن، پشتیبان بگیرید.
  ({int prices, int items, int documents}) deleteDocument(int id, {String? reason}) {
    final row = db.queryOne('SELECT id, project_id, title FROM documents WHERE id = ?', [id]);
    if (row == null) return (prices: 0, items: 0, documents: 0);
    final batch = Audit.newBatch();
    return db.transaction(() {
      final ids = <int>[
        id,
        for (final r in db.query("SELECT id FROM documents WHERE project_id IS ? AND doc_type = 'mto_previous' AND title LIKE ?",
            [row['project_id'], '${row['title']} — %']))
          r['id'] as int,
      ];
      final ph = List.filled(ids.length, '?').join(',');
      final touched = [for (final r in db.query('SELECT DISTINCT item_id FROM price_obs WHERE document_id IN ($ph)', ids)) r['item_id'] as int];
      final nPrices = db.scalar('SELECT COUNT(*) FROM price_obs WHERE document_id IN ($ph)', ids) as int;
      db.execute('DELETE FROM price_obs WHERE document_id IN ($ph)', ids);
      var nItems = 0;
      for (final it in touched) {
        final left = db.scalar('SELECT COUNT(*) FROM price_obs WHERE item_id = ?', [it]) as int;
        if (left > 0) continue;
        final r = db.queryOne('SELECT tag, name FROM items WHERE id = ?', [it]);
        audit.log(entity: 'item', entityId: it, field: 'delete', oldValue: '${r?['tag'] ?? ''} ${r?['name'] ?? ''}'.trim(),
            reason: reason ?? 'حذف سند منبع', batch: batch);
        db.execute('DELETE FROM items WHERE id = ?', [it]);
        nItems++;
      }
      db.execute('DELETE FROM documents WHERE id IN ($ph)', ids);
      audit.log(entity: 'document', entityId: id, field: 'delete',
          oldValue: '${row['title']} ($nPrices قیمت، $nItems قلم)', reason: reason, batch: batch);
      return (prices: nPrices, items: nItems, documents: ids.length);
    });
  }

  /// یک بار: اسناد تکراری یک پروژه (همان سند با عنوان کمی متفاوت) یکی می‌شوند؛ قیمت‌ها به سند ماندگار منتقل می‌شوند
  /// و فیلدهای خالی آن از سند تکراری پر می‌شود.
  int mergeDuplicateDocuments() {
    var merged = 0;
    db.transaction(() {
      final rows = db.query('SELECT * FROM documents ORDER BY project_id, id');
      final gone = <int>{};
      for (var i = 0; i < rows.length; i++) {
        final a = rows[i];
        if (gone.contains(a['id'])) continue;
        for (var j = i + 1; j < rows.length; j++) {
          final b = rows[j];
          if (gone.contains(b['id']) || a['project_id'] != b['project_id']) continue;
          if ((a['doc_type'] == 'mto_previous') != (b['doc_type'] == 'mto_previous')) continue;
          final ra = a['revision'] as String? ?? '', rb = b['revision'] as String? ?? '';
          if (!(ra == rb || ra.isEmpty || rb.isEmpty) || !sameTitle(a['title'] as String, b['title'] as String)) continue;
          db.execute('UPDATE price_obs SET document_id = ? WHERE document_id = ?', [a['id'], b['id']]);
          for (final f in ['doc_ref', 'issue_year', 'issue_month', 'source_fx_eur', 'source_fx_usd', 'fx_rate_type', 'consultant']) {
            if (a[f] == null && b[f] != null) db.execute('UPDATE documents SET $f = ? WHERE id = ?', [b[f], a['id']]);
          }
          db.execute('DELETE FROM documents WHERE id = ?', [b['id']]);
          audit.log(entity: 'document', entityId: a['id'], field: 'merge', oldValue: b['title'], newValue: a['title'],
              reason: 'یکی کردن سند تکراری (همان سند با عنوان متفاوت)');
          gone.add(b['id'] as int);
          merged++;
        }
      }
    });
    return merged;
  }

  List<DbRow> vendors() => db.query('SELECT * FROM vendors ORDER BY name');

  int ensureVendor(String name, {String? code}) {
    final id = db.scalar('SELECT id FROM vendors WHERE name = ?', [name]) as int?;
    if (id != null) return id;
    final nid = db.insert('INSERT INTO vendors(code, name, created_by, updated_by) VALUES (?,?,?,?)',
        [code, name, audit.userId, audit.userId]);
    audit.log(entity: 'vendor', entityId: nid, field: '*', newValue: name);
    return nid;
  }
}
