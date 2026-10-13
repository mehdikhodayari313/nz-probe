// روش‌های تعدیل: مشاهده، مقایسه‌ی دقت (صحت‌سنجی پازنان ۲)، اثر روی بانک فعلی و انتخاب روش فعال.

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/methods.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';

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

class _MethodsPageState extends State<MethodsPage> {
  int _rev = -1;
  Map<String, _Impact> _impact = const {};

  Map<String, _Impact> _computeImpact(AppState app) {
    if (_rev == app.revision) return _impact;
    final out = <String, _Impact>{};
    for (final m in escalationMethods.where((m) => m.selectable)) {
      final rows = app.pb.computePumps(engine: app.pb.pumpEngine(method: m.code));
      var n = 0, floors = 0;
      var sum = 0.0;
      for (final r in rows) {
        if (!r.item.include || !r.result.eurTarget.isNumber) continue;
        n++;
        sum += r.result.eurTarget.number! * (r.item.quantity ?? 1);
        if (r.result.floorBinding) floors++;
      }
      out[m.code] = _Impact(n, sum, floors);
    }
    _rev = app.revision;
    return _impact = out;
  }

  Future<void> _select(BuildContext context, EscalationMethod m) async {
    final reason = await askReason(context,
        title: 'تغییر روش تعدیل به ${m.code}', summary: '${m.nameFa}\nهمه‌ی قیمت‌های تعدیل‌شده با این روش دوباره محاسبه می‌شوند.');
    if (reason == null || !context.mounted) return;
    AppScope.read(context).setSetting('escalation_method', m.code, reason: reason.isEmpty ? 'انتخاب روش تعدیل' : reason);
    showSnack(context, 'روش تعدیل: ${m.code} — ${m.nameFa}');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final s = app.settings;
    final active = methodByCode(s.escalationMethod);
    final canEdit = app.user.isAdmin || app.user.role == 'reviewer';
    final mf = MethodFactors(app.pb.seriesSnapshot, ppiSeries: s.ppiSeries, fxType: s.fxRateType);
    final impact = _computeImpact(app);
    final ref = impact[defaultMethodCode]?.eurSum;

    return ListView(padding: const EdgeInsets.fromLTRB(24, 20, 24, 28), children: [
      PageHeader(
        icon: Icons.science_rounded,
        title: 'روش‌های تعدیل قیمت',
        subtitle: 'روش فعال: ${active.code} — ${active.nameFa} · پیش‌فرض و پیشنهادی: M6',
        actions: [
          if (active.code != defaultMethodCode && canEdit)
            OutlinedButton.icon(
              onPressed: () => _select(context, methodByCode(defaultMethodCode)),
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('بازگشت به M6'),
            ),
        ],
      ),
      const HelpPanel(
        id: 'methods',
        title: 'روش تعدیل چیست و کدام را انتخاب کنم؟',
        initiallyOpen: false,
        lines: [
          'روش تعدیل، قیمت یورویی سال منبع را به سال هدف می‌برد. سپس با نرخ یوروی سال هدف به ریال/تومان تبدیل می‌شود.',
          'آمار دقت از فایل Pump_Escalation_Validation است: قیمت ۱۴ پمپ پازنان ۲ در بهمن ۱۳۹۳ با هر روش به ۱۴۰۴ برده شده و با میانگین استعلام‌های واقعی ۱۴۰۴ مقایسه شده است.',
          '«خطای میانه» (MdAPE) هرچه کمتر بهتر؛ «سوگیری» منفی یعنی کم‌برآورد؛ «در بازه‌ی ±۲۵٪» یعنی چند پمپ از ۱۴ پمپ خطای کمتر از ۲۵٪ داشته‌اند.',
          'M6 کمترین خطای میانه و بیشترین تعداد پمپ در بازه‌ی ±۲۵٪ را دارد و پیش‌فرض است. روش‌های دیگر برای مقایسه و تحلیل حساسیت در دسترس‌اند.',
          'تغییر روش روی همه‌ی صفحه‌ها (تجهیزات، داشبورد، تخمین و ماشین‌حساب) اثر دارد و در تاریخچه ثبت می‌شود.',
        ],
      ),
      _AccuracyChart(active: active.code),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth > 1250 ? 3 : (c.maxWidth > 820 ? 2 : 1);
        final w = (c.maxWidth - (cols - 1) * 14) / cols;
        return Wrap(spacing: 14, runSpacing: 14, children: [
          for (final m in escalationMethods)
            SizedBox(
              width: w,
              child: _MethodCard(
                method: m,
                active: m.code == active.code,
                liveFactor: m.selectable ? mf.factor(m.code, 1393, null, s.targetYear, s.targetMonth) : null,
                targetYear: s.targetYear,
                impact: impact[m.code],
                refSum: ref,
                onSelect: (!canEdit || !m.selectable || m.code == active.code) ? null : () => _select(context, m),
              ),
            ),
        ]);
      }),
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
    ]);
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
        gradient: LinearGradient(colors: [c, Color.lerp(c, Colors.white, 0.25)!]),
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

