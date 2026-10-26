// روش‌های تعدیل: مشاهده، مقایسه‌ی دقت (صحت‌سنجی پازنان ۲)، اثر روی بانک فعلی و انتخاب روش فعال.

import 'package:flutter/material.dart';
import 'generic_equipment.dart' show CategorySettingsDialog;

import '../../app/app_state.dart';
import '../../core/calc/backtest.dart';
import '../../core/calc/methods.dart';
import '../../core/catalog/profiles.dart';
import '../../core/repo/catalog_repo.dart' show Category;
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'equipment_page.dart';

String pct(double v, {int decimals = 1, bool signed = false}) =>
    '${signed && v > 0 ? '+' : ''}${faNum(v * 100, decimals: decimals)}٪';

class MethodsPage extends StatefulWidget {
  const MethodsPage({super.key});

  @override
  State<MethodsPage> createState() => _MethodsPageState();
}

class _Impact {
  _Impact(this.priced, this.eurSum, this.floorCount);
  final int priced;
  final double eurSum;
  final int floorCount;
}

/// زبانه‌های رشته‌ها (کاربر ۱۴۰۵/۰۸/۰۵: هر رشته یک زبانه با تجهیزات خودش)
const _disciplines = [('MECH', 'مکانیک'), ('INST', 'ابزار دقیق'), ('ELEC', 'برق'), ('PIPE', 'پایپینگ')];

class _MethodsPageState extends State<MethodsPage> with SingleTickerProviderStateMixin {
  TabController? _discTabs;

  @override
  void dispose() {
    _discTabs?.dispose();
    super.dispose();
  }

  /// رده‌ی انتخاب‌شده (پیش‌فرض: رده‌ی باز در صفحه‌ی تجهیزات)
  late String _code = EquipmentPage.selectedCategory;
  String _cacheKey = '';
  Map<String, _Impact> _impact = const {};
  BacktestResult? _bt;

  void _compute(AppState app, bool isPump, List<String> codes) {
    final key = '${app.revision}|$_code';
    if (key == _cacheKey) return;
    final out = <String, _Impact>{};
    if (isPump) {
      for (final c in codes) {
        final rows = app.pb.computePumps(engine: app.pb.pumpEngine(method: c));
        var n = 0, floors = 0;
        var sum = 0.0;
        for (final r in rows) {
          if (!r.item.include || !r.result.eurTarget.isNumber) continue;
          n++;
          sum += r.result.eurTarget.number! * (r.item.quantity ?? 1);
          if (r.result.floorBinding) floors++;
        }
        out[c] = _Impact(n, sum, floors);
      }
      _bt = null;
    } else {
      final cat = app.pb.catalog.categoryByCode(_code)!;
      for (final c in codes) {
        final rows = app.pb.computeCategory(cat.id, engine: app.pb.genericEngine(categoryCode: _code, method: c));
        var n = 0;
        var sum = 0.0;
        for (final r in rows) {
          if (!r.item.include || !r.result.eurTarget.isNumber) continue;
          n++;
          sum += r.result.eurTarget.number! * (r.item.quantity ?? 1);
        }
        out[c] = _Impact(n, sum, 0);
      }
      _bt = app.pb.backtestCategory(_code, methods: codes);
    }
    _impact = out;
    _cacheKey = key;
  }

