import '../calc/pump_engine.dart';
import '../db/db.dart';
import 'audit.dart';

/// تنظیمات قابل ویرایش برنامه (سال هدف، نوع نرخ ارز، پارامترهای کف و ...).
class AppSettings {
  AppSettings(this._m);
  final Map<String, String> _m;

  String str(String k, [String def = '']) => _m[k] ?? def;
  double? numOrNull(String k) => double.tryParse(_m[k] ?? '');
  double numv(String k, double def) => numOrNull(k) ?? def;
  int intv(String k, int def) => int.tryParse(_m[k] ?? '') ?? def;

  int get targetYear => intv('target_year', 1404);
  int? get targetMonth => int.tryParse(_m['target_month'] ?? '');
  String get fxRateType => str('fx_rate_type', 'V8');
  String get ppiSeries => str('ppi_series', 'PPI_EU_C2813');
  String get escalationMethod => str('escalation_method', 'M6');

  // تنظیمات اختصاصی هر رده (خالی = پیش‌فرض برنامه یا قالب رده)
  String? catMethod(String code) => _m['cat_method_$code']?.isEmpty ?? true ? null : _m['cat_method_$code'];
  String? catPpi(String code) => _m['cat_ppi_$code']?.isEmpty ?? true ? null : _m['cat_ppi_$code'];
  double? catExponent(String code) => numOrNull('cat_n_$code');
  String? catEstimation(String code) => _m['cat_est_$code'];
  double get floorEur => numv('floor_eur', 25000);
  int get floorBaseYear => intv('floor_base_year', 1404);
  double get costExponent => numv('cost_exponent_n', 0.6);
  double get pumpEfficiency => numv('pump_efficiency', 0.6);
  double get eurCheckLimit => numv('eur_check_limit', 5000000);
  double? get eurTargetOverride => numOrNull('eur_target_override');
  double? get usdTargetOverride => numOrNull('usd_target_override');

  /// واحد نمایش پول: IRR (ریال) یا IRT (تومان). داده همیشه به ریال ذخیره می‌شود.
  String get displayUnit => str('display_unit', 'IRR');

  PumpCalcSettings toPumpSettings(
          {String? fxTypeOverride, int? targetYearOverride, String? methodOverride, String? ppiOverride}) =>
      PumpCalcSettings(
        method: methodOverride ?? escalationMethod,
        targetYear: targetYearOverride ?? targetYear,
        targetMonth: targetYearOverride == null ? targetMonth : null,
        fxType: fxTypeOverride ?? fxRateType,
        ppiSeries: ppiOverride ?? ppiSeries,
        floorEur: floorEur,
        floorBaseYear: floorBaseYear,
        costExponent: costExponent,
        pumpEfficiency: pumpEfficiency,
        eurCheckLimit: eurCheckLimit,
        eurTargetOverride: eurTargetOverride,
        usdTargetOverride: usdTargetOverride,
      );
}

class SettingsRepo {
  SettingsRepo(this.db, this.audit);
  final Db db;
  final Audit audit;

  AppSettings load() => AppSettings({
        for (final r in db.query('SELECT key, value FROM settings')) r['key'] as String: r['value'] as String,
      });

  void set(String key, String? value, {String? reason}) {
    final old = db.scalar('SELECT value FROM settings WHERE key = ?', [key]) as String?;
    if (old == value) return;
    if (value == null || value.isEmpty) {
      db.execute('DELETE FROM settings WHERE key = ?', [key]);
    } else {
      db.execute('INSERT INTO settings(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
          [key, value]);
    }
    audit.log(entity: 'settings', entityId: key, field: key, oldValue: old, newValue: value, reason: reason);
  }

  List<FxRateType> fxRateTypes() => [
        for (final r in db.query('SELECT code, name_fa, user_defined, description FROM fx_rate_types ORDER BY sort, code'))
          FxRateType(r['code'] as String, r['name_fa'] as String,
              userDefined: (r['user_defined'] as int? ?? 0) == 1, description: r['description'] as String?),
      ];

