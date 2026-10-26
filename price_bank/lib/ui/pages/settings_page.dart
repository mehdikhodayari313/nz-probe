import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/series.dart';
import '../../core/repo/settings_repo.dart';
import '../format.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _params = <(String, String, String)>[
    ('target_month', 'ماه هدف (اختیاری، ۱ تا ۱۲)', 'اگر شاخص و نرخ ارز ماهانه وارد شده باشد، قیمت به همان ماه تعدیل می‌شود. خالی = سالانه.'),
    ('floor_eur', 'کف قیمت پمپ API 610 (یورو)', 'حداقل قیمت پمپ گریز از مرکز API 610 با کلاس S یا D در سطح سال کف.'),
    ('floor_base_year', 'سال مبنای کف قیمت', 'کف قیمت با نسبت PPI(هدف)/PPI(این سال) تعدیل می‌شود.'),
    ('cost_exponent_n', 'توان اندازه n (قیمت ∝ kWⁿ)', 'برای تخمین پمپ جدید؛ مقدار پیش‌فرض ۰٫۶ (قانون شش‌دهم).'),
    ('pump_efficiency', 'راندمان پمپ η (برای برآورد توان)', 'kW ≈ Q[m³/h]·H[m] / (367·η) — آب با چگالی ۱.'),
    ('eur_check_limit', 'سقف کنترل قیمت یورویی', 'قیمت یورویی بیش از این مقدار احتمالاً ارز اشتباه دارد و از محاسبه کنار گذاشته می‌شود.'),
    ('eur_target_override', 'نرخ یوروی هدف دستی (ریال) — اختیاری', 'اگر پر شود، به‌جای جدول نرخ ارز استفاده می‌شود (مثلاً نرخ روز).'),
    ('usd_target_override', 'نرخ دلار هدف دستی (ریال) — اختیاری', 'اگر پر شود، به‌جای جدول نرخ ارز استفاده می‌شود.'),
  ];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.settings;
    final admin = app.user.isAdmin;
    final ppiSeries = app.pb.indices.series().where((x) => x.group.startsWith('ppi') && x.calendar == 'jalali').toList();

    return ListView(padding: const EdgeInsets.all(20), children: [
      const PageHeader(icon: Icons.settings_rounded, title: 'تنظیمات', subtitle: 'پارامترهای محاسبه، نرخ ارز و دیتابیس'),
      const HelpPanel(
        id: 'settings',
        title: 'تنظیمات',
        initiallyOpen: false,
        lines: [
          'سال هدف، جدول نرخ ارز، روش تعدیل و واحد نمایش (ریال/تومان) از نوار بالای برنامه هم قابل تغییرند.',
          'جدول نرخ ارز دلخواه (مثلاً نرخ بودجه یا نرخ قرارداد) در صفحه‌ی «شاخص‌ها و ارز» با دکمه‌ی «+ جدول نرخ ارز» ساخته و حذف می‌شود.',
          'در «ظاهر برنامه» حالت روز/شب و رنگ اصلی برنامه را انتخاب کنید.',
          'همه‌ی پارامترها در تاریخچه ثبت می‌شوند.',
          'از دیتابیس به‌طور منظم پشتیبان بگیرید؛ فایل پشتیبان یک فایل کامل و مستقل است.',
        ],
      ),
      SectionCard(
        title: 'پارامترهای محاسبه',
        icon: Icons.functions_rounded,
        child: Column(children: [
          Row(children: [
            const SizedBox(width: 300, child: Text('شاخص تعدیل پمپ (PPI)')),
            Expanded(
              child: DropdownButtonFormField<String>(itemHeight: null, 
                value: ppiSeries.any((x) => x.code == s.ppiSeries) ? s.ppiSeries : null,
                isExpanded: true,
                items: [for (final x in ppiSeries) DropdownMenuItem(value: x.code, child: DdText('${x.nameFa}  (${x.code})'))],
                onChanged: admin ? (v) => app.setSetting('ppi_series', v, reason: 'تغییر شاخص تعدیل پمپ') : null,
              ),
            ),
          ]),
          const SizedBox(height: 10),
          for (final (key, label, help) in _params) _ParamRow(keyName: key, label: label, help: help, enabled: admin),
        ]),
      ),
      const SizedBox(height: 14),
      const _AppearanceCard(),
      const SizedBox(height: 14),
      const _FxTypesCard(),
      const SizedBox(height: 14),
      const _DatabaseCard(),
    ]);
  }
}

class _ParamRow extends StatefulWidget {
  const _ParamRow({required this.keyName, required this.label, required this.help, required this.enabled});
  final String keyName;
  final String label;
  final String help;
  final bool enabled;

  @override
  State<_ParamRow> createState() => _ParamRowState();
}

