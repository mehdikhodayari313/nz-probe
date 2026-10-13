import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nz_probe/ui/theme.dart';

void main() {
  test('ارقام فارسی', () {
    expect(faDigits(1404), '۱۴۰۴');
    expect(faNumber(1234567), '۱٬۲۳۴٬۵۶۷');
    expect(faNumber(-1500), '-۱٬۵۰۰');
    expect(faNumber(999), '۹۹۹');
  });

  test('جهت متن هر خط', () {
    expect(directionOf('✔ نسخه‌ی SQLite'), TextDirection.rtl);
    expect(directionOf(r'C:\Users\test\app.exe'), TextDirection.ltr);
    expect(directionOf('PUMPS!M8: تاریخ نامعتبر'), TextDirection.ltr);
  });

  testWidgets('تم فارسی ساخته می‌شود', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Directionality(textDirection: TextDirection.rtl, child: Text('آزمون')),
    ));
    expect(find.text('آزمون'), findsOneWidget);
  });
}
