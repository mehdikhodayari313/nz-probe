import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/pump_engine.dart';
import '../../core/import/v8_importer.dart';
import '../../core/xlsx/xlsx_reader.dart';
import '../format.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/common.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final rows = app.pumps;
    final unit = app.unit;
    final s = app.settings;
    final t = Theme.of(context);

    final included = rows.where((r) => r.item.include).toList();
    final priced = included.where((r) => r.result.irrTarget.isNumber).toList();
    final totalIrr = priced.fold<double>(0, (a, r) => a + r.result.irrTarget.number! * (r.item.quantity ?? 1));
    final withIssues = rows.where((r) => r.result.qaFlags.isNotEmpty).length;
    final inferredFields = rows.fold<int>(0, (a, r) => a + r.item.meta.values.where((m) => m.flag == 'inferred').length);
    final projects = app.pb.docs.projects();
    final fxEur = app.pb.pumpEngine().eurRateTarget;

    // تفکیک زیرگروه
    final bySub = <String, List<dynamic>>{};
    for (final r in included) {
      final k = asText(r.item.values['sub_category']);
      final e = bySub[k.isEmpty ? '—' : k] ??= [0, 0, 0.0];
      e[0] = (e[0] as int) + 1;
      if (r.result.irrTarget.isNumber) {
        e[1] = (e[1] as int) + 1;
        e[2] = (e[2] as double) + r.result.irrTarget.number! * (r.item.quantity ?? 1);
      }
    }
    final subOpts = {for (final o in app.pb.catalog.options('SubCat')) o.value: o.labelFa ?? ''};

    return ListView(padding: const EdgeInsets.fromLTRB(24, 18, 24, 24), children: [
      PageHeader(
        icon: Icons.space_dashboard_rounded,
        title: 'داشبورد',
        subtitle: 'سال هدف ${fa(s.targetYear)} · نرخ ارز «${_fxName(app)}» · روش تعدیل M6',
      ),
      if (rows.isEmpty) _ImportCard(),
      if (rows.isEmpty) const SizedBox(height: 16),
      const HelpPanel(
        id: 'dashboard',
        title: 'شروع کار',
        lines: [
          'گام ۱ — اگر هنوز داده‌ای ندارید، فایل Pumps_Price_Bank_v8.xlsx را از کارت «ورود داده‌های v8» وارد کنید (فقط یک بار).',
          'گام ۲ — در «شاخص‌ها و ارز» نرخ‌های بازار آزاد و مرکز مبادله/نیما و شاخص PPI بخشی ایران را تکمیل یا تأیید کنید.',
          'گام ۳ — سال هدف و نوع نرخ ارز را از نوار بالا انتخاب کنید؛ همه‌ی قیمت‌ها فوراً دوباره محاسبه می‌شوند.',
          'گام ۴ — در «تجهیزات» جستجو، فیلتر و ویرایش کنید؛ در «تخمین و تعدیل» قیمت پمپ جدید یا قیمت قدیمی را به سال هدف ببرید.',
          'همه‌ی تغییرات با نام کاربر، زمان و دلیل در «تاریخچه» ثبت می‌شوند و هیچ داده‌ای پاک نمی‌شود.',
        ],
      ),
      Wrap(spacing: 12, runSpacing: 12, children: [
        KpiTile(label: 'پمپ‌های ثبت‌شده', value: fa(rows.length), sub: '${fa(included.length)} شمارش‌شده در جمع‌ها', icon: Icons.water_rounded),
        KpiTile(
          label: 'دارای قیمت تعدیل‌شده',
          value: fa(priced.length),
          sub: included.isEmpty ? null : '${fa((priced.length * 100 / included.length).round())}٪ از شمارش‌شده‌ها',
          icon: Icons.price_check_rounded,
          color: Tones.good(context),
        ),
        KpiTile(
          label: 'جمع قیمت پمپ‌ها (× تعداد)',
          value: money(totalIrr, unit, compact: true, withUnit: false),
          sub: '${unitLabel(unit)} · سال ${fa(s.targetYear)}',
          icon: Icons.account_balance_rounded,
          width: 260,
        ),
        KpiTile(
          label: 'نرخ یوروی سال هدف',
          value: fxEur == null ? 'وارد نشده' : faNum(unit == MoneyUnit.toman ? fxEur / 10 : fxEur),
          sub: '${unitLabel(unit)} به ازای هر یورو',
          icon: Icons.euro_rounded,
          color: fxEur == null ? Tones.bad(context) : null,
        ),
        KpiTile(
          label: 'رکوردهای دارای هشدار داده',
          value: fa(withIssues),
          sub: '${fa(inferredFields)} مقدار استنباطی',
          icon: Icons.warning_amber_rounded,
          color: Tones.warn(context),
        ),
        KpiTile(label: 'پروژه‌ها', value: fa(projects.length), icon: Icons.folder_rounded),
      ]),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, cons) {
        final wide = cons.maxWidth > 1100;
        final table = SectionCard(
          title: 'تفکیک بر اساس زیرگروه پمپ',
          subtitle: 'فقط رکوردهای شمارش‌شده در جمع‌ها',
          icon: Icons.donut_small_outlined,
          child: Table(
            columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1.2), 3: FlexColumnWidth(2.4), 4: FlexColumnWidth(2.4)},
            children: [
              TableRow(
                decoration: BoxDecoration(color: t.colorScheme.surfaceContainerHigh),
                children: [
                  _c(context, 'زیرگروه', b: true),
                  _c(context, 'تعداد', b: true),
                  _c(context, 'با قیمت', b: true),
                  _c(context, 'جمع (${unitLabel(unit)})', b: true),
                  _c(context, 'سهم', b: true),
                ],
              ),
              for (final e in (bySub.entries.toList()..sort((a, b) => (b.value[2] as double).compareTo(a.value[2] as double))))
                TableRow(children: [
                  _c(context, '${e.key}  ${subOpts[e.key] ?? ''}'),
                  _c(context, fa(e.value[0])),
                  _c(context, fa(e.value[1])),
                  _c(context, money(e.value[2] as double, unit, compact: true, withUnit: false)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: totalIrr == 0 ? 0 : (e.value[2] as double) / totalIrr,
                        minHeight: 8,
                      ),
                    ),
                  ),
                ]),
            ],
          ),
        );
        final recent = _RecentChanges();
        if (!wide) return Column(children: [table, const SizedBox(height: 16), recent]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: table),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: recent),
        ]);
      }),
      const SizedBox(height: 16),
      SectionCard(
        title: 'روش تعدیل قیمت پمپ (M6)',
        subtitle: 'مصوب فایل Pump_Escalation_Validation — بهترین دقت روی ۱۴ پمپ پازنان ۲',
        icon: Icons.verified_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(
            'ریال(هدف) = MAX[ قیمت پایه ÷ نرخ تسعیر منبع × PPI(هدف)/PPI(پایه) ، ${faNum(s.floorEur)} یورو × PPI(هدف)/PPI(${fa(s.floorBaseYear)}) ] × نرخ یورو(هدف)',
            style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 2),
          ),
          const SizedBox(height: 6),
          Text(
            'خطای میانه‌ی تک‌قلم ۱۳٪، سوگیری ‎−۷٪، نسبت جمع پیش‌بینی به واقعی ۱٫۰۱. کف قیمت فقط برای پمپ گریز از مرکز API 610 با کلاس متریال S یا D. '
            'تورم ریالی (CPI) برای پمپ استفاده نمی‌شود؛ برای تجهیزات ساخت داخل، PPI بخشی ایران در نظر گرفته شده است.',
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.9),
          ),
        ]),
      ),
    ]);
  }

  String _fxName(AppState app) {
    for (final f in app.pb.settingsRepo.fxRateTypes()) {
      if (f.code == app.settings.fxRateType) return f.nameFa;
    }
    return app.settings.fxRateType;
  }

  Widget _c(BuildContext context, String s, {bool b = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(s, style: TextStyle(fontSize: 13, fontWeight: b ? FontWeight.w700 : null)),
      );
}

