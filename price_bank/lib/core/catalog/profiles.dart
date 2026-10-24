// قالب تخصصی هر رده‌ی تجهیزات غیرپمپ: فیلدها، قواعد استخراج از شرح MTO، پارامتر اندازه برای تخمین،
// ضرایب نرمال‌سازی (جنس، NACE، فشار) و فیلترها/ستون‌های جستجوی پارامتریک.
//
// ضرایب و توان‌های اندازه «اولیه (قضاوت مهندسی)» هستند و در صفحه‌ی «ضرایب» و تنظیمات هر رده
// قابل کالیبره کردن‌اند.

import 'dart:math' as math;

import '../calc/methods.dart' show MixPart, defaultUsPpiSeries;

part 'compressor_profile.dart';
part 'desalter_profile.dart';

/// شرح چندخطی MTO: خط اول نام؛ «کلید: مقدار» مشخصات؛ خط بدون «:» ادامه‌ی مقدار قبلی یا دامنه‌ی کار.
({String name, Map<String, String> specs, List<String> scope}) parseMtoDescription(String description) {
  final lines = description.replaceAll('\r', '').split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  final specs = <String, String>{};
  final scope = <String>[];
  if (lines.isEmpty) return (name: '', specs: specs, scope: scope);
  String? lastKey;
  for (final line in lines.skip(1)) {
    final i = line.indexOf(':');
    if (i > 0 && i < 70 && !line.startsWith('&')) {
      final k = line.substring(0, i).trim();
      final v = line.substring(i + 1).trim();
      if (specs.containsKey(k) && v.isNotEmpty && specs[k]!.isNotEmpty) {
        specs[k] = '${specs[k]}; $v';
      } else {
        specs[k] = v;
      }
      lastKey = k;
    } else if (lastKey != null) {
      specs[lastKey] = '${specs[lastKey]} $line'.trim();
    } else {
      scope.add(line);
    }
  }
  specs.removeWhere((k, v) => v.isEmpty);
  return (name: lines.first, specs: specs, scope: scope);
}

/// یک فیلد قالب.
class ProfileField {
  const ProfileField(
    this.key,
    this.labelFa,
    this.group, {
    this.type = 'text',
    this.unit,
    this.list,
    this.help,
    this.labelEn,
  });
  final String key;
  final String labelFa;
  final String group; // key_specs, design, material, scope, package
  final String type; // text, number, enum
  final String? unit;
  final String? list;
  final String? help;
  final String? labelEn;
}

const profileGroupFa = {
  'key_specs': 'مشخصات کلیدی',
  'design': 'شرایط طراحی',
  'material': 'جنس، کد و استاندارد',
  'package': 'اجزای پکیج',
  'scope': 'دامنه‌ی تأمین',
  'source': 'منبع و مبنای قیمت',
};

const _groupSort = {'key_specs': 100, 'design': 200, 'material': 300, 'package': 400, 'scope': 500, 'source': 550};
int profileGroupSort(String g) => _groupSort[g] ?? 600;

/// قاعده‌ی تبدیل یک خط شرح MTO به فیلد(های) قالب.
class MtoRule {
  const MtoRule(this.pattern, this.apply);
  final String pattern; // RegExp (case-insensitive) روی برچسب خط
  final void Function(String value, Map<String, Object?> out) apply;
  bool matches(String label) => RegExp(pattern, caseSensitive: false).hasMatch(label);
}

/// پارامتر اندازه برای تخمین (قیمت ∝ اندازه^n).
class SizeDriver {
  const SizeDriver(this.labelFa, this.unit, this.n, this.compute);
  final String labelFa;
  final String unit;
  final double n;
  final double? Function(Map<String, Object?> v) compute;
}

class EquipmentProfile {
  const EquipmentProfile({
    required this.code,
    required this.fields,
    required this.rules,
    required this.driver,
    this.typeKey,
    this.gridKeys = const [],
    this.rangeKeys = const [],
    this.factorGroups = const ['MAT', 'NACE'],
    this.inferType,
    this.weightKey,
    this.factorSeeds,
    this.filterKeys,
  });
  final String code;
  final List<ProfileField> fields;
  final List<MtoRule> rules;
  final SizeDriver driver;

  /// فیلد «نوع» برای همتایابی هم‌نوع (مثلاً جهت نصب ظرف یا نوع مبدل)
  final String? typeKey;
  final List<String> gridKeys;
  final List<String> rangeKeys;
  final List<String> factorGroups;

  /// فیلد وزن خالی (ظرف‌ها و مخازن): اگر پر باشد، «ضریب وزن» در تخمین اعمال می‌شود؛ خالی = بی‌اثر.
  final String? weightKey;

  /// ضرایب اولیه‌ی اختصاصی رده (null = ضرایب مشترک [profileFactorSeeds])
  final List<(String, String, double, String)>? factorSeeds;

  /// استنباط فیلدها از نام/عنوان شیت (مثلاً «Burn Pit» ← نوع فلر)
  final void Function(String nameAndTitle, Map<String, Object?> out)? inferType;

  ProfileField? field(String key) => fields.where((f) => f.key == key).firstOrNull;

  /// فیلترهای صفحه‌ی تجهیزات (null = همه‌ی فیلدهای انتخابی)؛ مثل پمپ فقط مشخصاتی که در انتخاب تجهیز مؤثرند.
  final List<String>? filterKeys;

  /// فیلدهای انتخابی (برای فیلتر)
  List<ProfileField> get enumFields => filterKeys == null
      ? fields.where((f) => f.type == 'enum').toList()
      : [for (final k in filterKeys!) if (field(k) case final f? when f.type == 'enum') f];

  /// برچسب MTO به یکی از قواعد این قالب می‌خورد؟
  bool maps(String label) => rules.any((r) => r.matches(label));

  /// استخراج فیلدهای ساختاریافته از مشخصات «کلید: مقدار».
  Map<String, Object?> extract(Map<String, String> specs, {String context = '', List<String> scope = const []}) {
    final out = <String, Object?>{};
    for (final e in specs.entries) {
      for (final r in rules) {
        if (r.matches(e.key)) {
          r.apply(e.value, out);
          break;
        }
      }
    }
    if (scope.isNotEmpty && field('scope') != null) out['scope'] = scope.join(' ');
    inferType?.call(context, out);
    out.removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));
    return out;
  }

  double? sizeOf(Map<String, Object?> v) {
    final s = driver.compute(v);
    return (s == null || s.isNaN || s <= 0) ? null : s;
  }
}

// -----------------------------------------------------------------------------
// ابزار استخراج

final _numRe = RegExp(r'-?\d+(?:\.\d+)?');
List<double> _nums(String s) => [for (final m in _numRe.allMatches(s.replaceAll(',', ''))) double.parse(m.group(0)!)];

