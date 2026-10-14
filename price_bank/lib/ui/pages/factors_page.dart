import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/pump_engine.dart' show asText;
import '../../core/catalog/profiles.dart';
import '../../core/price_bank.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'equipment_page.dart';
import 'generic_equipment.dart';

const _groupFa = {
  'MAT': 'کلاس متریال API 610 (پایه S-5 = ۱)',
  'SEAL_ARR': 'آرایش آب‌بند API 682 (پایه Arr 1 = ۱)',
  'SEAL_CAT': 'گروه API 682 (پایه Cat 2 = ۱)',
  'SEAL_PLAN': 'پلن آب‌بندی (پایه Plan 11 = ۱)',
  'DRV': 'نوع محرک (پایه موتور برقی = ۱)',
  'NACE': 'NACE MR0175',
  'SC_DRV': 'Scope: محرک در قیمت (پایه = بله)',
  'SC_BSP': 'Scope: شاسی و کوپلینگ (پایه = بله)',
  'SC_SEAL': 'Scope: سیستم پشتیبان آب‌بند (پایه = بله)',
  'SC_COMM': 'Scope: یدکی راه‌اندازی (پایه = بله)',
  'SC_2Y': 'Scope: یدکی دوساله (پایه = خیر)',
  'SC_TPI': 'Scope: بازرسی شخص ثالث (پایه = خیر)',
  'SC_FAT': 'Scope: آزمون کارخانه با حضور (پایه = خیر)',
};

const _genGroupFa = {
  'MAT': 'کلاس جنس (پایه: فولاد کربنی = ۱)',
  'NACE': 'NACE MR0175 (پایه: خیر = ۱)',
  'PRESS': 'فشار طراحی (پایه: تا ۱۰ barg = ۱)',
  'LUBE': 'روغن‌کاری کمپرسور (پایه: روغن‌کاری‌شده = ۱)',
};

/// فیلد هر گروه ضریب پمپ (برای شمارش اقلام هر گزینه)
const _pumpGroupField = {
  'MAT': 'material_class',
  'SEAL_ARR': 'seal_arrangement',
  'SEAL_CAT': 'api682_category',
  'SEAL_PLAN': 'api682_plan',
  'DRV': 'driver_type',
  'NACE': 'nace',
  'SC_DRV': 'scope_driver',
  'SC_BSP': 'scope_baseplate',
  'SC_SEAL': 'scope_seal_support',
  'SC_COMM': 'scope_comm_spares',
  'SC_2Y': 'scope_2yr_spares',
  'SC_TPI': 'scope_tpi',
  'SC_FAT': 'scope_fat',
};

class FactorsPage extends StatefulWidget {
  const FactorsPage({super.key});

  @override
  State<FactorsPage> createState() => _FactorsPageState();
}

class _FactorsPageState extends State<FactorsPage> {
  /// رده‌ی انتخاب‌شده؛ پیش‌فرض همان رده‌ای که در صفحه‌ی تجهیزات باز است
  late String _code = EquipmentPage.selectedCategory;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final cats = app.pb.estimableCategories();
    if (!cats.any((c) => c.code == _code)) _code = 'PUMP';
    final cat = cats.firstWhere((c) => c.code == _code);
    final counts = app.pb.categoryCounts();
    final isPump = _code == 'PUMP';
    final profile = equipmentProfiles[_code];
    final setCode = isPump ? PriceBank.pumpFactorSet : factorSetOf(_code);
    final relevant = isPump ? null : profile!.factorGroups;
    final rows = [
      for (final r in app.pb.indices.factors(setCode))
        if (relevant == null || relevant.contains(r['grp'])) r,
    ];
    final groups = <String, List<Map<String, Object?>>>{};
    for (final r in rows) {
      (groups[r['grp'] as String] ??= []).add(r);
    }
    final order = relevant ?? groups.keys.toList();
    final calibrated = rows.where((r) => r['calibrated'] != null).length;
    final canEdit = app.user.isAdmin || app.user.role == 'reviewer';

    // تعداد اقلام این رده با هر گزینه‌ی هر گروه
    final optCounts = <String, Map<String, int>>{};
    void add(String g, String? v) {
      if (v == null || v.isEmpty) return;
      final m = optCounts[g] ??= {};
      m[v] = (m[v] ?? 0) + 1;
    }
    if (isPump) {
      for (final r in app.pumps) {
        for (final e in _pumpGroupField.entries) {
          add(e.key, asText(r.item.values[e.value]));
        }
      }
    } else {
      for (final r in app.genericRows(cat.id)) {
        for (final g in profile!.factorGroups) {
          add(g, factorOption(g, r.item.values));
        }
      }
    }

