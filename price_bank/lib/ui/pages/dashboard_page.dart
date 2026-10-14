import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/methods.dart';
import '../../core/import/v8_importer.dart';
import '../../core/xlsx/xlsx_reader.dart';
import '../format.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/mto_import_dialog.dart';
import 'equipment_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final rows = app.allRows;
    final unit = app.unit;
    final s = app.settings;
    final t = Theme.of(context);

    final included = rows.where((r) => r.item.include).toList();
    final priced = included.where((r) => r.irrTarget != null).toList();
    final projects = app.pb.docs.projects();
    final fxEur = app.pb.pumpEngine().eurRateTarget;
    final method = methodByCode(s.escalationMethod);
    final catsUsed = rows.map((r) => r.categoryId).toSet().length;
    final quotes = rows.fold<int>(0, (a, r) => a + r.item.observations.where((o) => o.kind == 'quote').length);
    // رده‌هایی که روش تعدیل اختصاصی دارند
    final custom = [
      for (final c in app.pb.bankCategories())
        if (c.code != 'PUMP' && s.catMethod(c.code) != null) '${c.nameFa}: ${s.catMethod(c.code)}',
    ];

    return ListView(padding: const EdgeInsets.fromLTRB(24, 20, 24, 28), children: [
      PageHeader(
        icon: Icons.space_dashboard_rounded,
        title: 'داشبورد',
        subtitle: 'سال هدف ${fa(s.targetYear)} · نرخ ارز «${_fxName(app)}» · روش تعدیل ${method.code}',
      ),
      if (app.pumps.isEmpty) _ImportCard(),
      if (app.pumps.isEmpty) const SizedBox(height: 16),
      _StartSteps(hasData: rows.isNotEmpty, hasPumps: app.pumps.isNotEmpty, method: method.code),
      const SizedBox(height: 16),
      Wrap(spacing: 12, runSpacing: 12, children: [
        KpiTile(
          label: 'تجهیزات ثبت‌شده',
          value: fa(rows.length),
          sub: '${fa(catsUsed)} رده · ${fa(included.length)} شمارش‌شده در جمع‌ها',
          icon: Icons.precision_manufacturing_rounded,
          onTap: () => AppShell.go(context, AppShell.equipment),
        ),
        KpiTile(
          label: 'دارای قیمت تعدیل‌شده',
          value: fa(priced.length),
          sub: included.isEmpty ? null : '${fa((priced.length * 100 / included.length).round())}٪ از شمارش‌شده‌ها',
          icon: Icons.price_check_rounded,
          color: Tones.good(context),
        ),
        KpiTile(
          label: 'نرخ یوروی سال ${fa(s.targetYear)}',
          value: fxEur == null ? 'وارد نشده' : faNum(unit == MoneyUnit.toman ? fxEur / 10 : fxEur),
          sub: '${unitLabel(unit)} به ازای هر یورو',
          icon: Icons.euro_rounded,
          color: fxEur == null ? Tones.bad(context) : AppColors.eur,
          onTap: () => AppShell.go(context, AppShell.indices),
        ),
        KpiTile(
          label: 'استعلام‌های فروشندگان',
          value: fa(quotes),
          sub: '${fa(rows.where((r) => r.item.observations.any((o) => o.kind == 'quote')).length)} قلم دارای استعلام',
          icon: Icons.request_quote_outlined,
          color: Tones.warn(context),
        ),
        KpiTile(
          label: 'پروژه‌ها',
          value: fa(projects.length),
          sub: '${fa(app.pb.docs.documents().length)} سند منبع',
          icon: Icons.folder_rounded,
          color: AppColors.teal,
          onTap: () => AppShell.go(context, AppShell.documents),
        ),
      ]),
      const SizedBox(height: 16),
      _ProjectChart(rows: included, unit: unit, targetYear: s.targetYear),
      const SizedBox(height: 16),
      _ProjectTotals(rows: included, unit: unit, targetYear: s.targetYear),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, cons) {
        final wide = cons.maxWidth > 1100;
        final cats = _CategoriesCard(rows: rows, unit: unit, targetYear: s.targetYear);
        final recent = _RecentChanges();
        if (!wide) return Column(children: [cats, const SizedBox(height: 16), recent]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: cats),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: recent),
        ]);
      }),
      const SizedBox(height: 16),
      SectionCard(
        title: 'روش تعدیل فعال: ${method.code} — ${method.nameFa}',
        subtitle: 'آمار صحت‌سنجی روی ۱۴ پمپ پازنان ۲ · برای مقایسه با روش‌های دیگر، صفحه‌ی «روش‌های تعدیل» را باز کنید',
        icon: Icons.verified_outlined,
        trailing: TextButton(onPressed: () => AppShell.go(context, AppShell.methods), child: const Text('همه‌ی روش‌ها')),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(method.formulaFa, style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 2)),
          const SizedBox(height: 6),
          Text(
            'خطای میانه‌ی تک‌قلم ${faNum(method.stats.mdape * 100, decimals: 1)}٪، سوگیری ${faNum(method.stats.bias * 100, decimals: 1)}٪، '
            '${fa(method.stats.within25)} پمپ از ۱۴ در بازه‌ی ±۲۵٪، نسبت جمع پیش‌بینی به واقعی ${faNum(method.stats.totalRatio, decimals: 2)}.'
            '${method.usesFloor ? ' کف قیمت ${faNum(s.floorEur)} یورو (سطح ${fa(s.floorBaseYear)}) فقط برای پمپ گریز از مرکز API 610 با کلاس متریال S یا D.' : ''}',
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.9),
          ),
          const SizedBox(height: 4),
          Text(
            custom.isEmpty
                ? 'همه‌ی رده‌ها با همین روش تعدیل می‌شوند (روش اختصاصی هر رده در «تنظیمات رده» صفحه‌ی تجهیزات).'
                : 'رده‌های با روش اختصاصی: ${custom.join('، ')}',
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
}