double? _num(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

MtoRule _text(String p, String key) => MtoRule(p, (v, o) => o[key] ??= v.trim());
MtoRule _numAt(String p, String key, [int i = 0, double scale = 1]) => MtoRule(p, (v, o) {
      final n = _nums(v);
      if (n.length > i) o[key] ??= n[i] * scale;
    });
MtoRule _yn(String p, String key) => MtoRule(p, (v, o) {
      final l = v.toLowerCase();
      o[key] ??= l.startsWith('y') ? 'Y' : (l.startsWith('n') ? 'N' : null);
    });

/// «2300 x 6900 mm» ← دو بُعد بر حسب میلی‌متر (اگر واحد متر باشد ضربدر ۱۰۰۰)
MtoRule _dims(String p, String k1, String k2) => MtoRule(p, (v, o) {
      final n = _nums(v);
      final l = v.toLowerCase();
      final scale = (l.contains('mm') || !RegExp(r'\bm\b').hasMatch(l)) ? 1.0 : 1000.0;
      if (n.isNotEmpty) o[k1] ??= n[0] * scale;
      if (n.length > 1) o[k2] ??= n[1] * scale;
    });

/// فشار طراحی: بیشینه‌ی اعداد، kPa ← bar، «F.V.» ← خلأ کامل
MtoRule _pressure(String p, {String key = 'design_pressure_barg', String? vacKey = 'full_vacuum'}) => MtoRule(p, (v, o) {
      final l = v.toLowerCase();
      var n = _nums(v);
      if (n.isEmpty) return;
      final kpa = l.contains('kpa');
      n = [for (final x in n) kpa ? x / 100 : x];
      o[key] ??= n.reduce(math.max);
      if (vacKey != null && (l.contains('f.v') || l.contains('full vac') || n.any((x) => x <= -0.9))) o[vacKey] ??= 'Y';
      o['${key}_text'] ??= v.trim();
    });

/// «-2.8 / 85 oC» ← کمینه و بیشینه‌ی دمای طراحی
MtoRule _temps(String p, {String minKey = 'design_temp_min_c', String maxKey = 'design_temp_max_c'}) => MtoRule(p, (v, o) {
      final n = _nums(v);
      if (n.isEmpty) return;
      if (n.length == 1) {
        o[maxKey] ??= n[0];
      } else {
        o[minKey] ??= n.reduce(math.min);
        o[maxKey] ??= n.reduce(math.max);
      }
    });

/// جنس (متن) + کلاس جنس (انتخابی)
MtoRule _material(String p, String textKey, {String classKey = 'material_class'}) => MtoRule(p, (v, o) {
      o[textKey] ??= v.trim();
      o[classKey] ??= materialClassOf(v);
    });

/// کلاس جنس از متن جنس.
String materialClassOf(String text) {
  final l = text.toLowerCase();
  if (l.contains('super duplex')) return 'Super Duplex';
  if (l.contains('duplex')) return 'Duplex';
  if (l.contains('titan')) return 'Titanium';
  if (l.contains('316')) return 'SS316';
  if (l.contains('304') || l.contains('s.s') || l.contains('stainless')) return 'SS304';
  if (l.contains('333') || l.contains('lt') && l.contains('cs') || l.contains('low temp')) return 'LTCS';
  if (l.contains('516') || l.contains('283') || l.contains('106') || l.contains('285') || l.contains('c.s') ||
      l.contains('carbon') || RegExp(r'\bcs\b').hasMatch(l)) {
    return 'CS';
  }
  return 'Other';
}

const _code = MtoRule(r'design codes?\s*(&|and)\s*standards?', _codeApply);
void _codeApply(String v, Map<String, Object?> o) => o['design_code'] ??= v.trim();
final _nace = _yn(r"nace", 'nace');

double? _cyl(Map<String, Object?> v, String d, String l, {bool heads = true}) {
  final dm = _num(v[d]), lm = _num(v[l]);
  if (dm == null || lm == null) return null;
  final dd = dm / 1000, ll = lm / 1000;
  final shell = math.pi / 4 * dd * dd * ll;
  return heads ? shell + math.pi * dd * dd * dd / 12 : shell; // دو عدسی بیضوی ۲:۱
}

// -----------------------------------------------------------------------------
// فیلدهای مشترک

const _fMat = ProfileField('material_class', 'کلاس جنس', 'material', type: 'enum', list: 'G_MAT',
    help: 'برای ضریب نرمال‌سازی جنس؛ از متن جنس خودکار تشخیص داده می‌شود.');
const _fNace = ProfileField('nace', 'الزام NACE MR-0175', 'material', type: 'enum', list: 'YNS');
const _fCode = ProfileField('design_code', 'کد و استاندارد طراحی', 'material');
const _fPress = ProfileField('design_pressure_barg', 'فشار طراحی', 'design', type: 'number', unit: 'barg',
    help: 'بیشینه‌ی فشار طراحی؛ kPa به bar تبدیل شده است.');
const _fPressText = ProfileField('design_pressure_barg_text', 'فشار طراحی (متن منبع)', 'design');
const _fVac = ProfileField('full_vacuum', 'خلأ کامل (F.V.)', 'design', type: 'enum', list: 'YNS');
const _fTmin = ProfileField('design_temp_min_c', 'دمای طراحی کمینه', 'design', type: 'number', unit: '°C');
const _fTmax = ProfileField('design_temp_max_c', 'دمای طراحی بیشینه', 'design', type: 'number', unit: '°C');
const _fScope = ProfileField('scope', 'دامنه‌ی تأمین (از شرح)', 'scope');
const weightFieldKey = 'empty_weight_kg';
const _fWeight = ProfileField(weightFieldKey, 'وزن خالی (ساخت)', 'key_specs', type: 'number', unit: 'kg',
    help: 'وزن خالی/ساخت از دیتاشیت سازنده (Empty / Fabricated weight). اختیاری: تا خالی است در محاسبات بی‌اثر است؛ '
        'وقتی برای این قلم و دست‌کم یک قلم دیگر همین رده وارد شود، «ضریب وزن» در تخمین و نرمال‌سازی اعمال می‌شود '
        'و جای ضریب فشار را می‌گیرد.');

/// «Empty Weight: 12.5 ton» ← کیلوگرم (وزن عملیاتی/آزمون آبی نادیده گرفته می‌شود)
final _weight = MtoRule(r'^(empty|fabricat\w*|erection|shipping|dry)?\s*weight', (v, o) {
  final n = _nums(v);
  if (n.isEmpty) return;
  final l = v.toLowerCase();
  final ton = RegExp(r'\bt\b|ton').hasMatch(l) && !l.contains('kg');
  o[weightFieldKey] ??= n.first * (ton ? 1000 : 1);
});

final _common = <MtoRule>[_code, _nace];

// -----------------------------------------------------------------------------
// قالب‌ها

final equipmentProfiles = <String, EquipmentProfile>{
  'VESSEL': EquipmentProfile(
    code: 'VESSEL',
    fields: const [
      ProfileField('orientation', 'جهت نصب', 'key_specs', type: 'enum', list: 'G_ORIENT'),
      ProfileField('id_mm', 'قطر داخلی (ID)', 'key_specs', type: 'number', unit: 'mm'),
      ProfileField('tl_mm', 'طول TL-TL', 'key_specs', type: 'number', unit: 'mm'),
      _fWeight,
      _fPress, _fPressText, _fVac, _fTmin, _fTmax,
      ProfileField('shell_material', 'جنس پوسته/عدسی', 'material'),
      _fMat, _fNace, _fCode, _fScope,
    ],
    rules: [
      _dims(r'^size|^dimension|^dim\b', 'id_mm', 'tl_mm'),
      MtoRule(r'installation|position|orientation', (v, o) {
        final l = v.toLowerCase();
        o['orientation'] ??= l.startsWith('h') ? 'Horizontal' : (l.startsWith('v') ? 'Vertical' : null);
      }),
      _pressure(r'design press|press\w*\.? design'),
      _temps(r'design temp|temp\w*\.? design'),
      _material(r'^mat', 'shell_material'),
      _weight,
      ..._common,
    ],
    weightKey: weightFieldKey,
    driver: SizeDriver('حجم ظرف', 'm³', 0.6, (v) => _cyl(v, 'id_mm', 'tl_mm')),
    typeKey: 'orientation',
    gridKeys: ['orientation', 'id_mm', 'tl_mm', 'design_pressure_barg', 'material_class', weightFieldKey],
    rangeKeys: ['design_pressure_barg', weightFieldKey],
    factorGroups: const ['MAT', 'NACE', 'PRESS'],
  ),
  'TANK': EquipmentProfile(
    code: 'TANK',
    fields: const [
      ProfileField('diameter_mm', 'قطر', 'key_specs', type: 'number', unit: 'mm'),
      ProfileField('height_mm', 'ارتفاع', 'key_specs', type: 'number', unit: 'mm'),
      _fWeight,
      ProfileField('roof_type', 'نوع سقف', 'key_specs', type: 'enum', list: 'G_ROOF'),
      _fPress, _fPressText, _fVac, _fTmin, _fTmax,
      ProfileField('shell_material', 'جنس پوسته/کف/سقف', 'material'),
      _fMat, _fNace, _fCode, _fScope,
    ],
    rules: [
      _dims(r'^size|^dimension|^dim\b', 'diameter_mm', 'height_mm'),
      MtoRule(r'^roof', (v, o) {
        final l = v.toLowerCase();
        o['roof_type'] ??= l.contains('dome')
            ? 'Dome'
            : (l.contains('cone') ? 'Cone' : (l.contains('float') ? 'Floating' : 'Other'));
      }),
      _pressure(r'design press|press\w*\.? design'),
      _temps(r'design temp|temp\w*\.? design'),
      _material(r'^mat', 'shell_material'),
      _weight,
      ..._common,
    ],
    weightKey: weightFieldKey,
    driver: SizeDriver('حجم مخزن', 'm³', 0.6, (v) => _cyl(v, 'diameter_mm', 'height_mm', heads: false)),
    typeKey: 'roof_type',
    gridKeys: ['diameter_mm', 'height_mm', 'roof_type', 'material_class', weightFieldKey],
    rangeKeys: [weightFieldKey],
  ),
  'HEX': EquipmentProfile(
    code: 'HEX',
    fields: const [
      ProfileField('hex_type', 'نوع مبدل', 'key_specs', type: 'enum', list: 'G_HEX'),
      ProfileField('duty_kw', 'حرارت مبادله‌شده', 'key_specs', type: 'number', unit: 'kW'),
      ProfileField('duty_case', 'حالت طراحی حرارت', 'key_specs'),
      _fPress, _fPressText, _fTmin, _fTmax,
      ProfileField('plate_material', 'جنس صفحه/لوله', 'material'),
      ProfileField('gasket_material', 'جنس گسکت', 'material'),
      _fMat, _fNace, _fCode, _fScope,
    ],
    rules: [
      MtoRule(r'heat exchanged|duty', (v, o) {
        final n = _nums(v);
        if (n.isNotEmpty) o['duty_kw'] ??= n.first * (v.toLowerCase().contains('mw') ? 1000 : 1);
        final c = RegExp(r'\(([^)]*)\)').firstMatch(v);
        if (c != null) o['duty_case'] ??= c.group(1);
      }),
      MtoRule(r'^type', (v, o) {
        final l = v.toLowerCase();
        o['hex_type'] ??= l.contains('plate')
            ? 'Plate & Frame'
            : (l.contains('air') ? 'Air Cooler' : (l.contains('shell') || l.contains('tube') ? 'Shell & Tube' : null));
      }),
      _pressure(r'design press|press\w*\.? design', vacKey: null),
      _temps(r'design temp|temp\w*\.? design'),
      MtoRule(r'^mat', (v, o) {
        final parts = v.split('/').map((e) => e.trim()).toList();
        o['plate_material'] ??= parts.first;
        if (parts.length > 1) o['gasket_material'] ??= parts[1];
        o['material_class'] ??= materialClassOf(parts.first);
      }),
      ..._common,
    ],
    driver: SizeDriver('حرارت مبادله‌شده', 'kW', 0.6, (v) => _num(v['duty_kw'])),
    typeKey: 'hex_type',
    gridKeys: ['hex_type', 'duty_kw', 'material_class'],
    rangeKeys: ['design_pressure_barg'],
    inferType: (ctx, o) {
      final l = ctx.toLowerCase();
      o['hex_type'] ??= l.contains('plate')
          ? 'Plate & Frame'
          : (l.contains('air cool') ? 'Air Cooler' : (l.contains('shell') ? 'Shell & Tube' : null));
    },
  ),
  'HEATER': EquipmentProfile(
    code: 'HEATER',
    fields: const [
      ProfileField('duty_kw', 'حرارت نامی', 'key_specs', type: 'number', unit: 'kW'),
      ProfileField('shell_id_mm', 'قطر پوسته', 'key_specs', type: 'number', unit: 'mm'),
      ProfileField('shell_tl_mm', 'طول پوسته TL-TL', 'key_specs', type: 'number', unit: 'mm'),
      ProfileField('design_pressure_shell_barg', 'فشار طراحی پوسته', 'design', type: 'number', unit: 'barg'),
      ProfileField('design_pressure_coil_barg', 'فشار طراحی کویل', 'design', type: 'number', unit: 'barg'),
      _fPress, _fTmin, _fTmax,
      ProfileField('shell_material', 'جنس پوسته/عدسی', 'material'),
      ProfileField('coil_material', 'جنس کویل', 'material'),
      _fMat, _fNace, _fCode, _fScope,
    ],
    rules: [
      MtoRule(r'heat exchanged|duty', (v, o) {
        final n = _nums(v);
        if (n.isNotEmpty) o['duty_kw'] ??= n.first * (v.toLowerCase().contains('mw') ? 1000 : 1);
      }),
      _dims(r'shell dim|^size|^dimension|^dim\b', 'shell_id_mm', 'shell_tl_mm'),
      MtoRule(r'design press|press\w*\.? design', (v, o) {
        final n = _nums(v);
        if (n.isEmpty) return;
        if (n.length >= 2) {
          final l = v.toLowerCase();
          final coilFirst = RegExp(r'^\W*(tube|coil)').hasMatch(l);
          o['design_pressure_shell_barg'] ??= coilFirst ? n[1] : n[0];
          o['design_pressure_coil_barg'] ??= coilFirst ? n[0] : n[1];
        }
        o['design_pressure_barg'] ??= n.reduce(math.max);
      }),
      _temps(r'design temp|temp\w*\.? design'),
      _material(r'mat.*coil', 'coil_material', classKey: '_coil_class'),
      _material(r'^mat', 'shell_material'),
      ..._common,
    ],
    driver: SizeDriver('حرارت نامی', 'kW', 0.8, (v) => _num(v['duty_kw'])),
    gridKeys: ['duty_kw', 'shell_id_mm', 'design_pressure_coil_barg', 'material_class'],
    rangeKeys: ['design_pressure_barg'],
    factorGroups: const ['MAT', 'NACE', 'PRESS'],
  ),
  'DESALTER': EquipmentProfile(
    code: 'DESALTER',
    fields: const [
      ProfileField('sub_category', 'زیرگروه', 'key_specs', type: 'enum', list: 'DES_SUBCAT'),
      ProfileField('desalting_technology', 'فناوری دیسالتر', 'key_specs', type: 'enum', list: 'DES_TECH',
          help: 'برای ضریب فناوری (TECH)؛ از شرح «Type:» منبع خودکار تشخیص داده می‌شود.'),
      ProfileField('desalter_type', 'نوع (متن منبع)', 'key_specs'),
      ProfileField('vessel_tag', 'تگ ظرف دیسالتر', 'key_specs'),
      ProfileField('vessel_id_mm', 'قطر داخلی ظرف', 'key_specs', type: 'number', unit: 'mm'),
      ProfileField('vessel_tl_mm', 'طول TL-TL ظرف', 'key_specs', type: 'number', unit: 'mm'),
      ProfileField('vessels_per_package', 'تعداد وسل در پکیج', 'key_specs', type: 'number',
          help: 'حجم کل پوسته = π/4 × ID² × T/T × تعداد وسل (مبنای روش B تخمین).'),
      ProfileField('trains_per_package', 'تعداد ترین در پکیج', 'key_specs', type: 'number'),
      ProfileField('no_of_stages', 'تعداد مرحله', 'key_specs', type: 'enum', list: 'DES_STAGE',
          help: 'ضریب مرحله (STAGE) فقط در روش ظرفیت‌محور (A) به کار می‌رود.'),
      ProfileField('capacity_bpd', 'ظرفیت کل پکیج', 'key_specs', type: 'number', unit: 'BPD',
          help: 'ظرفیت کل نفت ورودی پکیج (بشکه در روز)؛ ۱ m³/h = ۱۵۰٫۹۶ BPD. مبنای روش A تخمین.'),
      ProfileField('capacity_basis', 'مبنای ظرفیت (متن منبع)', 'key_specs'),
      _fWeight,
      _fPress, _fPressText, _fTmin, _fTmax,
      ProfileField('shell_material', 'جنس ظرف (متن منبع)', 'material'),
      ProfileField('des_material', 'متریال بدنه (ضریب)', 'material', type: 'enum', list: 'DES_MAT',
          help: 'برای ضریب متریال (MAT)؛ از متن جنس خودکار تشخیص داده می‌شود.'),
      _fNace,
      ProfileField('vessel_design_code', 'کد طراحی وسل', 'material', type: 'enum', list: 'DES_VSTD'),
      ProfileField('ips_standard', 'استاندارد IPS', 'material', type: 'enum', list: 'DES_IPS'),
      _fCode,
      ProfileField('n_transformers', 'تعداد ترانس', 'package', type: 'number', help: 'عدد اول در «3 x 50%».'),
      ProfileField('transformer_sizing', 'ظرفیت هر ترانس (کسر از توان لازم)', 'package', type: 'number',
          help: 'عدد دوم در «3 x 50%» به صورت کسر: 0.5'),
      ProfileField('kva_per_transformer', 'kVA هر ترانس', 'package', type: 'number', unit: 'kVA',
          help: 'در هیچ منبعی نیامده؛ از دیتاشیت سازنده وارد کنید. توان لازم = kVA ÷ کسر ظرفیت (محرک kVA، فعلاً خاموش).'),
      ProfileField('recycle_pumps', 'پمپ‌های Recycle (متن منبع)', 'package'),
      ProfileField('pumps_tag', 'تگ پمپ‌های گردشی', 'package'),
      ProfileField('pump_type', 'نوع پمپ‌ها', 'package'),
      ProfileField('pump_flow_m3h', 'دبی نامی پمپ', 'package', type: 'number', unit: 'm³/h'),
      ProfileField('pump_dp_bar', 'اختلاف فشار پمپ', 'package', type: 'number', unit: 'bar'),
      ProfileField('pump_material_class', 'کلاس متریال پمپ (API 610)', 'package'),
      ProfileField('pump_code', 'کد پمپ‌ها', 'package'),
      _fScope,
      // Scope (ترانس، پمپ Recycle، لوله‌کشی، ابزار دقیق، گمرک و حمل) و مرحله‌ی پروژه مشخصه‌ی تجهیز نیستند و
      // در منابع یا نیامده‌اند یا برای همه یکسان‌اند؛ فقط در «تخمین تجهیزات» به عنوان ضریب قیمت انتخاب می‌شوند.
      ProfileField('manufacturer', 'سازنده / پیشنهاددهنده (متن منبع)', 'source'),
      ProfileField('source_document', 'سند منبع (فایل، شیت، سلول)', 'source'),
    ],
    rules: [
      _text(r'^type', 'desalter_type'),
      _text(r'vessel tag', 'vessel_tag'),
      _dims(r'dim|size', 'vessel_id_mm', 'vessel_tl_mm'),
      _pressure(r'design press|press\w*\.? design', vacKey: null),
      _temps(r'design temp|temp\w*\.? design'),
      _text(r'pumps? tag', 'pumps_tag'),
      _text(r'pumps? type', 'pump_type'),
      _numAt(r'pumps? rated flow', 'pump_flow_m3h'),
      _numAt(r'pumps? diff', 'pump_dp_bar'),
      _text(r'pumps? mat', 'pump_material_class'),
      _text(r'pumps? design code', 'pump_code'),
      _material(r'^vessels? mat|^mat', 'shell_material'),
      _weight,
      ..._common,
    ],
    inferType: inferDesalter,
    typeKey: 'sub_category',
    driver: SizeDriver('حجم کل پوسته‌ی وسل‌ها', 'm³', 0.6, desalterShellVolume),
    gridKeys: ['capacity_bpd', 'vessel_id_mm', 'vessel_tl_mm', 'vessels_per_package', 'desalting_technology', 'no_of_stages'],
    rangeKeys: ['capacity_bpd', 'design_pressure_barg'],
    filterKeys: ['sub_category', 'desalting_technology', 'no_of_stages', 'des_material', 'nace'],
    factorGroups: desalterFactorGroups,
    factorSeeds: desalterFactorSeeds,
  ),
  'CIP': EquipmentProfile(
    code: 'CIP',
    fields: const [
      ProfileField('chemical', 'ماده‌ی شیمیایی', 'key_specs'),
      ProfileField('injection_rate_lph', 'حداکثر نرخ تزریق', 'key_specs', type: 'number', unit: 'L/h'),
      ProfileField('discharge_pressure_barg', 'حداکثر فشار رانش', 'key_specs', type: 'number', unit: 'barg'),
      ProfileField('pumps_qty', 'تعداد پمپ', 'package', type: 'number'),
      ProfileField('pump_material', 'جنس پمپ', 'package'),
      ProfileField('pump_standard', 'استاندارد پمپ', 'package'),
      ProfileField('tank_capacity_m3', 'حجم مخزن', 'package', type: 'number', unit: 'm³'),
      ProfileField('tank_design_pressure_barg', 'فشار طراحی مخزن', 'package', type: 'number', unit: 'barg'),
      _fTmin, _fTmax,
      ProfileField('tank_material', 'جنس مخزن', 'package'),
      ProfileField('agitator', 'همزن', 'package', type: 'enum', list: 'YNS'),
      _fMat, _fNace, _fCode, _fScope,
    ],
    rules: [
      _numAt(r'injection rate', 'injection_rate_lph'),
      _numAt(r'discharge press', 'discharge_pressure_barg'),
      _numAt(r'pumps? qty', 'pumps_qty'),
      _material(r'pumps? mat', 'pump_material'),
      _text(r'pumps? design code', 'pump_standard'),
      _numAt(r'tank capacity', 'tank_capacity_m3'),
      _numAt(r'tank design press', 'tank_design_pressure_barg'),
      _temps(r'tank design temp|design temp|temp\w*\.? design'),
      _text(r'tank mat', 'tank_material'),
      _yn(r'agitator', 'agitator'),
      ..._common,
    ],
    driver: SizeDriver('نرخ تزریق', 'L/h', 0.3, (v) => _num(v['injection_rate_lph'])),
    typeKey: 'chemical',
    gridKeys: ['chemical', 'injection_rate_lph', 'pumps_qty', 'tank_capacity_m3', 'material_class'],
    rangeKeys: ['tank_capacity_m3'],
    inferType: (ctx, o) {
      final n = ctx.split('\n').first;
      final m = RegExp(r'^(.*?)\s+Injection', caseSensitive: false).firstMatch(n);
      if (m != null) o['chemical'] ??= m.group(1)!.trim();
    },
  ),
  'DEAERATOR': EquipmentProfile(
    code: 'DEAERATOR',
    fields: const [
      ProfileField('flow_m3h', 'حداکثر دبی', 'key_specs', type: 'number', unit: 'm³/h'),
      ProfileField('tower_tag', 'تگ برج', 'key_specs'),
      ProfileField('internals', 'نوع داخلی‌ها', 'key_specs'),
      _fWeight,
      _fPress, _fPressText, _fVac, _fTmin, _fTmax,
      ProfileField('shell_material', 'جنس پوسته/عدسی', 'material'),
      ProfileField('internals_material', 'جنس داخلی‌های جداشدنی', 'material'),
      _fMat, _fNace, _fCode, _fScope,
    ],
    rules: [
      _numAt(r'flow', 'flow_m3h'),
      _text(r'tower tag', 'tower_tag'),
      _text(r'^internals$', 'internals'),
      _pressure(r'design press|press\w*\.? design'),
      _temps(r'design temp|temp\w*\.? design'),
      _text(r'remov', 'internals_material'),
      _material(r'^mat', 'shell_material'),
      _weight,
      ..._common,
    ],
    weightKey: weightFieldKey,
    driver: SizeDriver('دبی', 'm³/h', 0.6, (v) => _num(v['flow_m3h'])),
    gridKeys: ['flow_m3h', 'internals', 'material_class'],
    rangeKeys: [],
    factorGroups: const ['MAT', 'NACE', 'PRESS'],
  ),
  'IGF': EquipmentProfile(
    code: 'IGF',
    fields: const [
      ProfileField('flow_m3h', 'دبی طراحی', 'key_specs', type: 'number', unit: 'm³/h'),
      _fWeight,
      _fPress, _fPressText, _fVac, _fTmin, _fTmax,
      ProfileField('shell_material', 'جنس ظرف', 'material'),
      ProfileField('internals_material', 'جنس داخلی‌های جداشدنی', 'material'),
      _fMat, _fNace, _fCode, _fScope,
    ],
    rules: [
      _numAt(r'design flow|flow rate', 'flow_m3h'),
      _pressure(r'design press|press\w*\.? design'),
      _temps(r'design temp|temp\w*\.? design'),
      _text(r'remov', 'internals_material'),
      _material(r'^vessel mat|^mat', 'shell_material'),
      MtoRule(r'vessel design codes?', _codeApply),
      _weight,
      ..._common,
    ],
    weightKey: weightFieldKey,
    driver: SizeDriver('دبی طراحی', 'm³/h', 0.6, (v) => _num(v['flow_m3h'])),
    gridKeys: ['flow_m3h', 'internals_material', 'material_class'],
    rangeKeys: [],
    factorGroups: const ['MAT', 'NACE', 'PRESS'],
  ),
  'FILTER': EquipmentProfile(
    code: 'FILTER',
    fields: const [
      ProfileField('filter_type', 'نوع فیلتر', 'key_specs'),
      ProfileField('vessels_config', 'تعداد/آرایش ظروف', 'key_specs'),
      ProfileField('flow_m3h', 'دبی (معادل آب)', 'key_specs', type: 'number', unit: 'm³/h',
          help: 'دبی جرمی kg/h با چگالی آب به m³/h تبدیل شده است.'),
      ProfileField('flow_kgh', 'دبی جرمی', 'key_specs', type: 'number', unit: 'kg/h'),
      ProfileField('outlet_oil_ppm', 'روغن آزاد خروجی', 'key_specs', type: 'number', unit: 'ppmw'),
      _fWeight,
      _fPress, _fPressText, _fTmin, _fTmax,
      ProfileField('shell_material', 'جنس پوسته/عدسی', 'material'),
      ProfileField('internals_material', 'جنس اجزای داخلی', 'material'),
      ProfileField('agitator', 'همزن', 'package', type: 'enum', list: 'YNS'),
      _fMat, _fNace, _fCode, _fScope,
    ],
    rules: [
      _text(r'^type', 'filter_type'),
      _text(r'^including', 'vessels_config'),
      MtoRule(r'flow', (v, o) {
        final n = _nums(v);
        if (n.isEmpty) return;
        if (v.toLowerCase().contains('kg') || RegExp('kg', caseSensitive: false).hasMatch(v)) {
          o['flow_kgh'] ??= n.first;
          o['flow_m3h'] ??= n.first / 1000;
        } else {
          o['flow_m3h'] ??= n.first;
        }
      }),
      _numAt(r'oil content', 'outlet_oil_ppm'),
      _pressure(r'design press|press\w*\.? design', vacKey: null),
      _temps(r'design temp|temp\w*\.? design'),
      _text(r'internal', 'internals_material'),
      _yn(r'agitator', 'agitator'),
      _material(r'^mat', 'shell_material'),
      _weight,
      ..._common,
    ],
    weightKey: weightFieldKey,
    driver: SizeDriver('دبی', 'm³/h', 0.6, (v) => _num(v['flow_m3h'])),
    typeKey: 'filter_type',
    gridKeys: ['filter_type', 'flow_m3h', 'material_class'],
    rangeKeys: [],
    factorGroups: const ['MAT', 'NACE', 'PRESS'],
  ),
  'FLARE': EquipmentProfile(
    code: 'FLARE',
    fields: const [
      ProfileField('flare_type', 'نوع', 'key_specs', type: 'enum', list: 'G_FLARE'),
      ProfileField('capacity_kgh', 'ظرفیت کل', 'key_specs', type: 'number', unit: 'kg/h'),
      ProfileField('ignition_type', 'سیستم جرقه‌زنی', 'key_specs'),
      ProfileField('stack_diameter_in', 'قطر استک', 'key_specs', type: 'number', unit: 'in'),
      ProfileField('stack_height_m', 'ارتفاع استک', 'key_specs', type: 'number', unit: 'm'),
      ProfileField('stack_support', 'نوع نگهداری استک', 'key_specs'),
      ProfileField('burn_pit_diameter_m', 'قطر Burn Pit', 'key_specs', type: 'number', unit: 'm'),
      ProfileField('electrical_kw', 'توان برق', 'design', type: 'number', unit: 'kW'),
      ProfileField('elect_protection', 'حداقل حفاظت تجهیزات برقی', 'design'),
      _fCode, _fScope,
    ],
    rules: [
      _numAt(r'capacity', 'capacity_kgh'),
      _text(r'ignition', 'ignition_type'),
      MtoRule(r'stack size', (v, o) {
        final n = _nums(v);
        if (n.isNotEmpty) o['stack_diameter_in'] ??= n[0];
        if (n.length > 1) o['stack_height_m'] ??= n[1];
      }),
      MtoRule(r'(stack|tip).*diam', (v, o) {
        final n = _nums(v);
        if (n.isNotEmpty) o['stack_diameter_in'] ??= n.first * (v.toLowerCase().contains('mm') ? 1 / 25.4 : 1);
      }),
      MtoRule(r'(stack|flare).*height', (v, o) {
        final n = _nums(v);
        if (n.isNotEmpty) o['stack_height_m'] ??= n.first / (v.toLowerCase().contains('mm') ? 1000 : 1);
      }),
      _text(r'support', 'stack_support'),
      _numAt(r'burn pit diam', 'burn_pit_diameter_m'),
      _numAt(r'electrical duty', 'electrical_kw'),
      _text(r'protection', 'elect_protection'),
      _code,
    ],
    driver: SizeDriver('ظرفیت', 'kg/h', 0.5, (v) => _num(v['capacity_kgh'])),
    typeKey: 'flare_type',
    gridKeys: ['flare_type', 'capacity_kgh', 'stack_height_m'],
    rangeKeys: [],
    factorGroups: const ['NACE'],
    inferType: (ctx, o) => o['flare_type'] ??= ctx.toLowerCase().contains('burn pit') ? 'Burn Pit' : 'Flare',
  ),
  'COMPRESSOR': EquipmentProfile(
    code: 'COMPRESSOR',
    fields: const [
      ProfileField('sub_category', 'زیرگروه', 'key_specs', type: 'enum', list: 'CMP_SUBCAT',
          help: 'CMP-PKG = پکیج کمپرسور؛ CMP-IAP = پکیج کامل هوای ابزار دقیق (کمپرسورها + خشک‌کن + فیلتر + مخزن در یک قیمت)؛ '
              'CMP-CMB = یکجا با پکیج دیگر (فقط مرجع).'),
      ProfileField('compressor_type', 'نوع کمپرسور (ضریب)', 'key_specs', type: 'enum', list: 'CMP_TYPE',
          help: 'برای ضریب نوع (TYPE)؛ روغن‌کاری در نوع ادغام شده است.'),
      ProfileField('comp_type', 'نوع کمپرسور (متن MTO)', 'key_specs', type: 'enum', list: 'G_COMP'),
      ProfileField('lubrication', 'روغن‌کاری (متن MTO)', 'key_specs', type: 'enum', list: 'G_LUBE'),
      ProfileField('flow_m3h', 'دبی هر کمپرسور', 'key_specs', type: 'number', unit: 'Nm³/h',
          help: 'ظرفیت هر کمپرسور، نه کل پکیج (m³/h، Nm³/h و Sm³/h هم‌ارز). مبنای روش A تخمین.'),
      ProfileField('discharge_pressure_barg', 'فشار رانش', 'key_specs', type: 'number', unit: 'barg'),
      ProfileField('flow_basis', 'مبنای دبی (متن منبع)', 'key_specs'),
      ProfileField('configuration', 'آرایش', 'key_specs'),
      ProfileField('driver', 'محرک', 'key_specs', type: 'enum', list: 'CMP_DRV'),
      ProfileField('compressors_per_price_unit', 'تعداد کمپرسور در هر واحد قیمت', 'key_specs', type: 'number',
          help: 'پکیج کمپرسور = ۱؛ پکیج کامل ۲×۱۰۰٪ = ۲. قیمت بر این عدد تقسیم می‌شود (قیمت هر کمپرسور).'),
      ProfileField('unit_weight_kg', 'وزن هر کمپرسور', 'key_specs', type: 'number', unit: 'kg',
          help: 'مبنای روش B تخمین (یورو بر کیلوگرم).'),
      ProfileField('weight_basis', 'مبنای وزن (متن منبع)', 'key_specs'),
      ProfileField('pressure_dew_point_c', 'نقطه‌ی شبنم', 'key_specs', type: 'number', unit: '°C'),
      ProfileField('design_standard', 'استاندارد کمپرسور', 'material', type: 'enum', list: 'CMP_STD'),
      ProfileField('ips_standard', 'استاندارد IPS', 'material', type: 'enum', list: 'CMP_IPS'),
      _fCode,
      _fScope,
      ProfileField('scope_dryer', 'Scope: خشک‌کن هوا', 'scope', type: 'enum', list: 'YNS', help: 'پایه = خیر'),
      ProfileField('scope_receiver', 'Scope: مخزن هوا', 'scope', type: 'enum', list: 'YNS', help: 'پایه = خیر'),
      ProfileField('scope_filters', 'Scope: فیلترهای Pre/After', 'scope', type: 'enum', list: 'YNS', help: 'پایه = خیر'),
      ProfileField('scope_coolers', 'Scope: کولر میانی و انتهایی', 'scope', type: 'enum', list: 'YNS', help: 'پایه = بله'),
      ProfileField('scope_control_panel', 'Scope: پنل کنترل محلی', 'scope', type: 'enum', list: 'YNS', help: 'پایه = بله'),
      ProfileField('scope_spares', 'Scope: قطعات یدکی', 'scope', type: 'enum', list: 'YNS', help: 'پایه = خیر'),
      ProfileField('scope_vendor_services', 'Scope: خدمات سازنده در سایت', 'scope', type: 'enum', list: 'YNS', help: 'پایه = خیر'),
      ProfileField('scope_transport', 'Scope: حمل تا سایت', 'scope', type: 'enum', list: 'YNS', help: 'پایه = خیر'),
      ProfileField('supply_origin', 'مبدأ ساخت', 'source', type: 'enum', list: 'CMP_ORIGIN'),
      ProfileField('project_phase', 'مرحله‌ی پروژه', 'source', type: 'enum', list: 'Phase'),
      ProfileField('manufacturer', 'سازنده / پیشنهاددهنده (متن منبع)', 'source'),
      ProfileField('use_as_peer', 'همتای تخمین', 'source', type: 'enum', list: 'YN',
          help: 'N = در تخمین به کار نمی‌رود (مثلاً داده‌ی پرت)؛ قلم همچنان در بانک می‌ماند.'),
      ProfileField('source_document', 'سند منبع (فایل، شیت، سلول)', 'source'),
    ],
    rules: [
      MtoRule(r'^type', (v, o) {
        final l = v.toLowerCase();
        o['comp_type'] ??= l.contains('recip')
            ? 'Reciprocating'
            : (l.contains('screw') ? 'Screw' : (l.contains('centrif') ? 'Centrifugal' : 'Other'));
        o['lubrication'] ??= (l.contains('non-lub') || l.contains('oil-free') || l.contains('oil free'))
            ? 'Oil-free'
            : (l.contains('lub') ? 'Lubricated' : null);
      }),
      _numAt(r'flow|capacity', 'flow_m3h'),
      _numAt(r'discharge press|diff\w*\.? press', 'discharge_pressure_barg'),
      _code,
    ],
    inferType: inferCompressor,
    driver: SizeDriver('دبی هر کمپرسور', 'Nm³/h', 0.4, (v) => _num(v['flow_m3h'])),
    typeKey: 'sub_category',
    gridKeys: ['sub_category', 'compressor_type', 'flow_m3h', 'discharge_pressure_barg', 'compressors_per_price_unit'],
    rangeKeys: ['flow_m3h', 'discharge_pressure_barg'],
    factorGroups: compressorFactorGroups,
    factorSeeds: compressorFactorSeeds,
  ),
  'AIR_DRYER': EquipmentProfile(
    code: 'AIR_DRYER',
    fields: const [
      ProfileField('dryer_type', 'نوع خشک‌کن', 'key_specs'),
      ProfileField('drying_medium', 'ماده‌ی جاذب', 'key_specs'),
      ProfileField('flow_m3h', 'دبی ورودی', 'key_specs', type: 'number', unit: 'm³/h'),
      ProfileField('towers_qty', 'تعداد برج', 'package', type: 'number'),
      ProfileField('prefilters_qty', 'تعداد پیش‌فیلتر', 'package', type: 'number'),
      ProfileField('afterfilters_qty', 'تعداد پس‌فیلتر', 'package', type: 'number'),
      _fPress, _fPressText, _fTmin, _fTmax,
      ProfileField('shell_material', 'جنس', 'material'),
      _fMat, _fCode, _fScope,
    ],
    rules: [
      _text(r'^type', 'dryer_type'),
      _text(r'medium', 'drying_medium'),
      _numAt(r'flow', 'flow_m3h'),
      _numAt(r'tower', 'towers_qty'),
      _numAt(r'pre-?filter', 'prefilters_qty'),
      _numAt(r'after-?filter', 'afterfilters_qty'),
      _pressure(r'design press|press\w*\.? design', vacKey: null),
      _temps(r'design temp|temp\w*\.? design'),
      _material(r'^mat', 'shell_material'),
      _code,
    ],
    driver: SizeDriver('دبی ورودی', 'm³/h', 0.6, (v) => _num(v['flow_m3h'])),
    gridKeys: ['dryer_type', 'flow_m3h', 'towers_qty'],
    rangeKeys: [],
    factorGroups: const ['MAT', 'PRESS'],
  ),
  'CRANE': EquipmentProfile(
    code: 'CRANE',
    fields: const [
      ProfileField('crane_type', 'نوع جرثقیل', 'key_specs', type: 'enum', list: 'G_CRANE'),
      ProfileField('drive', 'محرک', 'key_specs'),
      ProfileField('capacity_kg', 'ظرفیت', 'key_specs', type: 'number', unit: 'kg'),
      ProfileField('lift_m', 'ارتفاع بالابری', 'key_specs', type: 'number', unit: 'm'),
      ProfileField('span_m', 'دهانه', 'key_specs', type: 'number', unit: 'm'),
      ProfileField('travel_m', 'طول حرکت', 'key_specs', type: 'number', unit: 'm'),
      ProfileField('motor', 'مشخصات موتور', 'design'),
      _fCode, _fScope,
    ],
    rules: [
      MtoRule(r'^type', (v, o) {
        final l = v.toLowerCase();
        o['crane_type'] ??= l.contains('top run')
            ? 'Top Running'
            : (l.contains('under') ? 'Under Hung' : (l.contains('gantry') ? 'Gantry' : (l.contains('mono') ? 'Monorail' : 'Other')));
        final parts = v.split(',');
        if (parts.length > 1) o['drive'] ??= parts.sublist(1).join(',').trim();
      }),
      _numAt(r'capacity', 'capacity_kg'),
      MtoRule(r'lift.*span', (v, o) {
        final n = _nums(v);
        if (n.isNotEmpty) o['lift_m'] ??= n[0];
        if (n.length > 1) o['span_m'] ??= n[1];
        if (n.length > 2) o['travel_m'] ??= n[2];
      }),
      _text(r'motor', 'motor'),
      _code,
    ],
    driver: SizeDriver('ظرفیت', 'kg', 0.6, (v) => _num(v['capacity_kg'])),
    typeKey: 'crane_type',
    gridKeys: ['crane_type', 'capacity_kg', 'span_m'],
    rangeKeys: ['span_m'],
    factorGroups: const [],
  ),
};

/// فهرست‌های انتخابی قالب‌ها: کلید ← گزینه‌ها (مقدار، برچسب فارسی)
const profileLists = <String, List<(String, String)>>{
  'G_MAT': [
    ('CS', 'فولاد کربنی'), ('LTCS', 'فولاد کربنی دمای پایین'), ('SS304', 'فولاد زنگ‌نزن ۳۰۴'),
    ('SS316', 'فولاد زنگ‌نزن ۳۱۶'), ('Duplex', 'داپلکس'), ('Super Duplex', 'سوپر داپلکس'), ('Titanium', 'تیتانیوم'),
    ('Other', 'سایر'),
  ],
  'G_ORIENT': [('Vertical', 'عمودی'), ('Horizontal', 'افقی')],
  'G_ROOF': [('Dome', 'گنبدی'), ('Cone', 'مخروطی'), ('Floating', 'شناور'), ('Other', 'سایر')],
  'G_HEX': [('Plate & Frame', 'صفحه‌ای'), ('Shell & Tube', 'پوسته و لوله'), ('Air Cooler', 'هوایی'), ('Other', 'سایر')],
  'G_FLARE': [('Flare', 'فلر'), ('Burn Pit', 'Burn Pit')],
  'G_COMP': [('Reciprocating', 'رفت‌وبرگشتی'), ('Screw', 'اسکرو'), ('Centrifugal', 'گریز از مرکز'), ('Other', 'سایر')],
  'G_LUBE': [('Oil-free', 'بدون روغن'), ('Lubricated', 'روغن‌کاری‌شده')],
  'G_CRANE': [('Top Running', 'روی ریل (Top Running)'), ('Under Hung', 'آویز (Under Hung)'), ('Gantry', 'دروازه‌ای'), ('Monorail', 'مونوریل'), ('Other', 'سایر')],
  ...desalterLists,
  ...compressorLists,
};

/// ضرایب نرمال‌سازی اولیه (قضاوت مهندسی، نسبت به پایه = ۱): (گروه، گزینه، ضریب، شرح)
const profileFactorSeeds = <(String, String, double, String)>[
  ('MAT', 'CS', 1.0, 'پایه: فولاد کربنی'),
  ('MAT', 'LTCS', 1.15, 'فولاد کربنی دمای پایین'),
  ('MAT', 'SS304', 1.8, 'فولاد زنگ‌نزن ۳۰۴'),
  ('MAT', 'SS316', 2.1, 'فولاد زنگ‌نزن ۳۱۶'),
  ('MAT', 'Duplex', 2.6, 'داپلکس'),
  ('MAT', 'Super Duplex', 3.0, 'سوپر داپلکس'),
  ('MAT', 'Titanium', 3.5, 'تیتانیوم'),
  ('MAT', 'Other', 1.0, 'نامشخص/سایر'),
  ('NACE', 'Y', 1.05, 'الزام NACE MR0175'),
  ('NACE', 'N', 1.0, 'پایه'),
  ('PRESS', '≤10', 1.0, 'فشار طراحی تا ۱۰ barg (پایه)'),
  ('PRESS', '10–20', 1.1, 'فشار طراحی ۱۰ تا ۲۰ barg'),
  ('PRESS', '20–40', 1.25, 'فشار طراحی ۲۰ تا ۴۰ barg'),
  ('PRESS', '>40', 1.45, 'فشار طراحی بیش از ۴۰ barg'),
  ('LUBE', 'Lubricated', 1.0, 'پایه: روغن‌کاری‌شده'),
  ('LUBE', 'Oil-free', 1.3, 'بدون روغن'),
];

String factorSetOf(String categoryCode) => 'GEN_$categoryCode';

/// روش تعدیل پیش‌فرض هر رده‌ی غیرپمپ (مستقل از روش پمپ‌ها): دیسالتر = شاخص ترکیبی، بقیه = PPI رده.
String defaultCategoryMethod(String code) => code == 'DESALTER' ? 'M7' : 'M4';

/// سبد پیش‌فرض شاخص ترکیبی (M7) هر رده.
List<MixPart> defaultCategoryMix(String code) => code == 'DESALTER' ? desalterDefaultMix : const [];

/// سری PPI آمریکای روش M5 هر رده: کمپرسور هوا = BLS PCU333912 (Air & gas compressors)، بقیه = پمپ 333914.
String defaultCategoryUsPpi(String code) => code == 'COMPRESSOR' ? 'PPI_US_333912_GREG' : defaultUsPpiSeries;

/// گزینه‌ی گروه ضریب برای مقادیر یک قلم ([code] = رده، برای رده‌هایی که گروه‌های اختصاصی دارند).
String? factorOption(String group, Map<String, Object?> v, {String? code}) {
  if (code == 'DESALTER') return desalterFactorOption(group, v);
  if (code == 'COMPRESSOR') return compressorFactorOption(group, v);
  switch (group) {
    case 'MAT':
      return v['material_class']?.toString();
    case 'NACE':
      return v['nace']?.toString();
    case 'LUBE':
      return v['lubrication']?.toString();
    case 'PRESS':
      final p = _num(v['design_pressure_barg']);
      if (p == null) return null;
      return p <= 10 ? '≤10' : (p <= 20 ? '10–20' : (p <= 40 ? '20–40' : '>40'));
  }
  return null;
}

// -----------------------------------------------------------------------------
// پمپ: مشخصات شرح MTO ← فیلدهای قالب ۵۹ فیلدی پمپ (دبی، هد، فشار رانش، کلاس متریال، …)

const _pumpStd = ['API 610', 'API 674', 'API 675', 'API 676', 'ISO 13709', 'ISO 5199', 'ISO 2858', 'NFPA 20', 'JIS B 8325'];
const _pumpIps = ['IPS-G-PM-105', 'IPS-M-PM-115', 'IPS-M-PM-125', 'IPS-M-PM-140'];
const _pumpMat = ['I-1', 'I-2', 'S-1', 'S-3', 'S-4', 'S-5', 'S-6', 'S-8', 'S-9', 'C-6', 'A-7', 'A-8', 'D-1', 'D-2'];

/// آیا برچسب مشخصه‌ی MTO در قالب پمپ جا دارد؟ (بقیه در «ملاحظات» می‌مانند)
bool pumpMaps(String label) => RegExp(
        r'^type|flow|capacity|(?<!over)head|discharge press|power|motor|material|nace|design code|standard|driver|speed|rpm',
        caseSensitive: false)
    .hasMatch(label);

Map<String, Object?> extractPumpSpecs(Map<String, String> specs, String name) {
  final o = <String, Object?>{};
  String? firstIn(List<String> list, String text) {
    final u = text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    for (final x in list) {
      if (u.contains(x.toUpperCase())) return x;
    }
    return null;
  }

  for (final e in specs.entries) {
    final k = e.key.toLowerCase();
    final v = e.value.trim();
    final l = v.toLowerCase();
    final n = _nums(v);
    if (k.startsWith('type')) {
      o['pump_family'] ??= l.contains('submers')
          ? 'Centrifugal - Submersible'
          : l.contains('centrif')
              ? 'Centrifugal'
              : l.contains('gear')
                  ? 'PD-Rotary (Gear)'
                  : l.contains('progress') || l.contains('cavity')
                      ? 'PD-Rotary (Progressing Cavity)'
                      : l.contains('screw')
                          ? 'PD-Rotary (Screw)'
                          : l.contains('vane')
                              ? 'PD-Rotary (Sliding Vane)'
                              : l.contains('diaphragm') || l.contains('metering') || l.contains('dosing')
                                  ? 'Metering (Diaphragm)'
                                  : l.contains('plunger') || l.contains('reciproc')
                                      ? 'PD-Reciprocating (Plunger)'
                                      : null;
      final t = RegExp(r'\b(OH|BB|VS)\s*-?\s*([1-7])\b', caseSensitive: false).firstMatch(v);
      if (t != null) o['api610_type'] ??= '${t.group(1)!.toUpperCase()}${t.group(2)}';
    } else if (RegExp(r'flow|capacity').hasMatch(k) && n.isNotEmpty) {
      var q = n.first;
      final unit = '$k $l';
      if (unit.contains('l/h') || unit.contains('lph') || unit.contains('lit')) q = q / 1000;
      if (unit.contains('gpm')) q = q * 0.2271;
      o['capacity_m3h'] ??= q;
    } else if (k.contains('head') && !k.contains('overhead') && n.isNotEmpty) {
      o['diff_head_m'] ??= n.first;
    } else if (k.contains('discharge press') && n.isNotEmpty) {
      o['discharge_pressure_barg'] ??= ('$k $l').contains('kpa') ? n.first / 100 : n.first;
    } else if ((k.contains('power') || k.contains('motor')) && n.isNotEmpty) {
      final hp = ('$k $l').contains('hp') && !('$k $l').contains('kw');
      o['power_kw'] ??= hp ? n.first * 0.7457 : n.first;
      o['power_basis'] ??= k.contains('motor') || l.contains('motor') ? 'Motor Rated' : 'Not stated';
    } else if (k.contains('material')) {
      final m = RegExp(r'\b([ISCAD])\s*-?\s*(\d)\b').firstMatch(v.toUpperCase());
      if (m != null) {
        final c = '${m.group(1)}-${m.group(2)}';
        if (_pumpMat.contains(c)) o['material_class'] ??= c;
      } else if (l.contains('316')) {
        o['material_class'] ??= 'SS316L (non-API)';
      } else if (RegExp(r'casing\s*:?\s*cast iron').hasMatch(l)) {
        o['material_class'] ??= 'I-1'; // پوسته و پروانه چدنی (API 610)
      }
    } else if (k.contains('nace')) {
      o['nace'] ??= l.startsWith('y') ? 'Y' : (l.startsWith('n') ? 'N' : null);
    } else if (k.contains('design code') || k.contains('standard')) {
      o['pump_standard'] ??= firstIn(_pumpStd, v);
      o['ips_standard'] ??= firstIn(_pumpIps, v);
      o['standards'] ??= v.replaceAll('\n', ' ');
    } else if (k.contains('driver')) {
      o['driver_type'] ??= l.contains('diesel')
          ? 'Diesel Engine'
          : l.contains('turbine')
              ? 'Steam Turbine'
              : l.contains('air') || l.contains('pneum')
                  ? 'Air / Pneumatic'
                  : l.contains('motor') || l.contains('electric')
                      ? 'Electric Motor'
                      : null;
    }
  }
  // زیرگروه و سیال از نام سرویس
  final s = name.toLowerCase();
  o['sub_category'] ??= s.contains('fire')
      ? 'ROT-FIR'
      : RegExp(r'inject|chemical|dosing|demulsif|anti.?scale|corrosion').hasMatch(s)
          ? 'ROT-INJ'
          : RegExp(r'drain|sump|slop').hasMatch(s)
              ? 'ROT-DRN'
              : RegExp(r'crude|oil|off.?spec|booster|transfer|shipping').hasMatch(s)
                  ? 'ROT-CRU'
                  : RegExp(r'water|wash|dilution|deaerat|brine|effluent').hasMatch(s)
                      ? 'ROT-WAT'
                      : 'ROT-AUX';
  o['service_fluid'] ??= s.contains('fire')
      ? 'Fire Water'
      : s.contains('deaerat')
          ? 'Deaerated Water'
          : RegExp(r'dilution|wash|process water').hasMatch(s)
              ? 'Process / Dilution Water'
              : RegExp(r'produced|disposal|effluent|brine').hasMatch(s)
                  ? 'Produced / Disposal Water'
                  : RegExp(r'drain|oily').hasMatch(s)
                      ? 'Oily Water / Drain'
                      : s.contains('slop')
                          ? 'Slop / Dirty Oil'
                          : RegExp(r'chemical|inject|dosing|demulsif').hasMatch(s)
                              ? 'Chemical'
                              : RegExp(r'diesel|fuel').hasMatch(s)
                                  ? 'Diesel / Fuel Oil'
                                  : RegExp(r'crude|oil|off.?spec').hasMatch(s)
                                      ? 'Crude Oil'
                                      : RegExp(r'potable|fresh|drinking').hasMatch(s)
                                          ? 'Fresh / Potable Water'
                                          : RegExp(r'cooling|seal water').hasMatch(s)
                                              ? 'Cooling / Seal Water'
                                              : null;
  if (o['pump_family'] == 'Centrifugal' && o['api610_type'] == null && o['pump_standard'] != 'API 610') {
    o['api610_type'] = 'N/A (non-API 610)';
  }
  o.removeWhere((k, v) => v == null);
  return o;
}

// -----------------------------------------------------------------------------
// تشخیص رده از متن (نام شیت، عنوان بخش یا نام قلم)

const _categoryWords = <(String, String)>[
  (r'desalt|dehydrat|electrostatic|نمک.?زدا|دیسالتر', 'DESALTER'),
  (r'deaerat|دی.?اریتور|هوازدا', 'DEAERATOR'),
  (r'\bigf\b|flotation|شناورساز', 'IGF'),
  (r'injection|dosing|chemical|c\.i\.p|تزریق', 'CIP'),
  (r'air\s*dryer|dryer|خشک.?کن', 'AIR_DRYER'),
  (r'compressor|کمپرسور', 'COMPRESSOR'),
  (r'pump|پمپ', 'PUMP'),
  (r'exchang|cooler|condenser|reboiler|\bphe\b|مبدل|کولر', 'HEX'),
  (r'heater|furnace|fired|گرم.?کن|کوره', 'HEATER'),
  (r'tank|مخزن', 'TANK'),
  (r'vessel|drum|separator|receiver|reciever|knock.?out|\bk\.?o\.?\b|scrubber|ظرف|درام|جداکننده', 'VESSEL'),
  (r'filter|strainer|فیلتر|صافی', 'FILTER'),
  (r'flare|burn\s*pit|stack|فلر|مشعل', 'FLARE'),
  (r'crane|hoist|monorail|جرثقیل|بالابر', 'CRANE'),
  (r'\bfire\b|safety|hydrant|extinguish|deluge|eye ?wash|breathing|first ?aid|\bhse\b|آتش|ایمنی', 'FIRE_SAFETY'),
  (r'valve|شیرآلات|شیر ', 'VALVE'),
  (r'\bpipe|piping|fitting|flange|elbow|stud ?bolt|gasket|لوله|اتصالات', 'PIPE_BULK'),
  (r'transformer|switchgear|\bcable|\bpanel|\bups\b|lighting|generator|capacitor|\bpower\b|\bmcc\b|motor control|\bvfd\b|'
      r'earthing|grounding|cathodic|electrical|ترانس|تابلو|کابل|ژنراتور|برق', 'ELEC_EQ'),
  (r'transmitter|analy[sz]er|gauge|instrument|\bplc\b|\bdcs\b|\besd\b|\bscada\b|corrosion (probe|coupon)|logger|'
      r'metering|sampling|control room|\bccr\b|ابزار ?دقیق|اندازه.?گیری', 'INST_EQ'),
  (r'\blab\b|laborator|آزمایشگاه', 'LAB'),
];

/// کلیدواژه‌های خاص که بر جایگاه واژه مقدم‌اند (مثل «Pig Launcher & Receiver» که ظرف نیست)
const _priorityWords = <(String, String)>[
  (r'pig\s*(launcher|receiver)|stripp', 'MISC_PKG'),
  (r'iwwtp|water ?treatment|reverse ?osmosis|\br\.\s?o\.\s*(package|unit|system)|پکیج تصفیه|تصفیه‌خانه', 'WATER_TREAT'),
  (r'hvac|air ?condition|fan ?coil|تهویه', 'HVAC'),
  (r'f\s*&\s*g\b|fire\s*(&|and)\s*gas|burner management|\bbms\b|metering\s*(system|skid|package|unit)|sampling system',
      'INST_EQ'),
];

/// خدمات و کارهای غیرتجهیز (نصب، اجرا، ساختمان، تجهیز کارگاه، ماشین‌آلات، حقوق) — بر رده‌ی شیت مقدم‌اند،
/// تا مثلاً «Desalter Installation» یا «Power Installation» در بانک تجهیز شمرده نشود.
const _serviceWords =
    r'(^|\s)(installation|erection|construction|pre.?commission\w*|commission\w*|contractors?|welding|mobili[sz]ation|'
    r'demobili[sz]ation|engineering|supervision|excavat\w*|civil works?|dormitor\w*|accommodation|accomodation|'
    r'salary|salaries|furnish\w*|نصب|اجرا|عملیات ساختمانی|تجهیز کارگاه|برچیدن کارگاه|حقوق|دستمزد)(\s|$|[,(&])';

String? serviceCategoryFromText(String text) {
  // فقط اسم اصلی: «HVAC for Accommodation» خدمات نیست، «Installation of Pumps» هست
  final t = text.split('\n').first.toLowerCase().split(RegExp(r'\s(for|of|in|at|to|برای)\s')).first;
  return RegExp(_serviceWords, caseSensitive: false).hasMatch(t) ? 'SERVICES' : null;
}

/// رده از کلیدواژه‌های خاص (پکیج تصفیه، HVAC، Pig Launcher) که بر عنوان بخش هم مقدم‌اند
String? priorityCategoryFromText(String text) {
  final t = text.split('\n').first.toLowerCase();
  for (final (p, code) in _priorityWords) {
    if (RegExp(p, caseSensitive: false).hasMatch(t)) return code;
  }
  return null;
}

/// پیشنهاد رده از روی متن آزاد (فارسی یا انگلیسی)؛ null = تشخیص داده نشد.
/// اسم اصلی برنده است: در انگلیسی آخرین کلیدواژه (Drum در «Pump Suction Drum»)،
/// در فارسی اولین کلیدواژه («پمپ» در «پمپ تزریق مواد»).
String? suggestCategoryFromText(String text) {
  final t = text.split('\n').first.toLowerCase().replaceAll('ي', 'ی').replaceAll('ك', 'ک');
  for (final (p, code) in _priorityWords) {
    if (RegExp(p, caseSensitive: false).hasMatch(t)) return code;
  }
  final fa = RegExp(r'[\u0600-\u06FF]');
  String? en, faBest;
  var enPos = -1, faPos = 1 << 30;
  for (final (p, code) in _categoryWords) {
    for (final m in RegExp(p, caseSensitive: false).allMatches(t)) {
      if (fa.hasMatch(m.group(0)!)) {
        if (m.start < faPos) {
          faPos = m.start;
          faBest = code;
        }
      } else if (m.start > enPos) {
        enPos = m.start;
        en = code;
      }
    }
  }
  return faBest ?? en;
}

// -----------------------------------------------------------------------------
// مشخصات به شکل متن آزاد (مثل «536 m3/hr , 19.5 bar D.P. T/T=18000 mm , ID=5300 mm»)
// ← فیلدهای قالب هر رده. فقط مقادیری که خالی‌اند پر می‌شوند.

double? _firstNum(RegExp re, String t, {int group = 1}) {
  final m = re.firstMatch(t);
  if (m == null) return null;
  return double.tryParse(m.group(group)!.replaceAll(',', ''));
}

double? _mm(RegExp re, String t) {
  final m = re.firstMatch(t);
  if (m == null) return null;
  final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
  if (v == null) return null;
  final unit = (m.groupCount >= 2 ? m.group(2) : null)?.toLowerCase();
  return (unit == 'm' || (unit == null && v < 60)) ? v * 1000 : v;
}

/// استخراج از متن آزاد برای رده‌ی [code]؛ خروجی: کلید فیلد ← مقدار
Map<String, Object?> extractFreeSpecs(String text, String code) {
  final t = text.replaceAll('\n', ' ').replaceAll('³', '3').replaceAll('٫', '.');
  final o = <String, Object?>{};
  const n = r'(\d+(?:[.,]\d+)?)';
  // «ID x T/T: 800mm x 2350 mm»، «ID x HEIGHT: 8000 x 10000 mm»، «D x H = …»: دو عدد به ترتیب عنوان
  final pair = RegExp(
          '\\b(I\\.?D|D(?:IA\\.?|iameter)?)\\.?\\s*[x×*]\\s*(T/T|TL(?:-TL)?|T\\.L\\.|H(?:eight|ight)?|L(?:ength)?)\\.?\\s*[=:]?\\s*'
          '$n\\s*(mm|m)?\\s*[x×*]\\s*$n\\s*(mm|m)?',
          caseSensitive: false)
      .firstMatch(t);
  double? pv(int g, int u) {
    final x = double.tryParse(pair!.group(g)!.replaceAll(',', '.'));
    final unit = (pair.group(u) ?? pair.group(6) ?? '').toLowerCase();
    return x == null ? null : (unit == 'm' ? x * 1000 : x);
  }
  final pairA = pair == null ? null : pv(3, 4), pairB = pair == null ? null : pv(5, 6);
  final id = pairA ??
      _mm(RegExp('\\bI\\.?D\\.?\\s*[=:]?\\s*$n\\s*(mm|m)?\\b', caseSensitive: false), t);
  final d = _mm(RegExp('(?<![A-Za-z/])D(?:IA\\.?|iameter)?\\s*=\\s*$n\\s*(mm|m)?\\b', caseSensitive: false), t);
  final tt = pairB ?? _mm(RegExp('(?:T/T|TL(?:-TL)?|T\\.L\\.)\\s*[=:]\\s*$n\\s*(mm|m)?\\b', caseSensitive: false), t);
  final l = _mm(RegExp('(?<![A-Za-z/])L(?:ength)?\\s*=\\s*$n\\s*(mm|m)?\\b', caseSensitive: false), t);
  final h = _mm(RegExp('(?<![A-Za-z/])H(?:eight)?\\s*=\\s*$n\\s*(mm|m)?\\b', caseSensitive: false), t);
  final flow = _firstNum(RegExp('$n\\s*(?:[ns]\\s*)?m3\\s*/\\s*h', caseSensitive: false), t);
  final kw = _firstNum(RegExp('$n\\s*kw\\b', caseSensitive: false), t);
  final dp = _firstNum(RegExp('D\\.?P\\.?\\s*[=:]?\\s*$n', caseSensitive: false), t) ??
      _firstNum(RegExp('$n\\s*bar\\s*(?:g\\b)?\\s*D\\.?P', caseSensitive: false), t) ??
      _firstNum(RegExp('$n\\s*barg\\b', caseSensitive: false), t);
  final bar = _firstNum(RegExp('$n\\s*bar', caseSensitive: false), t);
  final lph = RegExp('$n\\s*(?:-|to|~)\\s*$n\\s*lit\\w*\\s*/\\s*h', caseSensitive: false).firstMatch(t);
  final lph1 = _firstNum(RegExp('$n\\s*(?:lit\\w*|l)\\s*/\\s*h', caseSensitive: false), t);
  final injP = _firstNum(RegExp('injection\\s*pressure\\s*[=:]?\\s*$n', caseSensitive: false), t);
  final bpd = _firstNum(RegExp('$n\\s*s?bpd', caseSensitive: false), t);
  final ton = _firstNum(RegExp('$n\\s*(?:ton|tonne|t)\\b', caseSensitive: false), t);

  void put(String k, Object? v) {
    if (v != null) o[k] ??= v;
  }

  switch (code) {
    case 'VESSEL':
      put('id_mm', id ?? d);
      put('tl_mm', tt ?? l ?? h);
      put('design_pressure_barg', dp);
    case 'TANK':
      put('diameter_mm', d ?? id);
      put('height_mm', h ?? tt);
      put('design_pressure_barg', dp);
    case 'DESALTER':
      put('vessel_id_mm', id ?? d);
      put('vessel_tl_mm', tt ?? l);
      put('design_pressure_barg', dp);
    case 'HEX':
      put('duty_kw', kw);
      put('design_pressure_barg', dp);
    case 'HEATER':
      put('duty_kw', kw);
      put('design_pressure_coil_barg', dp);
      put('shell_id_mm', id ?? d);
      put('shell_tl_mm', tt ?? l);
    case 'CIP':
      put('injection_rate_lph',
          lph != null ? double.tryParse(lph.group(2)!.replaceAll(',', '')) : lph1);
      put('discharge_pressure_barg', injP ?? dp ?? bar);
    case 'DEAERATOR' || 'AIR_DRYER':
      put('flow_m3h', flow);
      put('design_pressure_barg', dp);
    case 'IGF' || 'FILTER':
      put('flow_m3h', flow ?? (bpd == null ? null : bpd * 0.158987 / 24));
      put('design_pressure_barg', dp);
    case 'COMPRESSOR':
      put('flow_m3h', flow);
      put('discharge_pressure_barg', dp ?? bar);
    case 'CRANE':
      put('capacity_kg', ton == null ? null : ton * 1000);
    case 'PUMP':
      put('capacity_m3h', flow);
      put('discharge_pressure_barg', bar);
      put('power_kw', kw);
  }
  return o;
}
