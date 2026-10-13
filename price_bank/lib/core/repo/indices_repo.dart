import '../calc/pump_engine.dart';
import '../calc/series.dart';
import '../db/db.dart';
import 'audit.dart';

class IndexSeriesInfo {
  IndexSeriesInfo.fromRow(DbRow r)
      : code = r['code'] as String,
        nameFa = r['name_fa'] as String,
        nameEn = r['name_en'] as String?,
        kind = r['kind'] as String,
        group = r['grp'] as String? ?? 'other',
        unit = r['unit'] as String?,
        base = r['base'] as String?,
        source = r['source'] as String?,
        calendar = r['calendar'] as String,
        userDefined = (r['user_defined'] as int) == 1,
        valueCount = (r['value_count'] as int?) ?? 0;
  final String code;
  final String nameFa;
  final String? nameEn;
  final String kind;
  final String group;
  final String? unit;
  final String? base;
  final String? source;
  final String calendar;
  final bool userDefined;
  final int valueCount;

  bool get isRate => kind == 'annual_rate';
}

class IndexValue {
  IndexValue.fromRow(DbRow r)
      : seriesCode = r['series_code'] as String,
        period = Period.tryParse(r['period_key'] as String)!,
        value = r['value'] as double,
        status = r['status'] as String,
        source = r['source'] as String?,
        updatedAt = r['updated_at'] as String?;
  final String seriesCode;
  final Period period;
  final double value;
  final String status;
  final String? source;
  final String? updatedAt;
}

const indexStatusFa = {
  'official': 'رسمی',
  'approx': 'تقریبی',
  'imputed': 'برآوردشده (Eurostat)',
  'forecast': 'پیش‌بینی',
  'needs_verification': 'نیاز به تأیید',
  'manual': 'ورود دستی',
};

const indexGroupFa = {
  'ppi_world': 'شاخص قیمت تولیدکننده — جهانی',
  'ppi_iran': 'شاخص قیمت تولیدکننده — ایران (مرکز آمار)',
  'fx': 'نرخ ارز',
  'inflation': 'تورم',
  'metal': 'قیمت فلزات',
  'other': 'سایر',
};

class IndicesRepo {
  IndicesRepo(this.db, this.audit);
  final Db db;
  final Audit audit;

  List<IndexSeriesInfo> series() => [
        for (final r in db.query('SELECT s.*, (SELECT COUNT(*) FROM index_values v WHERE v.series_code = s.code) '
            'AS value_count FROM index_series s ORDER BY s.sort, s.code'))
          IndexSeriesInfo.fromRow(r),
      ];

  List<IndexValue> values(String code) {
    final list = [
      for (final r in db.query('SELECT * FROM index_values WHERE series_code = ?', [code])) IndexValue.fromRow(r),
    ];
    list.sort((a, b) => a.period.compareTo(b.period));
    return list;
  }

  /// افزودن یا ویرایش یک مقدار (با تاریخچه).
  void upsert(String code, Period p, double value, {String status = 'manual', String? source, String? reason}) {
    final old = db.queryOne('SELECT value, status FROM index_values WHERE series_code = ? AND period_key = ?', [code, p.key]);
    db.execute(
      'INSERT INTO index_values(series_code, period_key, year, quarter, month, value, status, source, updated_at, updated_by) '
      'VALUES (?,?,?,?,?,?,?,?,?,?) ON CONFLICT(series_code, period_key) DO UPDATE SET value = excluded.value, '
      'status = excluded.status, source = COALESCE(excluded.source, index_values.source), '
      'updated_at = excluded.updated_at, updated_by = excluded.updated_by',
      [code, p.key, p.year, p.quarter, p.month, value, status, source, nowIso(), audit.userId],
    );
    audit.log(entity: 'index', entityId: code, field: p.key, oldValue: old?['value'], newValue: value, reason: reason);
  }

