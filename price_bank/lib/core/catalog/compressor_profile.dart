// قالب و ضرایب رده‌ی کمپرسور هوا — مطابق بانک Air_Compressor_Price_Bank v8 (Factors_CMP، Enum_Catalog، Calc_Spec).
//
// پیکربندی پایه: رفت‌وبرگشتی بدون روغن، API 618، ساخت خارج، موتور برقی، پکیج کمپرسور با کولر و پنل؛
// بدون خشک‌کن، مخزن، فیلتر، یدکی، خدمات سایت و حمل.
part of 'profiles.dart';

/// گروه‌های Scope (حاصل‌ضرب = SCOPE_F) و فیلد هر کدام
const compressorScopeFields = {
  'SC_DRY': 'scope_dryer',
  'SC_REC': 'scope_receiver',
  'SC_FLT': 'scope_filters',
  'SC_ACL': 'scope_coolers',
  'SC_PNL': 'scope_control_panel',
  'SC_SPR': 'scope_spares',
  'SC_VS': 'scope_vendor_services',
  'SC_TRN': 'scope_transport',
};

/// فیلد هر گروه ضریب کمپرسور
const compressorFactorFields = {
  'TYPE': 'compressor_type',
  'STD': 'design_standard',
  'ORIGIN': 'supply_origin',
  'DRV': 'driver',
  ...compressorScopeFields,
};

const compressorFactorGroups = ['TYPE', 'STD', 'ORIGIN', 'DRV', 'SC_DRY', 'SC_REC', 'SC_FLT', 'SC_ACL', 'SC_PNL', 'SC_SPR', 'SC_VS', 'SC_TRN'];

