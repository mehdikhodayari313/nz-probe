// ورود فایل MTO: انتخاب فایل ← پیش‌نمایش (پروژه، شیت‌ها و رده‌ها، اقلام و استعلام‌ها، هشدارها) ← ورود ← گزارش.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/import/mto_generic.dart';
import '../../core/import/mto_importer.dart';
import '../../core/repo/catalog_repo.dart';
import '../../core/xlsx/xlsx_reader.dart';
import '../format.dart';
import '../theme.dart';
import 'common.dart';

Future<void> showMtoImportDialog(BuildContext context) async {
  final res = await FilePicker.platform.pickFiles(
    dialogTitle: 'انتخاب فایل MTO (اکسل)',
    type: FileType.custom,
    allowedExtensions: const ['xlsx', 'xlsm'],
  );
  final path = res?.files.single.path;
  if (path == null || !context.mounted) return;
  final name = res!.files.single.name;
  MtoAnalysis a;
  try {
    a = MtoImporter.analyze(XlsxWorkbook.openFile(path), fileName: name);
  } catch (e) {
    if (context.mounted) showSnack(context, 'فایل خوانده نشد: $e', error: true);
    return;
  }
  if (!context.mounted) return;
  // قالب ناشناخته هم رد نمی‌شود: پیش‌نمایش با امکان تعریف دستی سطر عنوان و نقش ستون‌ها باز می‌شود
  await showDialog<void>(context: context, builder: (_) => MtoPreviewDialog(analysis: a));
}

class MtoPreviewDialog extends StatefulWidget {
  const MtoPreviewDialog({super.key, required this.analysis});
  final MtoAnalysis analysis;

  @override
  State<MtoPreviewDialog> createState() => MtoPreviewDialogState();
}

class MtoPreviewDialogState extends State<MtoPreviewDialog> {
  late final _project = TextEditingController(text: widget.analysis.suggestedProject ?? '');
  late final bool _pazanan = widget.analysis.format == 'mto_quote_blocks';
  // مقادیر پیش‌فرض پازنان ۲ فقط برای همان قالب؛ برای قالب‌های دیگر از فایل یا خالی
  late final _oldYear = TextEditingController(
      text: _pazanan ? '${MtoImporter.defaultOldYear}' : (_detectedOldYear()?.toString() ?? ''));
  late final _oldMonth = TextEditingController(text: _pazanan ? '${MtoImporter.defaultOldMonth}' : '');
  late final _oldFx = TextEditingController(text: _pazanan ? '${MtoImporter.defaultOldFx}' : '');
  late final _goingYear = TextEditingController(text: widget.analysis.issueYear?.toString() ?? '');
  late final _goingMonth = TextEditingController(text: widget.analysis.issueMonth?.toString() ?? '');
  String? _manualSheet;
  final _manualRow = TextEditingController();

  int? _detectedOldYear() => widget.analysis.sheets.map((s) => s.oldYear).whereType<int>().firstOrNull;

  bool get _hasOld => widget.analysis.sheets.any((s) => s.items.any((i) => i.oldIrr != null || i.oldEur != null || i.oldUsd != null));
  bool get _needsGoingYear => widget.analysis.sheets.any((s) =>
      s.goingYear == null && s.items.any((i) => i.goingIrr != null || i.goingEur != null || i.goingUsd != null || i.quotes.any((q) => q.year == null)));
  bool _busy = false;
  MtoImportReport? _report;

