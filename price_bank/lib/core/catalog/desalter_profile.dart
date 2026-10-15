// قالب و ضرایب رده‌ی دیسالتر — مطابق بانک Desalters_Price_Bank v8 (شیت‌های Factors_DES، Lookup_Codes و Calc_Spec).
//
// پیکربندی پایه: Electrostatic AC/DC، CS (SA-516 Gr.70)، بدون NACE، دو مرحله، پکیج کامل شامل ترانس،
// پمپ Recycle، لوله‌کشی و ابزار دقیق، بدون گمرک و حمل.
part of 'profiles.dart';

/// گروه‌های ضریب دیسالتر. STAGE فقط در روش ظرفیت‌محور (A) به کار می‌رود و در ALL_F نیست.
const desalterFactorGroups = ['TECH', 'MAT', 'NACE', 'STAGE', 'SC_TRF', 'SC_PMP', 'SC_PIP', 'SC_INS', 'SC_CT'];

/// گروه‌های Scope (حاصل‌ضرب = SCOPE_F) و فیلد هر کدام
const desalterScopeFields = {
  'SC_TRF': 'scope_transformers',
  'SC_PMP': 'scope_recycle_pumps',
  'SC_PIP': 'scope_related_piping',
  'SC_INS': 'scope_instruments',
  'SC_CT': 'scope_customs_transport',
};

/// فیلد هر گروه ضریب دیسالتر
const desalterFactorFields = {
  'TECH': 'desalting_technology',
  'MAT': 'des_material',
  'NACE': 'nace',
  'STAGE': 'no_of_stages',
  ...desalterScopeFields,
};

