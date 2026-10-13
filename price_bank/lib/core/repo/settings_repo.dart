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
  double get floorEur => numv('floor_eur', 25000);
  int get floorBaseYear => intv('floor_base_year', 1404);
  double get costExponent => numv('cost_exponent_n', 0.6);
  double get pumpEfficiency => numv('pump_efficiency', 0.6);
  double get eurCheckLimit => numv('eur_check_limit', 5000000);
  double? get eurTargetOverride => numOrNull('eur_target_override');
  double? get usdTargetOverride => numOrNull('usd_target_override');

  /// واحد نمایش پول: IRR (ریال) یا IRT (تومان). داده همیشه به ریال ذخیره می‌شود.
  String get displayUnit => str('display_unit', 'IRR');

  PumpCalcSettings toPumpSettings({String? fxTypeOverride, int? targetYearOverride}) => PumpCalcSettings(
        targetYear: targetYearOverride ?? targetYear,
        targetMonth: targetYearOverride == null ? targetMonth : null,
        fxType: fxTypeOverride ?? fxRateType,
        ppiSeries: ppiSeries,
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
        for (final r in db.query('SELECT code, name_fa FROM fx_rate_types ORDER BY sort, code'))
          FxRateType(r['code'] as String, r['name_fa'] as String),
      ];
}

class FxRateType {
  const FxRateType(this.code, this.nameFa);
  final String code;
  final String nameFa;
}
