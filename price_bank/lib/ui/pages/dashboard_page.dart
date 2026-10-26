import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/methods.dart';
import '../../core/import/compressor_importer.dart';
import '../../core/import/desalter_importer.dart';
import '../../core/import/price_bank_importer.dart';
import '../../core/import/v8_importer.dart';
import '../../core/xlsx/xlsx_reader.dart';
import '../format.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/mto_import_dialog.dart';
import '../widgets/backdrop.dart';
import '../widgets/command_palette.dart' show Kbd;
import '../widgets/trend_kpi_tile.dart';
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
    final engine = app.pb.pumpEngine();
    final fxEur = engine.eurRateTarget;
    // روند ۸ سال اخیر نرخ یورو و PPI (سال هدف و ۷ سال پیش از آن)
    final eurTrend = <double>[], eurYears = <int>[], ppiTrend = <double>[], ppiYears = <int>[];
    for (var y = s.targetYear - 7; y <= s.targetYear; y++) {
      final e = engine.series.resolve(engine.settings.fxEurCode, y)?.value;
      if (e != null && e > 0) {
        eurTrend.add(unit == MoneyUnit.toman ? e / 10 : e);
        eurYears.add(y);
      }
      final p = engine.ppi(y);
      if (p != null) {
        ppiTrend.add(p);
        ppiYears.add(y);
      }
    }
    // تغییر سال هدف نسبت به سال قبل (فقط وقتی هر دو سال مقدار دارند)
    double? change(List<double> v, List<int> ys) => v.length >= 2 && ys.last == s.targetYear && ys[ys.length - 2] == s.targetYear - 1
        ? (v.last / v[v.length - 2] - 1) * 100
        : null;
    final ppiNow = ppiYears.isNotEmpty && ppiYears.last == s.targetYear ? ppiTrend.last : null;
    final quoted = rows.where((r) => r.item.observations.any((o) => o.kind == 'quote')).length;
    final method = methodByCode(s.escalationMethod);
    final catsUsed = rows.map((r) => r.categoryId).toSet().length;
    final quotes = rows.fold<int>(0, (a, r) => a + r.item.observations.where((o) => o.kind == 'quote').length);
    // روش تعدیل هر رده‌ی دارای قلم (هر تجهیز روش خودش را دارد)
    final counts = app.pb.categoryCounts();
    final custom = [
      for (final c in app.pb.bankCategories())
        if (c.code != 'PUMP' && (counts[c.id] ?? 0) > 0) '${c.nameFa}: ${s.methodFor(c.code)}',
    ];
    final desCat = app.pb.catalog.categoryByCode('DESALTER');
    final hasDesBank = desCat != null &&
        (app.pb.db.scalar("SELECT COUNT(*) FROM items WHERE category_id = ? AND legacy_ref LIKE 'DES-%'", [desCat.id])
                as int) >
            0;
    final cmpCat = app.pb.catalog.categoryByCode('COMPRESSOR');
    final hasCmpBank = cmpCat != null &&
        (app.pb.db.scalar("SELECT COUNT(*) FROM items WHERE category_id = ? AND legacy_ref LIKE 'CMP-%'", [cmpCat.id])
                as int) >
            0;

    return ListView(padding: const EdgeInsets.fromLTRB(24, 20, 24, 28), children: [
      _Hero(
        meta: 'سال هدف ${fa(s.targetYear)} · نرخ ارز «${_fxName(app)}» · روش تعدیل ${method.code}',
        stats: [
          (fa(rows.length), 'قلم تجهیز'),
          (fa(projects.length), 'پروژه'),
          (fa(catsUsed), 'رده'),
          (fa(quotes), 'استعلام'),
        ],
      ),
      const SizedBox(height: 16),
      if (app.pumps.isEmpty || !hasDesBank || !hasCmpBank)
        _ImportCard(pumps: app.pumps.isNotEmpty, desalters: hasDesBank, compressors: hasCmpBank),
      if (app.pumps.isEmpty) const SizedBox(height: 16),
      _StartSteps(hasData: rows.isNotEmpty, hasPumps: app.pumps.isNotEmpty, method: method.code),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, cons) {
        // همه‌ی کاشی‌ها در یک ردیف با پهنای برابر؛ در پنجره‌ی باریک سه‌تایی
        final n = cons.maxWidth >= 1200 ? 6 : (cons.maxWidth >= 640 ? 3 : 2);
        final w = ((cons.maxWidth - 12 * (n - 1)) / n).floorToDouble();
        return Wrap(spacing: 12, runSpacing: 12, children: [
          TrendKpiTile(
            width: w,
            label: 'تجهیزات ثبت‌شده',
            value: fa(rows.length),
            caption: '${fa(catsUsed)} رده · ${fa(included.length)} شمارش‌شده در جمع‌ها',
            icon: Icons.precision_manufacturing_rounded,
            progress: rows.isEmpty ? null : included.length / rows.length,
            onTap: () => AppShell.go(context, AppShell.equipment),
          ),
          TrendKpiTile(
            width: w,
            label: 'دارای قیمت تعدیل‌شده',
            value: fa(priced.length),
            caption: included.isEmpty ? null : '${fa((priced.length * 100 / included.length).round())}٪ از شمارش‌شده‌ها',
            icon: Icons.price_check_rounded,
            color: Tones.good(context),
            progress: included.isEmpty ? null : priced.length / included.length,
          ),
          TrendKpiTile(
            width: w,
            label: 'نرخ یوروی سال ${fa(s.targetYear)}',
            value: fxEur == null ? 'وارد نشده' : faNum(unit == MoneyUnit.toman ? fxEur / 10 : fxEur),
            caption: change(eurTrend, eurYears) == null
                ? '${unitLabel(unit)} به ازای هر یورو'
                : '${unitLabel(unit)} · نسبت به ${fa(s.targetYear - 1)}',
            icon: Icons.euro_rounded,
            color: fxEur == null ? Tones.bad(context) : AppColors.eur,
            delta: change(eurTrend, eurYears),
            lowerIsBetter: true,
            trend: eurTrend,
            trendLabels: [for (final y in eurYears) 'سال ${fa(y)} · ${unitLabel(unit)}'],
            onTap: () => AppShell.go(context, AppShell.indices),
          ),
          TrendKpiTile(
            width: w,
            label: 'شاخص قیمت تولید (PPI)',
            value: ppiNow == null ? 'وارد نشده' : faNum(ppiNow, decimals: 1),
            caption: change(ppiTrend, ppiYears) == null ? null : 'نسبت به ${fa(s.targetYear - 1)}',
            icon: Icons.show_chart_rounded,
            color: ppiNow == null ? Tones.bad(context) : null,
            delta: change(ppiTrend, ppiYears),
            lowerIsBetter: true,
            trend: ppiTrend,
            trendLabels: [for (final y in ppiYears) 'سال ${fa(y)}'],
            formatPoint: (v) => faNum(v, decimals: 1),
            onTap: () => AppShell.go(context, AppShell.indices),
          ),
          TrendKpiTile(
            width: w,
            label: 'استعلام‌های فروشندگان',
            value: fa(quotes),
            caption: '${fa(quoted)} قلم دارای استعلام',
            icon: Icons.request_quote_outlined,
            color: Tones.warn(context),
            progress: rows.isEmpty ? null : quoted / rows.length,
          ),
          TrendKpiTile(
            width: w,
            label: 'پروژه‌ها',
            value: fa(projects.length),
            caption: '${fa(app.pb.docs.sourceDocumentCount())} سند منبع',
            icon: Icons.folder_rounded,
            color: AppColors.teal,
            onTap: () => AppShell.go(context, AppShell.documents),
          ),
        ]);
      }),
      const SizedBox(height: 16),
      _CategorySqueeze(rows: rows, unit: unit),
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
                ? 'این روش پمپ‌هاست؛ هر تجهیز دیگر روش تعدیل خودش را دارد («تنظیمات تخمین و تعدیل رده» در صفحه‌ی روش‌های تعدیل یا تخمین).'
                : 'روش پمپ‌ها؛ روش سایر تجهیزات: ${custom.join('، ')}',
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