    return ListView(padding: const EdgeInsets.all(20), children: [
      PageHeader(
        icon: Icons.tune_rounded,
        title: 'ضرایب نرمال‌سازی',
        subtitle: '${cat.nameFa} · ${fa(rows.length)} ضریب مربوط به این تجهیز · ${fa(calibrated)} کالیبره‌شده'
            '${isPump ? ' · پیکربندی پایه: S-5، Arr 1 / Plan 11 / Cat 2، موتور برقی، بدون NACE' : ''}',
      ),
      SectionCard(
        title: 'تجهیز',
        subtitle: 'فقط ضرایبی که در قیمت همین تجهیز اثر دارند نمایش داده می‌شوند · عدد = تعداد اقلام بانک',
        icon: Icons.category_outlined,
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in cats)
            _CatChip(
              key: ValueKey('factor-cat-${c.code}'),
              label: c.nameFa,
              count: counts[c.id] ?? 0,
              selected: c.code == _code,
              onTap: () => setState(() => _code = c.code),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      HelpPanel(
        id: 'factors',
        title: 'این ضرایب چه کار می‌کنند؟',
        initiallyOpen: false,
        lines: [
          if (isPump)
            'قیمت هر پمپ بر حاصل‌ضرب ضرایب پیکربندی‌اش تقسیم می‌شود تا «قیمت معادل پیکربندی پایه» به دست آید؛ این مبنای مقایسه‌ی پمپ‌ها و تخمین پمپ جدید است.'
          else
            'قیمت هر قلم «${cat.nameFa}» بر حاصل‌ضرب ضرایب پیکربندی‌اش (جنس، NACE، فشار، …) تقسیم می‌شود تا با همتاها قابل مقایسه شود؛ در تخمین تجهیز جدید همین ضرایب دوباره ضرب می‌شوند.',
          'ضرایب اولیه بر پایه‌ی قضاوت مهندسی‌اند و هنوز کالیبره نشده‌اند. وقتی با استعلام‌های واقعی ضریب دقیق‌تری به دست آمد، آن را در ستون «ضریب کالیبره» وارد کنید.',
          'ضریب کالیبره جایگزین ضریب اولیه می‌شود؛ پاک کردن آن، ضریب اولیه را برمی‌گرداند. همه‌ی تغییرات در تاریخچه ثبت می‌شود.',
          'ضرایب فقط روی «یورو نرمال‌شده» و «ضریب هزینه» (تخمین) اثر دارند، نه روی قیمت تعدیل‌شده‌ی خود قلم.',
        ],
      ),
      if (!isPump) ...[
        _EstimationParams(code: _code, profile: profile!),
        const SizedBox(height: 12),
      ],
      if (order.every((g) => !groups.containsKey(g)))
        SectionCard(
          title: 'ضریب پیکربندی',
          icon: Icons.info_outline_rounded,
          child: Text(
            'رده‌ی «${cat.nameFa}» ضریب پیکربندی ندارد؛ قیمت فقط با پارامتر اندازه و توان n مقایسه و تخمین زده می‌شود.',
            style: t.textTheme.bodySmall?.copyWith(height: 1.8),
          ),
        ),
      for (final g in order)
        if (groups[g] case final list?) ...[
          SectionCard(
            title: (isPump ? _groupFa[g] : _genGroupFa[g]) ?? g,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FixedColumnWidth(90),
                2: FixedColumnWidth(100),
                3: FixedColumnWidth(150),
                4: FixedColumnWidth(110),
                5: FlexColumnWidth(4),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: BoxDecoration(color: AppColors.headerBg),
                  children: [
                    for (final h in ['گزینه', 'اقلام بانک', 'ضریب اولیه', 'ضریب کالیبره', 'ضریب مورد استفاده', 'شرح'])
                      _c(h, b: true),
                  ],
                ),
                for (final r in list)
                  TableRow(children: [
                    _c(r['option'] as String, b: true),
                    Center(child: CountBadge(optCounts[g]?[r['option']] ?? 0)),
                    _c(faSmart(r['provisional'] as double)),
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: _CalibratedField(
                          key: ValueKey('$setCode|${r['grp']}|${r['option']}'), row: r, enabled: canEdit, setCode: setCode),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(children: [
                        Text(faSmart((r['calibrated'] as double?) ?? (r['provisional'] as double)),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(width: 6),
                        if (r['calibrated'] != null) Pill('کالیبره', color: Tones.good(context)),
                      ]),
                    ),
                    _c((r['description'] as String? ?? '').split('|').last.trim(), small: true),
                  ]),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
    ]);
  }

  Widget _c(String s, {bool b = false, bool small = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(s, style: TextStyle(fontWeight: b ? FontWeight.w700 : null, fontSize: small ? 11.5 : 13)),
      );
}

/// دکمه‌ی انتخاب رده با تعداد اقلام.
class _CatChip extends StatelessWidget {
  const _CatChip({super.key, required this.label, required this.count, required this.selected, required this.onTap});
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Material(
      color: selected ? AppColors.petrol : t.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? AppColors.petrol : t.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (selected) const Padding(
              padding: EdgeInsetsDirectional.only(end: 6),
              child: Icon(Icons.check_rounded, size: 16, color: Colors.white),
            ),
            Text(label,
                style: TextStyle(fontWeight: FontWeight.w700, color: selected ? Colors.white : t.colorScheme.onSurface)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.22) : AppColors.petrol.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(fa(count),
                  style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w800, color: selected ? Colors.white : AppColors.petrolDark)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// پارامترهای تخمین رده: پارامتر اندازه، توان n و توان وزن (با دکمه‌ی ویرایش در «تنظیمات رده»).
class _EstimationParams extends StatelessWidget {
  const _EstimationParams({required this.code, required this.profile});
  final String code;
  final EquipmentProfile profile;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final n = app.pb.exponentOf(code);
    final custom = app.settings.catExponent(code) != null;
    final wRef = profile.weightKey == null ? null : app.pb.weightRefOf(code);
    Widget item(String k, String v, String sub) => Container(
          width: 260,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.colorScheme.outlineVariant),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(v, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.strong)),
            Text(sub, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline, height: 1.6)),
          ]),
        );
    return SectionCard(
      title: 'پارامترهای تخمین این رده',
      subtitle: 'قیمت ∝ اندازه^n × ضرایب پیکربندی${profile.weightKey == null ? '' : ' × ضریب وزن'}',
      icon: Icons.straighten_rounded,
      trailing: TextButton.icon(
        onPressed: () => showDialog<void>(context: context, builder: (_) => CategorySettingsDialog(code: code)),
        icon: const Icon(Icons.edit_rounded, size: 18),
        label: const Text('تغییر در تنظیمات رده'),
      ),
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        item('پارامتر اندازه', '${profile.driver.labelFa} (${profile.driver.unit})', 'از مشخصات هر قلم محاسبه می‌شود'),
        item('توان اندازه n', faSmart(n), custom ? 'تعیین‌شده در تنظیمات رده' : 'پیش‌فرض قالب رده'),
        if (profile.weightKey != null)
          item(
            'توان وزن m',
            faSmart(app.pb.weightExponentOf(code)),
            wRef == null
                ? 'ضریب وزن فعلاً بی‌اثر: وزن کمتر از دو قلم ثبت شده'
                : 'مرجع: ${faSmart(wRef)} kg به ازای هر ${profile.driver.unit}',
          ),
      ]),
    );
  }
}

