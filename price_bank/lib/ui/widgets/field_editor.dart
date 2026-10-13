import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/calc/pump_engine.dart' show asText;
import '../../core/repo/catalog_repo.dart';
import '../../core/repo/items_repo.dart';
import '../format.dart';
import '../theme.dart';
import 'common.dart';

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
  });

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
    final unit = AppScope.of(context).unit;
    String text;
    final v = value;
    if (v == null || (v is String && v.isEmpty)) {
      text = '—';
    } else if (v is num) {
      text = _isMoney ? (field.unit == 'IRR' ? money(v.toDouble(), unit) : faNum(v, decimals: v.abs() < 100 ? 3 : 0)) : faSmart(v);
    } else {
      text = _enumLabel(context, v.toString());
    }
    final box = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: inferred
            ? Tones.inferredBg(context)
            : (fx ? Tones.fxBg(context) : t.colorScheme.surfaceContainerLowest),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: SelectableText(
        text,
        textDirection: dirOf(text),
        style: t.textTheme.bodyMedium?.copyWith(
          fontWeight: field.storage == FieldStorage.calc ? FontWeight.w600 : null,
          color: field.storage == FieldStorage.calc ? t.colorScheme.primary : null,
        ),
      ),
    );
    if (note == null || note.isEmpty) return box;
    return Tooltip(message: note, child: box);
  }

  bool get _isMoney => field.unit == 'EUR' || field.unit == 'USD' || field.unit == 'IRR' || field.key == 'unit_price';

  String _enumLabel(BuildContext context, String v) {
    if (field.listKey == null) return v;
    final opts = AppScope.of(context).pb.catalog.options(field.listKey!);
    for (final o in opts) {
      if (o.value == v) return o.labelFa != null && (field.listKey == 'YN' || field.listKey == 'YNS') ? o.labelFa! : v;
    }
    return v;
  }

  Widget _editor(BuildContext context) {
    switch (field.type) {
      case FieldType.enumeration:
        return _EnumEditor(field: field, value: value == null ? null : asText(value), onChanged: onChanged);
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
  const _EnumEditor({required this.field, required this.value, required this.onChanged});
  final FieldDef field;
  final String? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final opts = AppScope.of(context).pb.catalog.options(field.listKey ?? '');
    final values = [for (final o in opts) o.value];
    final hasValue = value != null && values.contains(value);
    return DropdownButtonFormField<String?>(
      value: hasValue ? value : null,
      isExpanded: true,
      hint: Text(value == null ? 'انتخاب کنید' : '$value (خارج از فهرست)'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('— خالی —')),
        for (final o in opts)
          DropdownMenuItem<String?>(
            value: o.value,
            child: Tooltip(
              message: o.description ?? o.labelFa ?? o.value,
              child: Text(
                (field.listKey == 'YN' || field.listKey == 'YNS') && o.labelFa != null
                    ? '${o.labelFa} (${o.value})'
                    : (o.labelFa != null && o.labelFa != o.value ? '${o.value} — ${o.labelFa}' : o.value),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
      onChanged: (v) => onChanged(v),
    );
  }
}