class _RecentChanges extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final list = app.pb.audit.recent(limit: 8).where((e) => !(e.reason ?? '').startsWith('انتقال از')).toList();
    return SectionCard(
      title: 'آخرین تغییرات',
      icon: Icons.history_rounded,
      trailing: TextButton(onPressed: () => AppShell.go(context, AppShell.history), child: const Text('همه')),
      child: list.isEmpty
          ? Text('هنوز تغییری ثبت نشده.', style: t.textTheme.bodySmall)
          : Column(children: [
              for (final e in list)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Icon(Icons.circle, size: 7, color: t.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_entityFa[e.entity] ?? e.entity} ${e.entityId ?? ''} · ${e.field == '*' ? 'ایجاد' : e.field ?? ''}',
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodySmall,
                      ),
                    ),
                    Text(shortTs(e.ts), style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  ]),
                ),
            ]),
    );
  }

  static const _entityFa = {
    'item': 'قلم',
    'index': 'شاخص',
    'settings': 'تنظیم',
    'document': 'سند',
    'project': 'پروژه',
    'factor': 'ضریب',
    'user': 'کاربر',
    'vendor': 'فروشنده',
  };
}

class _ImportCard extends StatefulWidget {
  @override
  State<_ImportCard> createState() => _ImportCardState();
}

