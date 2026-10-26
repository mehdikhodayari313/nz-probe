import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/series.dart';
import '../../core/repo/indices_repo.dart';
import '../../core/repo/settings_repo.dart';
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
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 4),
                  child: Row(children: [
                    Expanded(
                      child: Text(indexGroupFa[g.key] ?? g.key,
                          style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
                    ),
                    if (g.key == 'fx' && app.user.isAdmin)
                      TextButton.icon(
                        key: const ValueKey('add-fx-table'),
                        onPressed: () => _addFxTable(context),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('جدول نرخ ارز'),
                      ),
                  ]),
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
            : _SeriesDetail(
                key: ValueKey(sel.code),
                info: sel,
                onDeleted: () => setState(() => _selected = null),
              ),
      ),
    ]);
  }

  /// ساخت جدول نرخ ارز جدید (دو سری یورو و دلار) و رفتن مستقیم به آن برای ورود مقادیر.
  Future<void> _addFxTable(BuildContext context) async {
    final app = AppScope.read(context);
    final types = app.pb.settingsRepo.fxRateTypes();
    final res = await showDialog<(String, String?, double?, double?)>(
        context: context, builder: (_) => _NewFxTableDialog(types: types, year: app.settings.targetYear));
    if (res == null || !context.mounted) return;
    try {
      final code = app.pb.settingsRepo.createFxType(res.$1, copyFrom: res.$2);
      final y = Period.year(app.settings.targetYear);
      if (res.$3 != null) app.pb.indices.upsert('FX_EUR_$code', y, res.$3!, status: 'manual', reason: 'ساخت جدول');
      if (res.$4 != null) app.pb.indices.upsert('FX_USD_$code', y, res.$4!, status: 'manual', reason: 'ساخت جدول');
      app.dataChanged(calcInputs: true);
      setState(() => _selected = 'FX_EUR_$code');
      showSnack(context, 'جدول «${res.$1}» ساخت شد. مقادیر سال‌های دیگر را همین‌جا وارد کنید؛ از نوار بالا قابل انتخاب است.');
    } on ArgumentError catch (e) {
      showSnack(context, '${e.message}', error: true);
    }
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
              DropdownButtonFormField<String>(itemHeight: null, isExpanded: true, 
                value: kind,
                decoration: const InputDecoration(labelText: 'نوع'),
                items: const [
                  DropdownMenuItem(value: 'level', child: DdText('سطح شاخص / نرخ (مثل PPI یا ریال به ازای یورو)')),
                  DropdownMenuItem(value: 'annual_rate', child: DdText('نرخ رشد سالانه (مثل تورم ۰٫۴)')),
                ],
                onChanged: (v) => setD(() => kind = v!),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(itemHeight: null, isExpanded: true, 
                value: group,
                decoration: const InputDecoration(labelText: 'گروه'),
                items: [for (final e in indexGroupFa.entries) DropdownMenuItem(value: e.key, child: DdText(e.value))],
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
  const _SeriesDetail({super.key, required this.info, required this.onDeleted});
  final IndexSeriesInfo info;
  final VoidCallback onDeleted;

  @override
  State<_SeriesDetail> createState() => _SeriesDetailState();
}

class _SeriesDetailState extends State<_SeriesDetail> {
  final _year = TextEditingController();
  final _value = TextEditingController();
  String _status = 'manual';

  /// بازه‌ی دوره: Y = کل سال، Q1..Q4 = فصل، M1..M12 = ماه
  String _span = 'Y';

  @override
  void dispose() {
    _year.dispose();
    _value.dispose();
    super.dispose();
  }

  /// کد جدول نرخ ارز اگر این سری متعلق به یک جدول نرخ ارز باشد (FX_EUR_<کد>).
  String? get _fxTable {
    final m = RegExp(r'^FX_(EUR|USD)_(.+)$').firstMatch(widget.info.code);
    return m?.group(2);
  }

  Future<void> _deleteFxTable(BuildContext context, String code) async {
    final app = AppScope.read(context);
    final ft = app.pb.settingsRepo.fxRateTypes().where((f) => f.code == code).firstOrNull;
    if (ft == null) return;
    final ok = await confirm(context, 'حذف جدول «${ft.nameFa}»',
        'هر دو سری یورو و دلار این جدول با همه‌ی مقادیرشان حذف می‌شوند. اگر این جدول انتخاب شده باشد، «جدول پیش‌فرض» جایگزین می‌شود. حذف در تاریخچه ثبت می‌شود.',
        ok: 'حذف جدول');
    if (!ok || !context.mounted) return;
    app.pb.settingsRepo.deleteFxType(code);
    app.dataChanged(calcInputs: true);
    widget.onDeleted();
    showSnack(context, 'جدول «${ft.nameFa}» حذف شد.');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
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
          if (_fxTable != null && app.user.isAdmin &&
              app.pb.settingsRepo.fxRateTypes().any((f) => f.code == _fxTable && f.userDefined))
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Tones.bad(context)),
              onPressed: () => _deleteFxTable(context, _fxTable!),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('حذف این جدول نرخ ارز'),
            ),
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
          'نرخ‌های ارز در «جدول»‌های جداگانه‌اند: «جدول پیش‌فرض»، «بازار آزاد»، «مرکز مبادله / نیما» و هر جدولی که خودتان با دکمه‌ی «+ جدول نرخ ارز» (ستون کناری همین صفحه) بسازید. جدول مورد استفاده را از نوار بالا انتخاب کنید.',
          'نرخ‌های رشد (مثل تورم) را به درصد وارد کنید: برای ۳۵٪ فقط ۳۵ بنویسید.',
          'PPI بخشی ایران (مرکز آمار، پایه ۱۳۹۵=۱۰۰) برای تجهیزات ساخت داخل (مخزن، ظرف، سازه، برق و ابزار دقیق) در نظر گرفته شده؛ مقادیر «نیاز به تأیید» را با PDF مرکز آمار تطبیق دهید.',
          'هر ویرایش با مقدار قبلی، کاربر و زمان در تاریخچه ثبت می‌شود. «چسباندن از اکسل»: دو ستون دوره و مقدار را از اکسل کپی و اینجا بچسبانید.',
          if (s.source != null) 'منبع این سری: ${s.source}',
        ],
      ),
      if (values.length >= 2)
        SectionCard(
          title: 'روند',
          icon: Icons.timeline_rounded,
          child: SizedBox(height: 200, child: _LineChart(values: values, isRate: s.isRate)),
        ),
      const SizedBox(height: 14),
      if (canEdit)
        SectionCard(
          title: 'افزودن یا اصلاح مقدار',
          icon: Icons.edit_calendar_rounded,
          child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 120,
              child: TextField(
                controller: _year,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: s.calendar == 'gregorian' ? 'سال میلادی' : 'سال', hintText: s.calendar == 'gregorian' ? '2025' : '1404'),
              ),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(itemHeight: null, 
                value: _span,
                isExpanded: true,
                menuMaxHeight: 420,
                decoration: const InputDecoration(labelText: 'بازه'),
                items: [
                  const DropdownMenuItem(value: 'Y', child: DdText('کل سال')),
                  for (var q = 1; q <= 4; q++) DropdownMenuItem(value: 'Q$q', child: DdText('فصل ${fa(q)}')),
                  for (var m = 1; m <= 12; m++) DropdownMenuItem(value: 'M$m', child: DdText('ماه ${jalaliMonthNames[m - 1]}')),
                ],
                onChanged: (v) => setState(() => _span = v ?? 'Y'),
              ),
            ),
            SizedBox(
              width: 200,
              child: TextField(
                controller: _value,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: s.isRate ? 'نرخ (درصد)' : 'مقدار',
                  hintText: s.isRate ? 'مثلاً 35 یعنی ۳۵٪' : null,
                  suffixText: s.isRate ? '٪' : null,
                ),
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(itemHeight: null, isExpanded: true, 
                value: _status,
                decoration: const InputDecoration(labelText: 'وضعیت'),
                items: [for (final e in indexStatusFa.entries) DropdownMenuItem(value: e.key, child: DdText(e.value))],
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
                    decoration: BoxDecoration(color: AppColors.headerBg),
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
    final y = int.tryParse(_latin(_year.text.trim()));
    final raw = parseUserNumber(_value.text);
    if (y == null || y < 1300 || y > 2100) {
      showSnack(context, 'سال را به شکل چهاررقمی وارد کنید (مثلاً ۱۴۰۴).', error: true);
      return;
    }
    if (raw == null) {
      showSnack(context, 'مقدار عددی را وارد کنید.', error: true);
      return;
    }
    final pp = _span == 'Y'
        ? Period.year(y)
        : (_span.startsWith('Q') ? Period.quarter(y, int.parse(_span.substring(1))) : Period.month(y, int.parse(_span.substring(1))));
    // نرخ رشد به درصد وارد می‌شود و به کسر ذخیره می‌شود
    final v = widget.info.isRate ? raw / 100 : raw;
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
            Text(
                'دو ستون «دوره» و «مقدار» را از اکسل کپی کنید و اینجا بچسبانید. هر خط یک مقدار. مقادیر موجود همان دوره جایگزین می‌شوند.'
                '${widget.info.isRate ? '\nنرخ‌ها را به درصد بچسبانید (۳۵ یعنی ۳۵٪).' : ''}',
                style: const TextStyle(height: 1.8)),
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
    final (n, bad) = app.pb.indices.importText(widget.info.code, text, scale: widget.info.isRate ? 0.01 : 1);
    app.dataChanged(calcInputs: true);
    showSnack(context, '${fa(n)} مقدار ثبت شد${bad.isEmpty ? '' : '؛ ${fa(bad.length)} خط نامعتبر کنار گذاشته شد'}.',
        error: bad.isNotEmpty && n == 0);
  }
}

