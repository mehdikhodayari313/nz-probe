import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/mto/mto_scan.dart';
import '../probe/checks.dart';
import '../probe/probe_controller.dart';
import 'theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _c = ProbeController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _c.runAll());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  Future<void> _pickExcel() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        dialogTitle: 'انتخاب فایل‌های MTO یا برآورد',
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xlsm'],
        allowMultiple: true,
      );
      final paths = res?.paths.whereType<String>().toList() ?? const <String>[];
      if (paths.isEmpty) return;
      await _c.scanFiles(paths);
    } catch (e) {
      _toast('انتخاب فایل ناموفق بود: $e');
    }
  }

  Future<void> _copyReport() async {
    await Clipboard.setData(ClipboardData(text: _c.buildReport()));
    _toast('گزارش کپی شد');
  }

  Future<void> _saveReport() async {
    // BOM در ابتدای فایل تا Notepad نسخه‌های قدیمی هم فارسی را درست نشان دهد.
    final content = '﻿${_c.buildReport()}';
    try {
      String? path;
      if (_isDesktop) {
        path = await FilePicker.platform.saveFile(
          dialogTitle: 'ذخیره‌ی گزارش',
          fileName: 'nz_probe_report.txt',
          type: FileType.custom,
          allowedExtensions: const ['txt'],
        );
        if (path == null) return;
      } else {
        final dir = await getApplicationDocumentsDirectory();
        path = '${dir.path}${Platform.pathSeparator}nz_probe_report.txt';
      }
      await File(path).writeAsBytes(utf8.encode(content), flush: true);
      _toast('گزارش ذخیره شد: $path');
    } catch (e) {
      _toast('ذخیره ناموفق بود: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _c,
          builder: (context, _) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 940),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                children: [
                  _Header(
                    controller: _c,
                    onRerun: _c.running ? null : _c.runAll,
                    onCopy: _copyReport,
                    onSave: _saveReport,
                  ),
                  const SizedBox(height: 16),
                  _FontCheckCard(controller: _c),
                  const SizedBox(height: 16),
                  const _SectionTitle(
                    icon: Icons.fact_check_outlined,
                    title: 'آزمون‌های خودکار',
                    subtitle: 'بدون نیاز به کاری از طرف شما اجرا می‌شوند',
                  ),
                  for (final c in _c.checks) _CheckTile(check: c),
                  const SizedBox(height: 20),
                  _SectionTitle(
                    icon: Icons.table_view_outlined,
                    title: 'آزمون با فایل‌های واقعی اکسل',
                    subtitle: 'یک یا چند فایل MTO یا برآورد را انتخاب کنید؛ فقط خوانده می‌شوند و تغییری نمی‌کنند',
                    trailing: FilledButton.icon(
                      onPressed: _c.scanningFiles ? null : _pickExcel,
                      icon: _c.scanningFiles
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload_file_rounded),
                      label: Text(_c.scanningFiles ? 'در حال خواندن…' : 'انتخاب فایل'),
                    ),
                  ),
                  if (_c.fileReports.isEmpty)
                    const _EmptyHint(
                      text: 'هنوز فایلی انتخاب نشده. فایل‌های پازنان ۲، KPL، گچساران ۴ و مارون ۳ را امتحان کنید.',
                    ),
                  for (final r in _c.fileReports) _FileReportCard(report: r),
                  const SizedBox(height: 24),
                  const _PrivacyNote(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onRerun, required this.onCopy, required this.onSave});
  final ProbeController controller;
  final VoidCallback? onRerun;
  final VoidCallback onCopy;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = controller.overall;
    final done = controller.checks.where((c) => c.elapsed != null).length;
    final total = controller.checks.length;

    final verdict = switch (s) {
      CheckStatus.passed => 'این سیستم برای اجرای برنامه‌ی اصلی آماده است',
      CheckStatus.warning => 'قابل اجرا است؛ هشدارها را ببینید',
      CheckStatus.failed => 'مانع اجرا وجود دارد؛ گزارش را برای بررسی بفرستید',
      CheckStatus.needsUser => 'آزمون‌ها تمام شد؛ لطفاً نمایش متن فارسی را تأیید کنید',
      _ => 'در حال بررسی… (${faDigits(done)} از ${faDigits(total)})',
    };

    return _Panel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: t.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.water_drop_outlined, color: t.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('سنجش سازگاری', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      'بانک قیمت تجهیزات واحدهای نمک‌زدایی — برنامه‌ی آزمایشی نسخه‌ی ${faDigits(ProbeController.appVersion)}',
                      style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: StatusColors.bg(context, s),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                if (s == CheckStatus.running)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: StatusColors.fg(context, s)),
                  )
                else
                  Icon(StatusColors.icon(s), color: StatusColors.fg(context, s)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    verdict,
                    style: t.textTheme.titleMedium?.copyWith(color: StatusColors.fg(context, s), fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (controller.finished)
            Text(
              '${faDigits(controller.passedCount)} موفق · ${faDigits(controller.warningCount)} هشدار · '
              '${faDigits(controller.failedCount)} ناموفق',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
            )
          else
            LinearProgressIndicator(value: total == 0 ? null : done / total, borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(onPressed: onRerun, icon: const Icon(Icons.replay_rounded), label: const Text('اجرای دوباره')),
              OutlinedButton.icon(onPressed: onCopy, icon: const Icon(Icons.copy_rounded), label: const Text('کپی گزارش')),
              FilledButton.tonalIcon(onPressed: onSave, icon: const Icon(Icons.save_alt_rounded), label: const Text('ذخیره‌ی گزارش')),
            ],
          ),
        ],
      ),
    );
  }
}

