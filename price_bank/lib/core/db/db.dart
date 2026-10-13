// لایه‌ی نازک روی SQLite: باز کردن، مهاجرت نسخه‌ها، تراکنش و توابع کمکی.
//
// اصل مهم ارتقاپذیری: ساختار دیتابیس با «مهاجرت»های شماره‌دار تغییر می‌کند.
// هر بار که برنامه باز می‌شود، مهاجرت‌های اجرانشده به ترتیب اجرا می‌شوند و
// شماره‌ی نسخه در PRAGMA user_version ذخیره می‌شود. داده‌های قبلی هرگز پاک نمی‌شوند.

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'migrations.dart';

typedef DbRow = Map<String, Object?>;

class Db {
  Db._(this.raw, this.path);

  final Database raw;
  final String path;

  /// باز کردن (و در صورت نیاز ساختن) دیتابیس و اجرای مهاجرت‌ها.
  static Db open(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final raw = sqlite3.open(path);
    final db = Db._(raw, path);
    db._configure();
    db._migrate();
    return db;
  }

  /// دیتابیس در حافظه (برای آزمون‌ها).
  static Db memory() {
    final db = Db._(sqlite3.openInMemory(), ':memory:');
    db._configure();
    db._migrate();
    return db;
  }

  void _configure() {
    raw.execute('PRAGMA foreign_keys = ON;');
    if (path != ':memory:') {
      raw.execute('PRAGMA journal_mode = WAL;');
      raw.execute('PRAGMA synchronous = NORMAL;');
    }
  }

  int get schemaVersion => raw.userVersion;

  void _migrate() {
    final current = raw.userVersion;
    for (final m in migrations) {
      if (m.version <= current) continue;
      transaction(() {
        for (final stmt in m.statements) {
          raw.execute(stmt);
        }
      });
      raw.userVersion = m.version;
    }
  }

  void close() => raw.dispose();

  // ---------------------------------------------------------------------------

  List<DbRow> query(String sql, [List<Object?> params = const []]) {
    final rs = raw.select(sql, params);
    final names = rs.columnNames;
    return [
      for (final r in rs.rows) {for (var i = 0; i < names.length; i++) names[i]: r[i]},
    ];
  }

  DbRow? queryOne(String sql, [List<Object?> params = const []]) {
    final r = query(sql, params);
    return r.isEmpty ? null : r.first;
  }

  Object? scalar(String sql, [List<Object?> params = const []]) {
    final rs = raw.select(sql, params);
    if (rs.rows.isEmpty || rs.rows.first.isEmpty) return null;
    return rs.rows.first.first;
  }

  void execute(String sql, [List<Object?> params = const []]) => raw.execute(sql, params);

  /// اجرای INSERT و برگرداندن شناسه‌ی ردیف جدید.
  int insert(String sql, [List<Object?> params = const []]) {
    raw.execute(sql, params);
    return raw.lastInsertRowId;
  }

  int get changes => raw.updatedRows;

  int _depth = 0;

  /// تراکنش تودرتو با SAVEPOINT. اگر تابع خطا بدهد همه‌چیز برگردانده می‌شود.
  T transaction<T>(T Function() fn) {
    final name = 'sp${_depth++}';
    raw.execute('SAVEPOINT $name');
    try {
      final result = fn();
      raw.execute('RELEASE $name');
      return result;
    } catch (_) {
      raw.execute('ROLLBACK TO $name');
      raw.execute('RELEASE $name');
      rethrow;
    } finally {
      _depth--;
    }
  }

  /// پشتیبان‌گیری کامل (فایل مستقل و سازگار) با VACUUM INTO.
  void backupTo(String targetPath) {
    final f = File(targetPath);
    if (f.existsSync()) f.deleteSync();
    raw.execute('VACUUM INTO ?', [targetPath]);
  }
}

String nowIso() => DateTime.now().toIso8601String();
