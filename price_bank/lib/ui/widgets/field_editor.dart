import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/pump_engine.dart' show asText;
import '../../core/repo/catalog_repo.dart';
import '../../core/repo/items_repo.dart';
import '../format.dart';
import '../theme.dart';
import 'common.dart';
import 'data_grid.dart' show gridNotStated, isNotStated;

/// نمایش یا ویرایش یک فیلد قالب، با توضیح فیلد و برچسب «استنباطی».
class FieldTile extends StatelessWidget {
  const FieldTile({
    super.key,
    required this.field,
    required this.value,
    required this.meta,
    required this.editing,
    required this.changed,
    required this.onChanged,
    this.categoryId,
    this.extra,
  });

  /// متن کوچک زیر مقدار (مثلاً اختلاف فشار معادل زیر هد اختلافی)
  final String? extra;

  /// برای نمایش تعداد اقلام هر گزینه در دراپ‌داون
  final int? categoryId;
  final FieldDef field;
  final Object? value;
  final FieldMeta? meta;
  final bool editing;
  final bool changed;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final inferred = meta?.flag == 'inferred';
    final fx = meta?.flag == 'fx';
    final note = meta?.note;
    final help = [
      if (field.helpFa != null) field.helpFa!,
      if (field.labelEn != null) '(${field.labelEn})',
      if (field.sourceRef != null) 'مرجع: ${field.sourceRef}',
    ].join('\n');

    final label = Row(children: [
      Flexible(
        child: Text(
          '${field.labelFa}${field.unit != null ? ' (${field.unit})' : ''}',
          overflow: TextOverflow.ellipsis,
          style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
        ),
      ),
      if (help.isNotEmpty)
        Tooltip(
          message: help,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 4),
            child: Icon(Icons.info_outline_rounded, size: 15, color: t.colorScheme.outline),
          ),
        ),
      if (inferred)
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 6),
          child: Pill('استنباطی', color: Tones.warn(context), tooltip: note ?? 'مقدار در منبع صریح نبوده است'),
        ),
      if (fx)
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 6),
          child: Pill('تبدیل ارزی', color: Tones.info(context), tooltip: note ?? 'تبدیل با نرخ بانک'),
        ),
      if (changed)
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 6),
          child: Pill('تغییر کرده', color: Tones.good(context)),
        ),
    ]);

    final body = editing ? _editor(context) : _display(context, inferred, fx, note);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [label, const SizedBox(height: 4), body]);
  }

  Widget _display(BuildContext context, bool inferred, bool fx, String? note) {
    final t = Theme.of(context);
    final text = fieldDisplayText(context, field, value);
    // کادر نرم بدون قاب؛ مقدار استنباطی/تبدیل ارزی با رنگ ملایم و خط ابتدای کادر
    final box = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: inferred ? Tones.inferredBg(context) : (fx ? Tones.fxBg(context) : t.colorScheme.surfaceContainerLow),
          border: inferred || fx
              ? BorderDirectional(
                  start: BorderSide(color: inferred ? Tones.warn(context) : Tones.info(context), width: 3))
              : null,
        ),
        child: Row(children: [
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SelectableText(
                text,
                textDirection: dirOf(text),
                style: t.textTheme.bodyMedium?.copyWith(
                  fontWeight: field.storage == FieldStorage.calc ? FontWeight.w600 : null,
                  color: field.storage == FieldStorage.calc ? t.colorScheme.primary : null,
                ),
              ),
            ),
          ),
          if (extra != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: Text(extra!,
                  textDirection: dirOf(extra!),
                  style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ),
        ]),
      ),
    );
    final v = value;
    final tip = text == gridNotStated && v is String && v.trim().isNotEmpty ? v.trim() : note;
    if (tip == null || tip.isEmpty) return box;
    return Tooltip(message: tip, child: box);
  }

  Widget _editor(BuildContext context) {
    switch (field.type) {
      case FieldType.enumeration:
        return _EnumEditor(
            field: field, value: value == null ? null : asText(value), onChanged: onChanged, categoryId: categoryId);
      case FieldType.number:
        return _TextEditor(
          initial: value == null ? '' : (value is num ? asText(value) : value.toString()),
          numeric: true,
          onChanged: (s) => onChanged(s.trim().isEmpty ? null : (parseUserNumber(s) ?? s)),
        );
      case FieldType.text:
        return _TextEditor(
          initial: value?.toString() ?? '',
          numeric: false,
          maxLines: field.key == 'remarks' || field.key == 'price_basis' ? 3 : 1,
          onChanged: (s) => onChanged(s.trim().isEmpty ? null : s),
        );
    }
  }
}

