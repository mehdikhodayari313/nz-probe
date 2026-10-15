// جزئیات یک قلم غیرپمپ: مشخصات (قابل ویرایش)، همه‌ی قیمت‌ها و استعلام‌ها با تعدیل هرکدام،
// انتخاب قیمت مبنا، محاسبه‌ی گام‌به‌گام و تاریخچه.

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/desalter.dart';
import '../../core/calc/generic_engine.dart';
import '../../core/calc/pump_engine.dart' show CalcStep;
import '../../core/catalog/profiles.dart';
import '../../core/price_bank.dart';
import '../../core/repo/audit.dart';
import '../../core/repo/catalog_repo.dart';
import '../../core/repo/items_repo.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/field_editor.dart';

class GenericItemPage extends StatefulWidget {
  const GenericItemPage({super.key, required this.itemId});
  final int itemId;

  @override
  State<GenericItemPage> createState() => _GenericItemPageState();
}

class _GenericItemPageState extends State<GenericItemPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  bool _editing = false;
  final Map<String, Object?> _draft = {};

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pb = app.pb;
    final item = pb.items.get(widget.itemId);
    if (item == null) {
      return const Scaffold(body: EmptyState(icon: Icons.error_outline, title: 'قلم پیدا نشد'));
    }
    final cat = pb.catalog.categories().firstWhere((c) => c.id == item.categoryId);
    final fields = pb.catalog.fields(cat.id);
    final engine = pb.genericEngine(categoryCode: cat.code);
    final profile = equipmentProfiles[cat.code];
    final result = engine.calculate(PriceBank.genericInputFor(item.primary));
    final des = cat.code == 'DESALTER'
        ? app.genericRows(cat.id).where((r) => r.item.id == item.id).firstOrNull?.des
        : null;
    final canEdit = app.canEdit(cat.disciplineCode);
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          Text(item.tag?.isNotEmpty == true ? item.tag! : cat.nameFa,
              textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 12),
          Flexible(child: Text(item.name, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall)),
          const SizedBox(width: 10),
          Pill(cat.nameFa),
        ]),
        actions: [
          if (!_editing && canEdit) ...[
            OutlinedButton.icon(
              onPressed: () => _archive(context, item),
              icon: Icon(item.status == 'active' ? Icons.archive_outlined : Icons.unarchive_outlined),
              label: Text(item.status == 'active' ? 'بایگانی' : 'بازگرداندن'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => setState(() {
                _draft.clear();
                _editing = true;
                _tabs.index = 0;
              }),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('ویرایش'),
            ),
          ],
          if (_editing) ...[
            TextButton(
              onPressed: () => setState(() {
                _draft.clear();
                _editing = false;
              }),
              child: const Text('انصراف'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _save(context, item, fields),
              icon: const Icon(Icons.save_rounded),
              label: Text('ذخیره‌ی تغییرات${_draft.isEmpty ? '' : ' (${fa(_draft.length)})'}'),
            ),
          ],
          const SizedBox(width: 16),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            const Tab(icon: Icon(Icons.description_outlined), text: 'مشخصات'),
            Tab(icon: const Icon(Icons.request_quote_outlined), text: 'قیمت‌ها و استعلام‌ها (${fa(item.observations.length)})'),
            const Tab(icon: Icon(Icons.calculate_outlined), text: 'محاسبه‌ی قیمت'),
            const Tab(icon: Icon(Icons.history_rounded), text: 'تاریخچه'),
          ],
        ),
      ),
      body: Column(children: [
        _Strip(item: item, result: result, engine: engine, profile: profile),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            _specTab(context, fields, item),
            _PricesTab(item: item, engine: engine, canEdit: canEdit),
            _CalcTab(result: result, des: des),
            _HistoryTab(entries: pb.audit.history('item', item.id), fields: fields),
          ]),
        ),
      ]),
    );
  }

  Widget _specTab(BuildContext context, List<FieldDef> fields, ItemRecord item) {
    final groups = <String, List<FieldDef>>{};
    for (final f in fields) {
      if (f.storage == FieldStorage.calc) continue;
      // در حالت نمایش، فیلدهای مشخصاتِ خالی نشان داده نمی‌شوند
      if (!_editing && f.groupKey == 'mto_specs' && item.valueOf(f.key) == null) continue;
      (groups[f.groupFa] ??= []).add(f);
    }
    return ListView(padding: const EdgeInsets.all(20), children: [
      for (final g in groups.entries) ...[
        SectionCard(
          title: g.key,
          icon: switch (g.value.first.groupKey) {
            'identification' => Icons.badge_outlined,
            'mto_specs' => Icons.engineering_outlined,
            'description' => Icons.notes_rounded,
            'price' => Icons.payments_outlined,
            _ => Icons.fact_check_outlined,
          },
          child: LayoutBuilder(builder: (context, cons) {
            final wide = g.value.first.groupKey == 'description';
            final cols = wide ? 1 : (cons.maxWidth > 1100 ? 3 : (cons.maxWidth > 700 ? 2 : 1));
            final w = (cons.maxWidth - (cols - 1) * 16) / cols;
            return Wrap(spacing: 16, runSpacing: 14, children: [
              for (final f in g.value)
                SizedBox(
                  width: w,
                  child: FieldTile(
                    field: f,
                    categoryId: item.categoryId,
                    value: _draft.containsKey(f.key) ? _draft[f.key] : item.valueOf(f.key),
                    meta: item.meta[f.key],
                    editing: _editing && f.editable,
                    changed: _draft.containsKey(f.key),
                    onChanged: (v) => setState(() => _draft[f.key] = v),
                  ),
                ),
            ]);
          }),
        ),
        const SizedBox(height: 14),
      ],
    ]);
  }

  Future<void> _save(BuildContext context, ItemRecord item, List<FieldDef> fields) async {
    if (_draft.isEmpty) {
      setState(() => _editing = false);
      return;
    }
    final labels = {for (final f in fields) f.key: f.labelFa};
    final reason = await askReason(context, summary: 'فیلدهای تغییرکرده: ${_draft.keys.map((k) => labels[k] ?? k).join('، ')}');
    if (reason == null || !context.mounted) return;
    final app = AppScope.read(context);
    final n = app.pb.items.update(item.id, Map.of(_draft), reason: reason.isEmpty ? null : reason);
    app.dataChanged();
    setState(() {
      _editing = false;
      _draft.clear();
    });
    if (context.mounted) showSnack(context, n == 0 ? 'تغییری ثبت نشد.' : '${fa(n)} فیلد ذخیره شد.');
  }

  Future<void> _archive(BuildContext context, ItemRecord item) async {
    final archiving = item.status == 'active';
    final reason = await askReason(context,
        title: archiving ? 'بایگانی قلم' : 'بازگرداندن قلم',
        summary: archiving ? 'قلم از فهرست و جمع‌ها کنار می‌رود ولی حذف نمی‌شود.' : 'قلم دوباره در فهرست قرار می‌گیرد.');
    if (reason == null || !context.mounted) return;
    final app = AppScope.read(context);
    app.pb.items.archive(item.id, archived: archiving, reason: reason);
    app.dataChanged();
    if (archiving && context.mounted) Navigator.pop(context);
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.item, required this.result, required this.engine, this.profile});
  final ItemRecord item;
  final GenericCalcResult result;
  final GenericEngine engine;
  final EquipmentProfile? profile;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final unit = app.unit;
    final t = Theme.of(context);
    final qty = item.quantity ?? 1;
    final quotes = [
      for (final o in item.observations.where((o) => o.kind == 'quote'))
        if (engine.calculate(PriceBank.genericInputFor(o)).eurTarget.number case final v?) v,
    ];
    quotes.sort();
    return Container(
      color: t.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        KpiTile(
          label: 'یورو تعدیل‌شده (${fa(app.settings.targetYear)})',
          value: result.eurTarget.isNumber ? faNum(result.eurTarget.number) : '—',
          sub: result.eurTarget.isNumber ? 'روش ${result.methodCode} · از قیمت مبنا' : 'قیمت مبنا قابل تعدیل نیست',
          icon: Icons.euro_rounded,
          color: AppColors.eur,
          width: 230,
        ),
        KpiTile(
          label: 'قیمت واحد (${unitLabel(unit)})',
          value: money(result.irrTarget.number, unit, withUnit: false),
          sub: result.eurRateTarget == null ? 'نرخ یوروی سال هدف وارد نشده' : 'نرخ یورو: ${faNum(result.eurRateTarget)} ریال',
          icon: Icons.payments_outlined,
          color: AppColors.irr,
          width: 260,
        ),
        KpiTile(
          label: 'جمع برای ${fa(faSmart(qty))} دستگاه',
          value: money(result.irrTarget.isNumber ? result.irrTarget.number! * qty : null, unit, compact: true, withUnit: false),
          sub: unitLabel(unit),
          icon: Icons.functions_rounded,
          width: 220,
        ),
        if (profile != null)
          KpiTile(
            label: profile!.driver.labelFa,
            value: profile!.sizeOf(item.values) == null ? '—' : faSmart(profile!.sizeOf(item.values)),
            sub: profile!.sizeOf(item.values) == null ? 'ابعاد/ظرفیت ثبت نشده' : '${profile!.driver.unit} · پارامتر اندازه برای تخمین',
            icon: Icons.straighten_rounded,
            color: AppColors.petrol,
            width: 210,
          ),
        if (profile?.weightKey != null) _weightTile(context, app),
        KpiTile(
          label: 'بازه‌ی استعلام‌ها (یورو، سال هدف)',
          value: quotes.isEmpty ? '—' : '${compactNum(quotes.first)} تا ${compactNum(quotes.last)}',
          sub: quotes.isEmpty ? 'استعلام عددی ندارد' : '${fa(quotes.length)} استعلام · میانگین ${compactNum(quotes.reduce((a, b) => a + b) / quotes.length)}',
          icon: Icons.request_quote_outlined,
          color: AppColors.teal,
          width: 260,
        ),
      ]),
    );
  }
}

