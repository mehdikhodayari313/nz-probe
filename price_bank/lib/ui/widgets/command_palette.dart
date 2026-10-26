import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../theme.dart';
import 'data_grid.dart';

/// یک نتیجه‌ی جست‌وجوی سراسری: صفحه‌ی برنامه یا یک قلم تجهیز.
class PaletteEntry {
  const PaletteEntry(
      {required this.title, required this.icon, this.subtitle, this.tag, this.group = 'تجهیزات', this.keywords = ''});
  final String title;
  final String? subtitle;
  final String? tag;
  final IconData icon;
  final String group;
  final String keywords;
}

/// متن جست‌وجو یکسان می‌شود: ی/ک عربی، ارقام فارسی، نیم‌فاصله و حروف بزرگ.
String paletteNorm(String s) {
  const faDigits = '۰۱۲۳۴۵۶۷۸۹', arDigits = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().runes) {
    var c = String.fromCharCode(ch);
    final i = faDigits.indexOf(c), j = arDigits.indexOf(c);
    if (i >= 0) c = '$i';
    if (j >= 0) c = '$j';
    if (c == 'ي') c = 'ی';
    if (c == 'ك') c = 'ک';
    if (c == '‌') c = ' ';
    b.write(c);
  }
  return b.toString();
}

/// خانه‌ی جست‌وجوی نوار بالا: آیکن ذره‌بین، متن راهنما و نشان میان‌بر Ctrl K (الگو: Kbd Input Group، 21st.dev).
class SearchLauncher extends StatelessWidget {
  const SearchLauncher({super.key, required this.onTap, this.compact = false});
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'جست‌وجوی صفحه‌ها و تجهیزات (Ctrl+K)',
      child: Material(
        color: AppColors.isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.75),
        shape: StadiumBorder(
            side: BorderSide(color: AppColors.isDark ? Colors.white.withValues(alpha: 0.12) : cs.outlineVariant)),
        child: InkWell(
          key: const Key('global-search'),
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 38,
            width: compact ? 44 : 270,
            child: compact
                ? Icon(Icons.search_rounded, size: 19, color: cs.onSurfaceVariant)
                : Padding(
                    padding: const EdgeInsetsDirectional.only(start: 14, end: 9),
                    child: Row(children: [
                      Icon(Icons.search_rounded, size: 18, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('جست‌وجوی تجهیز، تگ یا صفحه…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      ),
                      const Kbd('K'),
                      const SizedBox(width: 3),
                      const Kbd('Ctrl'),
                    ]),
                  ),
          ),
        ),
      ),
    );
  }
}

/// نشان کلید صفحه‌کلید.
class Kbd extends StatelessWidget {
  const Kbd(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(label,
          textDirection: TextDirection.ltr,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant, height: 1.3)),
    );
  }
}

/// پنجره‌ی جست‌وجوی سراسری (الگو: Command Menu، 21st.dev): نتایج گروه‌بندی‌شده، جابه‌جایی با کلیدهای جهت،
/// Enter برای باز کردن و Esc برای بستن. خروجی: نمایه‌ی نتیجه‌ی انتخاب‌شده در [entries].
Future<int?> showCommandPalette(BuildContext context, List<PaletteEntry> entries, {String initial = ''}) {
  return showGeneralDialog<int>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'بستن',
    barrierColor: Colors.black.withValues(alpha: AppColors.isDark ? 0.55 : 0.28),
    transitionDuration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 140),
    pageBuilder: (context, a, b) => _Palette(entries: entries, initial: initial),
    transitionBuilder: (context, a, b, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(scale: Tween(begin: 0.98, end: 1.0).animate(a), child: child),
    ),
  );
}

class _Palette extends StatefulWidget {
  const _Palette({required this.entries, required this.initial});
  final List<PaletteEntry> entries;
  final String initial;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  late final TextEditingController _q = TextEditingController(text: widget.initial);
  final _scroll = ScrollController();
  int _sel = 0;
  static const _rowH = 48.0, _headH = 30.0, _maxItems = 40;

