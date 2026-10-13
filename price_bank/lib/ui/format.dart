// قالب‌بندی اعداد، پول و تاریخ برای نمایش فارسی.

const _faDigits = '۰۱۲۳۴۵۶۷۸۹';

String fa(Object? v) {
  if (v == null) return '';
  return v.toString().replaceAllMapped(RegExp(r'[0-9]'), (m) => _faDigits[int.parse(m[0]!)]);
}

/// عدد با جداکننده‌ی هزارگان و تعداد اعشار دلخواه، با ارقام فارسی.
String faNum(num? v, {int decimals = 0}) {
  if (v == null) return '—';
  if (v.isNaN || v.isInfinite) return '—';
  final neg = v < 0;
  final s = v.abs().toStringAsFixed(decimals);
  final parts = s.split('.');
  final ip = parts[0];
  final b = StringBuffer();
  for (var i = 0; i < ip.length; i++) {
    if (i > 0 && (ip.length - i) % 3 == 0) b.write('٬');
    b.write(ip[i]);
  }
  var out = b.toString();
  if (parts.length > 1) {
    final dec = parts[1].replaceFirst(RegExp(r'0+$'), '');
    if (dec.isNotEmpty) out = '$out٫$dec';
  }
  return fa('${neg ? '-' : ''}$out');
}

/// عدد با دقت مناسب اندازه‌اش (برای ضرایب و شاخص‌ها).
String faSmart(num? v) {
  if (v == null) return '—';
  final a = v.abs();
  if (a >= 1000) return faNum(v);
  if (a >= 10) return faNum(v, decimals: 2);
  if (a >= 1) return faNum(v, decimals: 3);
  return faNum(v, decimals: 4);
}

enum MoneyUnit { rial, toman }

MoneyUnit moneyUnitFrom(String code) => code == 'IRT' ? MoneyUnit.toman : MoneyUnit.rial;

String unitLabel(MoneyUnit u) => u == MoneyUnit.toman ? 'تومان' : 'ریال';

/// مبلغ ریالی (ذخیره‌شده) به واحد نمایش.
String money(double? irr, MoneyUnit u, {bool withUnit = true, bool compact = false}) {
  if (irr == null) return '—';
  final v = u == MoneyUnit.toman ? irr / 10 : irr;
  final s = compact ? compactNum(v) : faNum(v);
  return withUnit ? '$s ${unitLabel(u)}' : s;
}

/// نمایش خلاصه: ۱٫۲ میلیارد، ۳۴۰ میلیون.
String compactNum(double v) {
  final a = v.abs();
  if (a >= 1e12) return '${faNum(v / 1e12, decimals: 2)} هزار میلیارد';
  if (a >= 1e9) return '${faNum(v / 1e9, decimals: 2)} میلیارد';
  if (a >= 1e6) return '${faNum(v / 1e6, decimals: 1)} میلیون';
  if (a >= 1e3) return '${faNum(v / 1e3, decimals: 1)} هزار';
  return faNum(v);
}

String eur(double? v) => v == null ? '—' : '${faNum(v)} یورو';
String usd(double? v) => v == null ? '—' : '${faNum(v)} دلار';

/// تبدیل ورودی کاربر (با ارقام فارسی، ٬ و ٫) به عدد.
double? parseUserNumber(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  const ar = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = _faDigits.indexOf(ch), j = ar.indexOf(ch);
    if (i >= 0) {
      b.write(i);
    } else if (j >= 0) {
      b.write(j);
    } else if (ch == '٫') {
      b.write('.');
    } else if (ch == '٬' || ch == ',' || ch == ' ') {
      // جداکننده‌ی هزارگان
    } else {
      b.write(ch);
    }
  }
  s = b.toString();
  return double.tryParse(s);
}

/// تاریخ ISO ذخیره‌شده به نمایش کوتاه.
String shortTs(String? iso) {
  if (iso == null) return '';
  final t = iso.replaceFirst('T', ' ');
  return fa(t.length > 16 ? t.substring(0, 16) : t);
}