extension on _Strip {
  /// وزن خالی و ضریب وزن (بی‌اثر تا وقتی وزن ثبت نشده)
  Widget _weightTile(BuildContext context, AppState app) {
    final p = profile!;
    final w = item.values[p.weightKey];
    final cat = app.pb.catalog.categories().firstWhere((c) => c.id == item.categoryId);
    final est = app.pb.genericEstimator(cat.code);
    final wf = est.weightFactor(item.values);
    return Tooltip(
      message: 'وزن خالی/ساخت از دیتاشیت سازنده. برای ثبت، «ویرایش» را بزنید (گروه مشخصات کلیدی).\n'
          'ضریب وزن = (وزن ÷ ${p.driver.labelFa} ÷ میانه‌ی همین نسبت در رده)^${faSmart(est.weightExp)}؛ '
          'تا وزن این قلم و دست‌کم دو قلم رده ثبت نشده، بی‌اثر (۱) است.',
      child: KpiTile(
        label: 'وزن خالی',
        value: w is num ? '${faSmart(w)} kg' : 'ثبت نشده',
        sub: w is! num
            ? 'اختیاری · فعلاً بی‌اثر در محاسبه'
            : (wf == null ? 'ضریب وزن هنوز فعال نیست (مرجع رده کافی نیست)' : 'ضریب وزن × ${faSmart(wf)}'),
        icon: Icons.scale_rounded,
        color: w is num ? AppColors.teal : Theme.of(context).colorScheme.outline,
        width: 230,
      ),
    );
  }
}