class _TextEditor extends StatefulWidget {
  const _TextEditor({required this.initial, required this.numeric, required this.onChanged, this.maxLines = 1});
  final String initial;
  final bool numeric;
  final int maxLines;
  final ValueChanged<String> onChanged;

  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bad = widget.numeric && _c.text.trim().isNotEmpty && parseUserNumber(_c.text) == null;
    return TextField(
      controller: _c,
      maxLines: widget.maxLines,
      minLines: 1,
      textDirection: widget.numeric ? TextDirection.ltr : null,
      decoration: InputDecoration(
        errorText: bad ? 'عدد نیست؛ به صورت متن ذخیره می‌شود' : null,
        helperText: widget.numeric && !bad && _c.text.isNotEmpty ? faNum(parseUserNumber(_c.text), decimals: 4) : null,
      ),
      onChanged: (s) {
        setState(() {});
        widget.onChanged(s);
      },
    );
  }
}

class _EnumEditor extends StatelessWidget {
  const _EnumEditor({required this.field, required this.value, required this.onChanged, this.categoryId});
  final int? categoryId;
  final FieldDef field;
  final String? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final opts = app.pb.catalog.options(field.listKey ?? '');
    final values = [for (final o in opts) o.value];
    // تعداد اقلام همین رده با هر گزینه (فقط فیلدهای مشخصات که در item_values ذخیره می‌شوند)
    final counts = categoryId == null || field.storage != FieldStorage.spec
        ? null
        : {
            for (final r in app.pb.db.query(
                "SELECT v.value_text AS v, COUNT(*) AS n FROM item_values v JOIN items i ON i.id = v.item_id "
                "WHERE i.category_id = ? AND i.status = 'active' AND v.field_key = ? GROUP BY v.value_text",
                [categoryId, field.key]))
              '${r['v']}': r['n'] as int,
          };
    final hasValue = value != null && values.contains(value);
    return DropdownButtonFormField<String?>(
      itemHeight: null,
      value: hasValue ? value : null,
      isExpanded: true,
      hint: Text(value == null ? 'انتخاب کنید' : '$value (خارج از فهرست)'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: DdText('— خالی —')),
        for (final o in opts)
          DropdownMenuItem<String?>(
            value: o.value,
            child: Tooltip(
              message: o.description ?? o.labelFa ?? o.value,
              child: CountedLabel(
                (field.listKey == 'YN' || field.listKey == 'YNS') && o.labelFa != null
                    ? '${o.labelFa} (${o.value})'
                    : (o.labelFa != null && o.labelFa != o.value ? '${o.value} — ${o.labelFa}' : o.value),
                counts == null ? null : (counts[o.value] ?? 0),
                dimZero: false,
              ),
            ),
          ),
      ],
      onChanged: (v) => onChanged(v),
    );
  }
}

/// فیلد همراه: مقدار هم‌معنا با واحد/شکل دیگر که در نمایش کنار مقدار اصلی (داخل همان کادر) می‌آید، نه کادر جدا.
const fieldCompanions = {
  'diff_head_m': 'diff_pressure_bar',
  'design_pressure_barg': 'design_pressure_barg_text',
};

/// در نمایش، فیلدهای همراه حذف می‌شوند؛ در ویرایش به انتهای گروه می‌روند تا کنار فیلد اصلی نباشند.
List<FieldDef> arrangeCompanions(List<FieldDef> fields, {required bool editing}) {
  final keys = {for (final f in fields) f.key};
  bool isComp(FieldDef f) => fieldCompanions.entries.any((e) => e.value == f.key && keys.contains(e.key));
  final main = [
    for (final f in fields)
      if (!isComp(f)) f
  ];
  return editing
      ? [
          ...main,
          for (final f in fields)
            if (isComp(f)) f
        ]
      : main;
}

/// یادداشت کوچک داخل کادر فیلد اصلی برای مقدار فیلد همراه (اگر چیزی بیش از مقدار اصلی می‌گوید).
String? companionNote(FieldDef f, Object? Function(String key) valueOf) {
  final ck = fieldCompanions[f.key];
  if (ck == null) return null;
  final cv = valueOf(ck);
  if (cv == null || (cv is String && cv.trim().isEmpty)) return null;
  if (ck == 'diff_pressure_bar') return 'اختلاف فشار ${cv is num ? faSmart(cv) : cv} bar';
  final mv = valueOf(f.key);
  final n = cv is num ? cv : parseUserNumber(cv.toString());
  if (n != null && mv is num && (n - mv).abs() < 1e-9) return null;
  return 'منبع: $cv';
}

bool _isMoney(FieldDef f) => f.unit == 'EUR' || f.unit == 'USD' || f.unit == 'IRR' || f.key == 'unit_price';

