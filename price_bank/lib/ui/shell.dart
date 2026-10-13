import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../core/calc/methods.dart';
import 'format.dart';
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
  const _Dest(this.icon, this.selectedIcon, this.label, this.builder, {this.section});
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget Function() builder;

  /// عنوان گروه که بالای این گزینه نمایش داده می‌شود
  final String? section;
}

final _destinations = <_Dest>[
  _Dest(Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'داشبورد', () => const DashboardPage(),
      section: 'بانک قیمت'),
  _Dest(Icons.precision_manufacturing_outlined, Icons.precision_manufacturing_rounded, 'تجهیزات',
      () => const EquipmentPage()),
  _Dest(Icons.calculate_outlined, Icons.calculate_rounded, 'تخمین و تعدیل', () => const EstimatorPage(),
      section: 'محاسبات'),
  _Dest(Icons.science_outlined, Icons.science_rounded, 'روش‌های تعدیل', () => const MethodsPage()),
  _Dest(Icons.query_stats_outlined, Icons.query_stats_rounded, 'شاخص‌ها و ارز', () => const IndicesPage()),
  _Dest(Icons.tune_outlined, Icons.tune_rounded, 'ضرایب', () => const FactorsPage()),
  _Dest(Icons.folder_open_outlined, Icons.folder_rounded, 'پروژه‌ها و اسناد', () => const DocumentsPage(),
      section: 'مدیریت'),
  _Dest(Icons.history_outlined, Icons.history_rounded, 'تاریخچه', () => const HistoryPage()),
  _Dest(Icons.group_outlined, Icons.group_rounded, 'کاربران', () => const UsersPage()),
  _Dest(Icons.settings_outlined, Icons.settings_rounded, 'تنظیمات', () => const SettingsPage()),
];

/// قاب اصلی: نوار کناری تیره + نوار بالا (سال هدف، جدول نرخ ارز، روش تعدیل، ریال/تومان).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  /// تغییر صفحه از داخل صفحه‌های دیگر.
  static void go(BuildContext context, int index) => context.findAncestorStateOfType<_AppShellState>()?._go(index);

  static const dashboard = 0, equipment = 1, estimator = 2, methods = 3, indices = 4, factors = 5, documents = 6,
      history = 7, users = 8, settings = 9;

  static const sidebarKey = Key('sidebar');

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(builder: (context, c) {
        final compact = c.maxWidth < 1180;
        return Row(children: [
          _Sidebar(index: _index, onSelect: _go, compact: compact),
          Expanded(
            child: Column(children: [
              _TopBar(title: _destinations[_index].label, icon: _destinations[_index].selectedIcon),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: KeyedSubtree(key: ValueKey(_index), child: _destinations[_index].builder()),
                ),
              ),
            ]),
          ),
        ]);
      }),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.index, required this.onSelect, required this.compact});
  final int index;
  final ValueChanged<int> onSelect;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final w = compact ? 84.0 : 224.0;
    return Container(
      key: AppShell.sidebarKey,
      width: w,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.navy, AppColors.petrolDark],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(children: [
        // نشان برنامه
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? 0 : 18, 22, compact ? 0 : 18, 18),
          child: Row(mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.amber, Color(0xFFF4C46B)]),
                borderRadius: BorderRadius.circular(13),
                boxShadow: [BoxShadow(color: AppColors.amber.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: const Icon(Icons.water_drop_rounded, color: AppColors.navy, size: 26),
            ),
            if (!compact) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('بانک قیمت',
                      style: t.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                  Text('تجهیزات نمک‌زدایی',
                      style: t.textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.6))),
                ]),
              ),
            ],
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(horizontal: 10), children: [
            for (var i = 0; i < _destinations.length; i++) ...[
              if (_destinations[i].section != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(compact ? 0 : 10, i == 0 ? 0 : 14, compact ? 0 : 10, 6),
                  child: compact
                      ? Divider(color: Colors.white.withValues(alpha: 0.12), height: 1)
                      : Text(_destinations[i].section!,
                          style: t.textTheme.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.45), fontWeight: FontWeight.w700)),
                ),
              _NavItem(key: ValueKey('nav-$i'), dest: _destinations[i], selected: i == index, compact: compact, onTap: () => onSelect(i)),
            ],
          ]),
        ),
        // کاربر جاری
        Container(
          margin: const EdgeInsets.all(10),
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 10, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
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
                  Text('نسخه‌ی ۰٫۲ · آفلاین',
                      style: t.textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.5))),
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
    final fg = sel ? Colors.white : Colors.white.withValues(alpha: _hover ? 0.95 : 0.72);
    final item = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 44,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: sel
                ? Colors.white.withValues(alpha: 0.13)
                : (_hover ? Colors.white.withValues(alpha: 0.06) : Colors.transparent),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(mainAxisAlignment: widget.compact ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 4,
              height: sel ? 22 : 0,
              decoration: BoxDecoration(color: AppColors.amber, borderRadius: BorderRadius.circular(4)),
            ),
            SizedBox(width: widget.compact ? 0 : 10),
            Icon(sel ? widget.dest.selectedIcon : widget.dest.icon, color: sel ? AppColors.amber : fg, size: 21),
            if (!widget.compact) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(widget.dest.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: fg, fontSize: 13.5, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
              ),
            ] else
              const SizedBox(width: 4),
          ]),
        ),
      ),
    );
    return widget.compact ? Tooltip(message: widget.dest.label, child: Semantics(label: widget.dest.label, child: item)) : item;
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.icon});
  final String title;
  final IconData icon;

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
          child: DropdownButton<int>(
            value: years.contains(s.targetYear) ? s.targetYear : null,
            underline: const SizedBox(),
            isDense: true,
            style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            borderRadius: BorderRadius.circular(10),
            items: [for (final y in years) DropdownMenuItem(value: y, child: Text(fa(y)))],
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
            child: DropdownButton<String>(
              value: fxTypes.any((f) => f.code == s.fxRateType) ? s.fxRateType : null,
              underline: const SizedBox(),
              isDense: true,
              isExpanded: true,
              style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              borderRadius: BorderRadius.circular(10),
              items: [
                for (final f in fxTypes)
                  DropdownMenuItem(value: f.code, child: Text(f.nameFa, overflow: TextOverflow.ellipsis)),
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
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.navy)),
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