class _CalibratedField extends StatefulWidget {
  const _CalibratedField({super.key, required this.row, required this.enabled, required this.setCode});
  final String setCode;
  final Map<String, Object?> row;
  final bool enabled;

  @override
  State<_CalibratedField> createState() => _CalibratedFieldState();
}

class _CalibratedFieldState extends State<_CalibratedField> {
  late final _c = TextEditingController(
      text: widget.row['calibrated'] == null ? '' : (widget.row['calibrated'] as double).toString());

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final txt = _c.text.trim();
    final v = txt.isEmpty ? null : parseUserNumber(txt);
    if (txt.isNotEmpty && (v == null || v <= 0)) {
      showSnack(context, 'ضریب باید عدد مثبت باشد.', error: true);
      return;
    }
    if (v == widget.row['calibrated']) return;
    final reason = await askReason(context, title: 'ثبت ضریب کالیبره',
        summary: '${widget.row['grp']} / ${widget.row['option']}: ${v == null ? 'بازگشت به ضریب اولیه' : faSmart(v)}');
    if (reason == null || !mounted) return;
    final app = AppScope.read(context);
    app.pb.indices.setCalibrated(widget.setCode, widget.row['grp'] as String, widget.row['option'] as String, v,
        reason: reason);
    app.dataChanged(calcInputs: true);
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        enabled: widget.enabled,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          hintText: '—',
          isDense: true,
          suffixIcon: widget.enabled
              ? IconButton(tooltip: 'ثبت (یا Enter)', icon: const Icon(Icons.check_rounded, size: 18), onPressed: _save)
              : null,
        ),
        onSubmitted: (_) => _save(),
      );
}
