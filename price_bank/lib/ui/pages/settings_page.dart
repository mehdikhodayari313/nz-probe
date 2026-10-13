import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/series.dart';
import '../format.dart';
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
          'سال هدف، نوع نرخ ارز و واحد نمایش (ریال/تومان) از نوار بالای برنامه هم قابل تغییرند.',
          'همه‌ی پارامترها در تاریخچه ثبت می‌شوند. مقادیر پیش‌فرض همان مقادیر فایل v8 است.',
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
              child: DropdownButtonFormField<String>(
                value: ppiSeries.any((x) => x.code == s.ppiSeries) ? s.ppiSeries : null,
                isExpanded: true,
                items: [for (final x in ppiSeries) DropdownMenuItem(value: x.code, child: Text('${x.nameFa}  (${x.code})'))],
                onChanged: admin ? (v) => app.setSetting('ppi_series', v, reason: 'تغییر شاخص تعدیل پمپ') : null,
              ),
            ),
          ]),
          const SizedBox(height: 10),
          for (final (key, label, help) in _params) _ParamRow(keyName: key, label: label, help: help, enabled: admin),
        ]),
      ),
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

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final types = app.pb.settingsRepo.fxRateTypes();
    final snap = app.pb.seriesSnapshot;
    final y = app.settings.targetYear;
    return SectionCard(
      title: 'انواع نرخ ارز',
      subtitle: 'نوع فعال از نوار بالا انتخاب می‌شود. مقادیر هر نوع در صفحه‌ی «شاخص‌ها و ارز» ویرایش می‌شود.',
      icon: Icons.currency_exchange_rounded,
      child: Column(children: [
        for (final t in types)
          ListTile(
            dense: true,
            leading: Icon(t.code == app.settings.fxRateType ? Icons.radio_button_checked : Icons.radio_button_off),
            title: Text(t.nameFa),
            subtitle: Text('FX_EUR_${t.code} / FX_USD_${t.code}', textDirection: TextDirection.ltr, textAlign: TextAlign.end),
            trailing: SizedBox(
              width: 340,
              child: Text(
                'یورو ${fa(y)}: ${faNum(snap.resolve('FX_EUR_${t.code}', y)?.value)} · دلار: ${faNum(snap.resolve('FX_USD_${t.code}', y)?.value)}',
                textAlign: TextAlign.end,
              ),
            ),
            onTap: () => app.setSetting('fx_rate_type', t.code, reason: 'تنظیمات'),
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
