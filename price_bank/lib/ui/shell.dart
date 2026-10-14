import 'package:flutter/gestures.dart' show kBackMouseButton;
import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../core/calc/methods.dart';
import 'format.dart';
import 'widgets/common.dart';
import 'pages/dashboard_page.dart';
import 'pages/documents_page.dart';
import 'pages/equipment_page.dart';
import 'pages/estimator_page.dart';
import 'pages/factors_page.dart';
import 'pages/history_page.dart';
import 'pages/indices_page.dart';
import 'pages/methods_page.dart';
import 'pages/settings_page.dart';
import 'pages/users_page.dart';
import 'theme.dart';

class _Dest {
  const _Dest(this.icon, this.selectedIcon, this.label, this.builder, {this.section, this.step});
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget Function() builder;

  /// عنوان گروه که بالای این گزینه نمایش داده می‌شود
  final String? section;

  /// شماره‌ی گام «شروع کار» داشبورد
  final int? step;
}

// ترتیب منوها = ترتیب گام‌های «شروع کار» داشبورد:
// ۱ داده‌ها (داشبورد) ← ۲ شاخص‌ها و ارز ← ۳ روش تعدیل ← ۴ تجهیزات و تخمین
final _destinations = <_Dest>[
  _Dest(Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'داشبورد', () => const DashboardPage(),
      section: 'گام‌های کار', step: 1),
  _Dest(Icons.query_stats_outlined, Icons.query_stats_rounded, 'شاخص‌ها و ارز', () => const IndicesPage(), step: 2),
  _Dest(Icons.science_outlined, Icons.science_rounded, 'روش‌های تعدیل', () => const MethodsPage(), step: 3),
  _Dest(Icons.precision_manufacturing_outlined, Icons.precision_manufacturing_rounded, 'تجهیزات',
      () => const EquipmentPage(), step: 4),
  _Dest(Icons.calculate_outlined, Icons.calculate_rounded, 'تخمین و تعدیل', () => const EstimatorPage(), step: 4),
  _Dest(Icons.tune_outlined, Icons.tune_rounded, 'ضرایب', () => const FactorsPage(), section: 'داده‌های پایه'),
  _Dest(Icons.folder_open_outlined, Icons.folder_rounded, 'پروژه‌ها و اسناد', () => const DocumentsPage()),
  _Dest(Icons.history_outlined, Icons.history_rounded, 'تاریخچه', () => const HistoryPage(), section: 'مدیریت'),
  _Dest(Icons.group_outlined, Icons.group_rounded, 'کاربران', () => const UsersPage()),
  _Dest(Icons.settings_outlined, Icons.settings_rounded, 'تنظیمات', () => const SettingsPage()),
];

/// قاب اصلی: نوار کناری تیره + نوار بالا (سال هدف، جدول نرخ ارز، روش تعدیل، ریال/تومان).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  /// تغییر صفحه از داخل صفحه‌های دیگر.
  static void go(BuildContext context, int index) => context.findAncestorStateOfType<_AppShellState>()?._go(index);

  static const dashboard = 0, indices = 1, methods = 2, equipment = 3, estimator = 4, factors = 5, documents = 6,
      history = 7, users = 8, settings = 9;

  static const sidebarKey = Key('sidebar');
  static const backKey = Key('shell-back');

  @override
  State<AppShell> createState() => _AppShellState();
}

/// یک صفحه در تاریخچه‌ی پیمایش؛ [gen] نمونه‌ی صفحه را از نمونه‌ی تازه‌ی همان صفحه جدا می‌کند.
class _Visit {
  const _Visit(this.index, this.gen);
  final int index;
  final int gen;
}

class _AppShellState extends State<AppShell> {
  static const _maxHistory = 12;
  var _cur = const _Visit(0, 0);
  final List<_Visit> _history = [];
  int _gen = 0;

  /// رفتن به صفحه‌ی دیگر: صفحه‌ی فعلی (با همان حالت و جای اسکرول) در تاریخچه زنده می‌ماند.
  void _go(int i) {
    if (i == _cur.index) return;
    setState(() {
      _history.add(_cur);
      if (_history.length > _maxHistory) _history.removeAt(0);
      _cur = _Visit(i, ++_gen);
    });
  }

  /// بازگشت به صفحه‌ی قبل، دقیقاً با همان حالت (فیلترها، زبانه، جای اسکرول).
  void _back() {
    if (_history.isEmpty) return;
    setState(() => _cur = _history.removeLast());
  }