/// ساخت جدول نرخ ارز جدید: نام، مقادیر اولیه (خالی یا کپی) و در صورت تمایل نرخ سال هدف.
class _NewFxTableDialog extends StatefulWidget {
  const _NewFxTableDialog({required this.types, required this.year});
  final List<FxRateType> types;
  final int year;

  @override
  State<_NewFxTableDialog> createState() => _NewFxTableDialogState();
}

class _NewFxTableDialogState extends State<_NewFxTableDialog> {
  final _name = TextEditingController();
  final _eur = TextEditingController();
  final _usd = TextEditingController();
  String? _copy = 'V8';

  @override
  void dispose() {
    _name.dispose();
    _eur.dispose();
    _usd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.currency_exchange_rounded),
        SizedBox(width: 8),
        Text('جدول نرخ ارز جدید'),
      ]),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'نام جدول', hintText: 'مثلاً: نرخ بودجه ۱۴۰۵، نرخ قرارداد پازنان'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(itemHeight: null, 
            value: _copy,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'مقادیر سال‌های دیگر'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: DdText('خالی (همه را خودم وارد می‌کنم)')),
              for (final ft in widget.types) DropdownMenuItem<String?>(value: ft.code, child: DdText('کپی از «${ft.nameFa}»')),
            ],
            onChanged: (v) => setState(() => _copy = v),
          ),
          const SizedBox(height: 12),
          Text('نرخ سال ${fa(widget.year)} (اختیاری — همین حالا)', style: t.textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _eur,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'یورو (ریال)', hintText: '1130000'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _usd,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'دلار (ریال)', hintText: '1000000'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            'دو سری «یورو به ریال» و «دلار به ریال» با این نام ساخته می‌شوند و بلافاصله همین‌جا برای ورود یا اصلاح مقادیر باز می‌شوند.',
            style: t.textTheme.bodySmall?.copyWith(height: 1.8, color: t.colorScheme.onSurfaceVariant),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                  context, (_name.text.trim(), _copy, parseUserNumber(_eur.text), parseUserNumber(_usd.text))),
          child: const Text('ساخت جدول'),
        ),
      ],
    );
  }
}

