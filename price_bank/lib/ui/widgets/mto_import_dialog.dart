// ورود فایل MTO: انتخاب فایل ← پیش‌نمایش (پروژه، شیت‌ها و رده‌ها، اقلام و استعلام‌ها، هشدارها) ← ورود ← گزارش.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_state.dart';
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
  if (!a.supported) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.info_outline_rounded, color: Tones.warn(ctx), size: 40),
        title: const Text('قالب این فایل هنوز پشتیبانی نمی‌شود'),
        content: const SizedBox(
          width: 520,
          child: Text(
            'در این نسخه، قالب «MTO کاری مشاور با بلوک‌های استعلام» (مانند MTO پازنان ۲) خوانده می‌شود: '
            'ستون‌های Item No. / Description / Qty. و بلوک‌های «استعلام ۱، ۲، …».\n'
            'قالب‌های گزارش چاپی (مانند KPL) و PEP کارفرما (مانند گچساران ۴) در مرحله‌ی بعد اضافه می‌شوند.',
            style: TextStyle(height: 1.9),
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('بسیار خوب'))],
      ),
    );
    return;
  }
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
  final _oldYear = TextEditingController(text: '${MtoImporter.defaultOldYear}');
  final _oldMonth = TextEditingController(text: '${MtoImporter.defaultOldMonth}');
  final _oldFx = TextEditingController(text: '${MtoImporter.defaultOldFx}');
  bool _busy = false;
  MtoImportReport? _report;

  @override
  void dispose() {
    for (final c in [_project, _oldYear, _oldMonth, _oldFx]) {
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
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    MtoImportReport rep;
    try {
      rep = app.pb.mtoImporter().run(
            a,
            projectName: _project.text.trim(),
            oldYear: int.tryParse(_oldYear.text.trim()) ?? MtoImporter.defaultOldYear,
            oldMonth: int.tryParse(_oldMonth.text.trim()),
            oldFx: parseUserNumber(_oldFx.text),
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
          ]),
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
          SectionCard(
            title: 'قیمت‌های بازنگری قبلی (ستون‌های Unit Price)',
            subtitle: 'اگر سال در عنوان ستون نیامده باشد این مقادیر استفاده می‌شوند (پازنان ۲: بهمن ۱۳۹۳، نرخ تسعیر ۴۰٬۵۳۰٫۸)',
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
                        Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(s.title, overflow: TextOverflow.ellipsis, style: t.textTheme.labelSmall),
                      ]),
                    ),
                    SizedBox(
                      width: 230,
                      child: DropdownButtonFormField<String?>(
                        value: leafs.any((c) => c.code == s.categoryCode) ? s.categoryCode : null,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'رده'),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('— انتخاب کنید —')),
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
              if (a.skippedSheets.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text('شیت‌های بدون قالب اقلام (خوانده نشد): ${a.skippedSheets.join('، ')}',
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ),
            ]),
          ),
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