  @override
  Widget build(BuildContext context) {
    final alive = [..._history, _cur]..sort((a, b) => a.gen.compareTo(b.gen));
    final prev = _history.isEmpty ? null : _destinations[_history.last.index].label;
    return Scaffold(
      body: Listener(
        // دکمه‌ی «بازگشت» ماوس هم کار می‌کند
        onPointerDown: (e) {
          if (e.buttons & kBackMouseButton != 0) _back();
        },
        child: LayoutBuilder(builder: (context, c) {
          final compact = c.maxWidth < 1000;
          return Row(children: [
            _Sidebar(index: _cur.index, onSelect: _go, compact: compact),
            Expanded(
              child: Column(children: [
                _TopBar(
                  title: _destinations[_cur.index].label,
                  icon: _destinations[_cur.index].selectedIcon,
                  backTo: prev,
                  onBack: _back,
                ),
                Expanded(
                  child: Stack(fit: StackFit.expand, children: [
                    for (final v in alive)
                      KeyedSubtree(
                        key: ValueKey('page-${v.gen}'),
                        child: Offstage(
                          offstage: !identical(v, _cur),
                          child: TickerMode(
                            enabled: identical(v, _cur),
                            child: FocusScope(
                              canRequestFocus: identical(v, _cur),
                              // هر صفحه کنترل‌گر اسکرول خودش را دارد (صفحه‌های زنده‌ی پشت صحنه با هم تداخل ندارند)
                              child: PrimaryScrollController.none(child: _destinations[v.index].builder()),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ]),
            ),
          ]);
        }),
      ),
    );
  }
}

/// نوار کناری: رنگ یکدست تیره، متن سفید، گزینه‌ی فعال با نوار کهربایی.
/// در پنجره‌ی باریک، نام هر گزینه زیر آیکن نوشته می‌شود (هیچ‌وقت فقط آیکن نیست).
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.index, required this.onSelect, required this.compact});
  final int index;
  final ValueChanged<int> onSelect;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final w = compact ? 96.0 : 220.0;
    return Container(
      key: AppShell.sidebarKey,
      width: w,
      color: AppColors.navy,
      child: Column(children: [
        // نشان برنامه
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? 0 : 16, 20, compact ? 0 : 16, 14),
          child: Row(mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.amber,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: AppColors.amber.withValues(alpha: 0.45), blurRadius: 16)],
              ),
              child: Icon(Icons.water_drop_rounded, color: AppColors.navy, size: 25),
            ),
            if (!compact) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('بانک قیمت',
                      style: t.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                  Text('تجهیزات نمک‌زدایی',
                      style: t.textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.65))),
                ]),
              ),
            ],
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(horizontal: 8), children: [
            for (var i = 0; i < _destinations.length; i++) ...[
              if (_destinations[i].section != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(compact ? 4 : 10, i == 0 ? 2 : 14, compact ? 4 : 10, 6),
                  child: compact
                      ? Divider(color: Colors.white.withValues(alpha: 0.15), height: 1)
                      : Text(_destinations[i].section!,
                          style: t.textTheme.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.55), fontWeight: FontWeight.w700)),
                ),
              _NavItem(
                key: ValueKey('nav-$i'),
                dest: _destinations[i],
                selected: i == index,
                compact: compact,
                onTap: () => onSelect(i),
              ),
            ],
          ]),
        ),
        // کاربر جاری
        Container(
          margin: const EdgeInsets.all(8),
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 10, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.teal,
              child: Text(app.user.displayName.isEmpty ? '؟' : app.user.displayName.characters.first,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            if (!compact) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(app.user.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.labelLarge?.copyWith(color: Colors.white)),
                  Text('نسخه‌ی ۰٫۷ · آفلاین',
                      style: t.textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.55))),
                ]),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({super.key, required this.dest, required this.selected, required this.compact, required this.onTap});
  final _Dest dest;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    final fg = sel ? Colors.white : Colors.white.withValues(alpha: _hover ? 1 : 0.8);
    final step = widget.dest.step;
    final icon = Icon(sel ? widget.dest.selectedIcon : widget.dest.icon, color: sel ? AppColors.amber : fg, size: 21);
    final badge = step == null
        ? null
        : Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sel ? AppColors.amber : Colors.white.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Text(fa(step),
                style: TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w800, color: sel ? AppColors.navy : Colors.white, height: 1.1)),
          );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: widget.compact ? 50 : 44,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: sel
                ? Colors.white.withValues(alpha: 0.14)
                : (_hover ? Colors.white.withValues(alpha: 0.07) : Colors.transparent),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Stack(children: [
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 4,
                  height: sel ? 24 : 0,
                  decoration: BoxDecoration(color: AppColors.amber, borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ),
            if (widget.compact)
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    icon,
                    if (badge != null) ...[const SizedBox(width: 3), badge],
                  ]),
                  const SizedBox(height: 3),
                  Text(widget.dest.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg, fontSize: 10.5, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                ]),
              )
            else
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 14, end: 10),
                child: Row(children: [
                  icon,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(widget.dest.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: fg, fontSize: 13.5, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                  ),
                  if (badge != null)
                    Tooltip(message: 'گام ${fa(step)} از «شروع کار»', child: badge),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.icon, required this.backTo, required this.onBack});
  final String title;
  final IconData icon;

  /// نام صفحه‌ی قبل (null = تاریخچه خالی است)
  final String? backTo;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final s = app.settings;
    final years = [for (var y = 1385; y <= 1410; y++) y];
    final fxTypes = app.pb.settingsRepo.fxRateTypes();
    final method = methodByCode(s.escalationMethod);
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        border: Border(bottom: BorderSide(color: t.colorScheme.outlineVariant)),
        boxShadow: softShadow(context),
      ),
      child: Row(children: [
        // دکمه‌ی بازگشت: همیشه در همین جای ثابت (هم‌جای دکمه‌ی بازگشت صفحه‌های جزئیات)
        Tooltip(
          message: backTo == null ? 'صفحه‌ی قبلی وجود ندارد' : 'بازگشت به «$backTo» (همان جای قبلی)',
          child: IconButton.filledTonal(
            key: AppShell.backKey,
            onPressed: backTo == null ? null : onBack,
            icon: const BackButtonIcon(),
          ),
        ),
        if (backTo != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 2, end: 6),
            child: Text(backTo!,
                style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ),
        Container(width: 1, height: 26, margin: const EdgeInsets.symmetric(horizontal: 8), color: t.colorScheme.outlineVariant),
        Icon(icon, size: 20, color: t.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        ),
        _Control(
          label: 'سال هدف',
          tooltip: 'همه‌ی قیمت‌ها به این سال تعدیل می‌شوند (شاخص و نرخ ارز همین سال).',
          child: DropdownButton<int>(itemHeight: null, 
            value: years.contains(s.targetYear) ? s.targetYear : null,
            underline: const SizedBox(),
            isDense: true,
            style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            borderRadius: BorderRadius.circular(10),
            items: [for (final y in years) DropdownMenuItem(value: y, child: DdText(fa(y)))],
            onChanged: (y) => app.setSetting('target_year', '$y', reason: 'تغییر سال هدف از نوار بالا'),
          ),
        ),
        const SizedBox(width: 8),
        _Control(
          label: 'جدول نرخ ارز',
          tooltip: 'جدول نرخ ارز برای تبدیل ریال/دلار/یورو در همه‌ی محاسبات.\n'
              '«جدول پیش‌فرض» همان نرخ‌های فایل اکسل است؛ جدول جدید را در «تنظیمات» بسازید و در «شاخص‌ها و ارز» تکمیل کنید.',
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: DropdownButton<String>(itemHeight: null, 
              value: fxTypes.any((f) => f.code == s.fxRateType) ? s.fxRateType : null,
              underline: const SizedBox(),
              isDense: true,
              isExpanded: true,
              style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              borderRadius: BorderRadius.circular(10),
              selectedItemBuilder: (_) => [
                for (final f in fxTypes)
                  Tooltip(message: f.nameFa, child: Text(f.nameFa, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              items: [
                for (final f in fxTypes) DropdownMenuItem(value: f.code, child: DdText(f.nameFa)),
              ],
              onChanged: (v) => app.setSetting('fx_rate_type', v, reason: 'تغییر جدول نرخ ارز از نوار بالا'),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _Control(
          label: 'روش تعدیل',
          tooltip: '${method.code} — ${method.nameFa}\nبرای مقایسه و تغییر روش، صفحه‌ی «روش‌های تعدیل» را باز کنید.',
          onTap: () => AppShell.go(context, AppShell.methods),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: AppColors.amber, borderRadius: BorderRadius.circular(6)),
              child: Text(method.code,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.navy)),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_left_rounded, size: 18, color: t.colorScheme.outline),
          ]),
        ),
        const SizedBox(width: 12),
        SegmentedButton<MoneyUnit>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: MoneyUnit.rial, label: Text('ریال')),
            ButtonSegment(value: MoneyUnit.toman, label: Text('تومان')),
          ],
          selected: {app.unit},
          onSelectionChanged: (v) => app.toggleUnit(v.first),
        ),
      ]),
    );
  }
}

/// یک کنترل نوار بالا: برچسب کوچک بالای مقدار، داخل قاب گرد.
class _Control extends StatelessWidget {
  const _Control({required this.label, required this.child, this.tooltip, this.onTap});
  final String label;
  final Widget child;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget w = Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: t.colorScheme.onSurfaceVariant, height: 1.2)),
          DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            child: child,
          ),
        ],
      ),
    );
    if (onTap != null) {
      w = Material(
        type: MaterialType.transparency,
        child: InkWell(borderRadius: BorderRadius.circular(10), onTap: onTap, child: w),
      );
    }
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}
