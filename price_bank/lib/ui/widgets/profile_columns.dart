import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/catalog/profiles.dart';
import '../../core/price_bank.dart';
import '../../core/repo/catalog_repo.dart' show FieldDef, FieldType;
import '../format.dart';
import 'data_grid.dart';
import 'equipment_columns.dart';

/// ستون‌های جدول اقلام یک رده (انتخاب قلم از جدول و جدول همتاها در صفحه‌ی تخمین) با سرستون مشخصات کلیدی همان رده.
/// [rowOf] ردیف بانک را از نوع جدول درمی‌آورد؛ [extra] ستون‌های ویژه‌ی جدول (یورو، ضریب هزینه، …) در انتها.
List<GridColumn<T>> profileColumns<T>(AppState app, String code, GenericRow? Function(T row) rowOf,
    {List<GridColumn<T>> extra = const [], bool legacyRef = false}) {
  final p = equipmentProfiles[code];
  final cat = app.pb.catalog.categoryByCode(code);
  final fields = cat == null ? const <String, FieldDef>{} : {for (final f in app.pb.catalog.fields(cat.id)) f.key: f};
  String txt(Object? v) => v is num ? faSmart(v) : (v?.toString() ?? '');
  return [
    if (legacyRef)
      GridColumn<T>(
          label: 'شناسه', width: 84, ltr: true,
          text: (r) => rowOf(r)?.item.legacyRef ?? '', sortKey: (r) => rowOf(r)?.item.legacyRef ?? ''),
    GridColumn<T>(
        label: 'تگ', width: 100, ltr: true, notStated: true,
        text: (r) => rowOf(r)?.item.tag ?? '', sortKey: (r) => rowOf(r)?.item.tag ?? ''),
    GridColumn<T>(
        label: 'نام / سرویس', width: 190, fitMax: 300, align: TextAlign.start, ltr: true,
        text: (r) => rowOf(r)?.item.name ?? '', sortKey: (r) => rowOf(r)?.item.name ?? ''),
    GridColumn<T>(
        label: 'پروژه', width: 110, notStated: true,
        text: (r) => rowOf(r)?.item.projectName ?? '', sortKey: (r) => rowOf(r)?.item.projectName ?? ''),
    if (p != null)
      for (final k in p.gridKeys)
        if (fields[k] case final f?)
          GridColumn<T>(
            label: '${f.labelFa}${f.unit == null ? '' : '\n${f.unit}'}',
            width: 92,
            numeric: f.type == FieldType.number,
            ltr: f.type != FieldType.number,
            text: (r) => txt(rowOf(r)?.item.values[k]),
            sortKey: (r) {
              final v = rowOf(r)?.item.values[k];
              if (f.type == FieldType.number) return v is num ? v.toDouble() : double.negativeInfinity;
              return v?.toString() ?? '';
            },
          ),
    if (p != null)
      GridColumn<T>(
          label: '${p.driver.labelFa}\n${p.driver.unit}', width: 92, numeric: true,
          text: (r) => faSmart(rowOf(r)?.size), sortKey: (r) => rowOf(r)?.size),
    GridColumn<T>(
      label: costYearColumnLabel,
      width: 62,
      text: (r) => rowOf(r)?.item.primary?.costYear == null ? '' : fa(rowOf(r)!.item.primary!.costYear),
      sortKey: (r) => rowOf(r)?.item.primary?.costYear,
    ),
    ...extra,
  ];
}

/// ستون «یوروی تعدیل‌شده» برای جدول انتخاب قلم
GridColumn<GenericRow> adjustedEurColumn() => GridColumn<GenericRow>(
    label: 'یورو\nتعدیل‌شده', width: 100, numeric: true,
    text: (r) => faNum(r.result.eurTarget.number), sortKey: (r) => r.result.eurTarget.number);

/// متن جستجوی یک قلم (تگ، نام، پروژه، شناسه و همه‌ی مشخصات)
String rowSearchText(GenericRow r) =>
    [r.item.tag, r.item.name, r.item.projectName, r.item.legacyRef, ...r.item.values.values.map((v) => v?.toString())]
        .whereType<String>()
        .join(' ');
