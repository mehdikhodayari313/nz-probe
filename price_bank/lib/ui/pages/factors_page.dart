import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/catalog/profiles.dart';
import '../../core/price_bank.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';

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

class FactorsPage extends StatefulWidget {
  const FactorsPage({super.key});

  @override
  State<FactorsPage> createState() => _FactorsPageState();
}

class _FactorsPageState extends State<FactorsPage> {
  String _set = PriceBank.pumpFactorSet;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cats = app.pb.catalog.categories().where((c) => equipmentProfiles.containsKey(c.code)).toList();
    final sets = <String, String>{
      PriceBank.pumpFactorSet: 'پمپ',
      for (final c in cats)
        if (equipmentProfiles[c.code]!.factorGroups.isNotEmpty) factorSetOf(c.code): c.nameFa,
    };
    if (!sets.containsKey(_set)) _set = PriceBank.pumpFactorSet;
    final isPump = _set == PriceBank.pumpFactorSet;
    final rows = app.pb.indices.factors(_set);
    final groups = <String, List<Map<String, Object?>>>{};
    for (final r in rows) {
      (groups[r['grp'] as String] ??= []).add(r);
    }
    final calibrated = rows.where((r) => r['calibrated'] != null).length;
    final canEdit = app.user.isAdmin || app.user.role == 'reviewer';

    return ListView(padding: const EdgeInsets.all(20), children: [
      PageHeader(
        icon: Icons.tune_rounded,
        title: 'ضرایب نرمال‌سازی',
        subtitle: '${sets[_set]} · ${fa(rows.length)} ضریب · ${fa(calibrated)} کالیبره‌شده'
            '${isPump ? ' · پیکربندی پایه: S-5، Arr 1 / Plan 11 / Cat 2، موتور برقی، بدون NACE' : ''}',
        actions: [
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              value: _set,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'رده‌ی تجهیز'),
              items: [for (final e in sets.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _set = v ?? _set),
            ),
          ),
        ],
      ),
      const HelpPanel(
        id: 'factors',
        title: 'این ضرایب چه کار می‌کنند؟',
        lines: [
          'قیمت هر پمپ بر حاصل‌ضرب ضرایب پیکربندی‌اش تقسیم می‌شود تا «قیمت معادل پیکربندی پایه» به دست آید؛ این مبنای مقایسه‌ی پمپ‌ها و تخمین پمپ جدید است.',
          'ضرایب اولیه بر پایه‌ی قضاوت مهندسی‌اند و هنوز کالیبره نشده‌اند. وقتی با استعلام‌های واقعی ضریب دقیق‌تری به دست آمد، آن را در ستون «ضریب کالیبره» وارد کنید.',
          'ضریب کالیبره جایگزین ضریب اولیه می‌شود؛ پاک کردن آن، ضریب اولیه را برمی‌گرداند. همه‌ی تغییرات در تاریخچه ثبت می‌شود.',
          'ضرایب فقط روی «یورو نرمال‌شده» و «ضریب هزینه» (تخمین پمپ جدید) اثر دارند، نه روی قیمت تعدیل‌شده‌ی خود پمپ.',
        ],
      ),
      for (final g in groups.entries) ...[
        SectionCard(
          title: (isPump ? _groupFa[g.key] : _genGroupFa[g.key]) ?? g.key,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Table(
            columnWidths: const {0: FlexColumnWidth(2), 1: FixedColumnWidth(110), 2: FixedColumnWidth(150), 3: FixedColumnWidth(110), 4: FlexColumnWidth(4)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: BoxDecoration(color: AppColors.headerBg),
                children: [for (final h in ['گزینه', 'ضریب اولیه', 'ضریب کالیبره', 'ضریب مورد استفاده', 'شرح']) _c(h, b: true)],
              ),
              for (final r in g.value)
                TableRow(children: [
                  _c(r['option'] as String, b: true),
                  _c(faSmart(r['provisional'] as double)),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: _CalibratedField(key: ValueKey('$_set|${r['grp']}|${r['option']}'), row: r, enabled: canEdit, setCode: _set),
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