  /// ساخت جدول نرخ ارز جدید با نام دلخواه: یک نوع نرخ + دو سری FX_EUR_<کد> و FX_USD_<کد>.
  /// اگر [copyFrom] داده شود، مقادیر آن جدول به عنوان نقطه‌ی شروع کپی می‌شود.
  String createFxType(String nameFa, {String? copyFrom, String? description}) {
    final name = nameFa.trim();
    if (name.isEmpty) throw ArgumentError('نام جدول خالی است');
    if (db.scalar('SELECT 1 FROM fx_rate_types WHERE name_fa = ?', [name]) != null) {
      throw ArgumentError('جدولی با این نام وجود دارد');
    }
    var n = 1;
    String code;
    do {
      code = 'U$n';
      n++;
    } while (db.scalar('SELECT 1 FROM fx_rate_types WHERE code = ?', [code]) != null ||
        db.scalar("SELECT 1 FROM index_series WHERE code IN ('FX_EUR_' || ?, 'FX_USD_' || ?)", [code, code]) != null);
    db.transaction(() {
      final sort = (db.scalar('SELECT COALESCE(MAX(sort), 0) + 1 FROM fx_rate_types') as int);
      db.execute('INSERT INTO fx_rate_types(code, name_fa, sort, user_defined, description) VALUES (?,?,?,1,?)',
          [code, name, sort, description]);
      final sSort = (db.scalar("SELECT COALESCE(MAX(sort), 0) + 1 FROM index_series") as int);
      for (final (cur, curFa) in [('USD', 'دلار'), ('EUR', 'یورو')]) {
        final sc = 'FX_${cur}_$code';
        db.execute(
          "INSERT INTO index_series(code, name_fa, name_en, kind, grp, unit, source, calendar, sort, user_defined) "
          "VALUES (?,?,?,'level','fx','ریال',?, 'jalali', ?, 1)",
          [sc, '$curFa به ریال — $name', '$cur→IRR ($name)', copyFrom == null ? 'ورود توسط کاربر' : 'کپی از جدول $copyFrom',
            sSort + (cur == 'EUR' ? 1 : 0)],
        );
        if (copyFrom != null) {
          db.execute(
            'INSERT INTO index_values(series_code, period_key, year, quarter, month, value, status, source, updated_by) '
            'SELECT ?, period_key, year, quarter, month, value, status, source, ? FROM index_values WHERE series_code = ?',
            [sc, audit.userId, 'FX_${cur}_$copyFrom'],
          );
        }
      }
      audit.log(entity: 'fx_rate_type', entityId: code, field: 'create', newValue: name,
          reason: copyFrom == null ? null : 'کپی از $copyFrom');
    });
    return code;
  }

  void renameFxType(String code, String nameFa) {
    final old = db.scalar('SELECT name_fa FROM fx_rate_types WHERE code = ?', [code]) as String?;
    if (old == null || old == nameFa.trim() || nameFa.trim().isEmpty) return;
    db.transaction(() {
      db.execute('UPDATE fx_rate_types SET name_fa = ? WHERE code = ?', [nameFa.trim(), code]);
      for (final (cur, curFa) in [('USD', 'دلار'), ('EUR', 'یورو')]) {
        db.execute('UPDATE index_series SET name_fa = ? WHERE code = ?', ['$curFa به ریال — ${nameFa.trim()}', 'FX_${cur}_$code']);
      }
      audit.log(entity: 'fx_rate_type', entityId: code, field: 'name_fa', oldValue: old, newValue: nameFa.trim());
    });
  }

  /// حذف جدول نرخ ارز تعریف‌شده توسط کاربر (جدول‌های پایه حذف نمی‌شوند).
  void deleteFxType(String code) {
    final row = db.queryOne('SELECT name_fa, user_defined FROM fx_rate_types WHERE code = ?', [code]);
    if (row == null) return;
    if ((row['user_defined'] as int? ?? 0) != 1) throw ArgumentError('جدول‌های پایه حذف نمی‌شوند');
    db.transaction(() {
      db.execute("DELETE FROM index_series WHERE code IN ('FX_EUR_' || ?, 'FX_USD_' || ?)", [code, code]);
      db.execute('DELETE FROM fx_rate_types WHERE code = ?', [code]);
      if (load().fxRateType == code) set('fx_rate_type', 'V8', reason: 'جدول انتخاب‌شده حذف شد');
      audit.log(entity: 'fx_rate_type', entityId: code, field: 'delete', oldValue: row['name_fa'] as String?);
    });
  }
}

class FxRateType {
  const FxRateType(this.code, this.nameFa, {this.userDefined = false, this.description});
  final String code;
  final String nameFa;
  final bool userDefined;
  final String? description;
}