/// نمودار مقایسه‌ی دقت روش‌ها (خطای میانه و تعداد در بازه‌ی ±۲۵٪).
class _AccuracyChart extends StatelessWidget {
  const _AccuracyChart({required this.active});
  final String active;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final maxErr = escalationMethods.map((m) => m.stats.mdape).reduce((a, b) => a > b ? a : b);
    final best = escalationMethods.reduce((a, b) => a.stats.mdape < b.stats.mdape ? a : b).code;
    return SectionCard(
      title: 'مقایسه‌ی دقت روش‌ها',
      subtitle: '۱۴ پمپ پازنان ۲ · قیمت ۱۳۹۳ تعدیل‌شده به ۱۴۰۴ در برابر استعلام واقعی ۱۴۰۴',
      icon: Icons.leaderboard_rounded,
      child: Column(children: [
        Row(children: [
          const SizedBox(width: 44),
          const SizedBox(width: 180),
          Expanded(child: Text('خطای میانه (کمتر = بهتر)', style: t.textTheme.labelSmall)),
          SizedBox(width: 70, child: Text('سوگیری', textAlign: TextAlign.center, style: t.textTheme.labelSmall)),
          SizedBox(width: 170, child: Text('در بازه‌ی ±۲۵٪', textAlign: TextAlign.center, style: t.textTheme.labelSmall)),
        ]),
        const SizedBox(height: 6),
        for (final m in escalationMethods)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: m.code == active ? AppColors.amberSoft : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              SizedBox(width: 44, child: _CodeBadge(m.code, small: true, color: m.selectable ? null : t.colorScheme.outline)),
              SizedBox(
                width: 180,
                child: Text(m.nameFa,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(fontWeight: m.code == active ? FontWeight.w800 : FontWeight.w500)),
              ),
              Expanded(
                child: Row(children: [
                  Expanded(
                    child: LayoutBuilder(builder: (context, c) {
                      return Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Container(
                          height: 14,
                          width: c.maxWidth * m.stats.mdape / maxErr,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: m.code == best
                                  ? [Tones.good(context), Tones.good(context).withValues(alpha: 0.6)]
                                  : [AppColors.petrol, AppColors.teal],
                            ),
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                      );
                    }),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(pct(m.stats.mdape),
                        textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                ]),
              ),
              SizedBox(
                width: 70,
                child: Text(pct(m.stats.bias, signed: true),
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: m.stats.bias.abs() < 0.1 ? Tones.good(context) : Tones.warn(context),
                        fontWeight: FontWeight.w700)),
              ),
              SizedBox(width: 170, child: Center(child: _Dots(n: m.stats.within25, of: validationSampleSize))),
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
    required this.active,
    required this.liveFactor,
    required this.targetYear,
    required this.impact,
    required this.refSum,
    required this.onSelect,
  });
  final EscalationMethod method;
  final bool active;
  final MethodFactor? liveFactor;
  final int targetYear;
  final _Impact? impact;
  final double? refSum;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final m = method;
    final st = m.stats;
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
    return Container(
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? AppColors.amber : t.colorScheme.outlineVariant,
          width: active ? 2 : 1,
        ),
        boxShadow: softShadow(context),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _CodeBadge(m.code, color: m.selectable ? null : t.colorScheme.outline),
          const SizedBox(width: 12),
          Expanded(
            child: Text(m.nameFa, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ),
          if (m.code == defaultMethodCode) Pill('پیشنهادی', color: Tones.good(context), icon: Icons.verified_rounded),
          if (active) ...[const SizedBox(width: 4), const Pill('فعال', color: Color(0xFFB0700F), icon: Icons.check_circle_rounded)],
          if (!m.selectable) Pill('فقط مقایسه', color: t.colorScheme.outline),
        ]),
        const SizedBox(height: 10),
        Text(m.summaryFa, style: t.textTheme.bodySmall?.copyWith(height: 1.8)),
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
          stat('خطای میانه', pct(st.mdape), color: st.mdape < 0.15 ? Tones.good(context) : null),
          const SizedBox(width: 6),
          stat('سوگیری', pct(st.bias, signed: true)),
          const SizedBox(width: 6),
          stat('در ±۲۵٪', '${fa(st.within25)}/${fa(validationSampleSize)}'),
          const SizedBox(width: 6),
          stat('جمع/واقعی', faNum(st.totalRatio, decimals: 2)),
        ]),
        const SizedBox(height: 10),
        _kv(context, 'ضریب ۱۳۹۳→۱۴۰۴ (صحت‌سنجی)', m.factorRef == null ? 'برای هر ردیف جدا' : faSmart(m.factorRef)),
        if (liveFactor != null)
          _kv(context, 'ضریب ۱۳۹۳→${fa(targetYear)} با داده‌های فعلی',
              liveFactor!.factor == null ? liveFactor!.detail : faSmart(liveFactor!.factor)),
        if (imp != null)
          _kv(
            context,
            'جمع یوروی بانک فعلی (× تعداد)',
            '${compactNum(imp.eurSum)} یورو'
                '${refSum != null && refSum! > 0 && m.code != defaultMethodCode ? '  (${pct(imp.eurSum / refSum! - 1, signed: true)} نسبت به M6)' : ''}',
          ),
        if (imp != null && m.usesFloor) _kv(context, 'پمپ‌هایی که کف قیمت برایشان اعمال شده', fa(imp.floorCount)),
        if (m.noteFa != null) ...[
          const SizedBox(height: 6),
          Text(m.noteFa!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.8)),
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
    );
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
