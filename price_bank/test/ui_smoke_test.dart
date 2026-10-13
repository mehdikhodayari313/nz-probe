// آزمون رابط کاربری: برنامه با داده‌ی واقعی v8 ساخته می‌شود و همه‌ی صفحه‌ها باز می‌شوند.
// هر خطای چیدمان (overflow) یا استثنا باعث شکست آزمون می‌شود.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:price_bank/app/app_state.dart';
import 'package:price_bank/core/price_bank.dart';
import 'package:price_bank/core/xlsx/xlsx_reader.dart';
import 'package:price_bank/main.dart';
import 'package:price_bank/ui/pages/pump_detail_page.dart';

import 'support.dart';

void main() {
  const labels = ['داشبورد', 'تجهیزات', 'تخمین و تعدیل', 'شاخص‌ها و ارز', 'ضرایب', 'پروژه‌ها و اسناد', 'تاریخچه', 'کاربران', 'تنظیمات'];

  Future<AppState> boot(WidgetTester tester, {bool withData = true}) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final pb = PriceBank.memory(loadSeed());
    if (withData && hasFixtures) pb.v8Importer().run(XlsxWorkbook.openFile(v8Path), fileName: 'v8');
    final state = AppState(pb);
    await tester.pumpWidget(PriceBankApp(state: state));
    await tester.pumpAndSettle();
    return state;
  }

  Future<void> go(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text(label)));
    await tester.pumpAndSettle();
  }

  testWidgets('همه‌ی صفحه‌ها با داده‌ی v8 بدون خطا باز می‌شوند', (tester) async {
    await boot(tester);
    for (final l in labels) {
      await go(tester, l);
      expect(tester.takeException(), isNull, reason: 'صفحه‌ی $l');
    }
  });

  testWidgets('صفحه‌ها با دیتابیس خالی هم باز می‌شوند', (tester) async {
    await boot(tester, withData: false);
    expect(find.text('ورود داده‌های بانک قیمت v8'), findsOneWidget);
    for (final l in labels) {
      await go(tester, l);
      expect(tester.takeException(), isNull, reason: 'صفحه‌ی $l (خالی)');
    }
  });

  testWidgets('جزئیات پمپ: همه‌ی زبانه‌ها و حالت ویرایش', (tester) async {
    if (!hasFixtures) return;
    final app = await boot(tester);
    final id = app.pumps.firstWhere((r) => r.result.eurTarget.isNumber).item.id;
    await tester.pumpWidget(PriceBankApp(state: app));
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(builder: (_) => AppScope(state: app, child: PumpDetailPage(itemId: id))));
    await tester.pumpAndSettle();
    for (final tab in ['مشخصات', 'محاسبه‌ی قیمت', 'قیمت‌ها و استعلام‌ها', 'تاریخچه']) {
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'زبانه‌ی $tab');
    }
    await tester.tap(find.text('ویرایش'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'حالت ویرایش');
    // پمپ جدید
    nav.push(MaterialPageRoute<void>(builder: (_) => AppScope(state: app, child: const PumpDetailPage(itemId: null))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'پمپ جدید');
  });
}