/// جمع قیمت تجهیزات هر پروژه (همه‌ی رده‌ها): در سال قیمت منبع و در سال هدف، کنار هم.
class _ProjectTotals extends StatelessWidget {
  const _ProjectTotals({required this.rows, required this.unit, required this.targetYear});
  final List<EquipRow> rows;
  final MoneyUnit unit;
  final int targetYear;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final aggs = <String, _ProjAgg>{};
    for (final r in rows) {
      final name = r.item.projectName ?? 'بدون پروژه';
      final a = aggs[name] ??= _ProjAgg(name);
      a.count++;
      if (r.priced) {
        final q = r.qty;
        a.priced++;
        a.units += q;
        a.irrSrc += r.irrSource! * q;
        a.eurSrc += r.eurSource! * q;
        a.irrTgt += r.irrTarget! * q;
        a.eurTgt += r.eurTarget! * q;
        final y = r.item.primary?.costYear;
        if (y != null) a.years.add(y);
      }
    }
    final list = aggs.values.toList()..sort((a, b) => b.irrTgt.compareTo(a.irrTgt));
    final maxV = list.fold<double>(0, (m, a) => a.irrTgt > m ? a.irrTgt : m);
    final head = t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.petrolDark);

    Widget cell(Widget child, {int flex = 0, double? width}) => flex > 0
        ? Expanded(flex: flex, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: child))
        : SizedBox(width: width, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: child));

    return SectionCard(
      title: 'جمع قیمت تجهیزات به تفکیک پروژه',
      subtitle: 'قیمت واحد × تعداد · «سال منبع» = با نرخ ارز همان سال قیمت؛ «سال هدف» = تعدیل‌شده با روش فعال به سال ${fa(targetYear)}',
      icon: Icons.account_tree_outlined,
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
      child: list.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text('هنوز تجهیزی ثبت نشده.', style: t.textTheme.bodySmall),
            )
          : Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.headerBg,
                  border: Border(bottom: BorderSide(color: AppColors.petrol, width: 1.4)),
                ),
                child: Row(children: [
                  cell(Text('پروژه', style: head), flex: 3),
                  cell(Text('اقلام', style: head, textAlign: TextAlign.center), width: 90),
                  cell(Text('سال قیمت منبع', style: head, textAlign: TextAlign.center), width: 120),
                  cell(Text('جمع در سال منبع', style: head, textAlign: TextAlign.center), flex: 2),
                  cell(Text('جمع در سال ${fa(targetYear)}', style: head, textAlign: TextAlign.center), flex: 2),
                  cell(Text('ضریب رشد', style: head, textAlign: TextAlign.center), width: 96),
                ]),
              ),
              for (var i = 0; i < list.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  decoration: BoxDecoration(
                    color: i.isOdd ? AppColors.zebra : null,
                    border: Border(bottom: BorderSide(color: t.colorScheme.outlineVariant)),
                  ),
                  child: Row(children: [
                    cell(
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(list[i].name,
                            style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        _DualBar(src: list[i].irrSrc, tgt: list[i].irrTgt, max: maxV),
                      ]),
                      flex: 3,
                    ),
                    cell(
                      Column(children: [
                        Text(fa(list[i].count), style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${fa(list[i].priced)} با قیمت', style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
                      ]),
                      width: 90,
                    ),
                    cell(Text(_years(list[i].years), textAlign: TextAlign.center, style: t.textTheme.bodySmall), width: 120),
                    cell(_money(context, list[i].irrSrc, list[i].eurSrc, list[i].priced > 0, muted: true), flex: 2),
                    cell(_money(context, list[i].irrTgt, list[i].eurTgt, list[i].priced > 0), flex: 2),
                    cell(
                      Center(
                        child: list[i].irrSrc > 0
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: AppColors.amberSoft, borderRadius: BorderRadius.circular(8)),
                                child: Text('×${faNum(list[i].irrTgt / list[i].irrSrc, decimals: 1)}',
                                    style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.amberText)),
                              )
                            : Text('—', style: TextStyle(color: t.colorScheme.outline)),
                      ),
                      width: 96,
                    ),
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(children: [
                  _legend(context, AppColors.petrol.withValues(alpha: 0.35), 'سال منبع'),
                  const SizedBox(width: 14),
                  _legend(context, AppColors.amber, 'سال ${fa(targetYear)}'),
                  const Spacer(),
                  Text('ضریب رشد به ${unitLabel(unit)}: اثر هم‌زمان تعدیل یورویی و تغییر نرخ ارز',
                      style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
                ]),
              ),
            ]),
    );
  }

  Widget _legend(BuildContext context, Color c, String s) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(s, style: Theme.of(context).textTheme.labelSmall),
      ]);

  String _years(Set<int> ys) {
    if (ys.isEmpty) return '—';
    final l = ys.toList()..sort();
    if (l.length <= 3) return fa(l.join('، '));
    return fa('${l.first} تا ${l.last}');
  }

  Widget _money(BuildContext context, double irr, double eurV, bool has, {bool muted = false}) {
    final t = Theme.of(context);
    if (!has) return Center(child: Text('—', style: TextStyle(color: t.colorScheme.outline)));
    return Column(children: [
      Text('${money(irr, unit, compact: true, withUnit: false)} ${unitLabel(unit)}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
            color: muted ? t.colorScheme.onSurface.withValues(alpha: 0.75) : AppColors.petrolDark,
          )),
      Text('${compactNum(eurV)} یورو',
          textAlign: TextAlign.center, style: t.textTheme.labelSmall?.copyWith(color: AppColors.eur)),
    ]);
  }
}