/// نوار معرفی داشبورد (الگو: Northline و Mosa AI در 21st.dev): تصویر نور سبز، عنوان درشت با نقطه‌ی لیمویی،
/// دکمه‌های گرد و آمار کوتاه. همیشه تیره است (روی تصویر)، در حالت روز هم.
class _Hero extends StatelessWidget {
  const _Hero({required this.meta, required this.stats});
  final String meta;
  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    const white = Colors.white;
    final dim = white.withValues(alpha: 0.68);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF040A08),
          border: Border.all(color: white.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(24),
          image: const DecorationImage(image: AppBackdrop.heroImage, fit: BoxFit.cover),
        ),
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: white.withValues(alpha: 0.16)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.lime, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text('بانک قیمت تجهیزات نمک‌زدایی',
                    style: t.textTheme.labelMedium?.copyWith(color: white, fontWeight: FontWeight.w600)),
              ]),
            ),
            const Spacer(),
            Flexible(
              child: Text(meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.labelMedium?.copyWith(color: dim, letterSpacing: 0.3)),
            ),
          ]),
          const SizedBox(height: 26),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'قیمت تجهیزات'),
              TextSpan(text: '.', style: TextStyle(color: AppColors.lime.withValues(alpha: 1))),
            ]),
            style: t.textTheme.displaySmall?.copyWith(color: white, fontWeight: FontWeight.w700, height: 1.25),
          ),
          const SizedBox(height: 10),
          Text('هر قیمت مشاور و فروشنده، تعدیل‌شده به سال هدف؛ جست‌وجو، مقایسه و تخمین تجهیز تازه از هم‌رده‌ها.',
              style: t.textTheme.bodyMedium?.copyWith(color: dim, height: 1.8)),
          const SizedBox(height: 22),
          Container(height: 1, color: white.withValues(alpha: 0.12)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 28,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (v, l) in stats)
                Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(v, style: t.textTheme.titleLarge?.copyWith(color: white, fontWeight: FontWeight.w700, height: 1)),
                  const SizedBox(width: 6),
                  Text(l, style: t.textTheme.labelMedium?.copyWith(color: dim)),
                ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _HeroButton(
                  key: const Key('hero-equipment'),
                  label: 'تجهیزات',
                  icon: Icons.north_west_rounded,
                  filled: true,
                  onTap: () => AppShell.go(context, AppShell.equipment),
                ),
                const SizedBox(width: 10),
                _HeroButton(
                  label: 'جست‌وجو',
                  trailing: const Directionality(textDirection: TextDirection.ltr, child: Kbd('Ctrl K')),
                  onTap: () => AppShell.search(context),
                ),
              ]),
            ],
          ),
        ]),
      ),
    );
  }
}

