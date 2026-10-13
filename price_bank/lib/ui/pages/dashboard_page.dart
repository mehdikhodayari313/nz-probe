import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/methods.dart';
import '../../core/calc/pump_engine.dart';
import '../../core/import/v8_importer.dart';
import '../../core/price_bank.dart';
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
    final withIssues = rows.where((r) => r.result.qaFlags.isNotEmpty).length;
    final inferredFields = rows.fold<int>(0, (a, r) => a + r.item.meta.values.where((m) => m.flag == 'inferred').length);
    final projects = app.pb.docs.projects();
    final fxEur = app.pb.pumpEngine().eurRateTarget;
    final method = methodByCode(s.escalationMethod);

    // تفکیک زیرگروه (تعداد و سهم)
    final bySub = <String, (int, int)>{};
    for (final r in included) {
      final k = asText(r.item.values['sub_category']);
      final e = bySub[k.isEmpty ? '—' : k] ?? (0, 0);
      bySub[k.isEmpty ? '—' : k] = (e.$1 + 1, e.$2 + (r.result.irrTarget.isNumber ? 1 : 0));
    }
    final subOpts = {for (final o in app.pb.catalog.options('SubCat')) o.value: o.labelFa ?? ''};

    return ListView(padding: const EdgeInsets.fromLTRB(24, 20, 24, 28), children: [
      PageHeader(
        icon: Icons.space_dashboard_rounded,
        title: 'داشبورد',
        subtitle: 'سال هدف ${fa(s.targetYear)} · نرخ ارز «${_fxName(app)}» · روش تعدیل ${method.code}',
      ),
      if (rows.isEmpty) _ImportCard(),
      if (rows.isEmpty) const SizedBox(height: 16),
      const HelpPanel(
        id: 'dashboard',
        title: 'شروع کار',
        initiallyOpen: false,
        lines: [
          'گام ۱ — اگر هنوز داده‌ای ندارید، فایل Pumps_Price_Bank_v8.xlsx را از کارت «ورود داده‌های v8» وارد کنید (فقط یک بار).',
          'گام ۲ — در «شاخص‌ها و ارز» نرخ‌های ارز و شاخص‌ها را تکمیل یا تأیید کنید؛ در «تنظیمات» می‌توانید جدول نرخ ارز تازه با نام دلخواه بسازید.',
          'گام ۳ — سال هدف، جدول نرخ ارز و روش تعدیل را از نوار بالا انتخاب کنید؛ همه‌ی قیمت‌ها فوراً دوباره محاسبه می‌شوند.',
          'گام ۴ — در «تجهیزات» جستجو، فیلتر و ویرایش کنید؛ در «تخمین و تعدیل» قیمت پمپ جدید یا قیمت قدیمی را به سال هدف ببرید.',
          'همه‌ی تغییرات با نام کاربر، زمان و دلیل در «تاریخچه» ثبت می‌شوند.',
        ],
      ),
      Wrap(spacing: 12, runSpacing: 12, children: [
        KpiTile(
          label: 'پمپ‌های ثبت‌شده',
          value: fa(rows.length),
          sub: '${fa(included.length)} شمارش‌شده در جمع‌ها',
          icon: Icons.water_rounded,
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
          label: 'رکوردهای دارای هشدار داده',
          value: fa(withIssues),
          sub: '${fa(inferredFields)} مقدار استنباطی',
          icon: Icons.warning_amber_rounded,
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
      _ProjectTotals(rows: included, unit: unit, targetYear: s.targetYear),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, cons) {
        final wide = cons.maxWidth > 1100;
        final table = SectionCard(
          title: 'تفکیک بر اساس زیرگروه پمپ',
          subtitle: 'فقط رکوردهای شمارش‌شده در جمع‌ها',
          icon: Icons.donut_small_outlined,
          child: Column(children: [
            for (final e in (bySub.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1))))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(
                    width: 220,
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: e.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: '  ${subOpts[e.key] ?? ''}', style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
                    ]), style: t.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: included.isEmpty ? 0 : e.value.$1 / included.length,
                        minHeight: 10,
                        color: AppColors.teal,
                        backgroundColor: t.colorScheme.surfaceContainerHigh,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: Text('${fa(e.value.$1)} پمپ · ${fa(e.value.$2)} با قیمت',
                        textAlign: TextAlign.end, style: t.textTheme.bodySmall),
                  ),
                ]),
              ),
          ]),
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

/// جمع قیمت پمپ‌های هر پروژه: در سال قیمت منبع و در سال هدف، کنار هم.
class _ProjectTotals extends StatelessWidget {
  const _ProjectTotals({required this.rows, required this.unit, required this.targetYear});
  final List<PumpRow> rows;
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
      final res = r.result;
      if (res.irrSource.isNumber && res.irrTarget.isNumber && res.eurSource.isNumber && res.eurTarget.isNumber) {
        final q = r.item.quantity ?? 1;
        a.priced++;
        a.units += q;
        a.irrSrc += res.irrSource.number! * q;
        a.eurSrc += res.eurSource.number! * q;
        a.irrTgt += res.irrTarget.number! * q;
        a.eurTgt += res.eurTarget.number! * q;
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
      title: 'جمع قیمت پمپ‌ها به تفکیک پروژه',
      subtitle: 'قیمت واحد × تعداد · «سال منبع» = با نرخ ارز همان سال قیمت؛ «سال هدف» = تعدیل‌شده با روش فعال به سال ${fa(targetYear)}',
      icon: Icons.account_tree_outlined,
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
      child: list.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text('هنوز پمپی ثبت نشده.', style: t.textTheme.bodySmall),
            )
          : Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                decoration: const BoxDecoration(
                  color: Color(0xFFE3EFF2),
                  border: Border(bottom: BorderSide(color: AppColors.petrol, width: 1.4)),
                ),
                child: Row(children: [
                  cell(Text('پروژه', style: head), flex: 3),
                  cell(Text('پمپ‌ها', style: head, textAlign: TextAlign.center), width: 90),
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
                    color: i.isOdd ? const Color(0xFFF3F8FA) : null,
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
                                    style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF8A5A00))),
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