String? desalterFactorOption(String group, Map<String, Object?> v) {
  final k = desalterFactorFields[group];
  final s = k == null ? null : v[k]?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

/// ضرایب اولیه (Factors_DES ستون D — قضاوت مهندسی، کالیبره نشده)
const desalterFactorSeeds = <(String, String, double, String)>[
  ('TECH', 'Electrostatic AC', 0.90, 'فناوری — پایه Electrostatic AC/DC = ۱'),
  ('TECH', 'Electrostatic AC/DC', 1.00, 'پایه'),
  ('TECH', 'Dual Polarity', 1.00, 'فناوری — پایه Electrostatic AC/DC = ۱'),
  ('TECH', 'Electro-Dynamic', 1.15, 'فناوری — پایه Electrostatic AC/DC = ۱'),
  ('TECH', 'Electrostatic (unspecified)', 1.00, 'فناوری نامشخص'),
  ('TECH', 'Not stated', 1.00, 'ذکر نشده'),
  ('MAT', 'CS (SA-516 Gr.70)', 1.00, 'پایه'),
  ('MAT', 'CS (unspecified)', 1.00, 'فولاد کربنی بدون گرید'),
  ('MAT', 'LTCS', 1.08, 'فولاد کربنی دمای پایین'),
  ('MAT', 'CS + SS316L Clad', 1.50, 'کلد SS316L'),
  ('MAT', 'Not stated', 1.00, 'ذکر نشده'),
  ('NACE', 'Y', 1.05, 'الزام NACE MR0175 / ISO 15156'),
  ('NACE', 'N', 1.00, 'پایه'),
  ('NACE', 'Not stated', 1.00, 'ذکر نشده'),
  ('STAGE', '1-stage', 0.60, 'یک مرحله (فقط روش ظرفیت‌محور) — پایه دو مرحله = ۱'),
  ('STAGE', '2-stage', 1.00, 'پایه'),
  ('STAGE', 'Not stated', 1.00, 'ذکر نشده'),
  ('SC_TRF', 'Y', 1.00, 'پایه: ترانس‌ها در قیمت'),
  ('SC_TRF', 'N', 0.88, 'بدون ترانس'),
  ('SC_TRF', 'Not stated', 1.00, 'ذکر نشده'),
  ('SC_PMP', 'Y', 1.00, 'پایه: پمپ‌های Recycle در قیمت'),
  ('SC_PMP', 'N', 0.95, 'بدون پمپ Recycle'),
  ('SC_PMP', 'Not stated', 1.00, 'ذکر نشده'),
  ('SC_PIP', 'Y', 1.00, 'پایه: لوله‌کشی مربوط در قیمت'),
  ('SC_PIP', 'N', 0.95, 'بدون لوله‌کشی'),
  ('SC_PIP', 'Not stated', 1.00, 'ذکر نشده'),
  ('SC_INS', 'Y', 1.00, 'پایه: ابزار دقیق و کنترل در قیمت'),
  ('SC_INS', 'N', 0.95, 'بدون ابزار دقیق'),
  ('SC_INS', 'Not stated', 1.00, 'ذکر نشده'),
  ('SC_CT', 'Y', 1.06, 'گمرک و حمل در قیمت'),
  ('SC_CT', 'N', 1.00, 'پایه: بدون گمرک و حمل'),
  ('SC_CT', 'Not stated', 1.00, 'ذکر نشده'),
];

/// سبد پیش‌فرض شاخص ترکیبی دیسالتر (Assumptions بانک دیسالتر؛ وزن‌ها Provisional)
const desalterDefaultMix = [
  MixPart('PPI_EU_C2529_GREG', 0.70), // بدنه‌ی وسل، Internals و الکترودها
  MixPart('PPI_EU_C2711_GREG', 0.15), // ترانس‌ها
  MixPart('PPI_EU_C2813_GREG', 0.15), // پمپ‌های Recycle
];

/// فهرست‌های انتخابی دیسالتر (Lookup_Codes)
const desalterLists = <String, List<(String, String)>>{
  'DES_SUBCAT': [
    ('PKG-DES-2S', 'پکیج دو مرحله‌ای'),
    ('PKG-DES-1S', 'پکیج یک مرحله‌ای'),
    ('PKG-DES-MT', 'چند ترین در یک قلم'),
    ('PKG-DES-AGG', 'قلم تجمیعی (فقط مرجع)'),
  ],
  'DES_TECH': [
    ('Electrostatic AC', 'Electrostatic AC'),
    ('Electrostatic AC/DC', 'Electrostatic AC/DC'),
    ('Dual Polarity', 'Dual Polarity'),
    ('Electro-Dynamic', 'Electro-Dynamic'),
    ('Electrostatic (unspecified)', 'Electrostatic (نامشخص)'),
    ('Not stated', 'ذکر نشده'),
  ],
  'DES_MAT': [
    ('CS (SA-516 Gr.70)', 'CS (SA-516 Gr.70)'),
    ('CS (unspecified)', 'CS (بدون گرید)'),
    ('LTCS', 'LTCS'),
    ('CS + SS316L Clad', 'CS + SS316L Clad'),
    ('Not stated', 'ذکر نشده'),
  ],
  'DES_STAGE': [('1-stage', 'یک مرحله'), ('2-stage', 'دو مرحله'), ('Not stated', 'ذکر نشده')],
  'DES_VSTD': [('ASME VIII Div.1', 'ASME VIII Div.1'), ('ASME VIII Div.2', 'ASME VIII Div.2'), ('Not stated', 'ذکر نشده')],
  'DES_IPS': [('IPS-G-ME-150', 'IPS-G-ME-150'), ('None', 'ندارد')],
};

/// حجم کل پوسته (فقط استوانه، بدون عدسی) × تعداد وسل — همان GEO-1 بانک دیسالتر.
double? desalterShellVolume(Map<String, Object?> v) {
  final per = desalterVesselVolume(v);
  final n = _num(v['vessels_per_package']);
  if (per == null || n == null) return null;
  return per * n;
}

double? desalterVesselVolume(Map<String, Object?> v) => _cyl(v, 'vessel_id_mm', 'vessel_tl_mm', heads: false);

/// «Electrostatic - AC / DC» ← Electrostatic AC/DC و …
String? desalterTechnologyOf(String text) {
  final l = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (l.contains('dual')) return 'Dual Polarity';
  if (l.contains('dynamic')) return 'Electro-Dynamic';
  if (RegExp(r'ac\s*/\s*dc').hasMatch(l)) return 'Electrostatic AC/DC';
  if (RegExp(r'electrostatic\s*-?\s*ac\b').hasMatch(l)) return 'Electrostatic AC';
  if (l.contains('electrostatic')) return 'Electrostatic (unspecified)';
  return null;
}

String desalterMaterialOf(String text) {
  final l = text.toLowerCase();
  if (l.contains('clad') || l.contains('316')) return 'CS + SS316L Clad';
  if (l.contains('333') || l.contains('ltcs') || l.contains('low temp')) return 'LTCS';
  if (l.contains('516')) return 'CS (SA-516 Gr.70)';
  if (materialClassOf(text) == 'CS') return 'CS (unspecified)';
  return 'Not stated';
}

/// استنباط فیلدهای دیسالتر از متن شرح MTO (نوع، دامنه، کد طراحی): فناوری، مرحله، ترانس‌ها، Scope، متریال.
void inferDesalter(String ctx, Map<String, Object?> o) {
  final text = [ctx, o['desalter_type'], o['scope']].whereType<Object>().join(' ');
  final l = text.toLowerCase();
  if (o['desalting_technology'] == null) o['desalting_technology'] = desalterTechnologyOf(text);
  if (o['no_of_stages'] == null) {
    if (RegExp(r'1st\s*(&|and)\s*2nd').hasMatch(l) || l.contains('two stage') || l.contains('2-stage')) {
      o['no_of_stages'] = '2-stage';
    } else if (RegExp(r'including 1st desalter').hasMatch(l) || l.contains('single stage') || l.contains('1-stage')) {
      o['no_of_stages'] = '1-stage';
    }
  }
  final trf = RegExp(r'(\d+)\s*x\s*(\d+(?:\.\d+)?)\s*%\s*transformer').firstMatch(l);
  if (trf != null) {
    o['n_transformers'] ??= double.parse(trf.group(1)!);
    o['transformer_sizing'] ??= double.parse(trf.group(2)!) / 100;
  }
  if (l.contains('transformer')) o['scope_transformers'] ??= 'Y';
  if (l.contains('recycle pump') || l.contains('circulation pump')) o['scope_recycle_pumps'] ??= 'Y';
  if (l.contains('piping')) o['scope_related_piping'] ??= 'Y';
  if (l.contains('instrument')) o['scope_instruments'] ??= 'Y';
  final mat = o['shell_material']?.toString();
  if (mat != null && o['des_material'] == null) o['des_material'] = desalterMaterialOf(mat);
  final code = o['design_code']?.toString().toLowerCase() ?? '';
  if (code.contains('asme') && o['vessel_design_code'] == null) {
    o['vessel_design_code'] = code.contains('div.2') || code.contains('div 2') ? 'ASME VIII Div.2' : 'ASME VIII Div.1';
  }
  if (code.contains('ips-g-me-150')) o['ips_standard'] ??= 'IPS-G-ME-150';
}
