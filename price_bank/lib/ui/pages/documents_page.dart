import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/repo/docs_repo.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';

class DocumentsPage extends StatelessWidget {
  const DocumentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final projects = app.pb.docs.projects();
    final docs = app.pb.docs.documents();
    final canEdit = app.user.role != 'viewer';

    return ListView(padding: const EdgeInsets.all(20), children: [
      PageHeader(
        icon: Icons.folder_rounded,
        title: 'پروژه‌ها و اسناد منبع',
        subtitle: '${fa(projects.length)} پروژه · ${fa(docs.length)} سند',
      ),
      const HelpPanel(
        id: 'documents',
        title: 'چرا اسناد منبع مهم‌اند؟',
        lines: [
          'هر قیمت به سندی که از آن آمده وصل است (MTO، برآورد مشاور، استعلام، CSV).',
          '«نرخ تسعیر منبع» نرخی است که خود سند ریال را با آن از یورو ساخته (مثلاً گچساران ۴: ۴۵۵٬۶۹۲؛ پازنان ۹۳: ۴۰٬۵۳۱). با ثبت آن، همه‌ی قیمت‌های ریالی آن سند با همین نرخ به یورو برمی‌گردند — قاعده‌ی طلایی روش M6.',
          'اگر بعداً معلوم شد سال قیمت یک سند اشتباه بوده، با «اصلاح سال قیمت همه‌ی اقلام» یک‌جا اصلاح کنید؛ هر قلم جداگانه در تاریخچه ثبت می‌شود.',
          'ویرایش سند بلافاصله روی محاسبه‌ی همه‌ی اقلام آن اثر می‌گذارد.',
        ],
      ),
      SectionCard(
        title: 'پروژه‌ها',
        icon: Icons.factory_outlined,
        padding: EdgeInsets.zero,
        child: Table(
          columnWidths: const {0: FlexColumnWidth(3), 1: FixedColumnWidth(90), 2: FixedColumnWidth(150), 3: FlexColumnWidth(2), 4: FixedColumnWidth(104)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFFE3EFF2)),
              children: [for (final h in ['نام پروژه', 'اقلام', 'ظرفیت (بشکه/روز)', 'محل', '']) _c(h, b: true)],
            ),
            for (final p in projects)
              TableRow(children: [
                _c(p.nameFa == null ? p.name : '${p.nameFa} — ${p.name}', b: true),
                _c(fa(p.itemCount)),
                _c(p.capacityBpd == null ? '—' : faNum(p.capacityBpd)),
                _c(p.location ?? '—'),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (canEdit)
                    IconButton(
                        tooltip: 'ویرایش پروژه',
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _editProject(context, p)),
                  if (app.user.isAdmin)
                    IconButton(
                      tooltip: 'حذف پروژه',
                      icon: Icon(Icons.delete_outline_rounded, size: 19, color: Tones.bad(context)),
                      onPressed: () => _deleteProject(context, p),
                    ),
                ]),
              ]),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SectionCard(
        title: 'اسناد منبع',
        icon: Icons.description_outlined,
        padding: EdgeInsets.zero,
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(2), 1: FlexColumnWidth(3.5), 2: FixedColumnWidth(80), 3: FixedColumnWidth(90),
            4: FixedColumnWidth(150), 5: FixedColumnWidth(70), 6: FixedColumnWidth(100),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFFE3EFF2)),
              children: [for (final h in ['پروژه', 'عنوان سند', 'بازنگری', 'سال صدور', 'نرخ تسعیر منبع', 'قیمت‌ها', '']) _c(h, b: true)],
            ),
            for (final d in docs)
              TableRow(children: [
                _c(d.projectName ?? '—'),
                _c(d.title, b: true),
                _c(d.revision.isEmpty ? '—' : d.revision),
                _c(d.issueYear == null ? '—' : fa(d.issueYear)),
                _c(d.sourceFxEur == null ? 'جدول نرخ ارز' : '${faNum(d.sourceFxEur)} ریال/یورو'),
                _c(fa(d.priceCount)),
                canEdit
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(tooltip: 'ویرایش سند', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _editDoc(context, d)),
                        IconButton(
                          tooltip: 'اصلاح سال قیمت همه‌ی اقلام این سند',
                          icon: const Icon(Icons.event_repeat_rounded, size: 18),
                          onPressed: () => _bulkYear(context, d),
                        ),
                      ])
                    : const SizedBox(),
              ]),
          ],
        ),
      ),
    ]);
  }

  static Widget _c(String s, {bool b = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Text(s, maxLines: 2, overflow: TextOverflow.ellipsis, textDirection: dirOf(s),
            style: TextStyle(fontSize: 13, fontWeight: b ? FontWeight.w600 : null)),
      );

  Future<void> _editProject(BuildContext context, Project p) async {
    final values = await _formDialog(context, 'ویرایش پروژه', DocsRepo.projectFields, {
      'name': p.name, 'name_fa': p.nameFa, 'capacity_bpd': p.capacityBpd, 'location': p.location, 'notes': p.notes,
    }, numeric: const {'capacity_bpd'});
    if (values == null || !context.mounted) return;
    final reason = await askReason(context);
    if (reason == null || !context.mounted) return;
    final app = AppScope.read(context);
    app.pb.docs.updateProject(p.id, values, reason: reason);
    app.dataChanged();
  }

  Future<void> _deleteProject(BuildContext context, Project p) async {
    final app = AppScope.read(context);
    final nDocs = app.pb.docs.documents(projectId: p.id).length;
    final ok = await showDialog<String>(context: context, builder: (ctx) => _DeleteProjectDialog(project: p, docCount: nDocs));
    if (ok == null || !context.mounted) return;
    // پشتیبان خودکار پیش از حذف
    String? backup;
    try {
      final dbPath = app.pb.db.path;
      if (dbPath != ':memory:') {
        final dir = Directory('${File(dbPath).parent.path}${Platform.pathSeparator}backups')..createSync(recursive: true);
        final n = DateTime.now();
        String two(int v) => v.toString().padLeft(2, '0');
        backup = '${dir.path}${Platform.pathSeparator}before_delete_project_${p.id}_'
            '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}${two(n.second)}.db';
        app.pb.db.backupTo(backup);
      }
    } catch (e) {
      if (context.mounted) showSnack(context, 'پشتیبان‌گیری ناموفق بود؛ حذف انجام نشد: $e', error: true);
      return;
    }
    final res = app.pb.docs.deleteProject(p.id, reason: ok.isEmpty ? 'حذف پروژه' : ok);
    app.dataChanged(calcInputs: true);
    if (context.mounted) {
      showSnack(context,
          'پروژه حذف شد (${fa(res.items)} قلم، ${fa(res.documents)} سند).${backup == null ? '' : ' پشتیبان پیش از حذف: $backup'}');
    }
  }

  Future<void> _editDoc(BuildContext context, SourceDocument d) async {
    final values = await _formDialog(context, 'ویرایش سند منبع', DocsRepo.documentFields, {
      'title': d.title, 'doc_ref': d.docRef, 'revision': d.revision, 'doc_type': d.docType, 'issue_year': d.issueYear,
      'issue_month': d.issueMonth, 'source_fx_eur': d.sourceFxEur, 'source_fx_usd': d.sourceFxUsd,
      'fx_rate_type': d.fxRateType, 'consultant': d.consultant, 'notes': d.notes,
    }, numeric: const {'issue_year', 'issue_month', 'source_fx_eur', 'source_fx_usd'});
    if (values == null || !context.mounted) return;
    final reason = await askReason(context, summary: 'تغییر نرخ تسعیر یا سال، محاسبه‌ی همه‌ی اقلام این سند را عوض می‌کند.');
    if (reason == null || !context.mounted) return;
    final app = AppScope.read(context);
    for (final k in ['issue_year', 'issue_month']) {
      if (values[k] is double) values[k] = (values[k]! as double).toInt();
    }
    app.pb.docs.updateDocument(d.id, values, reason: reason);
    app.dataChanged(calcInputs: true);
    showSnack(context, 'سند به‌روز شد و ${fa(d.priceCount)} قیمت دوباره محاسبه شد.');
  }

  Future<void> _bulkYear(BuildContext context, SourceDocument d) async {
    final y = TextEditingController(), m = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اصلاح سال قیمت همه‌ی اقلام سند'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('سند: ${d.title}\nتعداد قیمت‌ها: ${fa(d.priceCount)}', style: const TextStyle(height: 1.8)),
            const SizedBox(height: 12),
            TextField(controller: y, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'سال قیمت (شمسی)')),
            const SizedBox(height: 10),
            TextField(controller: m, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'ماه (اختیاری)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('اعمال')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final year = parseUserNumber(y.text)?.toInt();
    final month = parseUserNumber(m.text)?.toInt();
    if (year == null || year < 1350 || year > 1450 || (month != null && (month < 1 || month > 12))) {
      showSnack(context, 'سال (۱۳۵۰ تا ۱۴۵۰) و ماه (۱ تا ۱۲) را درست وارد کنید.', error: true);
      return;
    }
    final reason = await askReason(context, title: 'دلیل اصلاح سال');
    if (reason == null || !context.mounted) return;
    final app = AppScope.read(context);
    final n = app.pb.docs.setCostYearForDocument(d.id, year, month: month, reason: reason.isEmpty ? null : reason);
    app.dataChanged(calcInputs: true);
    showSnack(context, 'سال ${fa(n)} قیمت اصلاح شد.');
  }

  static Future<Map<String, Object?>?> _formDialog(
    BuildContext context,
    String title,
    Map<String, String> labels,
    Map<String, Object?> initial, {
    Set<String> numeric = const {},
  }) {
    final ctls = {
      for (final k in labels.keys)
        k: TextEditingController(
          text: initial[k] == null
              ? ''
              : (initial[k] is double && (initial[k]! as double) == (initial[k]! as double).roundToDouble()
                  ? (initial[k]! as double).toStringAsFixed(0)
                  : initial[k].toString()),
        ),
    };
    return showDialog<Map<String, Object?>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final e in labels.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: ctls[e.key],
                    textDirection: numeric.contains(e.key) ? TextDirection.ltr : null,
                    maxLines: e.key == 'notes' ? 3 : 1,
                    decoration: InputDecoration(labelText: e.value),
                  ),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(
            onPressed: () {
              final out = <String, Object?>{};
              for (final e in ctls.entries) {
                final txt = e.value.text.trim();
                out[e.key] = numeric.contains(e.key) ? (txt.isEmpty ? null : parseUserNumber(txt)) : (txt.isEmpty ? null : txt);
              }
              Navigator.pop(ctx, out);
            },
            child: const Text('ادامه'),
          ),
        ],
      ),
    );
  }
}


