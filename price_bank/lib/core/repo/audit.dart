import '../db/db.dart';

/// ثبت تاریخچه‌ی تغییرات. هر تغییر: چه کسی، چه زمانی، چه فیلدی، از چه به چه، و چرا.
class Audit {
  Audit(this.db, this.userId);

  final Db db;
  int? userId;

  static int _seq = 0;
  static String newBatch() => '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  void log({
    required String entity,
    required Object? entityId,
    String? field,
    Object? oldValue,
    Object? newValue,
    String? reason,
    String? batch,
  }) {
    db.execute(
      'INSERT INTO audit_log(ts, user_id, entity, entity_id, field, old_value, new_value, reason, batch_id) '
      'VALUES (?,?,?,?,?,?,?,?,?)',
      [nowIso(), userId, entity, entityId?.toString(), field, _s(oldValue), _s(newValue), reason, batch],
    );
  }

  static String? _s(Object? v) {
    if (v == null) return null;
    if (v is double && v == v.roundToDouble() && v.abs() < 1e15) return v.toStringAsFixed(0);
    return v.toString();
  }

  List<AuditEntry> history(String entity, Object entityId, {int limit = 500}) => [
        for (final r in db.query(
          'SELECT a.*, u.display_name AS user_name FROM audit_log a LEFT JOIN users u ON u.id = a.user_id '
          'WHERE a.entity = ? AND a.entity_id = ? ORDER BY a.id DESC LIMIT ?',
          [entity, entityId.toString(), limit],
        ))
          AuditEntry.fromRow(r),
      ];

  List<AuditEntry> recent({int limit = 200}) => [
        for (final r in db.query(
          'SELECT a.*, u.display_name AS user_name FROM audit_log a LEFT JOIN users u ON u.id = a.user_id '
          'ORDER BY a.id DESC LIMIT ?',
          [limit],
        ))
          AuditEntry.fromRow(r),
      ];
}

class AuditEntry {
  AuditEntry.fromRow(DbRow r)
      : ts = r['ts'] as String,
        userName = r['user_name'] as String?,
        entity = r['entity'] as String,
        entityId = r['entity_id'] as String?,
        field = r['field'] as String?,
        oldValue = r['old_value'] as String?,
        newValue = r['new_value'] as String?,
        reason = r['reason'] as String?;

  final String ts;
  final String? userName;
  final String entity;
  final String? entityId;
  final String? field;
  final String? oldValue;
  final String? newValue;
  final String? reason;
}
