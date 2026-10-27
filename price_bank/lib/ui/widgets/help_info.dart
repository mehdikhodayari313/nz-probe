import 'package:flutter/material.dart';

import '../../core/calc/pump_engine.dart' show CalcStep;
import '../format.dart';
import '../theme.dart';

// راهنمای یکسان کل برنامه (قاعده‌ی کاربر ۱۴۰۵/۰۸/۰۶): هر ⓘ با نگه داشتن ماوس خلاصه را نشان می‌دهد و با کلیک
// پنجره‌ی توضیح کامل باز می‌کند: این بخش چیست، کِی به کار می‌آید، گام‌ها، فرمول و معنی خروجی‌ها.

/// یک بند از پنجره‌ی راهنما: عنوان، چند سطر، و (اختیاری) فرمول و نکته.
class HelpSection {
  const HelpSection(this.heading, {this.lines = const [], this.formula, this.note, this.numbered = false});
  final String heading;
  final List<String> lines;
  final String? formula;
  final String? note;

  /// سطرها به صورت گام‌های شماره‌دار نمایش داده شوند
  final bool numbered;
}

/// موضوع راهنما: عنوان، خلاصه‌ی یک‌خطی (راهنمای شناور) و بندها.
class HelpTopic {
  const HelpTopic({required this.title, required this.summary, this.sections = const [], this.icon});
  final String title;
  final String summary;
  final List<HelpSection> sections;
  final IconData? icon;

  /// راهنمای ساده‌ی یک‌بندی از یک متن (برای ⓘ کنار فیلدها)
  factory HelpTopic.text(String title, String text) =>
      HelpTopic(title: title, summary: text, sections: [HelpSection('', lines: [text])]);
}

/// علامت ⓘ: نگه داشتن ماوس = خلاصه؛ کلیک = پنجره‌ی توضیح کامل.
class InfoButton extends StatelessWidget {
  const InfoButton(this.topic, {super.key, this.size = 15, this.color});

  /// ⓘ کنار یک فیلد با متن کوتاه
  InfoButton.text(String title, String text, {Key? key, double size = 14})
      : this(HelpTopic.text(title, text), key: key, size: size);

  final HelpTopic topic;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Tooltip(
      message: '${topic.summary}\n(برای توضیح کامل کلیک کنید)',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => showHelp(context, topic),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(Icons.info_outline_rounded, size: size, color: color ?? t.colorScheme.primary.withValues(alpha: 0.85)),
        ),
      ),
    );
  }
}

/// پنجره‌ی توضیح کامل یک موضوع.
Future<void> showHelp(BuildContext context, HelpTopic topic) => showDialog<void>(
      context: context,
      builder: (ctx) => _HelpDialog(topic: topic),
    );

class _HelpDialog extends StatelessWidget {
  const _HelpDialog({required this.topic});
  final HelpTopic topic;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 760, maxHeight: (size.height - 48).clamp(300, 820).toDouble()),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // سرصفحه
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 14, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: AppColors.petrol.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
                child: Icon(topic.icon ?? Icons.menu_book_rounded, color: AppColors.petrol, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(topic.title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(topic.summary, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.8)),
                ]),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
              children: [
                for (final s in topic.sections) ...[
                  if (s.heading.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 6),
                      child: Row(children: [
                        Container(width: 4, height: 16, decoration: BoxDecoration(color: AppColors.lime, borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 8),
                        Text(s.heading, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.strong)),
                      ]),
                    ),
                  for (var i = 0; i < s.lines.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        s.numbered
                            ? Container(
                                width: 20,
                                height: 20,
                                margin: const EdgeInsetsDirectional.only(end: 8, top: 3),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: AppColors.petrol.withValues(alpha: 0.16), shape: BoxShape.circle),
                                child: Text(fa(i + 1),
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.strong)),
                              )
                            : Padding(
                                padding: const EdgeInsetsDirectional.only(end: 8, top: 9),
                                child: Container(width: 5, height: 5, decoration: BoxDecoration(color: cs.onSurfaceVariant, shape: BoxShape.circle)),
                              ),
                        Expanded(child: Text(s.lines[i], style: t.textTheme.bodyMedium?.copyWith(height: 1.9))),
                      ]),
                    ),
                  if (s.formula != null)
                    Container(
                      margin: const EdgeInsets.only(top: 2, bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: SelectableText(s.formula!,
                          style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.9, color: AppColors.strong)),
                    ),
                  if (s.note != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.amberSoft, borderRadius: BorderRadius.circular(10)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.lightbulb_outline_rounded, size: 18, color: AppColors.amberText),
                        const SizedBox(width: 8),
                        Expanded(child: Text(s.note!, style: t.textTheme.bodySmall?.copyWith(color: AppColors.amberText, height: 1.8))),
                      ]),
                    ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('متوجه شدم')),
            ),
          ),
        ]),
      ),
    );
  }
}

/// پنجره‌ی گام‌های محاسبه‌ی قیمت یک قلم بانک (همان گام‌های زبانه‌ی «محاسبه» صفحه‌ی آن قلم):
/// از قیمت منبع تا قیمت تعدیل‌شده‌ی سال هدف.
Future<void> showCalcSteps(BuildContext context, {required String title, String? subtitle, required List<CalcStep> steps}) =>
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final t = Theme.of(ctx);
        final cs = t.colorScheme;
        return AlertDialog(
          title: Row(children: [
            Icon(Icons.stairs_outlined, color: AppColors.petrol),
            const SizedBox(width: 8),
            Expanded(child: Text(title, textDirection: TextDirection.rtl)),
          ]),
          content: SizedBox(
            width: 720,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(subtitle, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.8)),
                ),
              Flexible(
                child: steps.isEmpty
                    ? const Text('برای این قلم گام محاسبه‌ای ثبت نشده است.')
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: steps.length,
                        separatorBuilder: (_, i) => Divider(height: 1, color: cs.outlineVariant),
                        itemBuilder: (_, i) {
                          final s = steps[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: s.warning ? AppColors.amberSoft : cs.primaryContainer,
                                child: Text(fa(i + 1), style: TextStyle(fontSize: 11, color: s.warning ? AppColors.amberText : null)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(s.title.replaceFirst(RegExp(r'^[0-9۰-۹]+[.)]\s*'), ''), style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                                  if (s.detail.isNotEmpty)
                                    Text(s.detail, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.7)),
                                ]),
                              ),
                              const SizedBox(width: 10),
                              Text(s.result,
                                  style: t.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w800, color: s.warning ? AppColors.amberText : AppColors.strong)),
                            ]),
                          );
                        },
                      ),
              ),
            ]),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
        );
      },
    );
