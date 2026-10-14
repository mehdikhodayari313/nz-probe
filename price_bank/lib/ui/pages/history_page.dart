import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../format.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import '../../core/repo/audit.dart';

const _entityFa = {
  'item': 'قلم تجهیز',
  'index': 'شاخص / نرخ',
  'index_series': 'سری شاخص',
  'settings': 'تنظیمات',
  'document': 'سند',
  'project': 'پروژه',
  'fx_rate_type': 'جدول نرخ ارز',
  'factor': 'ضریب',
  'user': 'کاربر',
  'vendor': 'فروشنده',
};

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String? _entity;
  bool _hideImport = true;
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final all = app.pb.audit.recent(limit: 5000);
    final q = _q.text.trim().toLowerCase();
    final rows = [
      for (final e in all)
        if ((_entity == null || e.entity == _entity) &&
            (!_hideImport || !(e.reason ?? '').startsWith('انتقال از')) &&
            (q.isEmpty ||
                [e.entityId, e.field, e.oldValue, e.newValue, e.reason, e.userName]
                    .whereType<String>()
                    .any((s) => s.toLowerCase().contains(q))))
          e,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(icon: Icons.history_rounded, title: 'تاریخچه‌ی تغییرات', subtitle: '${fa(rows.length)} مورد (آخرین ۵۰۰۰)'),
        const HelpPanel(
          id: 'history',
          title: 'تاریخچه',
          initiallyOpen: false,
          lines: [
            'هر تغییر در داده‌ها (اقلام، شاخص‌ها، اسناد، ضرایب، تنظیمات، کاربران) با مقدار قبلی و جدید، کاربر، زمان و دلیل اینجا ثبت می‌شود.',
            'هیچ رکوردی پاک نمی‌شود؛ اقلام فقط بایگانی می‌شوند و قابل بازگرداندن‌اند.',
          ],
        ),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _q,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'جستجو در شناسه، فیلد، مقدار، دلیل یا کاربر'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String?>(
              value: _entity,
              decoration: const InputDecoration(labelText: 'نوع'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('همه')),
                for (final e in _entityFa.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _entity = v),
            ),
          ),
          const SizedBox(width: 10),
          ToggleChip(
            label: 'پنهان کردن ثبت‌های انتقال اولیه',
            selected: _hideImport,
            onChanged: (v) => setState(() => _hideImport = v),
          ),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: rows.isEmpty
                ? const EmptyState(icon: Icons.history_toggle_off_rounded, title: 'موردی نیست')
                : DataGrid<AuditEntry>(
                    rows: rows,
                    columns: [
                      GridColumn(label: 'زمان', width: 150, text: (e) => shortTs(e.ts), sortKey: (e) => e.ts),
                      GridColumn(label: 'کاربر', width: 120, text: (e) => e.userName ?? '', sortKey: (e) => e.userName ?? ''),
                      GridColumn(label: 'نوع', width: 110, text: (e) => _entityFa[e.entity] ?? e.entity, sortKey: (e) => e.entity),
                      GridColumn(label: 'شناسه', width: 140, clean: false, text: (e) => e.entityId ?? ''),
                      GridColumn(label: 'فیلد', width: 160, clean: false, text: (e) => e.field == '*' ? 'ایجاد' : (e.field ?? ''), sortKey: (e) => e.field ?? ''),
                      GridColumn(label: 'مقدار قبلی', width: 200, clean: false, align: TextAlign.start, text: (e) => e.oldValue ?? ''),
                      GridColumn(label: 'مقدار جدید', width: 200, clean: false, align: TextAlign.start, text: (e) => e.newValue ?? ''),
                      GridColumn(label: 'دلیل', width: 260, clean: false, align: TextAlign.start, text: (e) => e.reason ?? ''),
                    ],
                  ),
          ),
        ),
      ]),
    );
  }
}