/// دکمه‌ی گرد نوار معرفی: لیمویی پر (اصلی) یا شیشه‌ای.
class _HeroButton extends StatelessWidget {
  const _HeroButton({super.key, required this.label, required this.onTap, this.icon, this.trailing, this.filled = false});
  final String label;
  final IconData? icon;
  final Widget? trailing;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? const Color(0xFF0B1A10) : Colors.white;
    return Material(
      color: filled ? AppColors.lime : Colors.white.withValues(alpha: 0.06),
      shape: StadiumBorder(side: BorderSide(color: filled ? AppColors.lime : Colors.white.withValues(alpha: 0.22))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13.5)),
            if (icon != null) ...[const SizedBox(width: 6), Icon(icon, size: 16, color: fg)],
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ]),
        ),
      ),
    );
  }
}

/// نوار رده‌ها به سبک Squeeze Carousel (21st.dev): هر رده یک باریکه روی تصویر نور سبز؛ رده‌ی زیر نشانگر
/// (یا پرقلم‌ترین رده) پهن می‌شود و نام، شمار اقلام و جمع قیمتش را نشان می‌دهد. زدن روی آن فهرست رده را باز می‌کند.
class _CategorySqueeze extends StatefulWidget {
  const _CategorySqueeze({required this.rows, required this.unit});
  final List<EquipRow> rows;
  final MoneyUnit unit;

