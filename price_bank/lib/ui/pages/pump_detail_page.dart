import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/app_state.dart';
import '../../core/calc/pump_engine.dart';
import '../../core/price_bank.dart';
import '../../core/repo/audit.dart';
import '../../core/repo/catalog_repo.dart';
import '../../core/repo/items_repo.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/hero_band.dart';
import '../widgets/data_grid.dart' show gridNotStated, isNotStated;
import '../widgets/field_editor.dart';

/// جزئیات، ویرایش و محاسبه‌ی یک پمپ. itemId == null یعنی پمپ جدید.
class PumpDetailPage extends StatefulWidget {
  const PumpDetailPage({super.key, required this.itemId});
  final int? itemId;

  @override
  State<PumpDetailPage> createState() => _PumpDetailPageState();
}

class _PumpDetailPageState extends State<PumpDetailPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  int? _id;
  bool _editing = false;
  final Map<String, Object?> _draft = {};

  @override
  void initState() {
    super.initState();
    _id = widget.itemId;
    _editing = _id == null;
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pb = app.pb;
    final cat = pb.pumpCategory;
    final fields = pb.catalog.fields(cat.id);
    final item = _id == null ? null : pb.items.get(_id!);
    final engine = pb.pumpEngine();
    final result = item == null ? null : engine.calculate(PriceBank.inputFor(item));
    final canEdit = app.canEdit('MECH');

    final actions = <Widget>[
      if (item != null && !_editing && canEdit) ...[
        OutlinedButton.icon(
          onPressed: () => _archive(context, item),
          icon: Icon(item.status == 'active' ? LucideIcons.archive : LucideIcons.archiveRestore, size: 18),
          label: Text(item.status == 'active' ? 'بایگانی' : 'بازگرداندن'),
        ),
        FilledButton.icon(
          onPressed: () => setState(() {
            _draft.clear();
            _editing = true;
            _tabs.index = 0;
          }),
          icon: const Icon(LucideIcons.pencil, size: 18),
          label: const Text('ویرایش'),
        ),
      ],
      if (_editing) ...[
        TextButton(
          onPressed: () {
            if (_id == null) {
              Navigator.pop(context);
            } else {
              setState(() {
                _draft.clear();
                _editing = false;
              });
            }
          },
          child: const Text('انصراف'),
        ),
        FilledButton.icon(
          onPressed: () => _save(context, item, fields),
          icon: const Icon(LucideIcons.save, size: 18),
          label: Text(_id == null ? 'ایجاد' : 'ذخیره‌ی تغییرات${_draft.isEmpty ? '' : ' (${fa(_draft.length)})'}'),
        ),
      ],
    ];
    final tabs = TabBar(
      controller: _tabs,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: [
        heroTab(LucideIcons.fileText, 'مشخصات'),
        heroTab(LucideIcons.calculator, 'محاسبه‌ی قیمت'),
        heroTab(LucideIcons.receipt, 'قیمت‌ها و استعلام‌ها'),
        heroTab(LucideIcons.history, 'تاریخچه'),
      ],
    );
    return Scaffold(
      body: Column(children: [
        _PumpHero(item: item, result: result, actions: actions, tabs: tabs),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            _SpecTab(
              fields: fields,
              item: item,
              result: result,
              editing: _editing,
              draft: _draft,
              onChanged: (k, v) => setState(() => _draft[k] = v),
            ),
            item == null || result == null
                ? const EmptyState(
                    icon: Icons.calculate_outlined, title: 'پس از ایجاد پمپ، محاسبه اینجا نمایش داده می‌شود')
                : _CalcTab(item: item, result: result),
            item == null
                ? const EmptyState(icon: Icons.request_quote_outlined, title: 'پس از ایجاد پمپ در دسترس است')
                : _PricesTab(item: item),
            item == null
                ? const EmptyState(icon: Icons.history_rounded, title: 'تاریخچه‌ای وجود ندارد')
                : _HistoryTab(entries: pb.audit.history('item', item.id)),
          ]),
        ),
      ]),
    );
  }

  Future<void> _save(BuildContext context, ItemRecord? item, List<FieldDef> fields) async {
    final app = AppScope.read(context);
    if (item == null) {
      final name = _draft['name']?.toString().trim() ?? '';
      if (name.isEmpty) {
        showSnack(context, 'نام تجهیز / سرویس را وارد کنید.', error: true);
        return;
      }
      final reason = await askReason(context, title: 'ایجاد پمپ جدید');
      if (reason == null) return;
      final projectName = _draft['project']?.toString().trim();
      final pid = (projectName == null || projectName.isEmpty) ? null : app.pb.docs.ensureProject(projectName);
      final id = app.pb.items.create(
        categoryId: app.pb.pumpCategory.id,
        values: {'include_in_totals': 'Y', ..._draft},
        projectId: pid,
        reason: reason.isEmpty ? 'ایجاد دستی' : reason,
      );
      app.dataChanged();
      setState(() {
        _id = id;
        _editing = false;
        _draft.clear();
      });
      if (context.mounted) showSnack(context, 'پمپ جدید ثبت شد.');
      return;
    }
    if (_draft.isEmpty) {
      setState(() => _editing = false);
      return;
    }
    final labels = {for (final f in fields) f.key: f.labelFa};
    final reason = await askReason(
      context,
      summary: 'فیلدهای تغییرکرده: ${_draft.keys.map((k) => labels[k] ?? k).join('، ')}',
    );
    if (reason == null) return;
    final n = app.pb.items.update(item.id, Map.of(_draft), reason: reason.isEmpty ? null : reason);
    app.dataChanged();
    setState(() {
      _editing = false;
      _draft.clear();
    });
    if (context.mounted)
      showSnack(context, n == 0 ? 'تغییری ثبت نشد (مقادیر یکسان بودند).' : '${fa(n)} فیلد ذخیره شد.');
  }

  Future<void> _archive(BuildContext context, ItemRecord item) async {
    final archiving = item.status == 'active';
    final reason = await askReason(context,
        title: archiving ? 'بایگانی پمپ' : 'بازگرداندن پمپ',
        summary: archiving
            ? 'پمپ از فهرست و جمع‌ها کنار می‌رود ولی حذف نمی‌شود و هر زمان قابل بازگرداندن است.'
            : 'پمپ دوباره در فهرست و محاسبات قرار می‌گیرد.');
    if (reason == null || !context.mounted) return;
    final app = AppScope.read(context);
    app.pb.items.archive(item.id, archived: archiving, reason: reason);
    app.dataChanged();
    if (archiving) {
      Navigator.pop(context);
    } else {
      setState(() {});
    }
  }
}

