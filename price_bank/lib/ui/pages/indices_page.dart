import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/series.dart';
import '../../core/repo/indices_repo.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';

class IndicesPage extends StatefulWidget {
  const IndicesPage({super.key});

  @override
  State<IndicesPage> createState() => _IndicesPageState();
}

class _IndicesPageState extends State<IndicesPage> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final series = app.pb.indices.series();
    _selected ??= series.isEmpty ? null : series.first.code;
    final sel = series.where((s) => s.code == _selected).firstOrNull;
    final groups = <String, List<IndexSeriesInfo>>{};
    for (final s in series) {
      (groups[s.group] ??= []).add(s);
    }

    return Row(children: [
      Material(
        color: t.colorScheme.surface,
        child: Container(
        width: 330,
        decoration: BoxDecoration(
          border: BorderDirectional(end: BorderSide(color: t.colorScheme.outlineVariant)),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Row(children: [
              Expanded(child: Text('شاخص‌ها و نرخ‌ها', style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
              if (app.user.isAdmin)
                IconButton(
                  tooltip: 'افزودن سری جدید (مثلاً شاخص فولاد یا CEPCI)',
                  onPressed: () => _addSeries(context),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
            ]),
          ),
          Expanded(
            child: ListView(children: [
              for (final g in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(indexGroupFa[g.key] ?? g.key,
                      style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
                ),
                for (final s in g.value)
                  ListTile(
                    dense: true,
                    selected: s.code == _selected,
                    selectedTileColor: t.colorScheme.primaryContainer.withValues(alpha: 0.6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    title: Text(s.nameFa, style: const TextStyle(fontSize: 13)),
                    subtitle: Text('${s.code} · ${fa(s.valueCount)} مقدار', textDirection: TextDirection.ltr,
                        textAlign: TextAlign.end, style: const TextStyle(fontSize: 11)),
                    trailing: s.valueCount == 0 ? Pill('خالی', color: Tones.warn(context)) : null,
                    onTap: () => setState(() => _selected = s.code),
                  ),
              ],
            ]),
          ),
        ]),
      ),
      ),
      Expanded(
        child: sel == null
            ? const EmptyState(icon: Icons.query_stats_rounded, title: 'سری‌ای انتخاب نشده')
            : _SeriesDetail(key: ValueKey(sel.code), info: sel),
      ),
    ]);
  }

  Future<void> _addSeries(BuildContext context) async {
    final code = TextEditingController(), name = TextEditingController(), unit = TextEditingController();
    String kind = 'level', group = 'other';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('سری جدید شاخص یا نرخ'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: code, decoration: const InputDecoration(labelText: 'کد (لاتین، یکتا) — مثلاً CEPCI یا FX_EUR_BANK'), textDirection: TextDirection.ltr),
              const SizedBox(height: 10),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'نام فارسی')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: kind,
                decoration: const InputDecoration(labelText: 'نوع'),
                items: const [
                  DropdownMenuItem(value: 'level', child: Text('سطح شاخص / نرخ (مثل PPI یا ریال به ازای یورو)')),
                  DropdownMenuItem(value: 'annual_rate', child: Text('نرخ رشد سالانه (مثل تورم ۰٫۴)')),
                ],
                onChanged: (v) => setD(() => kind = v!),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: group,
                decoration: const InputDecoration(labelText: 'گروه'),
                items: [for (final e in indexGroupFa.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setD(() => group = v!),
              ),
              const SizedBox(height: 10),
              TextField(controller: unit, decoration: const InputDecoration(labelText: 'واحد / پایه (اختیاری)')),
              const SizedBox(height: 8),
              const Text('برای نوع نرخ ارز جدید، کد را به شکل FX_EUR_<نوع> و FX_USD_<نوع> بسازید و نوع را در تنظیمات اضافه کنید.',
                  style: TextStyle(fontSize: 12)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ایجاد')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final c = code.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z][A-Z0-9_]{1,40}$').hasMatch(c) || name.text.trim().isEmpty) {
      showSnack(context, 'کد باید لاتین (حروف بزرگ، عدد و _) و نام فارسی پر باشد.', error: true);
      return;
    }
    try {
      final app = AppScope.read(context);
      app.pb.indices.addSeries(code: c, nameFa: name.text.trim(), kind: kind, group: group, unit: unit.text.trim());
      app.dataChanged(calcInputs: true);
      setState(() => _selected = c);
    } catch (e) {
      showSnack(context, 'ایجاد ناموفق: $e', error: true);
    }
  }
}

class _SeriesDetail extends StatefulWidget {
  const _SeriesDetail({super.key, required this.info});
  final IndexSeriesInfo info;

  @override
  State<_SeriesDetail> createState() => _SeriesDetailState();
}

class _SeriesDetailState extends State<_SeriesDetail> {
  final _period = TextEditingController();
  final _value = TextEditingController();
  String _status = 'manual';