  @override
  State<_CategorySqueeze> createState() => _CategorySqueezeState();
}

class _CategorySqueezeState extends State<_CategorySqueeze> {
  int _open = 0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final agg = <int, (int, double)>{};
    for (final r in widget.rows) {
      final e = agg[r.categoryId] ?? (0, 0.0);
      agg[r.categoryId] = (e.$1 + 1, e.$2 + (r.item.include && r.irrTarget != null ? r.irrTarget! * r.qty : 0));
    }
    final cats = [
      for (final c in app.pb.bankCategories())
        if ((agg[c.id]?.$1 ?? 0) > 0) c,
    ]..sort((a, b) => agg[b.id]!.$1.compareTo(agg[a.id]!.$1));
    if (cats.isEmpty) return const SizedBox.shrink();
    final shown = cats.take(8).toList();
    if (_open >= shown.length) _open = 0;
    final still = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      height: 220,
      child: LayoutBuilder(builder: (context, c) {
        const gap = 8.0, narrow = 58.0;
        final wide = c.maxWidth - (shown.length - 1) * (narrow + gap);
        // هنگام پویانمایی (یا وقتی رده‌ی تازه اضافه می‌شود) جمع پهناها لحظه‌ای بیشتر می‌شود: بریده شود، نه خطا
        return ClipRect(
            child: OverflowBox(
          maxWidth: double.infinity,
          alignment: AlignmentDirectional.centerStart,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            AnimatedContainer(
              key: ValueKey('squeeze-${shown[i].code}'),
              duration: still ? Duration.zero : const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              width: i == _open ? wide : narrow,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _open = i),
                child: GestureDetector(
                  onTap: () {
                    EquipmentPage.selectedCategory = shown[i].code;
                    AppShell.go(context, AppShell.equipment);
                  },
                  child: _Slat(
                    open: i == _open,
                    index: i,
                    title: shown[i].nameFa,
                    count: agg[shown[i].id]!.$1,
                    total: agg[shown[i].id]!.$2 <= 0 ? null : money(agg[shown[i].id]!.$2, widget.unit, compact: true),
                    style: t.textTheme,
                  ),
                ),
              ),
            ),
          ],
        ])));
      }),
    );
  }
}

class _Slat extends StatelessWidget {
  const _Slat({required this.open, required this.index, required this.title, required this.count, required this.total, required this.style});
  final bool open;
  final int index;
  final String title;
  final int count;
  final String? total;
  final TextTheme style;

  @override
  Widget build(BuildContext context) {
    const white = Colors.white;
    // هر باریکه بخش دیگری از تصویر نور را نشان می‌دهد
    final ax = -1.0 + (index % 4) * 0.66;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF040A08),
          image: DecorationImage(image: AppBackdrop.heroImage, fit: BoxFit.cover, alignment: Alignment(ax, 0.6)),
          border: Border.all(color: white.withValues(alpha: open ? 0.18 : 0.08)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: LayoutBuilder(builder: (context, c) {
          if (!open || c.maxWidth < 180) {
            return Stack(children: [
              Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.35))),
              Center(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style.labelLarge?.copyWith(color: white.withValues(alpha: 0.85), fontWeight: FontWeight.w600)),
                ),
              ),
            ]);
          }
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(99)),
                child: Text('${fa(count)} قلم', style: style.labelMedium?.copyWith(color: white, fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: style.headlineSmall?.copyWith(color: white, fontWeight: FontWeight.w700, height: 1.3)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Text(total == null ? 'بدون قیمت تعدیل‌شده' : 'جمع سال هدف: $total',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style.bodySmall?.copyWith(color: white.withValues(alpha: 0.75))),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(color: AppColors.lime, borderRadius: BorderRadius.circular(99)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('فهرست', style: style.labelMedium?.copyWith(color: const Color(0xFF0B1A10), fontWeight: FontWeight.w700)),
                    const SizedBox(width: 4),
                    const Icon(Icons.north_west_rounded, size: 14, color: Color(0xFF0B1A10)),
                  ]),
                ),
              ]),
            ]),
          );
        }),
      ),
    );
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
  const _ImportCard({required this.pumps, required this.desalters, required this.compressors});

  /// بانک پمپ / بانک دیسالتر / بانک کمپرسور هوا قبلاً وارد شده است
  final bool pumps, desalters, compressors;

  @override
  State<_ImportCard> createState() => _ImportCardState();
}

