import '../db/db.dart';
import 'audit.dart';

const roleFa = {
  'admin': 'مدیر سیستم',
  'editor': 'کارشناس ورود داده',
  'reviewer': 'بازبین',
  'viewer': 'مشاهده‌گر',
};

class AppUser {
  AppUser.fromRow(DbRow r)
      : id = r['id'] as int,
        username = r['username'] as String,
        displayName = r['display_name'] as String,
        role = r['role'] as String,
        active = (r['active'] as int) == 1;
  final int id;
  final String username;
  final String displayName;
  final String role;
  final bool active;

  bool get isAdmin => role == 'admin';
}

class UserScope {
  const UserScope(this.discipline, this.canView, this.canEdit, this.canApprove);
  final String discipline;
  final bool canView;
  final bool canEdit;
  final bool canApprove;
}

class UsersRepo {
  UsersRepo(this.db, this.audit);
  final Db db;
  final Audit audit;

  List<AppUser> all() => [for (final r in db.query('SELECT * FROM users ORDER BY id')) AppUser.fromRow(r)];

  AppUser? byId(int id) {
    final r = db.queryOne('SELECT * FROM users WHERE id = ?', [id]);
    return r == null ? null : AppUser.fromRow(r);
  }

  /// کاربر پیش‌فرض نسخه‌ی تک‌کاربره (اولین مدیر فعال).
  AppUser defaultUser() =>
      AppUser.fromRow(db.queryOne("SELECT * FROM users WHERE role = 'admin' AND active = 1 ORDER BY id LIMIT 1")!);

  Map<String, UserScope> scopes(int userId) => {
        for (final r in db.query('SELECT * FROM user_scopes WHERE user_id = ?', [userId]))
          r['discipline_code'] as String: UserScope(r['discipline_code'] as String, (r['can_view'] as int) == 1,
              (r['can_edit'] as int) == 1, (r['can_approve'] as int) == 1),
      };

  bool canEdit(AppUser u, String discipline) {
    if (u.isAdmin) return true;
    if (u.role == 'viewer') return false;
    return scopes(u.id)[discipline]?.canEdit ?? false;
  }

  bool canView(AppUser u, String discipline) {
    if (u.isAdmin) return true;
    return scopes(u.id)[discipline]?.canView ?? false;
  }

  int create(String username, String displayName, String role) {
    final id = db.insert('INSERT INTO users(username, display_name, role, created_by, updated_by) VALUES (?,?,?,?,?)',
        [username, displayName, role, audit.userId, audit.userId]);
    audit.log(entity: 'user', entityId: id, field: '*', newValue: '$displayName ($role)');
    return id;
  }

  void update(int id, {String? displayName, String? role, bool? active}) {
    final old = byId(id);
    if (old == null) return;
    if (displayName != null && displayName != old.displayName) {
      db.execute('UPDATE users SET display_name = ? WHERE id = ?', [displayName, id]);
      audit.log(entity: 'user', entityId: id, field: 'display_name', oldValue: old.displayName, newValue: displayName);
    }
    if (role != null && role != old.role) {
      db.execute('UPDATE users SET role = ? WHERE id = ?', [role, id]);
      audit.log(entity: 'user', entityId: id, field: 'role', oldValue: old.role, newValue: role);
    }
    if (active != null && active != old.active) {
      db.execute('UPDATE users SET active = ? WHERE id = ?', [active ? 1 : 0, id]);
      audit.log(entity: 'user', entityId: id, field: 'active', oldValue: old.active, newValue: active);
    }
  }

  void setScope(int userId, String discipline, {required bool view, required bool edit, required bool approve}) {
    db.execute(
      'INSERT INTO user_scopes(user_id, discipline_code, can_view, can_edit, can_approve) VALUES (?,?,?,?,?) '
      'ON CONFLICT(user_id, discipline_code) DO UPDATE SET can_view = excluded.can_view, '
      'can_edit = excluded.can_edit, can_approve = excluded.can_approve',
      [userId, discipline, view ? 1 : 0, edit ? 1 : 0, approve ? 1 : 0],
    );
    audit.log(entity: 'user', entityId: userId, field: 'scope:$discipline',
        newValue: 'مشاهده=${view ? 1 : 0} ویرایش=${edit ? 1 : 0} تأیید=${approve ? 1 : 0}');
  }
}