class _PricesTab extends StatelessWidget {
  const _PricesTab({required this.item, required this.engine, required this.canEdit});
  final ItemRecord item;
  final GenericEngine engine;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final unit = app.unit;
    if (item.observations.isEmpty) {
      return const EmptyState(icon: Icons.request_quote_outlined, title: 'برای این قلم قیمتی ثبت نشده است');
    }
    final head = TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.strong);
    Widget c(Widget w, {int flex = 1}) => Expanded(flex: flex, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: w));
    return ListView(padding: const EdgeInsets.all(20), children: [
      const HelpPanel(
        id: 'generic_prices',
        title: 'قیمت‌ها و استعلام‌ها',
        initiallyOpen: false,
        lines: [
          'هر ردیف یک قیمت است: قیمت مبنای مشاور، استعلام هر فروشنده یا قیمت بازنگری قبلی. هرکدام جداگانه به سال هدف تعدیل شده‌اند.',
          'ستاره = قیمت مبنا (اصلی) که در فهرست و جمع‌ها استفاده می‌شود. با «مبنا شود» می‌توانید قیمت دیگری را مبنا کنید.',
          'مقایسه‌ی «قیمت بازنگری قبلی تعدیل‌شده» با استعلام‌های جدید، دقت روش تعدیل را برای همین قلم نشان می‌دهد.',
        ],
      ),
      SectionCard(
        title: 'همه‌ی قیمت‌ها',
        icon: Icons.request_quote_outlined,
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            color: AppColors.headerBg,
            child: Row(children: [
              const SizedBox(width: 30),
              c(Text('نوع', style: head)),
              c(Text('منبع / فروشنده', style: head), flex: 3),
              c(Text('تاریخ', style: head)),
              c(Text('قیمت منبع', style: head), flex: 2),
              c(Text('یورو (سال منبع)', style: head), flex: 2),
              c(Text('یورو تعدیل‌شده', style: head), flex: 2),
              c(Text('${unitLabel(unit)} تعدیل‌شده', style: head), flex: 2),
              const SizedBox(width: 96),
            ]),
          ),
          for (var i = 0; i < item.observations.length; i++)
            Builder(builder: (context) {
              final o = item.observations[i];
              final r = engine.calculate(PriceBank.genericInputFor(o));
              final isP = o.isPrimary;
              final kind = switch (o.kind) {
                'quote' => ('استعلام', AppColors.teal),
                'estimate' => ((o.notes ?? '').contains('قبلی') ? 'بازنگری قبلی' : 'برآورد مشاور', AppColors.petrol),
                'contract' => ('قرارداد', Tones.good(context)),
                _ => (o.kind, t.colorScheme.outline),
              };
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isP ? AppColors.amberSoft : (i.isOdd ? AppColors.zebra : null),
                  border: Border(bottom: BorderSide(color: t.colorScheme.outlineVariant)),
                ),
                child: Row(children: [
                  SizedBox(
                    width: 30,
                    child: isP
                        ? const Tooltip(message: 'قیمت مبنا', child: Icon(Icons.star_rounded, color: AppColors.amber, size: 20))
                        : null,
                  ),
                  c(Align(alignment: AlignmentDirectional.centerStart, child: Pill(kind.$1, color: kind.$2))),
                  c(
                    Tooltip(
                      message: [o.sourceDisplay, if ((o.notes ?? '').isNotEmpty) o.notes!].join('\n'),
                      child: Text(o.vendorName ?? o.sourceDisplay,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                    ),
                    flex: 3,
                  ),
                  c(Text(
                      o.costYear == null
                          ? (o.costYearText ?? '—')
                          : fa('${o.costYear}${o.costMonth == null ? '' : '/${o.costMonth.toString().padLeft(2, '0')}'}'),
                      style: const TextStyle(fontSize: 12.5))),
                  c(
                    Row(children: [
                      Flexible(
                        child: Text(o.amount == null ? (o.amountText ?? '—') : faNum(o.amount),
                            overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                      ),
                      const SizedBox(width: 4),
                      if (o.currency != null)
                        Text(CurrencyBadge.faOf(o.currency!),
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: CurrencyBadge.colorOf(o.currency!))),
                    ]),
                    flex: 2,
                  ),
                  c(Text(r.eurSource.isNumber ? faNum(r.eurSource.number) : '—', style: const TextStyle(fontSize: 12.5)), flex: 2),
                  c(
                    Text(r.eurTarget.isNumber ? faNum(r.eurTarget.number) : '—',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.eur)),
                    flex: 2,
                  ),
                  c(
                    Text(r.irrTarget.isNumber ? money(r.irrTarget.number, unit, compact: true, withUnit: false) : '—',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.irr)),
                    flex: 2,
                  ),
                  SizedBox(
                    width: 96,
                    child: isP || !canEdit
                        ? null
                        : TextButton(
                            onPressed: () => _makePrimary(context, o),
                            child: const Text('مبنا شود'),
                          ),
                  ),
                ]),
              );
            }),
        ]),
      ),
    ]);
  }

  Future<void> _makePrimary(BuildContext context, PriceObs o) async {
    final reason = await askReason(context,
        title: 'تغییر قیمت مبنا', summary: '${o.vendorName ?? o.sourceDisplay}: ${faNum(o.amount)} ${o.currency ?? ''}');
    if (reason == null || !context.mounted) return;
    final app = AppScope.read(context);
    app.pb.items.setPrimary(item.id, o.id, reason: reason.isEmpty ? null : reason);
    app.dataChanged();
  }
}

