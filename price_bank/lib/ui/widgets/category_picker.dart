import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import 'common.dart';

/// انتخاب رده‌ی تجهیز (پمپ + رده‌های دارای قالب) با تعداد اقلام هر رده.
class EquipmentCategoryPicker extends StatelessWidget {
  const EquipmentCategoryPicker({super.key, required this.value, required this.onChanged, this.label});
  final String value;
  final ValueChanged<String> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cats = app.pb.estimableCategories();
    final counts = app.pb.categoryCounts();
    return DropdownButtonFormField<String>(
      key: const ValueKey('category-picker'),
      value: cats.any((c) => c.code == value) ? value : cats.first.code,
      isExpanded: true,
      menuMaxHeight: 460,
      decoration: label == null ? null : InputDecoration(labelText: label),
      items: [
        for (final c in cats)
          DropdownMenuItem(value: c.code, child: CountedLabel(c.nameFa, counts[c.id] ?? 0)),
      ],
      onChanged: (v) {
        if (v != null && v != value) onChanged(v);
      },
    );
  }
}
