// پنجره‌ی ویرایش یک ضریب نرمال‌سازی: فقط برای همین تخمین، یا ذخیره به عنوان ضریب کالیبره در بانک.

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/price_bank.dart';
import '../format.dart';
import '../theme.dart';
import 'common.dart';

/// نتیجه‌ی پنجره: [local] = ضریب موردی (null = حذف ضریب موردی)، [saved] = در بانک ذخیره شد.
class FactorEditResult {
  const FactorEditResult({this.local, this.clearLocal = false, this.saved = false});
  final double? local;
  final bool clearLocal;
  final bool saved;
}

Future<FactorEditResult?> showFactorDialog(
  BuildContext context, {
  required String group,
  required String option,
  required String label,
  double? localOverride,
}) {
  return showDialog<FactorEditResult>(
    context: context,
    builder: (ctx) => _FactorDialog(group: group, option: option, label: label, localOverride: localOverride),
  );
}

class _FactorDialog extends StatefulWidget {
  const _FactorDialog({required this.group, required this.option, required this.label, this.localOverride});
  final String group;
  final String option;
  final String label;
  final double? localOverride;

  @override
  State<_FactorDialog> createState() => _FactorDialogState();
}

class _FactorDialogState extends State<_FactorDialog> {
  late final TextEditingController _c;
  final _reason = TextEditingController();
  bool _persist = false;
  Map<String, Object?>? _row;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    for (final r in app.pb.indices.factors(PriceBank.pumpFactorSet)) {
      if (r['grp'] == widget.group && r['option'] == widget.option) _row = r;
    }
    final eff = widget.localOverride ?? app.pb.factorTable.get(widget.group, widget.option);
    _c = TextEditingController(text: _plain(eff));
  }

  static String _plain(double v) {
    var s = v.toStringAsFixed(4);
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  @override
  void dispose() {
    _c.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final v = parseUserNumber(_c.text);
    if (v == null || v <= 0 || v > 20) {
      showSnack(context, 'ضریب باید عددی مثبت (حداکثر ۲۰) باشد.', error: true);
      return;
    }
    if (_persist) {
      final app = AppScope.read(context);
      app.pb.indices.setCalibrated(PriceBank.pumpFactorSet, widget.group, widget.option, v,
          reason: _reason.text.trim().isEmpty ? 'ثبت از صفحه‌ی تخمین' : _reason.text.trim());
      app.dataChanged(calcInputs: true);
      Navigator.pop(context, const FactorEditResult(saved: true, clearLocal: true));
    } else {
      Navigator.pop(context, FactorEditResult(local: v));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final app = AppScope.read(context);
    final canPersist = _row != null && (app.user.isAdmin || app.user.role == 'reviewer');
    final prov = _row?['provisional'] as double?;
    final cal = _row?['calibrated'] as double?;
    Widget info(String k, String v, {Color? c}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: t.colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(10)),
            child: Column(children: [
              Text(v, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: c)),
              Text(k, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ]),
          ),
        );
    return AlertDialog(
      title: Row(children: [
        Icon(Icons.tune_rounded, color: AppColors.petrol),
        const SizedBox(width: 8),
        Expanded(child: Text('ضریب ${widget.label}')),
      ]),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('گزینه: ${widget.option}', textDirection: dirOf(widget.option), style: t.textTheme.bodyMedium),
          const SizedBox(height: 10),
          Row(children: [
            info('ضریب اولیه', prov == null ? '۱ (پیش‌فرض)' : faSmart(prov)),
            const SizedBox(width: 6),
            info('ضریب کالیبره', cal == null ? '—' : faSmart(cal), c: cal == null ? null : Tones.good(context)),
            const SizedBox(width: 6),
            info('ضریب موردی', widget.localOverride == null ? '—' : faSmart(widget.localOverride), c: AppColors.amber),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _c,
            autofocus: true,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'ضریب جدید', prefixText: '× '),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _persist,
            onChanged: canPersist ? (v) => setState(() => _persist = v) : null,
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(_persist ? 'ذخیره به عنوان ضریب کالیبره در بانک' : 'فقط برای همین تخمین'),
            subtitle: Text(_persist
                ? 'روی همه‌ی محاسبات (یورو نرمال‌شده، ضریب هزینه و تخمین‌ها) اثر دارد و در تاریخچه ثبت می‌شود.'
                : (canPersist
                    ? 'بانک تغییر نمی‌کند. برای ذخیره‌ی دائمی در بانک، این کلید را روشن کنید.'
                    : (_row == null
                        ? 'بانک تغییر نمی‌کند (این گزینه در جدول ضرایب ردیف ندارد).'
                        : 'بانک تغییر نمی‌کند (فقط مدیر یا بازبین می‌تواند ضریب بانک را تغییر دهد).'))),
          ),
          if (_persist) ...[
            const SizedBox(height: 6),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(labelText: 'دلیل یا مرجع (اختیاری)', hintText: 'مثلاً: کالیبره با استعلام‌های ۱۴۰۴'),
            ),
          ],
        ]),
      ),
      actions: [
        if (widget.localOverride != null)
          TextButton(
            onPressed: () => Navigator.pop(context, const FactorEditResult(clearLocal: true)),
            child: const Text('حذف ضریب موردی'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: _submit, child: const Text('اعمال')),
      ],
    );
  }
}
