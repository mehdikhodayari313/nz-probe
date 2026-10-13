import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:price_bank/core/calc/pump_engine.dart';
import 'package:price_bank/core/repo/seed.dart';
import 'package:price_bank/core/xlsx/xlsx_reader.dart';

const v8Path = 'test/fixtures_private/Pumps_Price_Bank_v8.xlsx';
const validationPath = 'test/fixtures_private/Pump_Escalation_Validation_2.xlsx';

bool get hasFixtures => File(v8Path).existsSync() && File(validationPath).existsSync();

Map<String, dynamic> loadJson(String name) =>
    jsonDecode(File('assets/seed/$name').readAsStringSync()) as Map<String, dynamic>;

SeedData loadSeed() => SeedData(
      lists: loadJson('lists.json'),
      pumpTemplate: loadJson('pump_template.json'),
      factors: loadJson('factors.json'),
      indices: loadJson('indices.json'),
      settings: loadJson('settings.json'),
    );

/// مقایسه‌ی یک خانه‌ی محاسبه‌شده با مقدار ذخیره‌شده در اکسل.
/// برمی‌گرداند null اگر برابر باشد، وگرنه شرح اختلاف.
String? compareCell(CalcCell actual, XlsxCell? cached, {double tol = 1e-9}) {
  final v = cached?.value;
  if (v is double) {
    if (!actual.isNumber) return 'انتظار عدد $v، محاسبه: «${actual.text ?? '(خالی)'}»';
    final a = actual.number!;
    final diff = (a - v).abs();
    if (diff > tol * (v.abs() > 1 ? v.abs() : 1)) return 'انتظار $v، محاسبه $a';
    return null;
  }
  final s = v == null ? '' : v.toString();
  if (s.isEmpty) {
    return actual.isBlank ? null : 'انتظار خالی، محاسبه: $actual';
  }
  if (actual.text != s) return 'انتظار «$s»، محاسبه: «$actual»';
  return null;
}

String? compareNum(double? actual, XlsxCell? cached, {double tol = 1e-9}) =>
    compareCell(actual == null ? const CalcCell.blank() : CalcCell.number(actual), cached, tol: tol);

void expectNoDiffs(List<String> diffs) {
  if (diffs.isNotEmpty) {
    fail('${diffs.length} اختلاف:\n${diffs.take(40).join('\n')}');
  }
}