class _ProjAgg {
  _ProjAgg(this.name);
  final String name;
  int count = 0, priced = 0;
  double units = 0, irrSrc = 0, eurSrc = 0, irrTgt = 0, eurTgt = 0;
  final Set<int> years = {};
}

class _DualBar extends StatelessWidget {
  const _DualBar({required this.src, required this.tgt, required this.max});
  final double src;
  final double tgt;
  final double max;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      double w(double v) => max <= 0 ? 0 : (v / max).clamp(0.0, 1.0) * c.maxWidth;
      Widget bar(double v, Color col) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              height: 6,
              width: w(v),
              margin: const EdgeInsets.symmetric(vertical: 1),
              decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(3)),
            ),
          );
      return Column(children: [
        bar(src, AppColors.petrol.withValues(alpha: 0.35)),
        bar(tgt, AppColors.amber),
      ]);
    });
  }
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
    'fx_rate_type': 'جدول نرخ ارز',
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
        color: t.colorScheme.primaryContainer,
        border: Border.all(color: AppColors.petrol.withValues(alpha: 0.3)),
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


/// چهار گام «شروع کار» — هم‌ترتیب با منوی کناری؛ هر گام صفحه‌ی مربوط را باز می‌کند.
class _StartSteps extends StatelessWidget {
  const _StartSteps({required this.hasData, required this.hasPumps, required this.method});
  final bool hasData;
  final bool hasPumps;
  final String method;