class _CalcTab extends StatelessWidget {
  const _CalcTab({required this.result, this.des});
  final GenericCalcResult result;
  final DesalterCalc? des;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final d = des;
    return ListView(padding: const EdgeInsets.all(20), children: [
      if (d != null) ...[
        _DesalterCalcCard(d: d),
        const SizedBox(height: 14),
      ],
      SectionCard(
        title: 'محاسبه‌ی گام‌به‌گام قیمت مبنا',
        subtitle: 'روش ${result.methodCode}',
        icon: Icons.stairs_outlined,
        child: Column(children: [
          for (var i = 0; i < result.steps.length; i++) _StepRow(n: i + 1, step: result.steps[i]),
          if (result.steps.isEmpty) Text('—', style: t.textTheme.bodySmall),
        ]),
      ),
    ]);
  }
}

/// محاسبات بانک دیسالتر یک قلم (هم‌نام ستون‌های فرمولی بانک Desalters v8)
class _DesalterCalcCard extends StatelessWidget {
  const _DesalterCalcCard({required this.d});
  final DesalterCalc d;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    String n(double? v, [String unit = '']) => v == null ? '—' : '${faSmart(v)}${unit.isEmpty ? '' : ' $unit'}';
    String f((String?, double)? x) => x == null ? '—' : '× ${faSmart(x.$2)}${x.$1 == null ? ' (خالی)' : ' («${x.$1}»)'}';
    final p = d.factors.parts;
    final bank = d.bank;
    final rows = <(String, String)>[
      ('حجم هر وسل (π/4 × ID² × T/T)', n(d.volumePerVessel, 'm³')),
      ('حجم کل پوسته (× تعداد وسل)', n(d.totalVolume, 'm³')),
      ('ظرفیت کل پکیج', n(d.bpd, 'BPD')),
      ('استانداردها', d.standards),
      ('kVA نصب‌شده / توان لازم', '${n(d.installedKva)} / ${n(d.demandKva)}'),
      ('ضریب فناوری TECH_F', f(p['TECH'])),
      ('ضریب متریال MAT_F', f(p['MAT'])),
      ('ضریب NACE_F', f(p['NACE'])),
      ('ضریب Scope (حاصل‌ضرب ۵ ضریب)', '× ${faSmart(d.factors.scope)}'),
      ('ضریب محرک kVA', '× ${faSmart(d.factors.kvaF)}'),
      ('ALL_F (کل پیکربندی)', '× ${faSmart(d.factors.all)}'),
      ('STAGE_F (فقط روش A)', f(p['STAGE'])),
      ('یورو سال منبع', n(d.eurSource, '€')),
      ('یورو نرمال‌شده (سال منبع ÷ ALL_F)', n(d.normEurSource, '€')),
      ('شاخص پایه / هدف', '${n(d.indexBase)} / ${n(d.indexTarget)}'),
      ('یورو نرمال‌شده‌ی تعدیل‌شده', n(d.normEsc, '€')),
      ('Coef A = NormEsc ÷ STAGE_F ÷ BPD^n', '${n(d.coefA)}${bank == null ? '' : '  (n = ${faSmart(bank.nA)})'}'),
      ('Coef B = NormEsc ÷ m³^n', '${n(d.coefB)}${bank == null ? '' : '  (n = ${faSmart(bank.nB)})'}'),
    ];
    return SectionCard(
      title: 'محاسبات بانک دیسالتر',
      subtitle: 'نرمال‌سازی به پیکربندی پایه و ضریب هزینه‌ی روش‌های تخمین A و B',
      icon: Icons.calculate_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            color: i.isOdd ? AppColors.zebra : null,
            child: Row(children: [
              Expanded(child: Text(rows[i].$1, style: t.textTheme.bodySmall)),
              Text(fa(rows[i].$2), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
            ]),
          ),
        if (d.qaFlag.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('کنترل کیفیت: ${d.qaFlag}', style: TextStyle(color: Tones.warn(context), fontSize: 12.5)),
          ),
      ]),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.n, required this.step});
  final int n;
  final CalcStep step;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = step.warning ? Tones.warn(context) : t.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.withValues(alpha: 0.14), shape: BoxShape.circle),
          child: Text(fa(n), style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(step.title, style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(fa(step.detail), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.7)),
          ]),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
          child: Text(fa(step.result), style: TextStyle(fontWeight: FontWeight.w700, color: c)),
        ),
      ]),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.entries, required this.fields});
  final List<AuditEntry> entries;
  final List<FieldDef> fields;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final labels = {for (final f in fields) f.key: f.labelFa};
    if (entries.isEmpty) return const EmptyState(icon: Icons.history_rounded, title: 'هنوز تغییری ثبت نشده');
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = entries[i];
        final field = e.field == '*' ? 'ایجاد رکورد' : (labels[e.field] ?? e.field ?? '');
        return ListTile(
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: t.colorScheme.primaryContainer,
            child: Icon(e.field == '*' ? Icons.add_rounded : Icons.edit_rounded, size: 16),
          ),
          title: Text(field, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (e.field != '*')
              Text('${e.oldValue ?? '(خالی)'}  ←  ${e.newValue ?? '(خالی)'}'),
            if (e.reason != null && e.reason!.isNotEmpty) Text('دلیل: ${e.reason}'),
          ]),
          trailing: Text(shortTs(e.ts), style: t.textTheme.labelSmall),
        );
      },
    );
  }
}