/// متن نمایشی مقدار یک فیلد (همان که در کادر فیلد دیده می‌شود).
String fieldDisplayText(BuildContext context, FieldDef field, Object? v) {
  final unit = AppScope.of(context).unit;
  // تگ/پروژه‌ای که در منبع نیامده: برچسب کوتاه (متن کامل منبع در راهنمای شناور کادر)
  if ((field.key == 'tag' || field.key == 'project') && (v == null || v is String) && isNotStated(v as String?)) {
    return gridNotStated;
  }
  if (v == null || (v is String && v.isEmpty)) return '—';
  if (v is num) {
    return _isMoney(field)
        ? (field.unit == 'IRR' ? money(v.toDouble(), unit) : faNum(v, decimals: v.abs() < 100 ? 3 : 0))
        : faSmart(v);
  }
  final s = v.toString();
  if (field.listKey == null || (field.listKey != 'YN' && field.listKey != 'YNS')) return s;
  for (final o in AppScope.of(context).pb.catalog.options(field.listKey!)) {
    if (o.value == s) return o.labelFa ?? s;
  }
  return s;
}

/// چیدمان فیلدها روی شبکه‌ی ستونی منظم: هر کادر به اندازه‌ی بزرگ‌ترین مقداری که ممکن است بگیرد
/// (عدد: یک خانه؛ گزینه‌ای: بلندترین گزینه؛ متن: مقدار فعلی) چند خانه‌ی هم‌عرض می‌گیرد.
class FieldGrid extends StatelessWidget {
  const FieldGrid({
    super.key,
    required this.fields,
    required this.valueOf,
    required this.tile,
    this.editing = false,
    this.fullWidth = false,
    this.badges,
    this.extraOf,
  });
  final List<FieldDef> fields;

  /// یادداشت داخل کادر (همان که به [FieldTile.extra] داده می‌شود) برای جا دادن عرض
  final String? Function(FieldDef f)? extraOf;
  final Object? Function(FieldDef f) valueOf;
  final Widget Function(FieldDef f) tile;
  final bool editing;

  /// همه‌ی کادرها تمام‌عرض (مثل گروه شرح)
  final bool fullWidth;

  /// تعداد برچسب‌های کنار عنوان (استنباطی، تغییر کرده…) برای جا دادن عنوان
  final int Function(FieldDef f)? badges;

  static const gap = 16.0;
  static const cell = 140.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scale = MediaQuery.textScalerOf(context);
    double measure(String s, TextStyle? st) {
      final tp = TextPainter(text: TextSpan(text: s, style: st), textDirection: TextDirection.rtl, textScaler: scale)
        ..layout();
      final w = tp.width;
      tp.dispose();
      return w;
    }

    final labelStyle = t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600);
    final valueStyle = t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    final catalog = AppScope.of(context).pb.catalog;
    return LayoutBuilder(builder: (context, cons) {
      final full = cons.maxWidth;
      final cols = fullWidth ? 1 : ((full + gap) / (cell + gap)).floor().clamp(1, 12);
      final cw = (full - (cols - 1) * gap) / cols;
      double widthOf(FieldDef f) {
        if (cols == 1) return full;
        final label = '${f.labelFa}${f.unit != null ? ' (${f.unit})' : ''}';
        final need = <double>[measure(label, labelStyle) + 22 + (badges?.call(f) ?? 0) * 72];
        if (f.type == FieldType.enumeration && f.listKey != null) {
          for (final o in catalog.options(f.listKey!)) {
            need.add(measure(fieldDisplayText(context, f, o.value), valueStyle) + (editing ? 56 : 24));
          }
        }
        final v = valueOf(f);
        final note = editing ? null : extraOf?.call(f);
        need.add(measure(fieldDisplayText(context, f, v), valueStyle) +
            (editing ? 40 : 24) +
            (note == null ? 0 : measure(note, t.textTheme.labelSmall) + 8));
        var span = need.map((w) => ((w + gap) / (cw + gap)).ceil()).reduce((a, b) => a > b ? a : b);
        if (editing && f.type == FieldType.text) span = span < 2 ? 2 : span;
        if (span >= cols || (f.type == FieldType.text && span > cols ~/ 2 + 1)) return full;
        return span * cw + (span - 1) * gap;
      }

      return Wrap(spacing: gap, runSpacing: 14, children: [
        for (final f in fields) SizedBox(width: widthOf(f), child: tile(f)),
      ]);
    });
  }
}

/// یادداشت «قیمت‌های اسناد پنهان» در زبانه‌ی قیمت‌ها: این قیمت‌ها نگه داشته شده‌اند ولی در هیچ محاسبه‌ای نیستند.
class HiddenPricesNote extends StatelessWidget {
  const HiddenPricesNote(this.obs, {super.key});
  final List<PriceObs> obs;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final docs = {for (final o in obs) o.documentTitle ?? '—'}.join('، ');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Tones.warn(context).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Tones.warn(context).withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Icon(Icons.visibility_off_outlined, size: 18, color: Tones.warn(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
              '${fa(obs.length)} قیمت از اسناد پنهان ($docs) در محاسبات و این فهرست نیست؛ '
              'برای برگرداندن، سند را در «پروژه‌ها و اسناد» پیدا کنید.',
              style: t.textTheme.bodySmall),
        ),
      ]),
    );
  }
}