  @override
  void dispose() {
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<int> _matches() {
    final words = paletteNorm(_q.text).split(' ').where((w) => w.isNotEmpty).toList();
    final pages = <int>[], items = <int>[];
    for (var i = 0; i < widget.entries.length; i++) {
      final e = widget.entries[i];
      final hay = paletteNorm('${e.title} ${e.subtitle ?? ''} ${e.tag ?? ''} ${e.keywords}');
      if (!words.every(hay.contains)) continue;
      if (e.group == 'صفحه‌ها') {
        pages.add(i);
      } else if (words.isNotEmpty && items.length < _maxItems) {
        items.add(i);
      }
    }
    return [...pages, ...items];
  }

  void _move(int d, int n) {
    if (n == 0) return;
    setState(() => _sel = (_sel + d) % n);
    // نگه داشتن ردیف انتخاب‌شده در دید
    final res = _matches();
    var y = 0.0;
    String? g;
    for (var k = 0; k <= _sel && k < res.length; k++) {
      final eg = widget.entries[res[k]].group;
      if (eg != g) {
        y += _headH;
        g = eg;
      }
      if (k < _sel) y += _rowH;
    }
    if (_scroll.hasClients) {
      final top = _scroll.offset, h = _scroll.position.viewportDimension;
      if (y < top + _headH) _scroll.jumpTo((y - _headH).clamp(0, _scroll.position.maxScrollExtent));
      if (y + _rowH > top + h) _scroll.jumpTo((y + _rowH - h).clamp(0, _scroll.position.maxScrollExtent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final res = _matches();
    if (_sel >= res.length) _sel = res.isEmpty ? 0 : res.length - 1;
    final rows = <Widget>[];
    String? group;
    for (var k = 0; k < res.length; k++) {
      final e = widget.entries[res[k]];
      if (e.group != group) {
        group = e.group;
        rows.add(SizedBox(
          height: _headH,
          child: Align(
            alignment: AlignmentDirectional.bottomStart,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 12, bottom: 5),
              child: Text(e.group,
                  style: t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
            ),
          ),
        ));
      }
      rows.add(_Row(
          entry: e,
          selected: k == _sel,
          onTap: () => Navigator.of(context).pop(res[k]),
          onHover: () {
            if (_sel != k) setState(() => _sel = k);
          }));
    }

    return Align(
      alignment: const Alignment(0, -0.55),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
          child: Material(
            color: cs.surface,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outlineVariant)),
            clipBehavior: Clip.antiAlias,
            child: DecoratedBox(
              decoration: BoxDecoration(boxShadow: [
                BoxShadow(
                    color: const Color(0xFF2D2D53).withValues(alpha: 0.16),
                    blurRadius: 32,
                    offset: const Offset(0, 12)),
              ]),
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1, res.length),
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1, res.length),
                  const SingleActivator(LogicalKeyboardKey.enter): () {
                    if (res.isNotEmpty) Navigator.of(context).pop(res[_sel]);
                  },
                  const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
                },
                child:
                    Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SizedBox(
                    height: 54,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        Icon(Icons.search_rounded, size: 20, color: cs.onSurfaceVariant),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            key: const Key('palette-input'),
                            controller: _q,
                            autofocus: true,
                            onChanged: (_) => setState(() => _sel = 0),
                            style: t.textTheme.bodyLarge,
                            decoration: const InputDecoration(
                              hintText: 'نام، تگ، پروژه یا نام صفحه را بنویسید…',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        const Kbd('Esc'),
                      ]),
                    ),
                  ),
                  Divider(height: 1, color: cs.outlineVariant),
                  Flexible(
                    child: res.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 36),
                            child: Text('نتیجه‌ای پیدا نشد',
                                textAlign: TextAlign.center,
                                style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                          )
                        : ListView(
                            controller: _scroll,
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                            children: rows,
                          ),
                  ),
                  Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      border: Border(top: BorderSide(color: cs.outlineVariant)),
                    ),
                    child: Row(children: [
                      Icon(Icons.swap_vert_rounded, size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 5),
                      Text('جابه‌جایی', style: t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(width: 14),
                      const Kbd('Enter'),
                      const SizedBox(width: 5),
                      Text('باز کردن', style: t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                      const Spacer(),
                      Text(
                          _q.text.trim().isEmpty
                              ? 'برای یافتن تجهیز بنویسید'
                              : '${fa(res.length)} نتیجه${res.length >= _maxItems ? ' (بیشتر را با کلمه‌ی دقیق‌تر ببینید)' : ''}',
                          style: t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.selected, required this.onTap, required this.onHover});
  final PaletteEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final tag = entry.tag;
    return MouseRegion(
      onHover: (_) => onHover(),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: _PaletteState._rowH,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.sidebarActive : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: selected ? cs.surface : cs.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Icon(entry.icon, size: 16, color: selected ? AppColors.petrol : cs.onSurfaceVariant),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.35)),
                    if (entry.subtitle != null)
                      Text(entry.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35)),
                  ]),
            ),
            if (tag != null && tag.isNotEmpty && !isNotStated(tag)) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(tag,
                    textDirection: TextDirection.ltr,
                    style: t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
              ),
            ],
            if (selected) ...[
              const SizedBox(width: 6),
              Icon(Icons.keyboard_return_rounded, size: 16, color: cs.onSurfaceVariant),
            ],
          ]),
        ),
      ),
    );
  }
}