class _ParamRowState extends State<_ParamRow> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: AppScope.read(context).settings.str(widget.keyName));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _save() {
    final app = AppScope.read(context);
    final txt = _c.text.trim();
    if (txt.isNotEmpty && parseUserNumber(txt) == null) {
      showSnack(context, 'مقدار باید عددی باشد.', error: true);
      return;
    }
    final v = txt.isEmpty ? null : parseUserNumber(txt)!;
    if (widget.keyName == 'target_month' && v != null && (v < 1 || v > 12)) {
      showSnack(context, 'ماه باید بین ۱ و ۱۲ باشد.', error: true);
      return;
    }
    final str = v == null ? null : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString());
    if (str == (app.settings.str(widget.keyName).isEmpty ? null : app.settings.str(widget.keyName))) return;
    app.setSetting(widget.keyName, str, reason: 'تنظیمات');
    showSnack(context, '«${widget.label}» ذخیره شد؛ محاسبات به‌روز شدند.');
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(
            width: 300,
            child: Row(children: [
              Flexible(child: Text(widget.label)),
              Tooltip(message: widget.help, child: const Padding(
                padding: EdgeInsetsDirectional.only(start: 4),
                child: Icon(Icons.info_outline_rounded, size: 15),
              )),
            ]),
          ),
          Expanded(
            child: TextField(
              controller: _c,
              enabled: widget.enabled,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                hintText: '—',
                suffixIcon: widget.enabled
                    ? IconButton(icon: const Icon(Icons.check_rounded, size: 18), tooltip: 'ذخیره (یا Enter)', onPressed: _save)
                    : null,
              ),
              onSubmitted: (_) => _save(),
            ),
          ),
        ]),
      );
}

class _FxTypesCard extends StatelessWidget {
  const _FxTypesCard();