  @override
  void dispose() {
    for (final c in [_project, _oldYear, _oldMonth, _oldFx, _goingYear, _goingMonth, _manualRow]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run() async {
    final app = AppScope.read(context);
    final a = widget.analysis;
    if (_project.text.trim().isEmpty) {
      showSnack(context, 'نام پروژه را وارد کنید.', error: true);
      return;
    }
    final oy = int.tryParse(_oldYear.text.trim());
    if (_hasOld && oy == null && a.sheets.any((s) => s.selected && s.oldYear == null)) {
      showSnack(context, 'سال قیمت‌های قدیمی را وارد کنید (در عنوان ستون نیامده است).', error: true);
      return;
    }
    final gy = int.tryParse(_goingYear.text.trim());
    if (_needsGoingYear && gy == null) {
      showSnack(context, 'سال قیمت مبنا را وارد کنید (در عنوان ستون و نام فایل نیامده است).', error: true);
      return;
    }
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    MtoImportReport rep;
    try {
      rep = app.pb.mtoImporter().run(
            a,
            projectName: _project.text.trim(),
            oldYear: oy ?? MtoImporter.defaultOldYear,
            oldMonth: int.tryParse(_oldMonth.text.trim()),
            oldFx: parseUserNumber(_oldFx.text),
            goingYear: gy,
            goingMonth: int.tryParse(_goingMonth.text.trim()),
          );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, 'ورود ناموفق: $e', error: true);
      }
      return;
    }
    app.dataChanged(calcInputs: true);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _report = rep;
    });
  }

  Future<void> _editLayout(String sheet) async {
    final a = widget.analysis;
    final l = a.layouts[sheet];
    if (l == null) return;
    final res = await showDialog<int>(context: context, builder: (_) => _LayoutDialog(layout: l));
    if (res == null || res < 0 || !mounted) return;
    if (res > 0 && res != l.headerRow) {
      // سطر عنوان عوض شد: تشخیص دوباره‌ی ستون‌ها و باز کردن دوباره‌ی همین پنجره
      setState(() => MtoImporter.relayout(a, sheet, headerRow: res));
      await _editLayout(sheet);
      return;
    }
    setState(() => MtoImporter.relayout(a, sheet));
  }

  Widget _reportDialog(BuildContext ctx, MtoImportReport rep) {
    final cats = {for (final c in AppScope.of(ctx).pb.catalog.categories()) c.code: c.nameFa};
    return AlertDialog(
      icon: Icon(rep.alreadyImported ? Icons.info_outline : Icons.check_circle_rounded,
          color: rep.alreadyImported ? Tones.warn(ctx) : Tones.good(ctx), size: 40),
      title: Text(rep.alreadyImported ? 'این MTO قبلاً برای همین پروژه وارد شده است' : 'ورود MTO کامل شد'),
      content: SizedBox(
        width: 480,
        child: rep.alreadyImported
            ? const Text(
                'برای جلوگیری از رکورد تکراری، ورود دوباره انجام نشد. اگر بازنگری جدیدی از MTO دارید، شماره‌ی سند آن متفاوت است و وارد می‌شود.',
                style: TextStyle(height: 1.8))
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('اقلام: ${fa(rep.items)} · استعلام‌ها: ${fa(rep.quotes)} · برآوردها: ${fa(rep.estimates)}'),
                Text('فروشندگان جدید: ${fa(rep.vendors)} · فیلدهای مشخصات جدید: ${fa(rep.specFields)}'),
                if (rep.skippedDuplicates > 0) Text('تکراری (همان تگ در همان پروژه، وارد نشد): ${fa(rep.skippedDuplicates)}'),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final e in rep.perCategory.entries) Pill('${cats[e.key] ?? e.key}: ${fa(e.value)}'),
                ]),
                for (final w in rep.warnings.take(5)) Text('⚠ $w', style: TextStyle(color: Tones.warn(ctx))),
                const SizedBox(height: 8),
                const Text('اقلام در «تجهیزات» (ستون رده‌ها) و کارت «تجهیزات به تفکیک رده» داشبورد دیده می‌شوند.',
                    style: TextStyle(fontSize: 12.5, height: 1.8)),
              ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('بسیار خوب'))],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_report != null) return _reportDialog(context, _report!);
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final a = widget.analysis;
    final all = app.pb.catalog.categories();
    final parents = {for (final c in all) c.parentId};
    final leafs = all.where((c) => c.enabled && !parents.contains(c.id)).toList();
    // تعداد اقلام موجود هر رده در بانک
    final counts = {
      for (final r in app.pb.db.query("SELECT category_id, COUNT(*) AS n FROM items WHERE status = 'active' GROUP BY category_id"))
        r['category_id'] as int: r['n'] as int,
    };
    final existing = app.pb.docs.projects().map((p) => p.name).toList();
    final exists = existing.contains(_project.text.trim());
    final selected = a.sheets.where((s) => s.selected && s.categoryCode != null).toList();

    return AlertDialog(
      title: Row(children: [
        Icon(Icons.upload_file_rounded, color: AppColors.petrol),
        const SizedBox(width: 8),
        const Expanded(child: Text('ورود MTO — پیش‌نمایش')),
      ]),
      content: SizedBox(
        width: 900,
        height: 560,
        child: ListView(children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            Pill(a.fileName, icon: Icons.description_outlined),
            if (a.docRef != null) Pill('سند: ${a.docRef}', color: AppColors.teal),
            if (a.issueYear != null) Pill('تاریخ فایل: ${fa(a.issueYear)}${a.issueMonth == null ? '' : '/${fa(a.issueMonth)}'}'),
            Pill('${fa(a.itemCount)} قلم · ${fa(a.quoteCount)} استعلام', color: Tones.good(context)),
            Pill(
              a.format == 'mto_quote_blocks'
                  ? 'قالب: MTO با بلوک‌های استعلام'
                  : (a.sheets.isEmpty ? 'قالب: ناشناخته' : 'قالب: تشخیص خودکار ستون‌ها'),
              icon: Icons.auto_fix_high_rounded,
              color: AppColors.petrol,
              tooltip: a.format == 'generic'
                  ? 'سطر عنوان و نقش ستون‌ها خودکار تشخیص داده شد؛ با دکمه‌ی «ستون‌ها» هر شیت را بررسی و اصلاح کنید.'
                  : null,
            ),
          ]),
          if (a.sheets.isEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.amberSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.amber),
              ),
              child: Text(
                'جدول اقلام به طور خودکار پیدا نشد. از کارت «تعریف دستی» پایین، شیت و شماره‌ی سطر عنوان جدول را '
                'انتخاب کنید؛ سپس نقش هر ستون (تگ، شرح، تعداد، قیمت، استعلام، …) را بررسی کنید.',
                style: TextStyle(height: 1.9, color: AppColors.amberText, fontWeight: FontWeight.w600),
              ),
            ),
          ],
          if (a.projectTitle != null) ...[
            const SizedBox(height: 8),
            Text('عنوان پروژه در فایل: ${a.projectTitle}', textDirection: TextDirection.ltr, textAlign: TextAlign.right, style: t.textTheme.bodySmall),
          ],
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: TextField(
                controller: _project,
                decoration: InputDecoration(
                  labelText: 'پروژه',
                  helperText: exists ? 'به پروژه‌ی موجود اضافه می‌شود' : 'پروژه‌ی جدید ساخته می‌شود',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final p in existing.take(8))
                  ActionChip(
                    label: Text(p, style: TextStyle(color: t.colorScheme.onSurface)),
                    onPressed: () => setState(() => _project.text = p),
                  ),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          if (_needsGoingYear || a.format == 'generic') ...[
            SectionCard(
              title: 'تاریخ قیمت مبنا و استعلام‌های بدون تاریخ',
              subtitle: 'وقتی سال در عنوان ستون قیمت یا ستون تاریخ نیامده باشد (پیش‌فرض: تاریخ نام فایل)',
              icon: Icons.event_outlined,
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                    child: TextField(
                        controller: _goingYear,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(labelText: 'سال (شمسی)'))),
                const SizedBox(width: 10),
                Expanded(
                    child: TextField(
                        controller: _goingMonth,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(labelText: 'ماه (۱ تا ۱۲، اختیاری)'))),
                const Spacer(flex: 2),
              ]),
            ),
            const SizedBox(height: 14),
          ],
          if (_hasOld)
          SectionCard(
            title: 'قیمت‌های قدیمی (بازنگری قبلی)',
            subtitle: _pazanan
                ? 'اگر سال در عنوان ستون نیامده باشد این مقادیر استفاده می‌شوند (پازنان ۲: بهمن ۱۳۹۳، نرخ تسعیر ۴۰٬۵۳۰٫۸)'
                : 'سال قیمت‌های قدیمی و نرخ تسعیر قیمت‌های ریالی آن (اگر معلوم نیست خالی بگذارید تا نرخ جدول ارز همان سال استفاده شود)',
            icon: Icons.history_edu_outlined,
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: TextField(controller: _oldYear, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'سال'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _oldMonth, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'ماه (۱ تا ۱۲)'))),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                    controller: _oldFx,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(labelText: 'نرخ تسعیر قیمت‌های ریالی (ریال/یورو)')),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'شیت‌ها و رده‌ها',
            subtitle: 'رده‌ی هر شیت را بررسی کنید؛ شیت‌های بدون تیک وارد نمی‌شوند',
            icon: Icons.table_view_outlined,
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
            child: Column(children: [
              for (final s in a.sheets)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.colorScheme.outlineVariant))),
                  child: Row(children: [
                    Checkbox(value: s.selected, onChanged: (v) => setState(() => s.selected = v ?? false)),
                    SizedBox(
                      width: 170,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Tooltip(
                          message: s.display,
                          child: Text(s.display, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        Text(s.title, overflow: TextOverflow.ellipsis, style: t.textTheme.labelSmall),
                      ]),
                    ),
                    SizedBox(
                      width: 230,
                      child: DropdownButtonFormField<String?>(itemHeight: null, 
                        value: leafs.any((c) => c.code == s.categoryCode) ? s.categoryCode : null,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'رده'),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: DdText('— انتخاب کنید —')),
                          for (final Category c in leafs)
                            DropdownMenuItem<String?>(value: c.code, child: CountedLabel(c.nameFa, counts[c.id] ?? 0)),
                        ],
                        onChanged: (v) => setState(() => s.categoryCode = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Tooltip(
                        message: s.items.map((i) => '${i.tag}: ${i.name} (${i.quotes.length} استعلام)').join('\n'),
                        child: Text(
                          '${fa(s.items.length)} قلم · ${fa(s.quoteCount)} استعلام'
                          '${s.goingLabel.isEmpty ? '' : ' · قیمت مبنا ${fa(s.goingLabel)}'}'
                          '${s.oldLabel.isEmpty ? '' : ' · قبلی ${fa(s.oldLabel)}'}',
                          style: t.textTheme.bodySmall,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'مشاهده‌ی اقلام، قیمت‌ها و مشخصات خوانده‌شده',
                      icon: const Icon(Icons.visibility_outlined, size: 20),
                      onPressed: () => showDialog<void>(context: context, builder: (_) => _ItemsPreview(sheet: s)),
                    ),
                    if (s.source != null)
                      TextButton.icon(
                        key: ValueKey('layout-${s.source}'),
                        onPressed: () => _editLayout(s.source!),
                        icon: const Icon(Icons.view_column_outlined, size: 18),
                        label: const Text('ستون‌ها'),
                      ),
                    if (s.warningCount > 0)
                      Tooltip(
                        message: s.items.expand((i) => i.warnings).take(12).join('\n'),
                        child: Pill('${fa(s.warningCount)} هشدار', color: Tones.warn(context), icon: Icons.warning_amber_rounded),
                      ),
                    if (s.categoryCode == 'PUMP')
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 6),
                        child: Tooltip(
                          message: 'پمپ‌هایی که همان تگ را در همان پروژه دارند (مثلاً از v8) دوباره وارد نمی‌شوند.',
                          child: Icon(Icons.info_outline_rounded, size: 18, color: t.colorScheme.outline),
                        ),
                      ),
                  ]),
                ),
              if (a.sheets.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('هنوز شیتی خوانده نشده است.', style: t.textTheme.bodySmall),
                ),
            ]),
          ),
          if (a.skippedSheets.isNotEmpty) ...[
            const SizedBox(height: 14),
            SectionCard(
              title: 'تعریف دستی (شیت‌هایی که خوانده نشدند)',
              subtitle: 'شیت‌های بدون جدول اقلام شناخته‌شده: ${a.skippedSheets.join('، ')}',
              icon: Icons.edit_note_rounded,
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    key: const ValueKey('manual-sheet'),
                    itemHeight: null,
                    isExpanded: true,
                    value: a.skippedSheets.contains(_manualSheet) ? _manualSheet : null,
                    decoration: const InputDecoration(labelText: 'شیت'),
                    items: [for (final n in a.skippedSheets) DropdownMenuItem(value: n, child: DdText(n))],
                    onChanged: (v) => setState(() => _manualSheet = v),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 200,
                  child: TextField(
                    key: const ValueKey('manual-row'),
                    controller: _manualRow,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(labelText: 'شماره‌ی سطر عنوان جدول', hintText: 'مثلاً 7'),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.tonalIcon(
                  key: const ValueKey('manual-read'),
                  onPressed: () {
                    final row = int.tryParse(_manualRow.text.trim());
                    final sh = _manualSheet;
                    if (sh == null || row == null || row < 1) {
                      showSnack(context, 'شیت و شماره‌ی سطر عنوان را وارد کنید.', error: true);
                      return;
                    }
                    setState(() => MtoImporter.relayout(a, sh, headerRow: row));
                    _editLayout(sh);
                  },
                  icon: const Icon(Icons.table_rows_outlined),
                  label: const Text('خواندن و تعیین ستون‌ها'),
                ),
              ]),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton.icon(
          onPressed: _busy || selected.isEmpty ? null : _run,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download_done_rounded),
          label: Text(_busy
              ? 'در حال ورود…'
              : 'ورود ${fa(selected.fold<int>(0, (s, x) => s + x.items.length))} قلم از ${fa(selected.length)} شیت'),
        ),
      ],
    );
  }
}


