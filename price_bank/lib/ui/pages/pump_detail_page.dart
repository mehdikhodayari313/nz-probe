import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/pump_engine.dart';
import '../../core/price_bank.dart';
import '../../core/repo/audit.dart';
import '../../core/repo/catalog_repo.dart';
import '../../core/repo/items_repo.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
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
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          Text(item == null ? 'پمپ جدید' : (item.tag?.isNotEmpty == true ? item.tag! : 'پمپ'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (item != null) ...[
            const SizedBox(width: 12),
            Flexible(child: Text(item.name, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall)),
          ],
        ]),
        actions: [
          if (item != null && !_editing && canEdit) ...[
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
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _save(context, item, fields),
              icon: const Icon(Icons.save_rounded),
              label: Text(_id == null ? 'ایجاد' : 'ذخیره‌ی تغییرات${_draft.isEmpty ? '' : ' (${fa(_draft.length)})'}'),
            ),
          ],
          const SizedBox(width: 16),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.description_outlined), text: 'مشخصات'),
            Tab(icon: Icon(Icons.calculate_outlined), text: 'محاسبه‌ی قیمت'),
            Tab(icon: Icon(Icons.request_quote_outlined), text: 'قیمت‌ها و استعلام‌ها'),
            Tab(icon: Icon(Icons.history_rounded), text: 'تاریخچه'),
          ],
        ),
      ),
      body: Column(children: [
        if (item != null && result != null) _PriceStrip(item: item, result: result),
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
                ? const EmptyState(icon: Icons.calculate_outlined, title: 'پس از ایجاد پمپ، محاسبه اینجا نمایش داده می‌شود')
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
    if (context.mounted) showSnack(context, n == 0 ? 'تغییری ثبت نشد (مقادیر یکسان بودند).' : '${fa(n)} فیلد ذخیره شد.');
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

class _PriceStrip extends StatelessWidget {
  const _PriceStrip({required this.item, required this.result});
  final ItemRecord item;
  final PumpCalcResult result;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final unit = app.unit;
    final t = Theme.of(context);
    final qty = item.quantity ?? 1;
    final flags = qaFlagsFa(result.qaFlags);
    return Container(
      color: t.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        KpiTile(
          label: 'یورو تعدیل‌شده (${fa(app.settings.targetYear)})',
          value: result.eurTarget.isNumber ? faNum(result.eurTarget.number) : '—',
          sub: !result.eurTarget.isNumber
              ? calcMessageFa(result.eurTarget.text)
              : (result.floorBinding ? 'کف قیمت API 610 اعمال شد' : 'روش ${result.methodCode}'),
          icon: Icons.euro_rounded,
          color: AppColors.eur,
          width: 220,
        ),
        KpiTile(
          label: 'قیمت واحد (${unitLabel(unit)})',
          value: money(result.irrTarget.number, unit, withUnit: false),
          sub: result.eurRateTarget == null ? 'نرخ یوروی سال هدف وارد نشده' : 'نرخ یورو: ${faNum(result.eurRateTarget)} ریال',
          icon: Icons.payments_outlined,
          color: AppColors.irr,
          width: 250,
        ),
        KpiTile(
          label: 'جمع برای ${fa(faSmart(qty))} دستگاه',
          value: money(result.irrTarget.isNumber ? result.irrTarget.number! * qty : null, unit, compact: true, withUnit: false),
          sub: unitLabel(unit),
          icon: Icons.functions_rounded,
          width: 220,
        ),
        KpiTile(
          label: 'ضریب هزینه (یورو/kWⁿ)',
          value: faSmart(result.costCoef.number),
          sub: 'ضریب پیکربندی: ${faSmart(result.allF)}',
          icon: Icons.speed_rounded,
          width: 200,
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (item.projectName != null) Pill(item.projectName!, icon: Icons.folder_outlined),
            if (!item.include) Pill('خارج از جمع‌ها', color: t.colorScheme.outline),
            if (item.status != 'active') Pill('بایگانی‌شده', color: Tones.bad(context)),
            for (final f in flags) Pill(f, color: Tones.warn(context), icon: Icons.warning_amber_rounded),
            if (flags.isEmpty) Pill('داده‌ی کامل', color: Tones.good(context), icon: Icons.check_circle_outline),
          ]),
        ]),
      ]),
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
      for (final g in groups.entries) ...[
        SectionCard(
          title: g.key,
          icon: _groupIcon(g.value.first.groupKey),
          child: LayoutBuilder(builder: (context, cons) {
            final cols = cons.maxWidth > 1100 ? 3 : (cons.maxWidth > 700 ? 2 : 1);
            final w = (cons.maxWidth - (cols - 1) * 16) / cols;
            return Wrap(spacing: 16, runSpacing: 14, children: [
              for (final f in g.value)
                SizedBox(
                  width: w,
                  child: FieldTile(
                    field: f,
                    categoryId: AppScope.of(context).pb.pumpCategory.id,
                    value: draft.containsKey(f.key) ? draft[f.key] : _value(f),
                    meta: item?.meta[f.key],
                    editing: editing && f.editable,
                    changed: draft.containsKey(f.key),
                    onChanged: (v) => onChanged(f.key, v),
                  ),
                ),
            ]);
          }),
        ),
        const SizedBox(height: 14),
      ],
    ]);
  }

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
    if (item.observations.isEmpty) {
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
              _kv(t, 'سال قیمت', fa(o.costYear ?? o.costYearText ?? '—') + (o.costMonth == null ? '' : '/${fa(o.costMonth)}')),
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
    final labels = {for (final f in AppScope.of(context).pb.catalog.fields(AppScope.of(context).pb.pumpCategory.id)) f.key: f.labelFa};
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
                TextSpan(text: e.oldValue ?? '(خالی)', style: TextStyle(color: Tones.bad(context), decoration: TextDecoration.lineThrough)),
                const TextSpan(text: '  ←  '),
                TextSpan(text: e.newValue ?? '(خالی)', style: TextStyle(color: Tones.good(context), fontWeight: FontWeight.w600)),
              ])),
            if (e.reason != null && e.reason!.isNotEmpty) Text('دلیل: ${e.reason}'),
          ]),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(shortTs(e.ts), style: t.textTheme.labelSmall),
            Text(e.userName ?? '', style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ]),
        );
      },
    );
  }
}