class _ImportCardState extends State<_ImportCard> {
  bool _busy = false;

  Future<void> _run() async {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'انتخاب فایل Pumps_Price_Bank_v8.xlsx',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      if (!mounted) return;
      final app = AppScope.read(context);
      final wb = XlsxWorkbook.openFile(path);
      final err = V8Importer.validate(wb);
      if (err != null) throw FormatException(err);
      final rep = app.pb.v8Importer().run(wb, fileName: res!.files.single.name);
      app.dataChanged(calcInputs: true);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(rep.alreadyImported ? Icons.info_outline : Icons.check_circle_rounded, color: Tones.good(ctx), size: 40),
          title: Text(rep.alreadyImported ? 'این داده‌ها قبلاً وارد شده‌اند' : 'انتقال کامل شد'),
          content: rep.alreadyImported
              ? const Text('برای جلوگیری از رکورد تکراری، ورود دوباره انجام نشد.')
              : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('پمپ‌ها: ${fa(rep.items)}'),
                  Text('پروژه‌ها: ${fa(rep.projects)} · اسناد منبع: ${fa(rep.documents)}'),
                  Text('فروشندگان: ${fa(rep.vendors)} · استعلام‌ها: ${fa(rep.quotes)}'),
                  Text('مقادیر استنباطی (زرد): ${fa(rep.inferredFlags)} · تبدیل ارزی (آبی): ${fa(rep.fxFlags)}'),
                  Text('یادداشت‌های شاهد: ${fa(rep.notes)}'),
                  for (final w in rep.warnings.take(5)) Text('⚠ $w', style: TextStyle(color: Tones.warn(ctx))),
                ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('بسیار خوب'))],
        ),
      );
    } catch (e) {
      if (mounted) showSnack(context, 'ورود ناموفق: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.colorScheme.primaryContainer, t.colorScheme.tertiaryContainer],
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Icon(Icons.upload_file_rounded, size: 46, color: t.colorScheme.onPrimaryContainer),
        const SizedBox(width: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ورود داده‌های بانک قیمت v8',
                style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: t.colorScheme.onPrimaryContainer)),
            const SizedBox(height: 4),
            Text(
              'فایل Pumps_Price_Bank_v8.xlsx را انتخاب کنید. ۱۴۶ پمپ با همه‌ی مشخصات، پروژه‌ها، اسناد منبع، فروشندگان، استعلام‌ها، '
              'یادداشت‌های شاهد و برچسب مقادیر استنباطی منتقل می‌شوند. فایل اکسل تغییر نمی‌کند.',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onPrimaryContainer, height: 1.8),
            ),
          ]),
        ),
        const SizedBox(width: 18),
        FilledButton.icon(
          onPressed: _busy ? null : _run,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.file_open_rounded),
          label: Text(_busy ? 'در حال انتقال…' : 'انتخاب فایل v8'),
        ),
      ]),
    );
  }
}
