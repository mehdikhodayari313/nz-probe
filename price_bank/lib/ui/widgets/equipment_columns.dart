import 'package:flutter/material.dart';

import '../../core/repo/items_repo.dart';
import '../format.dart';
import 'data_grid.dart';

// ستون‌های مشترک جدول همه‌ی تجهیزات (پمپ و سایر رده‌ها): ظرفیت واحد پروژه (بند ۲e) و سال قیمت مبنا (بند ۱۶).

const capacityColumnLabel = 'ظرفیت واحد\n(هزار BPD)';
const capacityRangeLabel = 'ظرفیت (هزار BPD)';
const costYearColumnLabel = 'سال قیمت';

String _kbpd(double? bpd) => bpd == null ? '' : faSmart(bpd / 1000);

Widget _dash(BuildContext c, String why) =>
    Tooltip(message: why, child: Text(gridEmpty, style: TextStyle(color: Theme.of(c).colorScheme.outline)));

/// ظرفیت واحد نمک‌زدایی پروژه‌ی قلم، به هزار بشکه در روز (از «پروژه‌ها و اسناد»).
GridColumn<T> capacityColumn<T>(double? Function(T row) bpd) => GridColumn<T>(
      label: capacityColumnLabel,
      width: 78,
      numeric: true,
      tooltip: 'ظرفیت واحد نمک‌زدایی پروژه‌ی این قلم (هزار بشکه در روز). ظرفیت هر پروژه در «پروژه‌ها و اسناد» وارد می‌شود.',
      text: (r) => _kbpd(bpd(r)),
      sortKey: (r) => bpd(r),
      cell: (c, r) {
        final v = bpd(r);
        if (v == null) return _dash(c, 'ظرفیت این پروژه در «پروژه‌ها و اسناد» وارد نشده');
        return Text(_kbpd(v), style: Theme.of(c).textTheme.bodySmall);
      },
    );

/// سال قیمت مبنای قلم (سال قیمت منبع، شمسی، بدون جداکننده).
GridColumn<T> costYearColumn<T>(ItemRecord Function(T row) item) => GridColumn<T>(
      label: costYearColumnLabel,
      width: 62,
      text: (r) => item(r).primary?.costYear == null ? '' : fa(item(r).primary!.costYear),
      sortKey: (r) => item(r).primary?.costYear,
      cell: (c, r) {
        final p = item(r).primary;
        if (p?.costYear == null) {
          final raw = p?.costYearText ?? '';
          return _dash(c, 'سال قیمت در منبع ذکر نشده${raw.isEmpty ? '' : ' («$raw»)'}');
        }
        return Text(fa(p!.costYear), style: Theme.of(c).textTheme.bodySmall);
      },
    );

/// آیا ظرفیت (BPD) در بازه‌ی «از/تا» (هزار BPD) هست؟ بازه‌ی خالی = همه.
bool capacityInRange(double? bpd, double? loK, double? hiK) {
  if (loK == null && hiK == null) return true;
  if (bpd == null) return false;
  final k = bpd / 1000;
  return (loK == null || k >= loK) && (hiK == null || k <= hiK);
}