/// نمودار خطی تعاملی (بدون کتابخانه‌ی خارجی): نشانگر ماوس نزدیک‌ترین نقطه را با مقدارش نشان می‌دهد.
class _LineChart extends StatefulWidget {
  const _LineChart({required this.values, required this.isRate});
  final List<IndexValue> values;
  final bool isRate;

  @override
  State<_LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<_LineChart> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return LayoutBuilder(builder: (context, c) {
      final n = widget.values.length;
      const padL = 64.0, padR = 8.0;
      final w = c.maxWidth - padL - padR;
      int? nearest(Offset p) {
        if (n == 0) return null;
        final x = p.dx - padL;
        final i = n == 1 ? 0 : (x / w * (n - 1)).round();
        return i.clamp(0, n - 1);
      }

      return MouseRegion(
        onHover: (e) => setState(() => _hover = nearest(e.localPosition)),
        onExit: (_) => setState(() => _hover = null),
        child: CustomPaint(
          painter: _ChartPainter(
            values: widget.values,
            isRate: widget.isRate,
            hover: _hover,
            line: AppColors.petrol,
            accent: AppColors.amber,
            grid: t.colorScheme.outlineVariant,
            text: t.colorScheme.onSurfaceVariant,
            tipBg: AppColors.navy,
          ),
          size: Size.infinite,
        ),
      );
    });
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.values,
    required this.isRate,
    required this.hover,
    required this.line,
    required this.accent,
    required this.grid,
    required this.text,
    required this.tipBg,
  });
  final List<IndexValue> values;
  final bool isRate;
  final int? hover;
  final Color line, accent, grid, text, tipBg;

  String _fmt(double v) => isRate ? '${faNum(v * 100, decimals: 1)}٪' : fa(compactNum(v));

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 64.0, padB = 22.0, padT = 10.0, padR = 8.0;
    final w = size.width - padL - padR, h = size.height - padB - padT;
    final vs = values.map((v) => v.value).toList();
    var lo = vs.reduce((a, b) => a < b ? a : b), hi = vs.reduce((a, b) => a > b ? a : b);
    if (hi == lo) {
      hi += hi.abs() * 0.1 + 1e-9;
      lo -= lo.abs() * 0.1 + 1e-9;
    }
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    TextPainter tp(String s, {Color? color, double size = 10, FontWeight? weight}) => TextPainter(
          text: TextSpan(
              text: s, style: TextStyle(color: color ?? text, fontSize: size, fontFamily: 'Vazirmatn', fontWeight: weight)),
          textDirection: TextDirection.rtl,
        )..layout();
    for (var i = 0; i <= 3; i++) {
      final y = padT + h * i / 3;
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), gp);
      final p = tp(_fmt(hi - (hi - lo) * i / 3));
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
    canvas.drawPath(fill, Paint()..color = line.withValues(alpha: 0.10));
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke);
    for (final p in pts) {
      canvas.drawCircle(p, 2.8, Paint()..color = line);
    }
    final step = (values.length / 8).ceil().clamp(1, 1000);
    for (var i = 0; i < values.length; i += step) {
      final p = tp(fa(values[i].period.key));
      p.paint(canvas, Offset(pts[i].dx - p.width / 2, padT + h + 5));
    }
    // نقطه‌ی زیر نشانگر ماوس
    final hv = hover;
    if (hv != null && hv >= 0 && hv < pts.length) {
      final p = pts[hv];
      canvas.drawLine(Offset(p.dx, padT), Offset(p.dx, padT + h), Paint()..color = accent.withValues(alpha: 0.6));
      canvas.drawCircle(p, 7, Paint()..color = accent.withValues(alpha: 0.3));
      canvas.drawCircle(p, 4.5, Paint()..color = accent);
      final label = tp('${fa(values[hv].period.label)}:  ${isRate ? _fmt(values[hv].value) : faSmart(values[hv].value)}',
          color: Colors.white, size: 11.5, weight: FontWeight.w700);
      final bw = label.width + 16, bh = label.height + 10;
      var bx = p.dx - bw / 2;
      bx = bx.clamp(padL, size.width - bw);
      final by = (p.dy - bh - 10).clamp(0.0, size.height - bh);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, bw, bh), const Radius.circular(7)), Paint()..color = tipBg);
      label.paint(canvas, Offset(bx + 8, by + 5));
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => old.values != values || old.hover != hover || old.line != line;
}