  @override
  Widget build(BuildContext context) {
    final steps = <(int, IconData, String, String, int?)>[
      (1, Icons.upload_file_rounded, 'ورود داده‌ها',
          hasData
              ? (hasPumps
                  ? 'داده‌ها وارد شده‌اند ✓ — برای افزودن تجهیزات، MTO پروژه‌ی تازه را از کارت «تجهیزات به تفکیک رده» وارد کنید.'
                  : 'MTO وارد شده ✓ — بانک پمپ‌ها (v8) را هم از کارت بالا وارد کنید.')
              : 'بانک پمپ‌ها (v8) را از کارت بالا و MTO پروژه‌ها را از «ورود MTO» وارد کنید.',
          null),
      (2, Icons.query_stats_rounded, 'شاخص‌ها و ارز',
          'نرخ ارز و شاخص‌ها را تکمیل کنید؛ جدول نرخ ارز تازه با نام دلخواه هم همان‌جا ساخته می‌شود.', AppShell.indices),
      (3, Icons.science_rounded, 'روش تعدیل و سال هدف',
          'روش فعال: $method. سال هدف، جدول نرخ ارز و روش را از نوار بالا انتخاب کنید.', AppShell.methods),
      (4, Icons.precision_manufacturing_rounded, 'تجهیزات و تخمین',
          'جستجوی پارامتریک و ویرایش همه‌ی تجهیزات؛ تخمین تجهیز جدید و انتقال قیمت قدیم به سال هدف.', AppShell.equipment),
    ];
    return SectionCard(
      title: 'شروع کار',
      subtitle: 'چهار گام — به همین ترتیب در منوی کناری',
      icon: Icons.route_rounded,
      child: LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth > 1000 ? 4 : 2;
        final w = (c.maxWidth - (cols - 1) * 12) / cols;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final (n, icon, title, body, target) in steps)
            SizedBox(width: w, child: _StepCard(n: n, icon: icon, title: title, body: body, done: n == 1 && hasData, target: target)),
        ]);
      }),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.n, required this.icon, required this.title, required this.body, required this.done, this.target});
  final int n;
  final IconData icon;
  final String title;
  final String body;
  final bool done;
  final int? target;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = done ? Tones.good(context) : AppColors.petrol;
    return HoverLift(
      radius: 14,
      child: Material(
        color: t.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: t.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: target == null ? null : () => AppShell.go(context, target!),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                child: done
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                    : Text(fa(n), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(icon, size: 16, color: c),
                    const SizedBox(width: 6),
                    Expanded(child: Text(title, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                    if (target != null) Icon(Icons.chevron_left_rounded, size: 18, color: t.colorScheme.outline),
                  ]),
                  const SizedBox(height: 4),
                  Text(body, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.7)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// نمودار ستونی تعاملی: جمع قیمت هر پروژه در سال منبع و سال هدف.
/// نشانگر ماوس روی هر ستون، مبلغ دقیق را نشان می‌دهد؛ ستون‌ها با انیمیشن رشد می‌کنند.
class _ProjectChart extends StatefulWidget {
  const _ProjectChart({required this.rows, required this.unit, required this.targetYear});
  final List<EquipRow> rows;
  final MoneyUnit unit;
  final int targetYear;

  @override
  State<_ProjectChart> createState() => _ProjectChartState();
}

class _ProjectChartState extends State<_ProjectChart> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final data = <String, (double, double)>{};
    for (final r in widget.rows) {
      if (r.irrSource == null || r.irrTarget == null) continue;
      final q = r.qty;
      final k = r.item.projectName ?? 'بدون پروژه';
      final e = data[k] ?? (0, 0);
      data[k] = (e.$1 + r.irrSource! * q, e.$2 + r.irrTarget! * q);
    }
    final list = data.entries.toList()..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    if (list.isEmpty) return const SizedBox();
    final maxV = list.map((e) => e.value.$2 > e.value.$1 ? e.value.$2 : e.value.$1).reduce((a, b) => a > b ? a : b);
    const chartH = 190.0;
    final srcColor = AppColors.petrol.withValues(alpha: 0.45);
    const tgtColor = AppColors.amber;

    Widget bar(double v, Color c, String tip, bool hl) => Tooltip(
          message: tip,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: maxV <= 0 ? 0 : v / maxV),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, f, _) => AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: hl ? 26 : 22,
              height: (chartH - 20) * f + 2,
              decoration: BoxDecoration(
                color: c,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                boxShadow: hl ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 12)] : null,
              ),
            ),
          ),
        );

    return SectionCard(
      title: 'مقایسه‌ی پروژه‌ها: سال منبع در برابر سال ${fa(widget.targetYear)}',
      subtitle: 'همه‌ی تجهیزات · نشانگر ماوس را روی هر ستون نگه دارید تا مبلغ دقیق دیده شود (${unitLabel(widget.unit)}، قیمت × تعداد)',
      icon: Icons.bar_chart_rounded,
      trailing: Wrap(spacing: 12, children: [
        _legendDot(context, srcColor, 'سال منبع'),
        _legendDot(context, tgtColor, 'سال ${fa(widget.targetYear)}'),
      ]),
      child: SizedBox(
        height: chartH + 64,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < list.length; i++)
              MouseRegion(
                onEnter: (_) => setState(() => _hover = i),
                onExit: (_) => setState(() => _hover = null),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 150,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: _hover == i ? AppColors.petrol.withValues(alpha: 0.06) : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text('×${faNum(list[i].value.$1 > 0 ? list[i].value.$2 / list[i].value.$1 : 0, decimals: 1)}',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.amberText)),
                    const SizedBox(height: 4),
                    Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      bar(list[i].value.$1, srcColor,
                          '${list[i].key}\nسال منبع: ${money(list[i].value.$1, widget.unit)}', _hover == i),
                      const SizedBox(width: 6),
                      bar(list[i].value.$2, tgtColor,
                          '${list[i].key}\nسال ${fa(widget.targetYear)}: ${money(list[i].value.$2, widget.unit)}', _hover == i),
                    ]),
                    Container(height: 1.5, color: t.colorScheme.outlineVariant),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 34,
                      child: Text(list[i].key,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: t.textTheme.labelSmall?.copyWith(fontWeight: _hover == i ? FontWeight.w800 : FontWeight.w500)),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _legendDot(BuildContext context, Color c, String s) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(s, style: Theme.of(context).textTheme.labelSmall),
      ]);
}