  @override
  void dispose() {
    _period.dispose();
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final s = widget.info;
    final values = app.pb.indices.values(s.code);
    final canEdit = app.user.role != 'viewer';
    final isFx = s.group == 'fx';

    return ListView(padding: const EdgeInsets.all(20), children: [
      PageHeader(
        icon: isFx ? Icons.currency_exchange_rounded : Icons.show_chart_rounded,
        title: s.nameFa,
        subtitle: [
          s.code,
          if (s.unit != null) 'واحد: ${s.unit}',
          if (s.base != null) 'پایه: ${s.base}',
          s.isRate ? 'نوع: نرخ رشد سالانه' : 'نوع: سطح شاخص / نرخ',
          s.calendar == 'gregorian' ? 'تقویم میلادی' : 'تقویم شمسی',
        ].join(' · '),
        actions: [
          if (canEdit)
            OutlinedButton.icon(
              onPressed: () => _paste(context),
              icon: const Icon(Icons.content_paste_go_rounded),
              label: const Text('چسباندن از اکسل'),
            ),
        ],
      ),
      HelpPanel(
        id: 'indices',
        title: 'راهنمای شاخص‌ها و نرخ ارز',
        initiallyOpen: false,
        lines: [
          'هر مقدار برای یک «دوره» ثبت می‌شود: سال (۱۴۰۴)، فصل (1404Q1) یا ماه (1404-03). در محاسبه، اول مقدار ماه، بعد فصل و بعد سال جستجو می‌شود.',
          'نرخ‌های ارز سه نوع دارند: «جدول مرجع v8»، «بازار آزاد» و «مرکز مبادله / نیما». نوع مورد استفاده را از نوار بالا انتخاب کنید.',
          'PPI بخشی ایران (مرکز آمار، پایه ۱۳۹۵=۱۰۰) برای تجهیزات ساخت داخل (مخزن، ظرف، سازه، برق و ابزار دقیق) در نظر گرفته شده؛ مقادیر «نیاز به تأیید» را با PDF مرکز آمار تطبیق دهید.',
          'هر ویرایش با مقدار قبلی، کاربر و زمان در تاریخچه ثبت می‌شود. «چسباندن از اکسل»: دو ستون دوره و مقدار را از اکسل کپی و اینجا بچسبانید.',
          if (s.source != null) 'منبع این سری: ${s.source}',
        ],
      ),
      if (values.length >= 2)
        SectionCard(
          title: 'روند',
          icon: Icons.timeline_rounded,
          child: SizedBox(height: 180, child: _LineChart(values: values)),
        ),
      const SizedBox(height: 14),
      if (canEdit)
        SectionCard(
          title: 'افزودن یا اصلاح مقدار',
          icon: Icons.edit_calendar_rounded,
          child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 200,
              child: TextField(
                controller: _period,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'دوره', hintText: '1404 یا 1404Q1 یا 1404-03'),
              ),
            ),
            SizedBox(
              width: 200,
              child: TextField(
                controller: _value,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: s.isRate ? 'نرخ (مثلاً 0.35 = ۳۵٪)' : 'مقدار'),
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'وضعیت'),
                items: [for (final e in indexStatusFa.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _status = v!),
              ),
            ),
            FilledButton.icon(onPressed: () => _add(context), icon: const Icon(Icons.save_rounded), label: const Text('ثبت')),
          ]),
        ),
      const SizedBox(height: 14),
      SectionCard(
        title: 'مقادیر (${fa(values.length)})',
        icon: Icons.table_rows_outlined,
        padding: EdgeInsets.zero,
        child: values.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: Text('هنوز مقداری وارد نشده است. از فرم بالا یا «چسباندن از اکسل» استفاده کنید.'),
              )
            : Table(
                columnWidths: const {
                  0: FixedColumnWidth(140), 1: FixedColumnWidth(170), 2: FixedColumnWidth(140), 3: FlexColumnWidth(), 4: FixedColumnWidth(150), 5: FixedColumnWidth(60),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: t.colorScheme.surfaceContainerHigh),
                    children: [for (final h in ['دوره', 'مقدار', 'وضعیت', 'منبع / یادداشت', 'آخرین ویرایش', '']) _c(h, b: true)],
                  ),
                  for (final v in values.reversed)
                    TableRow(children: [
                      _c(fa(v.period.label)),
                      _c(s.isRate ? '${faNum(v.value * 100, decimals: 2)}٪' : faSmart(v.value), b: true),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Pill(indexStatusFa[v.status] ?? v.status,
                              color: switch (v.status) {
                                'needs_verification' => Tones.bad(context),
                                'forecast' => Tones.warn(context),
                                'approx' || 'imputed' => Tones.info(context),
                                _ => Tones.good(context),
                              }),
                        ),
                      ),
                      _c(v.source ?? '', small: true),
                      _c(shortTs(v.updatedAt), small: true),
                      canEdit
                          ? IconButton(
                              tooltip: 'حذف',
                              icon: const Icon(Icons.delete_outline_rounded, size: 18),
                              onPressed: () => _delete(context, v),
                            )
                          : const SizedBox(),
                    ]),
                ],
              ),
      ),
    ]);
  }

  Widget _c(String s, {bool b = false, bool small = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(s,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textDirection: dirOf(s),
            style: TextStyle(fontWeight: b ? FontWeight.w700 : null, fontSize: small ? 11.5 : 13)),
      );

  void _add(BuildContext context) {
    final pp = Period.tryParse(_latin(_period.text));
    final v = parseUserNumber(_value.text);
    if (pp == null || v == null) {
      showSnack(context, 'دوره (مثل 1404، 1404Q1 یا 1404-03) و مقدار عددی را درست وارد کنید.', error: true);
      return;
    }
    final app = AppScope.read(context);
    app.pb.indices.upsert(widget.info.code, pp, v, status: _status, reason: 'ورود دستی');
    app.dataChanged(calcInputs: true);
    _value.clear();
    showSnack(context, 'مقدار ${fa(pp.label)} ثبت شد؛ همه‌ی محاسبات به‌روز شدند.');
  }

  String _latin(String s) {
    const f = '۰۱۲۳۴۵۶۷۸۹';
    return s.split('').map((c) => f.contains(c) ? '${f.indexOf(c)}' : c).join();
  }

  Future<void> _delete(BuildContext context, IndexValue v) async {
    final ok = await confirm(context, 'حذف مقدار', 'مقدار ${fa(v.period.label)} حذف شود؟ (در تاریخچه ثبت می‌ماند)', ok: 'حذف');
    if (!ok || !context.mounted) return;
    final app = AppScope.read(context);
    app.pb.indices.delete(widget.info.code, v.period, reason: 'حذف دستی');
    app.dataChanged(calcInputs: true);
  }

  Future<void> _paste(BuildContext context) async {
    final ctl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('چسباندن مقادیر — ${widget.info.nameFa}'),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('دو ستون «دوره» و «مقدار» را از اکسل کپی کنید و اینجا بچسبانید. هر خط یک مقدار. مقادیر موجود همان دوره جایگزین می‌شوند.',
                style: TextStyle(height: 1.8)),
            const SizedBox(height: 10),
            TextField(
              controller: ctl,
              maxLines: 12,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(hintText: '1403\t640000\n1404Q1\t980000\n1404-05\t1020000'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('ثبت')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    final app = AppScope.read(context);
    final (n, bad) = app.pb.indices.importText(widget.info.code, text);
    app.dataChanged(calcInputs: true);
    showSnack(context, '${fa(n)} مقدار ثبت شد${bad.isEmpty ? '' : '؛ ${fa(bad.length)} خط نامعتبر کنار گذاشته شد'}.',
        error: bad.isNotEmpty && n == 0);
  }
}

/// نمودار خطی ساده (بدون کتابخانه‌ی خارجی).
class _LineChart extends StatelessWidget {
  const _LineChart({required this.values});
  final List<IndexValue> values;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return CustomPaint(
      painter: _ChartPainter(
        values: values,
        line: t.colorScheme.primary,
        grid: t.colorScheme.outlineVariant,
        text: t.colorScheme.onSurfaceVariant,
      ),
      size: Size.infinite,
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.values, required this.line, required this.grid, required this.text});
  final List<IndexValue> values;
  final Color line, grid, text;

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 64.0, padB = 22.0, padT = 8.0, padR = 8.0;
    final w = size.width - padL - padR, h = size.height - padB - padT;
    final vs = values.map((v) => v.value).toList();
    var lo = vs.reduce((a, b) => a < b ? a : b), hi = vs.reduce((a, b) => a > b ? a : b);
    if (hi == lo) {
      hi += 1;
      lo -= 1;
    }
    final gp = Paint()..color = grid..strokeWidth = 1;
    TextPainter tp(String s) => TextPainter(
          text: TextSpan(text: s, style: TextStyle(color: text, fontSize: 10, fontFamily: 'Vazirmatn')),
          textDirection: TextDirection.ltr,
        )..layout();
    for (var i = 0; i <= 3; i++) {
      final y = padT + h * i / 3;
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), gp);
      final v = hi - (hi - lo) * i / 3;
      final p = tp(fa(compactNum(v)));
      p.paint(canvas, Offset(padL - p.width - 6, y - p.height / 2));
    }
    // محور افقی چپ‌به‌راست (زمان) حتی در رابط راست‌به‌چپ
    final pts = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = padL + (values.length == 1 ? w / 2 : w * i / (values.length - 1));
      final y = padT + h * (1 - (values[i].value - lo) / (hi - lo));
      pts.add(Offset(x, y));
    }
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final fill = Path.from(path)
      ..lineTo(pts.last.dx, padT + h)
      ..lineTo(pts.first.dx, padT + h)
      ..close();
    canvas.drawPath(fill, Paint()..color = line.withValues(alpha: 0.08));
    canvas.drawPath(path, Paint()..color = line..strokeWidth = 2..style = PaintingStyle.stroke);
    for (final p in pts) {
      canvas.drawCircle(p, 2.6, Paint()..color = line);
    }
    final step = (values.length / 8).ceil().clamp(1, 1000);
    for (var i = 0; i < values.length; i += step) {
      final p = tp(fa(values[i].period.key));
      p.paint(canvas, Offset(pts[i].dx - p.width / 2, padT + h + 5));
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => old.values != values;
}
