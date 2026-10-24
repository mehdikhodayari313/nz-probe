// کتابخانه‌های رابط کاربری (۱۴۰۵/۰۸/۰۲): بارگذاری و رسم هر کدام در چیدمان راست‌به‌چپ برنامه.
// fl_chart نمودار، data_table_2 جدول با سرستون ثابت، flex_color_scheme تم، flutter_animate و animations
// جلوه‌ها و انتقال‌ها، lucide_icons_flutter آیکن‌ها.

import 'package:animations/animations.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  testWidgets('کتابخانه‌های UI در چیدمان راست‌به‌چپ رسم می‌شوند', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: FlexThemeData.light(scheme: FlexScheme.blueWhale, fontFamily: 'Vazirmatn'),
      darkTheme: FlexThemeData.dark(scheme: FlexScheme.blueWhale, fontFamily: 'Vazirmatn'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Column(children: [
            SizedBox(
              height: 160,
              child: BarChart(BarChartData(barGroups: [
                for (var i = 0; i < 4; i++)
                  BarChartGroupData(x: i, barRods: [BarChartRodData(toY: (i + 1) * 10.0, color: Colors.teal)]),
              ])),
            ),
            SizedBox(
              height: 160,
              child: DataTable2(
                fixedTopRows: 1,
                columns: const [DataColumn2(label: Text('تگ')), DataColumn2(label: Text('قیمت'), numeric: true)],
                rows: const [
                  DataRow(cells: [DataCell(Text('P-101')), DataCell(Text('۱۲٬۳۰۰'))]),
                  DataRow(cells: [DataCell(Text('P-102')), DataCell(Text('۹٬۸۰۰'))]),
                ],
              ),
            ),
            const Icon(LucideIcons.gauge),
            const Text('جلوه').animate().fadeIn(duration: 200.ms),
            OpenContainer(
              closedBuilder: (_, open) => TextButton(onPressed: open, child: const Text('باز کن')),
              openBuilder: (_, __) => const Scaffold(body: Text('جزئیات')),
            ),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(BarChart), findsOneWidget);
    expect(find.text('P-102'), findsOneWidget);
    expect(find.text('جلوه'), findsOneWidget);
    await tester.tap(find.text('باز کن'));
    await tester.pumpAndSettle();
    expect(find.text('جزئیات'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