class _FontCheckCard extends StatelessWidget {
  const _FontCheckCard({required this.controller});
  final ProbeController controller;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final answered = controller.fontConfirmed;
    final status = answered == null
        ? CheckStatus.needsUser
        : (answered ? CheckStatus.passed : CheckStatus.failed);

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(StatusColors.icon(status), color: StatusColors.fg(context, status)),
              const SizedBox(width: 8),
              Text('نمایش متن فارسی', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'متن زیر ترکیبی از فارسی، انگلیسی و عدد است. آیا حروف به هم چسبیده و ترتیب کلمات درست است؟',
            style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'پمپ انتقال نفت نمک‌دار P-111 A/B — دبی ۳۵۴ مترمکعب بر ساعت، هد ۳۱٫۲ متر، '
              'کلاس متریال D1 طبق API 610؛ قیمت واحد ${faNumber(55000)} یورو (مبنای 1404Q1).',
              style: t.textTheme.bodyLarge?.copyWith(height: 1.9),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => controller.confirmFont(true),
                icon: const Icon(Icons.thumb_up_alt_outlined),
                label: const Text('درست نمایش داده می‌شود'),
              ),
              OutlinedButton.icon(
                onPressed: () => controller.confirmFont(false),
                icon: const Icon(Icons.thumb_down_alt_outlined),
                label: const Text('به‌هم‌ریخته است'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({required this.check});
  final ProbeCheck check;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = check.status;
    final fg = StatusColors.fg(context, s);

    final leading = s == CheckStatus.running
        ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
        : Icon(StatusColors.icon(s), color: fg);

    final subtitle = check.summary.isEmpty ? check.description : check.summary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _Panel(
        padding: EdgeInsets.zero,
        child: Theme(
          // حذف خط‌های پیش‌فرض ExpansionTile
          data: t.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: leading,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            title: Text(check.title, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            subtitle: Text(
              subtitle,
              style: t.textTheme.bodySmall?.copyWith(
                color: check.summary.isEmpty ? t.colorScheme.onSurfaceVariant : fg,
              ),
            ),
            trailing: check.elapsed == null
                ? null
                : Text(
                    '${faNumber(check.elapsed!.inMilliseconds)} ms',
                    style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (check.details.isEmpty)
                Text('جزئیاتی ثبت نشده.', style: t.textTheme.bodySmall)
              else
                _DetailsBox(lines: check.details),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailsBox extends StatelessWidget {
  const _DetailsBox({required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: SelectableText(
                line,
                textDirection: directionOf(line),
                style: t.textTheme.bodySmall?.copyWith(height: 1.7),
              ),
            ),
        ],
      ),
    );
  }
}

class _FileReportCard extends StatelessWidget {
  const _FileReportCard({required this.report});
  final FileScanReport report;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final r = report.result;
    final failed = report.error != null;
    final status = failed
        ? CheckStatus.failed
        : (r!.format == MtoFormat.unknown ? CheckStatus.warning : CheckStatus.passed);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(StatusColors.icon(status), color: StatusColors.fg(context, status)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    report.fileName,
                    textDirection: directionOf(report.fileName),
                    style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${faNumber(report.sizeBytes / 1024)} KB · ${faNumber(report.elapsed.inMilliseconds)} ms',
                  style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (failed)
              Text(report.error!, style: t.textTheme.bodyMedium?.copyWith(color: StatusColors.fg(context, status)))
            else
              ..._resultWidgets(context, r!),
          ],
        ),
      ),
    );
  }

