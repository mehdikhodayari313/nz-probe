import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/repo/users_repo.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';

class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final users = app.pb.users.all();
    final discs = app.pb.catalog.disciplines();
    final admin = app.user.isAdmin;

    return ListView(padding: const EdgeInsets.all(20), children: [
      PageHeader(
        icon: Icons.group_rounded,
        title: 'کاربران و سطح دسترسی',
        subtitle: '${fa(users.length)} کاربر',
        actions: [
          if (admin) FilledButton.icon(onPressed: () => _add(context), icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('کاربر جدید')),
        ],
      ),
      const HelpPanel(
        id: 'users',
        title: 'نقش‌ها و محدوده‌ی دسترسی',
        lines: [
          'مدیر سیستم: همه‌ی کارها، شامل کاربران، ضرایب و تنظیمات. کارشناس ورود داده: افزودن و ویرایش اقلام در رشته‌های مجاز. بازبین: ویرایش و تأیید. مشاهده‌گر: فقط دیدن.',
          'برای هر کاربر مشخص کنید در هر رشته (مکانیک، پایپینگ، برق، ابزار دقیق) چه دسترسی دارد.',
          'نسخه‌ی فعلی تک‌کاربره است و با «مدیر سیستم» باز می‌شود. ساختار کاربران از هم‌اکنون آماده است تا با دیتابیس مشترک یا بسته‌ی داده‌ی رمزنگاری‌شده (مرحله‌ی ۵) فعال شود.',
        ],
      ),
      for (final u in users) ...[
        SectionCard(
          title: '${u.displayName}  (${u.username})',
          subtitle: roleFa[u.role] ?? u.role,
          icon: u.isAdmin ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
          trailing: Wrap(spacing: 8, children: [
            if (!u.active) Pill('غیرفعال', color: Tones.bad(context)),
            if (u.id == app.user.id) Pill('کاربر فعلی', color: Tones.good(context)),
            if (admin && u.id != app.user.id)
              TextButton(
                onPressed: () {
                  app.pb.users.update(u.id, active: !u.active);
                  app.dataChanged();
                },
                child: Text(u.active ? 'غیرفعال کردن' : 'فعال کردن'),
              ),
          ]),
          child: Table(
            columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: BoxDecoration(color: AppColors.headerBg),
                children: [for (final h in ['رشته', 'مشاهده', 'ویرایش', 'تأیید']) Padding(padding: const EdgeInsets.all(8), child: Text(h, style: const TextStyle(fontWeight: FontWeight.w700)))],
              ),
              for (final d in discs)
                (() {
                  final sc = app.pb.users.scopes(u.id)[d.code];
                  final v = u.isAdmin || (sc?.canView ?? false);
                  final e = u.isAdmin || (sc?.canEdit ?? false);
                  final a = u.isAdmin || (sc?.canApprove ?? false);
                  void set({bool? view, bool? edit, bool? approve}) {
                    app.pb.users.setScope(u.id, d.code, view: view ?? v, edit: edit ?? e, approve: approve ?? a);
                    app.dataChanged();
                  }

                  final locked = !admin || u.isAdmin;
                  return TableRow(children: [
                    Padding(padding: const EdgeInsets.all(8), child: Text(d.nameFa)),
                    Checkbox(value: v, onChanged: locked ? null : (x) => set(view: x)),
                    Checkbox(value: e, onChanged: locked ? null : (x) => set(edit: x)),
                    Checkbox(value: a, onChanged: locked ? null : (x) => set(approve: x)),
                  ]);
                })(),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    ]);
  }

  Future<void> _add(BuildContext context) async {
    final user = TextEditingController(), name = TextEditingController();
    String role = 'editor';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('کاربر جدید'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: user, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'نام کاربری (لاتین)')),
              const SizedBox(height: 10),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'نام نمایشی')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(itemHeight: null, isExpanded: true, 
                value: role,
                decoration: const InputDecoration(labelText: 'نقش'),
                items: [for (final e in roleFa.entries) DropdownMenuItem(value: e.key, child: DdText(e.value))],
                onChanged: (v) => setD(() => role = v!),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ایجاد')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_.]{2,30}$').hasMatch(user.text.trim()) || name.text.trim().isEmpty) {
      showSnack(context, 'نام کاربری لاتین (۳ تا ۳۰ نویسه) و نام نمایشی لازم است.', error: true);
      return;
    }
    try {
      final app = AppScope.read(context);
      final id = app.pb.users.create(user.text.trim(), name.text.trim(), role);
      for (final d in app.pb.catalog.disciplines()) {
        app.pb.users.setScope(id, d.code, view: true, edit: role == 'editor' || role == 'reviewer', approve: role == 'reviewer');
      }
      app.dataChanged();
    } catch (e) {
      showSnack(context, 'ایجاد ناموفق (نام کاربری تکراری؟): $e', error: true);
    }
  }
}