// -----------------------------------------------------------------------------

class _PumpHero extends StatelessWidget {
  const _PumpHero({required this.item, required this.result, required this.actions, required this.tabs});
  final ItemRecord? item;
  final PumpCalcResult? result;
  final List<Widget> actions;
  final TabBar tabs;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final unit = app.unit;
    final it = item;
    final r = result;
    void back() => Navigator.maybePop(context);
    if (it == null || r == null) {
      return HeroBand(title: 'پمپ جدید', icon: LucideIcons.fuel, actions: actions, tabs: tabs, onBack: back);
    }
    final qty = it.quantity ?? 1;
    final flags = qaFlagsFa(r.qaFlags);
    String? spec(String key, String unitText) {
      final v = it.valueOf(key);
      return v is num ? '${faSmart(v)} $unitText' : null;
    }

    final sub = it.values['sub_category']?.toString();
    return HeroBand(
      onBack: back,
      tag: isNotStated(it.tag) ? gridNotStated : it.tag!,
      tagMuted: isNotStated(it.tag),
      title: it.name,
      subtitle: [
        'پمپ',
        if (sub != null && sub.isNotEmpty) sub,
        if (it.projectName != null) isNotStated(it.projectName) ? 'پروژه $gridNotStated' : it.projectName!,
      ].join('  ·  '),
      chips: [
        if (spec('capacity_m3h', 'm³/h') case final s?) HeroChip(LucideIcons.waves, 'دبی $s'),
        if (spec('diff_head_m', 'm') case final s?) HeroChip(LucideIcons.arrowUpFromLine, 'هد $s'),
        if (spec('power_kw', 'kW') case final s?) HeroChip(LucideIcons.zap, 'توان $s'),
        if (it.valueOf('material_class') case final String m when m.isNotEmpty && !isNotStated(m))
          HeroChip(LucideIcons.layers, 'متریال $m'),
      ],
      actions: actions,
      readouts: [
        HeroReadout(
          label: 'یورو تعدیل‌شده (${fa(app.settings.targetYear)})',
          number: r.eurTarget.isNumber ? r.eurTarget.number : null,
          format: (v) => faNum(v),
          unit: '€',
          sub: !r.eurTarget.isNumber
              ? calcMessageFa(r.eurTarget.text)
              : (r.floorBinding ? 'کف قیمت API 610 اعمال شد' : 'روش ${r.methodCode}'),
          primary: true,
        ),
        HeroReadout(
          label: 'قیمت واحد',
          number: r.irrTarget.number,
          format: (v) => money(v.toDouble(), unit, withUnit: false),
          unit: unitLabel(unit),
          sub: r.eurRateTarget == null ? 'نرخ یوروی سال هدف وارد نشده' : 'نرخ یورو: ${faNum(r.eurRateTarget)} ریال',
        ),
        HeroReadout(
          label: 'جمع برای ${fa(faSmart(qty))} دستگاه',
          number: r.irrTarget.isNumber ? r.irrTarget.number! * qty : null,
          format: (v) => money(v.toDouble(), unit, compact: true, withUnit: false),
          unit: unitLabel(unit),
        ),
        HeroReadout(
          label: 'ضریب هزینه (یورو/kWⁿ)',
          number: r.costCoef.number,
          format: (v) => faSmart(v),
          sub: 'ضریب پیکربندی: ${faSmart(r.allF)}',
        ),
      ],
      footer: Wrap(spacing: 6, runSpacing: 6, children: [
        if (!it.include) const HeroStatus('خارج از جمع‌ها'),
        if (it.status != 'active') HeroStatus('بایگانی‌شده', color: Tones.bad(context)),
        for (final f in flags) HeroStatus(f, icon: LucideIcons.triangleAlert, color: const Color(0xFFF6C35B)),
        if (flags.isEmpty) const HeroStatus('داده‌ی کامل', icon: LucideIcons.circleCheck, color: Color(0xFF7BE0A6)),
      ]),
      tabs: tabs,
    );
  }
}