String? compressorFactorOption(String group, Map<String, Object?> v) {
  final k = compressorFactorFields[group];
  final s = k == null ? null : v[k]?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

/// ضریب خشک‌کن (تصمیم کاربر ۱۴۰۵/۰۷/۲۳): ضریب کل «خشک‌کن + مخزن + فیلتر» = ۱٫۵۳ (از مقایسه‌ی پکیج کامل IA/PA
/// با پکیج کمپرسور تنهای گچساران در همان دبی)؛ با مخزن ۱٫۰۵ و فیلتر ۱٫۰۲ ← خشک‌کن = ۱٫۵۳ ÷ ۱٫۰۷۱.
const compressorDryerFactor = 1.53 / (1.05 * 1.02);

/// ضرایب اولیه (Factors_CMP ستون D — قضاوت مهندسی، کالیبره نشده؛ SC_DRY|Y طبق تصمیم کاربر)
const compressorFactorSeeds = <(String, String, double, String)>[
  ('TYPE', 'Reciprocating – non-lubricated', 1.00, 'پایه: رفت‌وبرگشتی بدون روغن'),
  ('TYPE', 'Reciprocating – lubricated', 0.85, 'رفت‌وبرگشتی روغن‌کاری‌شده'),
  ('TYPE', 'Screw – oil-free', 0.90, 'اسکرو بدون روغن'),
  ('TYPE', 'Screw – oil-injected', 0.55, 'اسکرو روغن‌پاش'),
  ('TYPE', 'Centrifugal', 1.20, 'گریز از مرکز (API 672)'),
  ('TYPE', 'Not stated', 1.00, 'ذکر نشده'),
  ('STD', 'API 618', 1.00, 'پایه'),
  ('STD', 'API 619', 0.95, 'اسکرو صنایع نفت'),
  ('STD', 'API 672', 1.05, 'گریز از مرکز پکیج'),
  ('STD', 'Manufacturer std / ISO 1217', 0.60, 'استاندارد سازنده (صنعتی)'),
  ('STD', 'Not stated', 1.00, 'ذکر نشده'),
  ('ORIGIN', 'Import', 1.00, 'پایه: ساخت خارج'),
  ('ORIGIN', 'Domestic', 0.60, 'ساخت داخل (از نسبت استعلام پازنان به برآورد گچساران)'),
  ('ORIGIN', 'Domestic (Licensed)', 0.75, 'ساخت داخل با لایسنس'),
  ('ORIGIN', 'Not stated', 1.00, 'ذکر نشده'),
  ('DRV', 'Electric Motor', 1.00, 'پایه: موتور برقی'),
  ('DRV', 'Diesel Engine', 1.30, 'موتور دیزل'),
  ('DRV', 'Not stated', 1.00, 'ذکر نشده'),
  ('SC_DRY', 'Y', compressorDryerFactor,
      'خشک‌کن در قیمت — تصمیم کاربر: خشک‌کن × مخزن × فیلتر = ۱٫۵۳ (اکسل: ۱٫۱۰)'),
  ('SC_DRY', 'N', 1.00, 'پایه'),
  ('SC_DRY', 'Not stated', 1.00, 'ذکر نشده'),
  ('SC_REC', 'Y', 1.05, 'مخزن هوا در قیمت'),
  ('SC_REC', 'N', 1.00, 'پایه'),
  ('SC_REC', 'Not stated', 1.00, 'ذکر نشده'),
  ('SC_FLT', 'Y', 1.02, 'فیلترهای Pre/After در قیمت'),
  ('SC_FLT', 'N', 1.00, 'پایه'),
  ('SC_FLT', 'Not stated', 1.00, 'ذکر نشده'),
  ('SC_ACL', 'Y', 1.00, 'پایه: کولر میانی و انتهایی در قیمت'),
  ('SC_ACL', 'N', 0.95, 'بدون کولر'),
  ('SC_ACL', 'Not stated', 1.00, 'ذکر نشده'),
  ('SC_PNL', 'Y', 1.00, 'پایه: پنل کنترل محلی در قیمت'),
  ('SC_PNL', 'N', 0.95, 'بدون پنل'),
  ('SC_PNL', 'Not stated', 1.00, 'ذکر نشده'),
  ('SC_SPR', 'Y', 1.05, 'یدکی در قیمت'),
  ('SC_SPR', 'N', 1.00, 'پایه'),
  ('SC_SPR', 'Not stated', 1.00, 'ذکر نشده'),
  ('SC_VS', 'Y', 1.03, 'خدمات سازنده در سایت در قیمت'),
  ('SC_VS', 'N', 1.00, 'پایه'),
  ('SC_VS', 'Not stated', 1.00, 'ذکر نشده'),
  ('SC_TRN', 'Y', 1.03, 'حمل تا سایت در قیمت'),
  ('SC_TRN', 'N', 1.00, 'پایه'),
  ('SC_TRN', 'Not stated', 1.00, 'ذکر نشده'),
];

/// فهرست‌های انتخابی کمپرسور (Enum_Catalog)
const compressorLists = <String, List<(String, String)>>{
  'CMP_SUBCAT': [
    ('CMP-PKG', 'پکیج کمپرسور هوا (کمپرسور، محرک، کولر و پنل)'),
    ('CMP-IAP', 'پکیج کامل هوای ابزار دقیق و سرویس (کمپرسورها + خشک‌کن + فیلتر + مخزن)'),
    ('CMP-CMB', 'یکجا با پکیج دیگر (فقط مرجع)'),
  ],
  'CMP_TYPE': [
    ('Reciprocating – non-lubricated', 'رفت‌وبرگشتی بدون روغن'),
    ('Reciprocating – lubricated', 'رفت‌وبرگشتی روغن‌کاری‌شده'),
    ('Screw – oil-free', 'اسکرو بدون روغن'),
    ('Screw – oil-injected', 'اسکرو روغن‌پاش'),
    ('Centrifugal', 'گریز از مرکز'),
    ('Not stated', 'ذکر نشده'),
  ],
  'CMP_STD': [
    ('API 618', 'API 618'),
    ('API 619', 'API 619'),
    ('API 672', 'API 672'),
    ('Manufacturer std / ISO 1217', 'استاندارد سازنده / ISO 1217'),
    ('Not stated', 'ذکر نشده'),
  ],
  'CMP_IPS': [('IPS-M-PM-211', 'IPS-M-PM-211'), ('None', 'ندارد')],
  'CMP_ORIGIN': [
    ('Import', 'ساخت خارج'),
    ('Domestic', 'ساخت داخل'),
    ('Domestic (Licensed)', 'ساخت داخل با لایسنس'),
    ('Not stated', 'ذکر نشده'),
  ],
  'CMP_DRV': [('Electric Motor', 'موتور برقی'), ('Diesel Engine', 'موتور دیزل'), ('Not stated', 'ذکر نشده')],
};

/// نوع کمپرسور بانک از نوع و روغن‌کاری قدیمی (ورود MTO)
String? compressorTypeOf(String? type, String? lube) {
  final oilFree = lube == 'Oil-free';
  final lubed = lube == 'Lubricated';
  switch (type) {
    case 'Reciprocating':
      return lubed ? 'Reciprocating – lubricated' : (oilFree ? 'Reciprocating – non-lubricated' : null);
    case 'Screw':
      return lubed ? 'Screw – oil-injected' : (oilFree ? 'Screw – oil-free' : null);
    case 'Centrifugal':
      return 'Centrifugal';
  }
  return null;
}

/// استنباط فیلدهای کمپرسور از شرح MTO: نوع بانک، استاندارد، IPS
void inferCompressor(String ctx, Map<String, Object?> o) {
  o['compressor_type'] ??= compressorTypeOf(o['comp_type']?.toString(), o['lubrication']?.toString());
  final code = '${o['design_code'] ?? ''} $ctx'.toUpperCase();
  for (final s in ['API 618', 'API 619', 'API 672']) {
    if (code.replaceAll('-', ' ').contains(s)) {
      o['design_standard'] ??= s;
      break;
    }
  }
  if (code.contains('IPS-M-PM-211')) o['ips_standard'] ??= 'IPS-M-PM-211';
  final l = ctx.toLowerCase();
  if (l.contains('instrument') && l.contains('air') && l.contains('package')) o['sub_category'] ??= 'CMP-IAP';
}

/// خانواده‌ی کمپرسور (ستون Family بانک)
String compressorFamily(String? type) {
  final t = type ?? '';
  if (t.startsWith('Recip')) return 'Positive displacement – reciprocating';
  if (t.startsWith('Screw')) return 'Positive displacement – rotary screw';
  if (t == 'Centrifugal') return 'Dynamic – centrifugal';
  return 'Not stated';
}