class _ImportCardState extends State<_ImportCard> {
  bool _busy = false;

  Future<void> _run() async {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'انتخاب فایل بانک قیمت تجهیزات',
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
      if (PriceBankImporter.isPriceBank(wb)) {
        final rep = app.pb.priceBankImporter().run(wb, fileName: res!.files.single.name);
        app.dataChanged(calcInputs: true);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(rep.items == 0 ? Icons.info_outline : Icons.check_circle_rounded, color: Tones.good(ctx), size: 40),
            title: Text(rep.items == 0 ? 'همه‌ی رکوردهای این بانک قبلاً وارد شده‌اند' : 'ورود بانک قیمت کامل شد'),
            content: SizedBox(
              width: 520,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('تجهیزات: ${fa(rep.items)}${rep.components > 0 ? ' (${fa(rep.components)} جزء پکیج بدون قیمت جدا)' : ''}'),
                if (rep.perCategory.isNotEmpty)
                  Text(rep.perCategory.entries
                      .map((e) => '${app.pb.catalog.categoryByCode(e.key)?.nameFa ?? e.key}: ${fa(e.value)}')
                      .join('، ')),
                Text('پروژه‌ها: ${fa(rep.projects)} · اسناد منبع: ${fa(rep.documents)}'),
                Text('استعلام‌ها: ${fa(rep.quotes)} (${fa(rep.quotesPriced)} قیمت‌دار، بقیه بی‌پاسخ/انصراف)'),
                if (rep.specFields > 0) Text('مشخصات فنی بدون فیلد قالب که به‌صورت مشخصه ثبت شد: ${fa(rep.specFields)} عنوان'),
                if (rep.skippedExisting > 0) Text('رکوردهای قبلاً واردشده (تکرار نشد): ${fa(rep.skippedExisting)}'),
                if (rep.archivedDuplicates > 0)
                  Text('اقلام تکراری از MTO یا بانک‌های دیگر بایگانی شد: ${fa(rep.archivedDuplicates)} (بانک قیمت مرجع است)'),
                for (final w in rep.warnings.take(5)) Text('⚠ $w', style: TextStyle(color: Tones.warn(ctx))),
              ]),
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('بسیار خوب'))],
          ),
        );
        return;
      }
      if (CompressorImporter.isCompressorBank(wb)) {
        final err = CompressorImporter.validate(wb);
        if (err != null) throw FormatException(err);
        final rep = app.pb.compressorImporter().run(wb, fileName: res!.files.single.name);
        app.dataChanged(calcInputs: true);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(rep.alreadyImported ? Icons.info_outline : Icons.check_circle_rounded, color: Tones.good(ctx), size: 40),
            title: Text(rep.alreadyImported ? 'بانک کمپرسور هوا قبلاً وارد شده است' : 'انتقال بانک کمپرسور هوا کامل شد'),
            content: rep.alreadyImported
                ? const Text('برای جلوگیری از رکورد تکراری، ورود دوباره انجام نشد.')
                : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('کمپرسورها و پکیج‌ها: ${fa(rep.items)}'),
                    Text('پروژه‌ها: ${fa(rep.projects)} · اسناد منبع: ${fa(rep.documents)}'),
                    Text('فروشندگان: ${fa(rep.vendors)} · استعلام‌ها: ${fa(rep.quotes)} (${fa(rep.quotesPriced)} قیمت‌دار، بقیه بی‌پاسخ/انصراف)'),
                    Text('مقادیر استنباطی (زرد): ${fa(rep.inferredFlags)} · یادداشت‌های شاهد: ${fa(rep.notes)}'),
                    if (rep.corrections > 0) Text('اصلاح تأییدشده: سال قیمت KPL-476 ← ۱۳۹۴/۱۰ (${fa(rep.corrections)} قلم)'),
                    if (rep.dryerLinks > 0)
                      Text('پکیج کامل هوای ابزار دقیق در رده‌ی خشک‌کن هوا هم ثبت شد: ${fa(rep.dryerLinks)} قلم بدون قیمت '
                          '(برآورد سهم خشک‌کن در ملاحظات)'),
                    for (final w in rep.warnings.take(5)) Text('⚠ $w', style: TextStyle(color: Tones.warn(ctx))),
                  ]),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('بسیار خوب'))],
          ),
        );
        return;
      }
      if (DesalterImporter.isDesalterBank(wb)) {
        final err = DesalterImporter.validate(wb);
        if (err != null) throw FormatException(err);
        final rep = app.pb.desalterImporter().run(wb, fileName: res!.files.single.name);
        app.dataChanged(calcInputs: true);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(rep.alreadyImported ? Icons.info_outline : Icons.check_circle_rounded, color: Tones.good(ctx), size: 40),
            title: Text(rep.alreadyImported ? 'بانک دیسالتر قبلاً وارد شده است' : 'انتقال بانک دیسالتر کامل شد'),
            content: rep.alreadyImported
                ? const Text('برای جلوگیری از رکورد تکراری، ورود دوباره انجام نشد.')
                : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('دیسالترها: ${fa(rep.items)}'),
                    Text('پروژه‌ها: ${fa(rep.projects)} · اسناد منبع: ${fa(rep.documents)}'),
                    Text('فروشندگان: ${fa(rep.vendors)} · استعلام‌ها: ${fa(rep.quotes)}'),
                    Text('مقادیر استنباطی (زرد): ${fa(rep.inferredFlags)} · یادداشت‌های شاهد: ${fa(rep.notes)}'),
                    if (rep.corrections > 0) Text('اصلاح تأییدشده: سال قیمت KPL-476 ← ۱۳۹۴/۱۰ (${fa(rep.corrections)} قلم)'),
                    if (rep.archivedDuplicates > 0)
                      Text('دیسالترهای تکراری MTO بایگانی شد: ${fa(rep.archivedDuplicates)} (بانک دیسالتر مرجع است)'),
                    for (final w in rep.warnings.take(5)) Text('⚠ $w', style: TextStyle(color: Tones.warn(ctx))),
                  ]),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('بسیار خوب'))],
          ),
        );
        return;
      }
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
            Text('ورود بانک قیمت تجهیزات',
                style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: t.colorScheme.onPrimaryContainer)),
            const SizedBox(height: 4),
            Text(
              'فایل بانک قیمت را انتخاب کنید: بانک تجمیعی (یک شیت برای هر تجهیز) یا بانک جداگانه‌ی پمپ، دیسالتر یا کمپرسور هوا؛ '
              'نوع فایل خودکار تشخیص داده می‌شود. همه‌ی مشخصات، پروژه‌ها، اسناد منبع، فروشندگان، استعلام‌ها، یادداشت‌های شاهد و '
              'برچسب مقادیر استنباطی منتقل می‌شوند؛ رکورد تکراری دوباره وارد نمی‌شود. فایل اکسل تغییر نمی‌کند.',
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
          label: Text(_busy ? 'در حال انتقال…' : 'انتخاب فایل'),
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
                  : 'MTO وارد شده ✓ — بانک قیمت تجهیزات را هم از کارت بالا وارد کنید.')
              : 'بانک قیمت تجهیزات را از کارت بالا و MTO پروژه‌ها را از «ورود MTO» وارد کنید.',
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