  Future<void> _select(BuildContext context, EscalationMethod m, {required bool isPump, required String catName}) async {
    final reason = await askReason(context,
        title: isPump ? 'تغییر روش تعدیل به ${m.code}' : 'روش تعدیل «$catName»: ${m.code}',
        summary: isPump
            ? '${m.nameFa}\nفقط روش پمپ‌ها؛ روش هر تجهیز دیگر جداگانه تعیین می‌شود.'
            : '${m.nameFa}\nفقط قیمت‌های تعدیل‌شده‌ی این رده دوباره محاسبه می‌شوند.');
    if (reason == null || !context.mounted) return;
    final app = AppScope.read(context);
    if (isPump) {
      app.setSetting('escalation_method', m.code, reason: reason.isEmpty ? 'انتخاب روش تعدیل' : reason);
    } else {
      app.setSetting('cat_method_$_code', m.code, reason: reason.isEmpty ? 'روش تعدیل رده' : reason);
    }
    showSnack(context, '${isPump ? 'روش تعدیل' : 'روش تعدیل $catName'}: ${m.code} — ${m.nameFa}');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final s = app.settings;
    final cats = app.pb.bankCategories();
    if (!cats.any((c) => c.code == _code)) _code = 'PUMP';
    final cat = cats.firstWhere((c) => c.code == _code);
    final counts = app.pb.categoryCounts();
    final isPump = _code == 'PUMP';
    final canEdit = app.user.isAdmin || app.user.role == 'reviewer';

    // روش‌های این رده
    final methods = isPump
        ? escalationMethods
        : [for (final c in app.pb.methodCodesFor(_code)) methodByCode(c)];
    final selectable = [for (final m in methods) if (m.selectable) m.code];
    final global = s.escalationMethod;
    final own = isPump ? null : s.catMethod(_code);
    final catDefault = isPump ? defaultMethodCode : defaultCategoryMethod(_code);
    var effective = isPump ? global : s.methodFor(_code);
    if (!isPump && effective == 'M6') effective = 'M4'; // M6 در رده‌های غیرپمپ همان M4 است
    final ppiCode = isPump ? s.ppiSeries : (s.catPpi(_code) ?? s.ppiSeries);
    final ppiName = app.pb.indices.series().where((x) => x.code == ppiCode).map((x) => x.nameFa).firstOrNull ?? ppiCode;
    final usCode = isPump ? defaultUsPpiSeries : s.catUsPpi(_code);
    final usName = app.pb.indices.series().where((x) => x.code == usCode).map((x) => x.nameFa).firstOrNull ?? usCode;
    final mf = MethodFactors(app.pb.seriesSnapshot,
        ppiSeries: ppiCode,
        fxType: s.fxRateType,
        mix: s.catMix(_code),
        mixStrict: s.catMixStrict(_code),
        usPpiSeries: usCode);
    _compute(app, isPump, selectable);
    final bt = _bt;
    final refCode = isPump ? defaultMethodCode : effective;
    final ref = _impact[refCode]?.eurSum;

    String title(EscalationMethod m) => isPump ? m.nameFa : methodLabelFor(m, pump: false, ppiName: ppiName, usPpiName: usName).split(' — ').last;

    return ListView(padding: const EdgeInsets.fromLTRB(24, 20, 24, 28), children: [
      PageHeader(
        icon: Icons.science_rounded,
        title: 'روش‌های تعدیل قیمت',
        subtitle: '${cat.nameFa} · روش فعال: $effective'
            '${isPump ? ' · پیشنهادی پمپ: M6 (PPI یورو + کف قیمت)' : (own == null ? ' (پیش‌فرض همین رده)' : ' (انتخاب‌شده برای این رده)')}',
        actions: [
          if (isPump && global != defaultMethodCode && canEdit)
            OutlinedButton.icon(
              onPressed: () => _select(context, methodByCode(defaultMethodCode), isPump: true, catName: cat.nameFa),
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('بازگشت به M6'),
            ),
          if (!isPump && canEdit)
            OutlinedButton.icon(
              key: const ValueKey('cat-settings'),
              onPressed: () => showDialog<void>(context: context, builder: (_) => CategorySettingsDialog(code: _code)),
              icon: const Icon(Icons.settings_suggest_outlined),
              label: const Text('تنظیمات تخمین و تعدیل رده'),
            ),
          if (!isPump && own != null && own != catDefault && canEdit)
            OutlinedButton.icon(
              onPressed: () => app.setSetting('cat_method_$_code', null, reason: 'بازگشت به روش پیش‌فرض رده'),
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text('بازگشت به پیش‌فرض رده ($catDefault)'),
            ),
        ],
      ),
      SectionCard(
        title: 'تجهیز',
        subtitle: 'هر رشته یک زبانه؛ هر تجهیز روش‌ها، صحت‌سنجی، تنظیمات و روش انتخابی خودش را دارد · عدد = تعداد اقلام بانک',
        icon: Icons.category_outlined,
        child: Builder(builder: (context) {
          final disc = _disciplines.indexWhere((d) => d.$1 == cat.disciplineCode);
          final tabs = _discTabs ??= TabController(length: _disciplines.length, vsync: this, initialIndex: disc < 0 ? 0 : disc);
          final shown = _disciplines[tabs.index].$1;
          List<Category> catsOf(String d) => [for (final c in cats) if (c.disciplineCode == d) c];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TabBar(
              controller: tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              onTap: (i) => setState(() {
                // اولین تجهیزِ دارای قلم در همان رشته
                final list = catsOf(_disciplines[i].$1);
                if (list.isEmpty) return;
                final withItems = list.where((c) => (counts[c.id] ?? 0) > 0);
                _code = (withItems.isNotEmpty ? withItems.first : list.first).code;
              }),
              tabs: [
                for (final d in _disciplines)
                  Tab(key: ValueKey('method-disc-${d.$1}'), text: '${d.$2} (${fa(catsOf(d.$1).length)})'),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in catsOf(shown))
                CategoryChip(
                  key: ValueKey('method-cat-${c.code}'),
                  label: '${c.nameFa} · ${s.methodFor(c.code)}',
                  count: counts[c.id] ?? 0,
                  selected: c.code == _code,
                  onTap: () => setState(() => _code = c.code),
                ),
              if (catsOf(shown).isEmpty)
                Text('هنوز تجهیزی در این رشته تعریف نشده است.',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ]),
          ]);
        }),
      ),
      const SizedBox(height: 12),
      HelpPanel(
        id: 'methods',
        title: 'روش تعدیل چیست و کدام را انتخاب کنم؟',
        initiallyOpen: false,
        lines: [
          'روش تعدیل، قیمت یورویی سال منبع را به سال هدف می‌برد. سپس با نرخ یوروی سال هدف به ریال/تومان تبدیل می‌شود.',
          if (isPump) ...[
            'آمار دقت پمپ‌ها از فایل Pump_Escalation_Validation است: قیمت ۱۴ پمپ پازنان ۲ در بهمن ۱۳۹۳ با هر روش به ۱۴۰۴ برده شده و با میانگین استعلام‌های واقعی ۱۴۰۴ مقایسه شده است.',
            'M6 کمترین خطای میانه و بیشترین تعداد پمپ در بازه‌ی ±۲۵٪ را دارد و پیش‌فرض است. روش پمپ فقط روی پمپ‌ها اثر دارد؛ هر تجهیز روش تعدیل خودش را دارد.',
          ] else ...[
            'صحت‌سنجی «${cat.nameFa}» خودکار از داده‌های همین بانک است: هر قلمی که هم قیمت قدیمی (مثلاً بازنگری ۱۳۹۳) و هم استعلام جدید دارد، یک آزمون است؛ قیمت قدیمی با هر روش به سال استعلام برده و با میانگین استعلام‌ها مقایسه می‌شود.',
            'با ورود MTO پروژه‌های بیشتر، تعداد آزمون‌ها و اعتبار این مقایسه خودکار بیشتر می‌شود.',
            'M4 در این رده با شاخص PPI انتخاب‌شده در «تنظیمات تخمین و تعدیل رده» ($ppiName) محاسبه می‌شود؛ کف قیمت M6 فقط برای پمپ است، پس M6 در این رده همان M4 است.',
            if (s.catMix(_code).isNotEmpty)
              'M7 (شاخص ترکیبی) سبدی از چند شاخص PPI با وزن اجزای تجهیز است: ${fa(mixLabel(s.catMix(_code)))}. '
                  'وزن‌ها در «تنظیمات تخمین و تعدیل رده» (صفحه‌ی روش‌های تعدیل یا تخمین) قابل تغییرند. پیش‌فرض این رده: $catDefault.',
          ],
          '«خطای میانه» هرچه کمتر بهتر؛ «سوگیری» منفی یعنی کم‌برآورد؛ «در بازه‌ی ±۲۵٪» یعنی چند قلم خطای کمتر از ۲۵٪ داشته‌اند.',
          'انتخاب روش در پایین صفحه، روی همه‌ی صفحه‌ها (تجهیزات، داشبورد، تخمین و انتقال قیمت) اثر دارد و در تاریخچه ثبت می‌شود.',
        ],
      ),
      if (isPump)
        _StatsChart(
          title: 'مقایسه‌ی دقت روش‌ها — پمپ',
          subtitle: '۱۴ پمپ پازنان ۲ · قیمت ۱۳۹۳ تعدیل‌شده به ۱۴۰۴ در برابر استعلام واقعی ۱۴۰۴ (فایل صحت‌سنجی)',
          rows: [for (final m in escalationMethods) (m.code, m.nameFa, m.stats, m.selectable)],
          n: validationSampleSize,
          active: effective,
        )
      else if (bt == null || bt.n == 0)
        SectionCard(
          title: 'مقایسه‌ی دقت روش‌ها — ${cat.nameFa}',
          icon: Icons.leaderboard_rounded,
          child: Text(
            'هنوز داده‌ی صحت‌سنجی برای این رده در بانک نیست. برای هر آزمون، قلمی لازم است که هم قیمت قدیمی (دست‌کم دو سال قبل) '
            'و هم استعلام جدید داشته باشد — مثل MTOهایی که «قیمت بازنگری قبلی» و «استعلام» دارند. با ورود MTO بعدی خودکار پر می‌شود.',
            style: t.textTheme.bodySmall?.copyWith(height: 1.9),
          ),
        )
      else ...[
        _StatsChart(
          title: 'مقایسه‌ی دقت روش‌ها — ${cat.nameFa}',
          subtitle: '${fa(bt.n)} قلم از بانک · قیمت قدیمی تعدیل‌شده به سال استعلام در برابر میانگین استعلام‌های واقعی',
          rows: [for (final m in methods) (m.code, title(m), bt.stats(m.code), true)],
          n: bt.n,
          active: effective,
        ),
        const SizedBox(height: 12),
        _BacktestItems(bt: bt, active: effective),
      ],
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth > 1250 ? 3 : (c.maxWidth > 820 ? 2 : 1);
        final w = (c.maxWidth - (cols - 1) * 14) / cols;
        return Wrap(spacing: 14, runSpacing: 14, children: [
          for (final m in methods)
            SizedBox(
              width: w,
              child: _MethodCard(
                method: m,
                title: title(m),
                summary: !isPump && m.code == 'M4'
                    ? 'شاخص قیمت تولیدکننده‌ی انتخاب‌شده برای این رده: $ppiName (در «تنظیمات تخمین و تعدیل رده» قابل تغییر).'
                    : (m.code == 'M7'
                        ? 'سبد شاخص این رده: ${fa(mixLabel(s.catMix(_code)))}'
                            '${s.catMixStrict(_code) ? ' · شاخص ناموجود = بدون تعدیل' : ' · شاخص ناموجود = بازتوزیع وزن‌ها'}'
                        : m.summaryFa),
                note: !isPump && m.code == 'M5' ? 'از شاخص پمپ آمریکا استفاده می‌کند؛ برای این رده فقط جهت مقایسه.' : m.noteFa,
                stats: isPump ? m.stats : bt?.stats(m.code),
                sample: isPump ? validationSampleSize : (bt?.n ?? 0),
                isPump: isPump,
                active: m.code == effective,
                recommended: isPump ? m.code == defaultMethodCode : (bt != null && bt.n > 0 && bt.best == m.code),
                liveFactor: m.selectable ? mf.factor(m.code, 1393, null, s.targetYear, s.targetMonth) : null,
                targetYear: s.targetYear,
                impact: _impact[m.code],
                refSum: ref,
                refCode: refCode,
                onSelect: (!canEdit || !m.selectable || m.code == effective)
                    ? null
                    : () => _select(context, m, isPump: isPump, catName: cat.nameFa),
              ),
            ),
        ]);
      }),
      if (_code == 'CIP') ...[
        const SizedBox(height: 16),
        SectionCard(
          title: 'روش‌های ریالی (پکیج‌های تزریق پازنان ۲) — فقط برای اطلاع',
          subtitle: 'نسبت برآورد به استعلام ریالی ۱۴۰۴ برای ۱۱ پکیج؛ عدد ۱ یعنی دقیق',
          icon: Icons.inventory_2_outlined,
          accent: AppColors.irr,
          child: Column(children: [
            for (final r in rialPackageResults)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  SizedBox(width: 40, child: _CodeBadge(r.code, color: AppColors.irr, small: true)),
                  SizedBox(width: 230, child: Text(r.nameFa, style: t.textTheme.bodySmall)),
                  Expanded(child: _RatioBar(value: r.medianRatio)),
                  SizedBox(
                    width: 170,
                    child: Text('میانه ${faNum(r.medianRatio, decimals: 2)} · جمع ${faNum(r.totalRatio, decimals: 2)}',
                        textAlign: TextAlign.end, style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            const SizedBox(height: 6),
            Text(
              'مسیر تورم ریالی (R1، R2) قیمت را حدود نصف واقعیت برآورد می‌کند؛ از ۱۳۹۳ تا ۱۴۰۳ دلار حدود ۲۸ برابر شده ولی CPI حدود ۱۶ برابر. '
              'به همین دلیل در این برنامه قیمت‌ها در یورو تعدیل و سپس با نرخ یوروی سال هدف به ریال تبدیل می‌شوند (معادل R4).',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.9),
            ),
          ]),
        ),
      ],
    ]);
  }
}

