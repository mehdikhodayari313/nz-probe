import 'package:flutter/material.dart';

import '../theme.dart';

/// سرصفحه‌ی هر صفحه: عنوان، زیرعنوان و دکمه‌ها.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.icon, this.actions = const []});
  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: t.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: t.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              if (subtitle != null)
                Text(subtitle!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ]),
          ),
          if (actions.isNotEmpty)
            Flexible(child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: actions)),
        ],
      ),
    );
  }
}

/// قاب بخش‌ها.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.icon,
  });
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.colorScheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(children: [
                if (icon != null) ...[Icon(icon, size: 20, color: t.colorScheme.primary), const SizedBox(width: 8)],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title!, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    if (subtitle != null)
                      Text(subtitle!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  ]),
                ),
                if (trailing != null) Flexible(child: Align(alignment: AlignmentDirectional.centerEnd, child: trailing!)),
              ]),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// پنل راهنما با قابلیت جمع شدن (وضعیت هر پنل در طول اجرا حفظ می‌شود).
class HelpPanel extends StatefulWidget {
  const HelpPanel({super.key, required this.id, required this.title, required this.lines, this.initiallyOpen = true});
  final String id;
  final String title;
  final List<String> lines;
  final bool initiallyOpen;

  @override
  State<HelpPanel> createState() => _HelpPanelState();
}

class _HelpPanelState extends State<HelpPanel> {
  static final Map<String, bool> _open = {};

  bool get open => _open[widget.id] ?? widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = Tones.info(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _open[widget.id] = !open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Icon(Icons.lightbulb_outline_rounded, size: 20, color: c),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.title, style: t.textTheme.labelLarge?.copyWith(color: c, fontWeight: FontWeight.w700)),
              ),
              Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: c),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final l in widget.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 8),
                      child: Container(width: 5, height: 5, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                    ),
                    Expanded(child: Text(l, style: t.textTheme.bodySmall?.copyWith(height: 1.9))),
                  ]),
                ),
            ]),
          ),
      ]),
    );
  }
}

/// کاشی شاخص کلیدی.
class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.label, required this.value, this.sub, this.icon, this.color, this.width = 220});
  final String label;
  final String value;
  final String? sub;
  final IconData? icon;
  final Color? color;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = color ?? t.colorScheme.primary;
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.colorScheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 18, color: c), const SizedBox(width: 6)],
          Expanded(
            child: Text(label,
                style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: 6),
        Text(value, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: c)),
        if (sub != null)
          Text(sub!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

/// برچسب کوچک رنگی.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.icon, this.tooltip});
  final String text;
  final Color? color;
  final IconData? icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    final w = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 11.5, color: c, fontWeight: FontWeight.w600)),
      ]),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

/// حالت خالی با توضیح.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 52, color: t.colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: t.textTheme.titleMedium),
          if (message != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(message!,
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.8)),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

void showSnack(BuildContext context, String msg, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    width: 560,
    backgroundColor: error ? Tones.bad(context) : null,
  ));
}

/// پرسیدن دلیل تغییر (اختیاری). null = انصراف.
Future<String?> askReason(BuildContext context, {String title = 'ثبت تغییرات', String? summary}) async {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (summary != null) ...[Text(summary), const SizedBox(height: 12)],
          TextField(
            controller: ctl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'دلیل یا مرجع تغییر (اختیاری)',
              hintText: 'مثلاً: اصلاح طبق دیتاشیت، نامه‌ی شماره‌ی …',
            ),
            onSubmitted: (_) => Navigator.pop(ctx, ctl.text.trim()),
          ),
          const SizedBox(height: 8),
          Text('این توضیح همراه تغییر در تاریخچه ذخیره می‌شود.',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('ثبت')),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String message, {String ok = 'تأیید'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: 440, child: Text(message, style: const TextStyle(height: 1.8))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

/// متن با جهت خودکار (خطوط لاتین چپ‌به‌راست).
TextDirection dirOf(String s) {
  for (final ch in s.runes) {
    if (ch >= 0x0600 && ch <= 0x06FF) return TextDirection.rtl;
    if ((ch >= 0x41 && ch <= 0x5A) || (ch >= 0x61 && ch <= 0x7A)) return TextDirection.ltr;
  }
  return TextDirection.rtl;
}