  Future<void> _rename(BuildContext context, FxRateType ft) async {
    final c = TextEditingController(text: ft.nameFa);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تغییر نام جدول نرخ ارز'),
        content: SizedBox(
          width: 420,
          child: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'نام جدید')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('ذخیره')),
        ],
      ),
    );
    c.dispose();
    if (name == null || name.isEmpty || !context.mounted) return;
    final app = AppScope.read(context);
    app.pb.settingsRepo.renameFxType(ft.code, name);
    app.dataChanged(calcInputs: true);
  }

  Future<void> _delete(BuildContext context, FxRateType ft) async {
    final ok = await confirm(context, 'حذف جدول «${ft.nameFa}»',
        'همه‌ی نرخ‌های یورو و دلار این جدول حذف می‌شوند. اگر این جدول انتخاب شده باشد، «جدول پیش‌فرض» جایگزین می‌شود. حذف در تاریخچه ثبت می‌شود.',
        ok: 'حذف');
    if (!ok || !context.mounted) return;
    final app = AppScope.read(context);
    app.pb.settingsRepo.deleteFxType(ft.code);
    app.dataChanged(calcInputs: true);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final th = Theme.of(context);
    final types = app.pb.settingsRepo.fxRateTypes();
    final snap = app.pb.seriesSnapshot;
    final y = app.settings.targetYear;
    final admin = app.user.isAdmin;
    return SectionCard(
      title: 'جدول‌های نرخ ارز',
      subtitle: 'جدول فعال از نوار بالا یا با زدن روی هر ردیف انتخاب می‌شود. ساخت، حذف و ورود مقادیر جدول‌ها در صفحه‌ی «شاخص‌ها و ارز» است.',
      icon: Icons.currency_exchange_rounded,
      trailing: OutlinedButton.icon(
        onPressed: () => AppShell.go(context, AppShell.indices),
        icon: const Icon(Icons.open_in_new_rounded, size: 18),
        label: const Text('شاخص‌ها و ارز'),
      ),
      child: Column(children: [
        for (final ft in types)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: ft.code == app.settings.fxRateType ? AppColors.amberSoft : th.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: ft.code == app.settings.fxRateType ? AppColors.amber : th.colorScheme.outlineVariant),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => app.setSetting('fx_rate_type', ft.code, reason: 'تنظیمات'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    Icon(ft.code == app.settings.fxRateType ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: ft.code == app.settings.fxRateType ? AppColors.amberText : th.colorScheme.outline, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Flexible(child: Text(ft.nameFa, style: const TextStyle(fontWeight: FontWeight.w700))),
                          const SizedBox(width: 6),
                          if (ft.userDefined) Pill('تعریف کاربر', color: AppColors.teal),
                          if (ft.code == 'V8') Pill('داده‌ی پیش‌فرض فایل v8', color: AppColors.petrol),
                        ]),
                        Text('FX_EUR_${ft.code} / FX_USD_${ft.code}',
                            textDirection: TextDirection.ltr,
                            style: th.textTheme.labelSmall?.copyWith(color: th.colorScheme.outline)),
                      ]),
                    ),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: 'یورو ${fa(y)}: '),
                        TextSpan(
                            text: faNum(snap.resolve('FX_EUR_${ft.code}', y)?.value),
                            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.eur)),
                        const TextSpan(text: '   دلار: '),
                        TextSpan(
                            text: faNum(snap.resolve('FX_USD_${ft.code}', y)?.value),
                            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.usd)),
                      ]),
                      style: th.textTheme.bodySmall,
                    ),
                    if (admin) ...[
                      const SizedBox(width: 6),
                      IconButton(tooltip: 'تغییر نام', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _rename(context, ft)),
                      if (ft.userDefined)
                        IconButton(
                          tooltip: 'حذف جدول',
                          icon: Icon(Icons.delete_outline_rounded, size: 19, color: Tones.bad(context)),
                          onPressed: () => _delete(context, ft),
                        ),
                    ],
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _DatabaseCard extends StatelessWidget {
  const _DatabaseCard();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pb = app.pb;
    return SectionCard(
      title: 'دیتابیس و پشتیبان',
      icon: Icons.storage_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SelectableText('محل فایل: ${pb.db.path}', textDirection: TextDirection.ltr),
        const SizedBox(height: 4),
        Text('نسخه‌ی ساختار: ${fa(pb.db.schemaVersion)} · اقلام: ${fa(pb.items.count(pb.pumpCategory.id))} · سری‌های شاخص: ${fa(pb.indices.series().length)}'),
        const SizedBox(height: 12),
        Wrap(spacing: 10, children: [
          FilledButton.tonalIcon(
            onPressed: () => _backup(context),
            icon: const Icon(Icons.backup_rounded),
            label: const Text('تهیه‌ی پشتیبان'),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          'برای بازگرداندن پشتیبان: برنامه را ببندید و فایل پشتیبان را با نام price_bank.db در محل بالا جایگزین کنید.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Text('دوره‌ی فعلی تعدیل: ${Period.year(app.settings.targetYear).label}', style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }

  Future<void> _backup(BuildContext context) async {
    final now = DateTime.now();
    final name = 'price_bank_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.db';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'ذخیره‌ی پشتیبان دیتابیس',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: const ['db'],
    );
    if (path == null || !context.mounted) return;
    try {
      AppScope.read(context).pb.db.backupTo(path);
      showSnack(context, 'پشتیبان ذخیره شد: $path');
    } catch (e) {
      showSnack(context, 'پشتیبان‌گیری ناموفق: $e', error: true);
    }
  }
}


/// ظاهر برنامه: حالت روز/شب و رنگ اصلی (پالت).
class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final mode = app.settings.str('theme_mode', 'light');
    final pal = app.settings.str('theme_palette', 'mist');
    return SectionCard(
      title: 'ظاهر برنامه',
      subtitle: 'حالت روز و شب و رنگ اصلی؛ بلافاصله اعمال و برای دفعه‌های بعد ذخیره می‌شود',
      icon: Icons.palette_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const SizedBox(width: 160, child: Text('حالت نمایش')),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'light', icon: Icon(Icons.light_mode_rounded, size: 18), label: Text('روز')),
              ButtonSegment(value: 'dark', icon: Icon(Icons.dark_mode_rounded, size: 18), label: Text('شب')),
              ButtonSegment(value: 'system', icon: Icon(Icons.brightness_auto_rounded, size: 18), label: Text('مطابق ویندوز')),
            ],
            selected: {mode},
            onSelectionChanged: (v) => app.setSetting('theme_mode', v.first, reason: 'ظاهر برنامه'),
          ),
        ]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(width: 160, child: Padding(padding: EdgeInsets.only(top: 8), child: Text('رنگ اصلی'))),
          Expanded(
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              for (final p in appPalettes)
                _Swatch(
                  palette: p,
                  selected: p.code == pal,
                  onTap: () => app.setSetting('theme_palette', p.code, reason: 'ظاهر برنامه'),
                ),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Text('رنگ‌های ارزها (یورو آبی، دلار سبز، ریال/تومان قهوه‌ای) در همه‌ی پالت‌ها ثابت می‌مانند.',
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.palette, required this.selected, required this.onTap});
  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Tooltip(
      message: palette.nameFa,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 96,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AppColors.amber : t.colorScheme.outlineVariant, width: selected ? 2 : 1),
            color: t.colorScheme.surfaceContainerLow,
          ),
          child: Column(children: [
            Row(children: [
              Expanded(child: Container(height: 26, decoration: BoxDecoration(color: palette.navy, borderRadius: BorderRadius.circular(6)))),
              const SizedBox(width: 3),
              Expanded(child: Container(height: 26, decoration: BoxDecoration(color: palette.primary, borderRadius: BorderRadius.circular(6)))),
              const SizedBox(width: 3),
              Expanded(child: Container(height: 26, decoration: BoxDecoration(color: palette.accent2, borderRadius: BorderRadius.circular(6)))),
            ]),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (selected) const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.amber),
              if (selected) const SizedBox(width: 4),
              Text(palette.nameFa, style: t.textTheme.labelMedium?.copyWith(fontWeight: selected ? FontWeight.w800 : null)),
            ]),
          ]),
        ),
      ),
    );
  }
}