/// اقلام صحت‌سنجی یک رده: قیمت قدیمی، استعلام، و نسبت برآورد روش فعال به واقعی.
class _BacktestItems extends StatelessWidget {
  const _BacktestItems({required this.bt, required this.active});
  final BacktestResult bt;
  final String active;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final head = t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.strong);
    return SectionCard(
      title: 'اقلام آزمون',
      subtitle: 'نسبت = برآورد روش $active ÷ میانگین استعلام‌ها (۱ = دقیق)',
      icon: Icons.fact_check_outlined,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          color: AppColors.headerBg,
          child: Row(children: [
            SizedBox(width: 110, child: Text('تگ', style: head)),
            Expanded(child: Text('نام · پروژه', style: head)),
            SizedBox(width: 110, child: Text('قدیمی → استعلام', textAlign: TextAlign.center, style: head)),
            SizedBox(width: 110, child: Text('یوروی استعلام', textAlign: TextAlign.center, style: head)),
            SizedBox(width: 160, child: Text('نسبت $active', textAlign: TextAlign.center, style: head)),
          ]),
        ),
        for (var i = 0; i < bt.pairs.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            color: i.isOdd ? AppColors.zebra : null,
            child: Row(children: [
              SizedBox(
                width: 110,
                child: Text(bt.pairs[i].item.tag ?? '',
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.strong)),
              ),
              Expanded(
                child: Text('${bt.pairs[i].item.name} · ${bt.pairs[i].item.projectName ?? ''}',
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
              ),
              SizedBox(
                width: 110,
                child: Text('${fa(bt.pairs[i].oldYear)} → ${fa(bt.pairs[i].quoteYear)} (${fa(bt.pairs[i].quoteCount)})',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              ),
              SizedBox(
                width: 110,
                child: Text('${compactNum(bt.pairs[i].actualEur)} €',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.eur)),
              ),
              SizedBox(
                width: 160,
                child: bt.pairs[i].ratio(active) == null
                    ? const Center(child: Text('—'))
                    : Row(children: [
                        Expanded(child: _RatioBar(value: bt.pairs[i].ratio(active)!)),
                        const SizedBox(width: 6),
                        Text(faNum(bt.pairs[i].ratio(active)!, decimals: 2),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _CodeBadge extends StatelessWidget {
  const _CodeBadge(this.code, {this.color, this.small = false});
  final String code;
  final Color? color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.petrol;
    final size = small ? 30.0 : 42.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(small ? 8 : 12),
      ),
      child: Text(code,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: small ? 11.5 : 14)),
    );
  }
}

class _RatioBar extends StatelessWidget {
  const _RatioBar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // مقیاس ۰ تا ۱٫۵؛ خط عمودی = ۱ (دقیق)
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final x = (value / 1.5).clamp(0.0, 1.0) * w;
      final good = (value - 1).abs() < 0.15;
      return SizedBox(
        height: 16,
        child: Stack(children: [
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(color: t.colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(6)),
            ),
          ),
          PositionedDirectional(
            start: 0,
            top: 4,
            bottom: 4,
            child: Container(
              width: x,
              decoration: BoxDecoration(
                color: good ? Tones.good(context) : Tones.warn(context),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          PositionedDirectional(
            start: w / 1.5 - 1,
            top: 0,
            bottom: 0,
            child: Container(width: 2, color: t.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
        ]),
      );
    });
  }
}

/// نمودار مقایسه‌ی دقت روش‌ها (خطای میانه، سوگیری و تعداد در بازه‌ی ±۲۵٪).
class _StatsChart extends StatelessWidget {
  const _StatsChart({required this.title, required this.subtitle, required this.rows, required this.n, required this.active});
  final String title;
  final String subtitle;

  /// (کد، نام، آمار، قابل انتخاب)
  final List<(String, String, MethodStats?, bool)> rows;
  final int n;
  final String active;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final valid = [for (final r in rows) if (r.$3 != null) r];
    final maxErr = valid.isEmpty ? 1.0 : valid.map((r) => r.$3!.mdape).reduce((a, b) => a > b ? a : b);
    final best = valid.isEmpty ? null : valid.reduce((a, b) => a.$3!.mdape < b.$3!.mdape ? a : b).$1;
    return SectionCard(
      title: title,
      subtitle: subtitle,
      icon: Icons.leaderboard_rounded,
      child: Column(children: [
        Row(children: [
          SizedBox(width: 44, child: Text('کد', textAlign: TextAlign.center, style: t.textTheme.labelSmall)),
          SizedBox(width: 196, child: Text('روش', style: t.textTheme.labelSmall)),
          Expanded(child: Text('خطای میانه‌ی برآورد (کمتر = بهتر)', style: t.textTheme.labelSmall)),
          SizedBox(width: 70, child: Text('سوگیری', textAlign: TextAlign.center, style: t.textTheme.labelSmall)),
          SizedBox(width: 170, child: Text('در بازه‌ی ±۲۵٪', textAlign: TextAlign.center, style: t.textTheme.labelSmall)),
        ]),
        const SizedBox(height: 6),
        for (final (code, name, st, selectable) in rows)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: code == active ? AppColors.amberSoft : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              SizedBox(width: 44, child: _CodeBadge(code, small: true, color: selectable ? null : t.colorScheme.outline)),
              const SizedBox(width: 8),
              SizedBox(
                width: 188,
                child: Tooltip(
                  message: name,
                  child: Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodySmall?.copyWith(fontWeight: code == active ? FontWeight.w800 : FontWeight.w500)),
                ),
              ),
              Expanded(
                child: st == null
                    ? Text('—', style: TextStyle(color: t.colorScheme.outline))
                    : LayoutBuilder(builder: (context, c) {
                        // نوار و عدد کنار هم: عدد درست در انتهای نوار
                        final barMax = (c.maxWidth - 70).clamp(40.0, 520.0);
                        return Row(children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: maxErr <= 0 ? 0 : st.mdape / maxErr),
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeOutCubic,
                            builder: (context, v, _) => Container(
                              height: 14,
                              width: barMax * v,
                              decoration: BoxDecoration(
                                color: code == best ? Tones.good(context) : (selectable ? AppColors.petrol : t.colorScheme.outline),
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(pct(st.mdape), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                        ]);
                      }),
              ),
              SizedBox(
                width: 70,
                child: Text(st == null ? '—' : pct(st.bias, signed: true),
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: st == null
                            ? t.colorScheme.outline
                            : (st.bias.abs() < 0.1 ? Tones.good(context) : Tones.warn(context)),
                        fontWeight: FontWeight.w700)),
              ),
              SizedBox(width: 170, child: Center(child: st == null ? const Text('—') : _Dots(n: st.within25, of: n))),
            ]),
          ),
      ]),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.n, required this.of});
  final int n;
  final int of;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (of > 16) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 90,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: of == 0 ? 0 : n / of,
              minHeight: 6,
              color: Tones.good(context),
              backgroundColor: t.colorScheme.outlineVariant,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text('${fa(n)}/${fa(of)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      ]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < of; i++)
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < n ? Tones.good(context) : t.colorScheme.outlineVariant,
          ),
        ),
      const SizedBox(width: 6),
      Text('${fa(n)}/${fa(of)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
    ]);
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.method,
    required this.title,
    required this.summary,
    required this.note,
    required this.stats,
    required this.sample,
    required this.isPump,
    required this.active,
    required this.recommended,
    required this.liveFactor,
    required this.targetYear,
    required this.impact,
    required this.refSum,
    required this.refCode,
    required this.onSelect,
  });
  final EscalationMethod method;
  final String title;
  final String summary;
  final String? note;
  final MethodStats? stats;
  final int sample;
  final bool isPump;
  final bool active;
  final bool recommended;
  final MethodFactor? liveFactor;
  final int targetYear;
  final _Impact? impact;
  final double? refSum;
  final String refCode;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final m = method;
    final st = stats;
    Widget stat(String label, String value, {Color? color}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(color: t.colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(10)),
            child: Column(children: [
              Text(value,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: color ?? t.colorScheme.onSurface)),
              const SizedBox(height: 2),
              Text(label, textAlign: TextAlign.center, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ]),
          ),
        );
    final imp = impact;
    return HoverLift(child: Container(
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? AppColors.amber : t.colorScheme.outlineVariant,
          width: active ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _CodeBadge(m.code, color: m.selectable ? null : t.colorScheme.outline),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ),
          if (recommended)
            Pill(isPump ? 'پیشنهادی' : 'دقیق‌ترین در بانک', color: Tones.good(context), icon: Icons.verified_rounded),
          if (active) ...[const SizedBox(width: 4), Pill('فعال', color: AppColors.amberText, icon: Icons.check_circle_rounded)],
          if (!m.selectable) Pill('فقط مقایسه', color: t.colorScheme.outline),
        ]),
        const SizedBox(height: 10),
        Text(summary, style: t.textTheme.bodySmall?.copyWith(height: 1.8)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.petrol.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.petrol.withValues(alpha: 0.15)),
          ),
          child: Text(m.formulaFa, style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, height: 1.8)),
        ),
        const SizedBox(height: 10),
        Row(children: [
          stat('خطای میانه', st == null ? '—' : pct(st.mdape), color: st != null && st.mdape < 0.15 ? Tones.good(context) : null),
          const SizedBox(width: 6),
          stat('سوگیری', st == null ? '—' : pct(st.bias, signed: true)),
          const SizedBox(width: 6),
          stat('در ±۲۵٪', st == null ? '—' : '${fa(st.within25)}/${fa(sample)}'),
          const SizedBox(width: 6),
          stat('جمع/واقعی', st == null || st.totalRatio.isNaN ? '—' : faNum(st.totalRatio, decimals: 2)),
        ]),
        const SizedBox(height: 10),
        if (isPump)
          _kv(context, 'ضریب ۱۳۹۳→۱۴۰۴ (صحت‌سنجی)', m.factorRef == null ? 'برای هر ردیف جدا' : faSmart(m.factorRef)),
        if (liveFactor != null)
          _kv(context, 'ضریب ۱۳۹۳→${fa(targetYear)} با داده‌های فعلی',
              liveFactor!.factor == null ? liveFactor!.detail : faSmart(liveFactor!.factor)),
        if (imp != null)
          _kv(
            context,
            'جمع یوروی بانک فعلی (× تعداد)',
            '${compactNum(imp.eurSum)} یورو'
                '${refSum != null && refSum! > 0 && m.code != refCode ? '  (${pct(imp.eurSum / refSum! - 1, signed: true)} نسبت به $refCode)' : ''}',
          ),
        if (imp != null && m.usesFloor) _kv(context, 'پمپ‌هایی که کف قیمت برایشان اعمال شده', fa(imp.floorCount)),
        if (note != null) ...[
          const SizedBox(height: 6),
          Text(note!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.8)),
        ],
        const SizedBox(height: 12),
        if (m.selectable)
          active
              ? FilledButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('روش فعال'),
                )
              : FilledButton.tonalIcon(
                  key: ValueKey('select-${m.code}'),
                  onPressed: onSelect,
                  icon: const Icon(Icons.radio_button_unchecked_rounded),
                  label: const Text('انتخاب این روش'),
                ),
      ]),
    ));
  }

  Widget _kv(BuildContext context, String k, String v) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(k, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant))),
        const SizedBox(width: 8),
        Flexible(child: Text(v, textAlign: TextAlign.end, style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700))),
      ]),
    );
  }
}