class _SpecTab extends StatelessWidget {
  const _SpecTab({
    required this.fields,
    required this.item,
    required this.result,
    required this.editing,
    required this.draft,
    required this.onChanged,
  });
  final List<FieldDef> fields;
  final ItemRecord? item;
  final PumpCalcResult? result;
  final bool editing;
  final Map<String, Object?> draft;
  final void Function(String key, Object? value) onChanged;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<FieldDef>>{};
    for (final f in fields) {
      if (f.key == 'v8_row') continue;
      if (editing && f.storage == FieldStorage.calc) continue;
      (groups[f.groupFa] ??= []).add(f);
    }
    return ListView(padding: const EdgeInsets.all(20), children: [
      if (editing)
        const HelpPanel(
          id: 'pump_edit',
          title: 'راهنمای ویرایش',
          lines: [
            'فقط فیلدهایی که تغییر می‌دهید ذخیره می‌شوند؛ مقدار قبلی، نام شما، زمان و دلیل تغییر در تاریخچه ثبت می‌شود.',
            'فیلدهای زرد «مقدار استنباطی» هستند (در منبع صریح نبوده)؛ با وارد کردن مقدار جدید، برچسب استنباطی برداشته می‌شود.',
            'روی علامت ⓘ کنار هر فیلد، توضیح و شاهد آن را ببینید. ستون‌های محاسباتی در حالت ویرایش پنهان‌اند و خودکار حساب می‌شوند.',
            'اگر سال قیمت یا نرخ تسعیر کل یک سند اشتباه است، از صفحه‌ی «پروژه‌ها و اسناد» یک‌جا اصلاح کنید.',
          ],
        ),
      for (final (gi, g) in groups.entries.indexed) ...[
        FadeIn(
          delay: gi,
          child: SectionCard(
            title: g.key,
            icon: _groupIcon(g.value.first.groupKey),
            child: FieldGrid(
              fields: arrangeCompanions(g.value, editing: editing),
              editing: editing,
              extraOf: _extra,
              valueOf: (f) => draft.containsKey(f.key) ? draft[f.key] : _value(f),
              badges: (f) => (item?.meta[f.key]?.flag == null ? 0 : 1) + (draft.containsKey(f.key) ? 1 : 0),
              tile: (f) => FieldTile(
                field: f,
                categoryId: AppScope.of(context).pb.pumpCategory.id,
                value: draft.containsKey(f.key) ? draft[f.key] : _value(f),
                meta: item?.meta[f.key],
                editing: editing && f.editable,
                changed: draft.containsKey(f.key),
                onChanged: (v) => onChanged(f.key, v),
                extra: _extra(f),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
    ]);
  }

  String? _extra(FieldDef f) =>
      editing ? null : companionNote(f, (k) => draft.containsKey(k) ? draft[k] : item?.valueOf(k));

  Object? _value(FieldDef f) {
    if (f.storage != FieldStorage.calc) return item?.valueOf(f.key);
    final r = result;
    if (r == null) return null;
    Object? cell(CalcCell c) => c.isNumber ? c.number : (c.text == null ? null : calcMessageFa(c.text));
    return switch (f.key) {
      'size_kw' => cell(r.sizeKw),
      'standards' => r.standards,
      'eur_source' => cell(r.eurSource),
      'usd_source' => cell(r.usdSource),
      'irr_source' => cell(r.irrSource),
      'eur_target' => cell(r.eurTarget),
      'usd_target' => cell(r.usdTarget),
      'irr_target' => cell(r.irrTarget),
      'qa_flags' => qaFlagsFa(r.qaFlags).join('، '),
      'mat_f' => r.matF,
      'seal_f' => r.sealF,
      'drive_f' => r.driveF,
      'scope_f' => r.scopeF,
      'all_f' => r.allF,
      'normalized_eur' => cell(r.normalizedEur),
      'ppi_base' => cell(r.ppiBase),
      'ppi_target' => cell(r.ppiTarget),
      'floor_applies' => r.floorApplies ? 'بله' : 'خیر',
      'normalized_escalated_eur' => cell(r.normalizedEscalatedEur),
      'cost_coef' => cell(r.costCoef),
      _ => null,
    };
  }

  IconData _groupIcon(String g) => switch (g) {
        'identification' => Icons.badge_outlined,
        'key_specs' => Icons.engineering_outlined,
        'extra_specs' => Icons.add_box_outlined,
        'price' => Icons.payments_outlined,
        'source' => Icons.source_outlined,
        'scope' => Icons.checklist_rounded,
        'calc' => Icons.calculate_outlined,
        _ => Icons.fact_check_outlined,
      };
}

class _CalcTab extends StatelessWidget {
  const _CalcTab({required this.item, required this.result});
  final ItemRecord item;
  final PumpCalcResult result;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.settings;
    final fxTypes = app.pb.settingsRepo.fxRateTypes();
    final unit = app.unit;
    return ListView(padding: const EdgeInsets.all(20), children: [
      HelpPanel(
        id: 'calc_tab',
        title: 'روش محاسبه (روش فعال: ${s.escalationMethod})',
        initiallyOpen: false,
        lines: [
          'گام‌های زیر با روش فعال (${s.escalationMethod}) محاسبه شده‌اند؛ روش را در صفحه‌ی «روش‌های تعدیل» عوض کنید. شرح زیر مربوط به روش پیش‌فرض M6 است.',
          'قیمت منبع با «نرخ تسعیر همان منبع» (یا نرخ یوروی سال قیمت) به یورو برگردانده می‌شود.',
          'یورو با شاخص PPI پمپ و کمپرسور منطقه‌ی یورو (Eurostat C28.13) به سال هدف تعدیل می‌شود.',
          'برای پمپ گریز از مرکز API 610 با کلاس S یا D، حداقل ${faNum(s.floorEur)} یورو در سطح ${fa(s.floorBaseYear)} (تعدیل‌شده با همان شاخص) اعمال می‌شود.',
          'یوروی نهایی با نرخ یوروی سال هدف از نوع نرخ انتخاب‌شده («${s.fxRateType}») به ریال تبدیل می‌شود. تورم ریالی (CPI) برای پمپ استفاده نمی‌شود.',
        ],
      ),
      SectionCard(
        title: 'محاسبه‌ی گام‌به‌گام',
        subtitle: 'سال هدف ${fa(s.targetYear)} · شاخص ${s.ppiSeries} · نرخ ارز «${s.fxRateType}»',
        icon: Icons.stairs_outlined,
        child: Column(children: [
          for (var i = 0; i < result.steps.length; i++)
            _StepRow(index: i + 1, step: result.steps[i], last: i == result.steps.length - 1),
        ]),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: 'اثر انتخاب نوع نرخ ارز',
        subtitle: 'همین پمپ با هر نوع نرخ ارز (سال هدف ${fa(s.targetYear)})',
        icon: Icons.compare_arrows_rounded,
        child: Table(
          columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(2), 2: FlexColumnWidth(3)},
          children: [
            TableRow(
              decoration: BoxDecoration(color: AppColors.headerBg),
              children: [
                _cell(context, 'نوع نرخ', bold: true),
                _cell(context, 'نرخ یوروی سال هدف', bold: true),
                _cell(context, 'قیمت واحد (${unitLabel(unit)})', bold: true),
              ],
            ),
            for (final f in fxTypes)
              (() {
                final r = app.pb.pumpEngine(fxType: f.code).calculate(PriceBank.inputFor(item));
                return TableRow(children: [
                  _cell(context, f.nameFa, bold: f.code == s.fxRateType),
                  _cell(context, r.eurRateTarget == null ? 'وارد نشده' : faNum(r.eurRateTarget)),
                  _cell(context, r.irrTarget.isNumber ? money(r.irrTarget.number, unit, withUnit: false) : '—'),
                ]);
              })(),
          ],
        ),
      ),
    ]);
  }

  Widget _cell(BuildContext c, String s, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Text(s, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null, fontSize: 13)),
      );
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.index, required this.step, required this.last});
  final int index;
  final CalcStep step;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = step.warning ? Tones.warn(context) : t.colorScheme.primary;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Column(children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Text(fa(index), style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          if (!last) Expanded(child: Container(width: 2, color: t.colorScheme.outlineVariant)),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(step.title, style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(fa(step.detail),
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.7)),
                ]),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                child: Text(fa(step.result), style: TextStyle(fontWeight: FontWeight.w700, color: c)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _PricesTab extends StatelessWidget {
  const _PricesTab({required this.item});
  final ItemRecord item;

  static const _kindFa = {
    'quote': 'استعلام فروشنده',
    'estimate': 'برآورد / سند منبع',
    'contract': 'قرارداد',
    'escalated': 'تعدیل‌شده‌ی مشاور',
    'other': 'سایر',
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (item.observations.isEmpty && item.hiddenObservations.isEmpty) {
      return const EmptyState(icon: Icons.request_quote_outlined, title: 'قیمتی ثبت نشده');
    }
    return ListView(padding: const EdgeInsets.all(20), children: [
      const HelpPanel(
        id: 'prices_tab',
        title: 'قیمت‌ها و استعلام‌ها',
        initiallyOpen: false,
        lines: [
          'هر قیمت یک «مشاهده» است با نوع منبع: استعلام فروشنده، برآورد سند، قرارداد یا تعدیل‌شده‌ی مشاور.',
          'قیمت «اصلی» مبنای محاسبه‌ی بانک است؛ استعلام‌ها برای مقایسه و کالیبره کردن نگه داشته می‌شوند و هرگز پاک نمی‌شوند.',
          'قیمت‌های «تعدیل‌شده‌ی مشاور» استعلام واقعی نیستند و نباید در صحت‌سنجی روش تعدیل استفاده شوند.',
        ],
      ),
      if (item.hiddenObservations.isNotEmpty) HiddenPricesNote(item.hiddenObservations),
      for (final o in item.observations)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SectionCard(
            title: o.vendorName ?? (o.isPrimary ? 'قیمت اصلی' : _kindFa[o.kind] ?? o.kind),
            subtitle: o.sourceDisplay.isEmpty ? null : o.sourceDisplay,
            icon: o.kind == 'quote' ? Icons.storefront_outlined : Icons.description_outlined,
            trailing: Wrap(spacing: 6, children: [
              if (o.isPrimary) Pill('مبنای محاسبه', color: Tones.good(context)),
              Pill(_kindFa[o.kind] ?? o.kind),
            ]),
            child: Wrap(spacing: 28, runSpacing: 10, children: [
              _kv(t, 'مبلغ', o.amount != null ? '${faNum(o.amount)} ${o.currency ?? ''}' : (o.amountText ?? '—')),
              _kv(t, 'سال قیمت',
                  fa(o.costYear ?? o.costYearText ?? '—') + (o.costMonth == null ? '' : '/${fa(o.costMonth)}')),
              _kv(t, 'شرط تحویل', o.incoterm ?? '—'),
              if (o.priceBasis != null) _kv(t, 'مبنای قیمت', o.priceBasis!),
              if (o.effectiveSourceFx != null) _kv(t, 'نرخ تسعیر منبع', '${faNum(o.effectiveSourceFx)} ریال/یورو'),
              for (final e in o.extra.entries) _kv(t, _extraFa[e.key] ?? e.key, fa(e.value)),
              if (o.notes != null) _kv(t, 'یادداشت', o.notes!),
            ]),
          ),
        ),
    ]);
  }

  static const _extraFa = {
    'quote_id': 'شناسه‌ی استعلام',
    'quote_ref': 'مرجع / تاریخ استعلام',
    'validity_days': 'اعتبار (روز)',
    'tbe': 'تأیید فنی (TBE)',
    'delivery_weeks': 'زمان تحویل (هفته)',
    'scope_driver': 'Scope: محرک',
    'scope_baseplate': 'Scope: شاسی',
    'scope_seal_system': 'Scope: سیستم آب‌بند',
    'scope_spares': 'Scope: یدکی',
    'scope_tpi': 'Scope: بازرسی',
  };

  Widget _kv(ThemeData t, String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        Text(v, style: t.textTheme.bodyMedium),
      ]);
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.entries});
  final List<AuditEntry> entries;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final labels = {
      for (final f in AppScope.of(context).pb.catalog.fields(AppScope.of(context).pb.pumpCategory.id)) f.key: f.labelFa
    };
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
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: e.oldValue ?? '(خالی)',
                    style: TextStyle(color: Tones.bad(context), decoration: TextDecoration.lineThrough)),
                const TextSpan(text: '  ←  '),
                TextSpan(
                    text: e.newValue ?? '(خالی)',
                    style: TextStyle(color: Tones.good(context), fontWeight: FontWeight.w600)),
              ])),
            if (e.reason != null && e.reason!.isNotEmpty) Text('دلیل: ${e.reason}'),
          ]),
          trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(shortTs(e.ts), style: t.textTheme.labelSmall),
                Text(e.userName ?? '', style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ]),
        );
      },
    );
  }
}