/// نقش ستون‌های یک شیت (تشخیص خودکار + اصلاح کاربر).
class _LayoutDialog extends StatefulWidget {
  const _LayoutDialog({required this.layout});
  final MtoLayout layout;

  @override
  State<_LayoutDialog> createState() => _LayoutDialogState();
}

class _LayoutDialogState extends State<_LayoutDialog> {
  late final _hdr = TextEditingController(text: '${widget.layout.headerRow}');
  final Map<int, TextEditingController> _years = {};

  @override
  void dispose() {
    _hdr.dispose();
    for (final c in _years.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _y(MtoColumn c) => _years[c.col] ??= TextEditingController(text: c.year?.toString() ?? '');

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final l = widget.layout;
    final head = t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.strong);
    return AlertDialog(
      title: Row(children: [
        Icon(Icons.view_column_outlined, color: AppColors.petrol),
        const SizedBox(width: 8),
        Expanded(child: Text('ستون‌های شیت «${l.sheet}»')),
      ]),
      content: SizedBox(
        width: 940,
        height: 560,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            'نقش هر ستون خودکار تشخیص داده شده است؛ هرجا درست نیست اصلاح کنید. ستون‌های «مشخصه‌ی فنی» به صورت «عنوان: مقدار» '
            'در مشخصات قلم ثبت می‌شوند (فشار، ابعاد، جنس، دبی، … در فیلدهای قالب همان رده). برای ستون‌های قیمت، ارز و سال را بررسی کنید.',
            style: t.textTheme.bodySmall?.copyWith(height: 1.8),
          ),
          for (final n in l.notes)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('⚠ $n', style: TextStyle(color: Tones.warn(context), fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(
              width: 220,
              child: TextField(
                controller: _hdr,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'سطر عنوان جدول',
                  helperText: 'اقلام از سطر ${fa(l.dataStart)} خوانده می‌شوند',
                ),
              ),
            ),
            const Spacer(),
            ToggleChip(
              label: 'ستون تگ فقط شماره‌ردیف است',
              selected: l.tagIsSerial,
              onChanged: (v) => setState(() => l.tagIsSerial = v),
            ),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            color: AppColors.headerBg,
            child: Row(children: [
              SizedBox(width: 44, child: Text('ستون', style: head)),
              Expanded(flex: 3, child: Text('عنوان در فایل', style: head)),
              Expanded(flex: 2, child: Text('نمونه‌ی مقدار', style: head)),
              SizedBox(width: 190, child: Text('نقش', style: head)),
              SizedBox(width: 100, child: Text('ارز', style: head)),
              SizedBox(width: 80, child: Text('سال', style: head)),
            ]),
          ),
          Expanded(
            child: ListView(children: [
              for (var i = 0; i < l.columns.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  color: i.isOdd ? AppColors.zebra : null,
                  child: Row(children: [
                    SizedBox(width: 44, child: Text(columnName(l.columns[i].col), style: const TextStyle(fontWeight: FontWeight.w700))),
                    Expanded(
                      flex: 3,
                      child: Text(
                        '${l.columns[i].blockLabel == null ? '' : '[${l.columns[i].blockLabel}] '}${l.columns[i].header}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(l.columns[i].sample,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.labelSmall),
                    ),
                    SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<MtoColRole>(
                        key: ValueKey('role-${l.columns[i].col}'),
                        itemHeight: null,
                        isExpanded: true,
                        isDense: true,
                        value: l.columns[i].role,
                        items: [for (final r in MtoColRole.values) DropdownMenuItem(value: r, child: DdText(r.fa))],
                        onChanged: (v) => setState(() {
                          final c = l.columns[i];
                          c.role = v ?? c.role;
                          if (c.role.isPrice) c.currency ??= currencyOf('${c.header} ${c.blockLabel ?? ''}');
                        }),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 94,
                      child: !l.columns[i].role.isPrice
                          ? const SizedBox()
                          : DropdownButtonFormField<String?>(
                              itemHeight: null,
                              isExpanded: true,
                              isDense: true,
                              value: l.columns[i].currency,
                              items: const [
                                DropdownMenuItem<String?>(value: null, child: DdText('خودکار')),
                                DropdownMenuItem<String?>(value: 'IRR', child: DdText('ریال')),
                                DropdownMenuItem<String?>(value: 'EUR', child: DdText('یورو')),
                                DropdownMenuItem<String?>(value: 'USD', child: DdText('دلار')),
                              ],
                              onChanged: (v) => setState(() => l.columns[i].currency = v),
                            ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 74,
                      child: !l.columns[i].role.isPrice
                          ? const SizedBox()
                          : TextField(
                              controller: _y(l.columns[i]),
                              textDirection: TextDirection.ltr,
                              decoration: const InputDecoration(isDense: true, hintText: '—'),
                              onChanged: (v) => l.columns[i].year = int.tryParse(v.trim()),
                            ),
                    ),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, -1), child: const Text('انصراف')),
        FilledButton.icon(
          key: const ValueKey('layout-apply'),
          onPressed: () => Navigator.pop(context, int.tryParse(_hdr.text.trim()) ?? 0),
          icon: const Icon(Icons.check_rounded),
          label: const Text('اعمال و خواندن دوباره'),
        ),
      ],
    );
  }
}

/// اقلام خوانده‌شده‌ی یک شیت: تگ، نام، تعداد، قیمت‌ها، استعلام‌ها و مشخصات.
class _ItemsPreview extends StatelessWidget {
  const _ItemsPreview({required this.sheet});
  final MtoSheet sheet;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    String price(double? irr, double? eur, double? usd) => [
          if (eur != null) '${compactNum(eur)} €',
          if (usd != null) '${compactNum(usd)} \$',
          if (irr != null) '${compactNum(irr)} ریال',
        ].join(' · ');
    final head = t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.strong);
    return AlertDialog(
      title: Text('اقلام «${sheet.display}» (${fa(sheet.items.length)})'),
      content: SizedBox(
        width: 980,
        height: 560,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            color: AppColors.headerBg,
            child: Row(children: [
              SizedBox(width: 120, child: Text('تگ', style: head)),
              Expanded(flex: 3, child: Text('نام و مشخصات', style: head)),
              SizedBox(width: 50, child: Text('تعداد', style: head)),
              Expanded(flex: 2, child: Text('قیمت مبنا${sheet.goingYear == null ? '' : ' (${fa(sheet.goingYear)})'}', style: head)),
              Expanded(flex: 2, child: Text('استعلام‌ها', style: head)),
              Expanded(flex: 2, child: Text('قیمت قدیمی${sheet.oldYear == null ? '' : ' (${fa(sheet.oldYear)})'}', style: head)),
            ]),
          ),
          Expanded(
            child: ListView(children: [
              for (var i = 0; i < sheet.items.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  color: i.isOdd ? AppColors.zebra : null,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 120,
                      child: Text(sheet.items[i].tag,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.right,
                          style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.strong, fontSize: 12.5)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Tooltip(
                        message: sheet.items[i].description,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(sheet.items[i].name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          if (sheet.items[i].specs.isNotEmpty)
                            Text('${fa(sheet.items[i].specs.length)} مشخصه: ${sheet.items[i].specs.keys.take(4).join('، ')}',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.labelSmall),
                        ]),
                      ),
                    ),
                    SizedBox(width: 50, child: Text(faSmart(sheet.items[i].quantity), style: const TextStyle(fontSize: 12.5))),
                    Expanded(
                        flex: 2,
                        child: Text(price(sheet.items[i].goingIrr, sheet.items[i].goingEur, sheet.items[i].goingUsd),
                            style: const TextStyle(fontSize: 12))),
                    Expanded(
                      flex: 2,
                      child: Text(
                        sheet.items[i].quotes.isEmpty
                            ? '—'
                            : sheet.items[i].quotes
                                .map((q) => '${q.vendor}: ${compactNum(q.amount)} ${q.currency}${q.year == null ? '' : ' (${fa(q.year)})'}')
                                .join('\n'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Expanded(
                        flex: 2,
                        child: Text(price(sheet.items[i].oldIrr, sheet.items[i].oldEur, sheet.items[i].oldUsd),
                            style: const TextStyle(fontSize: 12))),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('بستن'))],
    );
  }
}