/// تفکیک تجهیزات بر اساس رده: تعداد، سهم از جمع سال هدف، استعلام‌ها + ورود MTO.
class _CategoriesCard extends StatelessWidget {
  const _CategoriesCard({required this.rows, required this.unit, required this.targetYear});
  final List<EquipRow> rows;
  final MoneyUnit unit;
  final int targetYear;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final cats = app.pb.bankCategories();
    final agg = <int, (int, int, double, int)>{}; // تعداد، با قیمت، جمع ریالی هدف، استعلام
    for (final r in rows) {
      final e = agg[r.categoryId] ?? (0, 0, 0.0, 0);
      final inc = r.item.include && r.irrTarget != null;
      agg[r.categoryId] = (
        e.$1 + 1,
        e.$2 + (r.irrTarget != null ? 1 : 0),
        e.$3 + (inc ? r.irrTarget! * r.qty : 0),
        e.$4 + r.item.observations.where((o) => o.kind == 'quote').length,
      );
    }
    final total = agg.values.fold<double>(0, (a, e) => a + e.$3);
    final list = [...cats]..sort((a, b) {
        final c = (agg[b.id]?.$3 ?? 0).compareTo(agg[a.id]?.$3 ?? 0);
        return c != 0 ? c : (agg[b.id]?.$1 ?? 0).compareTo(agg[a.id]?.$1 ?? 0);
      });
    return SectionCard(
      title: 'تجهیزات به تفکیک رده',
      subtitle: 'سهم هر رده از جمع سال ${fa(targetYear)} (شمارش‌شده‌ها) · روی هر رده بزنید تا فهرستش باز شود',
      icon: Icons.category_outlined,
      trailing: app.canEdit('MECH')
          ? FilledButton.icon(
              onPressed: () => showMtoImportDialog(context),
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('ورود MTO'),
            )
          : null,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Column(children: [
        for (final c in list)
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                EquipmentPage.selectedCategory = c.code;
                AppShell.go(context, AppShell.equipment);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: Row(children: [
                  SizedBox(
                    width: 150,
                    child: Text(c.nameFa,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: (agg[c.id]?.$1 ?? 0) == 0 ? t.colorScheme.outline : null)),
                  ),
                  SizedBox(width: 44, child: Center(child: CountBadge(agg[c.id]?.$1 ?? 0))),
                  Expanded(
                    child: Tooltip(
                      message: total <= 0 ? '' : '${faNum((agg[c.id]?.$3 ?? 0) * 100 / total, decimals: 1)}٪ از جمع',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: total <= 0 ? 0 : (agg[c.id]?.$3 ?? 0) / total,
                          minHeight: 10,
                          color: AppColors.teal,
                          backgroundColor: t.colorScheme.surfaceContainerHigh,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 130,
                    child: Text(
                      (agg[c.id]?.$3 ?? 0) <= 0 ? '—' : money(agg[c.id]!.$3, unit, compact: true),
                      textAlign: TextAlign.end,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.petrolDark),
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: Text(
                      (agg[c.id]?.$4 ?? 0) == 0 ? '' : '${fa(agg[c.id]!.$4)} استعلام',
                      textAlign: TextAlign.end,
                      style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
