import 'package:flutter/material.dart';

import '../app/app_state.dart';
import 'format.dart';
import 'pages/dashboard_page.dart';
import 'pages/documents_page.dart';
import 'pages/equipment_page.dart';
import 'pages/estimator_page.dart';
import 'pages/factors_page.dart';
import 'pages/history_page.dart';
import 'pages/indices_page.dart';
import 'pages/settings_page.dart';
import 'pages/users_page.dart';

class _Dest {
  const _Dest(this.icon, this.selectedIcon, this.label, this.builder);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget Function() builder;
}

final _destinations = <_Dest>[
  _Dest(Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'داشبورد', () => const DashboardPage()),
  _Dest(Icons.precision_manufacturing_outlined, Icons.precision_manufacturing_rounded, 'تجهیزات',
      () => const EquipmentPage()),
  _Dest(Icons.calculate_outlined, Icons.calculate_rounded, 'تخمین و تعدیل', () => const EstimatorPage()),
  _Dest(Icons.query_stats_outlined, Icons.query_stats_rounded, 'شاخص‌ها و ارز', () => const IndicesPage()),
  _Dest(Icons.tune_outlined, Icons.tune_rounded, 'ضرایب', () => const FactorsPage()),
  _Dest(Icons.folder_open_outlined, Icons.folder_rounded, 'پروژه‌ها و اسناد', () => const DocumentsPage()),
  _Dest(Icons.history_outlined, Icons.history_rounded, 'تاریخچه', () => const HistoryPage()),
  _Dest(Icons.group_outlined, Icons.group_rounded, 'کاربران', () => const UsersPage()),
  _Dest(Icons.settings_outlined, Icons.settings_rounded, 'تنظیمات', () => const SettingsPage()),
];

/// قاب اصلی: نوار ناوبری کناری + نوار بالا (سال هدف، نوع نرخ ارز، ریال/تومان).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  /// تغییر صفحه از داخل صفحه‌های دیگر.
  static void go(BuildContext context, int index) => context.findAncestorStateOfType<_AppShellState>()?._go(index);

  static const dashboard = 0, equipment = 1, estimator = 2, indices = 3, factors = 4, documents = 5, history = 6,
      users = 7, settings = 8;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: Row(children: [
        Container(
          decoration: BoxDecoration(
            color: t.colorScheme.surface,
            border: BorderDirectional(end: BorderSide(color: t.colorScheme.outlineVariant)),
          ),
          child: NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: _go,
            labelType: NavigationRailLabelType.all,
            minWidth: 92,
            leading: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 18),
              child: Column(children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [t.colorScheme.primary, t.colorScheme.tertiary]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.water_drop_rounded, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text('بانک قیمت', style: t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
            ],
          ),
        ),
        Expanded(
          child: Column(children: [
            const _TopBar(),
            Expanded(
              child: KeyedSubtree(key: ValueKey(_index), child: _destinations[_index].builder()),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context);
    final s = app.settings;
    final years = [for (var y = 1385; y <= 1410; y++) y];
    final fxTypes = app.pb.settingsRepo.fxRateTypes();
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        border: Border(bottom: BorderSide(color: t.colorScheme.outlineVariant)),
      ),
      child: Row(children: [
        Expanded(
          child: Text('بانک قیمت تجهیزات واحدهای نمک‌زدایی',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: t.colorScheme.primary)),
        ),
        Tooltip(
          message: 'همه‌ی قیمت‌ها به این سال تعدیل می‌شوند (شاخص PPI و نرخ ارز همین سال).',
          child: Row(children: [
            Text('سال هدف:', style: t.textTheme.labelMedium),
            const SizedBox(width: 6),
            DropdownButton<int>(
              value: years.contains(s.targetYear) ? s.targetYear : null,
              underline: const SizedBox(),
              borderRadius: BorderRadius.circular(10),
              items: [for (final y in years) DropdownMenuItem(value: y, child: Text(fa(y)))],
              onChanged: (y) => app.setSetting('target_year', '$y', reason: 'تغییر سال هدف از نوار بالا'),
            ),
          ]),
        ),
        const SizedBox(width: 18),
        Tooltip(
          message: 'نوع نرخ ارز برای تبدیل ریال/دلار/یورو در همه‌ی محاسبات.\n'
              '«جدول مرجع v8» همان نرخ‌های فایل اکسل است؛ بازار آزاد و نیما را در صفحه‌ی شاخص‌ها تکمیل کنید.',
          child: Row(children: [
            Text('نرخ ارز:', style: t.textTheme.labelMedium),
            const SizedBox(width: 6),
            DropdownButton<String>(
              value: fxTypes.any((f) => f.code == s.fxRateType) ? s.fxRateType : null,
              underline: const SizedBox(),
              borderRadius: BorderRadius.circular(10),
              items: [for (final f in fxTypes) DropdownMenuItem(value: f.code, child: Text(f.nameFa))],
              onChanged: (v) => app.setSetting('fx_rate_type', v, reason: 'تغییر نوع نرخ ارز از نوار بالا'),
            ),
          ]),
        ),
        const SizedBox(width: 18),
        SegmentedButton<MoneyUnit>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: MoneyUnit.rial, label: Text('ریال')),
            ButtonSegment(value: MoneyUnit.toman, label: Text('تومان')),
          ],
          selected: {app.unit},
          onSelectionChanged: (v) => app.toggleUnit(v.first),
        ),
        const SizedBox(width: 18),
        Chip(
          avatar: const Icon(Icons.person_rounded, size: 18),
          label: Text(app.user.displayName),
          visualDensity: VisualDensity.compact,
        ),
      ]),
    );
  }
}