  void delete(String code, Period p, {String? reason}) {
    final old = db.scalar('SELECT value FROM index_values WHERE series_code = ? AND period_key = ?', [code, p.key]);
    if (old == null) return;
    db.execute('DELETE FROM index_values WHERE series_code = ? AND period_key = ?', [code, p.key]);
    audit.log(entity: 'index', entityId: code, field: p.key, oldValue: old, newValue: '(حذف)', reason: reason);
  }

  /// ورود گروهی از متن چسبانده‌شده (دو ستون: دوره و مقدار؛ جداکننده تب، ویرگول یا فاصله).
  /// برمی‌گرداند (تعداد ثبت‌شده، خطوط نامعتبر).
  (int, List<String>) importText(String code, String text, {String status = 'manual', String? source}) {
    final bad = <String>[];
    var n = 0;
    db.transaction(() {
      for (final raw in text.split(RegExp(r'\r?\n'))) {
        final line = _latinDigits(raw.trim());
        if (line.isEmpty) continue;
        final List<String> split;
        if (line.contains('\t')) {
          split = line.split('\t');
        } else if (line.contains(';')) {
          split = line.split(';');
        } else {
          split = line.split(RegExp(r'\s+'));
        }
        final parts = split.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        if (parts.length < 2) {
          bad.add(raw);
          continue;
        }
        final p = Period.tryParse(parts.sublist(0, parts.length - 1).join(''));
        final v = double.tryParse(parts.last.replaceAll(',', '').trim());
        if (p == null || v == null) {
          bad.add(raw);
          continue;
        }
        upsert(code, p, v, status: status, source: source, reason: 'ورود گروهی');
        n++;
      }
    });
    return (n, bad);
  }

  void addSeries({required String code, required String nameFa, required String kind, required String group,
      String? unit, String? base, String? source}) {
    db.execute(
      'INSERT INTO index_series(code, name_fa, kind, grp, unit, base, source, user_defined, sort) VALUES (?,?,?,?,?,?,?,1,999)',
      [code, nameFa, kind, group, unit, base, source],
    );
    audit.log(entity: 'index_series', entityId: code, field: '*', newValue: nameFa);
  }

  /// ساخت جدول درون‌حافظه‌ای همه‌ی شاخص‌ها برای موتور محاسبات.
  MemorySeries snapshot() {
    final m = MemorySeries();
    for (final r in db.query('SELECT series_code, period_key, value FROM index_values')) {
      final p = Period.tryParse(r['period_key'] as String);
      if (p != null) m.put(r['series_code'] as String, p, r['value'] as double);
    }
    return m;
  }

  /// ضرایب نرمال‌سازی (ضریب کالیبره، وگرنه ضریب اولیه).
  FactorTable factorTable(String setCode) => FactorTable({
        for (final r in db.query('SELECT grp, option, provisional, calibrated FROM factors WHERE set_code = ?', [setCode]))
          '${r['grp']}|${r['option']}': (r['calibrated'] as double?) ?? (r['provisional'] as double),
      });

  List<DbRow> factors(String setCode) =>
      db.query('SELECT * FROM factors WHERE set_code = ? ORDER BY grp, rowid', [setCode]);

  void setCalibrated(String setCode, String grp, String option, double? value, {String? reason}) {
    final old = db.scalar('SELECT calibrated FROM factors WHERE set_code = ? AND grp = ? AND option = ?',
        [setCode, grp, option]);
    db.execute(
      'UPDATE factors SET calibrated = ?, updated_at = ?, updated_by = ? WHERE set_code = ? AND grp = ? AND option = ?',
      [value, nowIso(), audit.userId, setCode, grp, option],
    );
    audit.log(entity: 'factor', entityId: '$setCode|$grp|$option', field: 'calibrated', oldValue: old, newValue: value,
        reason: reason);
  }

  static String _latinDigits(String s) {
    const fa = '۰۱۲۳۴۵۶۷۸۹', ar = '٠١٢٣٤٥٦٧٨٩';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = fa.indexOf(ch), j = ar.indexOf(ch);
      b.write(i >= 0 ? '$i' : (j >= 0 ? '$j' : (ch == '٫' ? '.' : (ch == '٬' ? ',' : ch))));
    }
    return b.toString();
  }
}