/// تأیید حذف پروژه: نمایش اثر حذف + تایپ کلمه‌ی «حذف» + دلیل.
class _DeleteProjectDialog extends StatefulWidget {
  const _DeleteProjectDialog({required this.project, required this.docCount});
  final Project project;
  final int docCount;

  @override
  State<_DeleteProjectDialog> createState() => _DeleteProjectDialogState();
}

class _DeleteProjectDialogState extends State<_DeleteProjectDialog> {
  final _confirm = TextEditingController();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _confirm.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = widget.project;
    final ready = _confirm.text.trim() == 'حذف';
    return AlertDialog(
      icon: Icon(Icons.delete_forever_rounded, color: Tones.bad(context), size: 40),
      title: Text('حذف پروژه «${p.nameFa ?? p.name}»'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Tones.bad(context).withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Tones.bad(context).withValues(alpha: 0.3)),
            ),
            child: Text(
              'با حذف این پروژه، ${fa(p.itemCount)} قلم (با همه‌ی مشخصات، قیمت‌ها و استعلام‌ها) و ${fa(widget.docCount)} سند منبع آن حذف می‌شوند.\n'
              'پیش از حذف، یک نسخه‌ی پشتیبان کامل از دیتابیس به طور خودکار در پوشه‌ی backups کنار دیتابیس ذخیره می‌شود و حذف در تاریخچه ثبت می‌شود.',
              style: t.textTheme.bodySmall?.copyWith(height: 1.9),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'دلیل حذف (اختیاری)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _confirm,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'برای تأیید، کلمه‌ی «حذف» را بنویسید'),
            onChanged: (_) => setState(() {}),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Tones.bad(context)),
          onPressed: ready ? () => Navigator.pop(context, _reason.text.trim()) : null,
          icon: const Icon(Icons.delete_rounded),
          label: const Text('حذف پروژه'),
        ),
      ],
    );
  }
}