  List<Widget> _resultWidgets(BuildContext context, MtoScanResult r) {
    final t = Theme.of(context);
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(
            avatar: const Icon(Icons.category_outlined, size: 18),
            label: Text(r.format.title),
            visualDensity: VisualDensity.compact,
          ),
          if (r.documentRef != null)
            Chip(
              avatar: const Icon(Icons.tag_rounded, size: 18),
              label: Text(r.documentRef!, textDirection: TextDirection.ltr),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _Stat(label: 'شیت', value: faNumber(r.sheetCount), hint: 'مخفی: ${faNumber(r.hiddenSheetCount)}'),
          _Stat(label: 'شیت داده', value: faNumber(r.dataSheets.length)),
          _Stat(label: 'قلم', value: faNumber(r.items.length)),
          _Stat(label: 'مقدار قیمت', value: faNumber(r.priceValues)),
          _Stat(label: 'سلول خوانده‌شده', value: faNumber(r.cellsRead)),
          _Stat(
            label: 'ایراد',
            value: faNumber(r.issueCount),
            color: r.issueCount == 0 ? null : StatusColors.fg(context, CheckStatus.warning),
          ),
        ],
      ),
      if (r.evidence.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('دلیل تشخیص: ${r.evidence.join(' ')}',
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ],
      if (r.items.isNotEmpty || r.issues.isNotEmpty)
        Theme(
          data: t.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('نمونه‌ی اقلام و ایرادها', style: t.textTheme.labelLarge),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (r.items.isNotEmpty)
                _DetailsBox(lines: [
                  for (final i in r.items.take(12))
                    '${i.sheet} ردیف ${i.row}:  ${i.tag}  —  ${i.name}'
                        '${i.qty == null ? '' : '  (تعداد ${i.qty!.toStringAsFixed(0)})'}'
                        '  · ${i.priceCount} قیمت',
                  if (r.items.length > 12) '… و ${r.items.length - 12} قلم دیگر',
                ]),
              if (r.issues.isNotEmpty) ...[
                const SizedBox(height: 8),
                _DetailsBox(lines: [
                  for (final i in r.issues.take(30)) '[${issueLabel(i.level)}] ${i.location}: ${i.message}',
                  if (r.issueCount > 30) '… و ${r.issueCount - 30} ایراد دیگر (در گزارش ذخیره‌شده کامل‌تر است)',
                ]),
              ],
            ],
          ),
        ),
    ];
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.hint, this.color});
  final String label;
  final String value;
  final String? hint;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: t.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          Text(value, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: color)),
          if (hint != null) Text(hint!, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title, required this.subtitle, this.trailing});
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: t.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(subtitle, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return _Panel(
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: t.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant))),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, size: 18, color: t.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'این برنامه به اینترنت یا شبکه وصل نمی‌شود و هیچ داده‌ای را از این رایانه خارج نمی‌کند. '
            'فایل‌های اکسل فقط خوانده می‌شوند. فایل آزمایشی دیتابیس پس از آزمون حذف می‌شود.',
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.8),
          ),
        ),
      ],
    );
  }
}

/// قاب یکسان برای همه‌ی بخش‌ها.
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.colorScheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
