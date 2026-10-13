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
  setUpAll(loadAppFonts);
  const labels = [
    'داشبورد', 'تجهیزات', 'تخمین و تعدیل', 'روش‌های تعدیل', 'شاخص‌ها و ارز', 'ضرایب', 'پروژه‌ها و اسناد',
    'تاریخچه', 'کاربران', 'تنظیمات',
  ];

  Future<AppState> boot(WidgetTester tester, {bool withData = true, Size size = const Size(1600, 1000)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final pb = PriceBank.memory(loadSeed());
    if (withData && hasFixtures) pb.v8Importer().run(XlsxWorkbook.openFile(v8Path), fileName: 'v8');
    final state = AppState(pb);
    await tester.pumpWidget(PriceBankApp(state: state));
    await tester.pumpAndSettle();
    return state;
  }

  Future<void> go(WidgetTester tester, int i) async {
    await tester.tap(find.byKey(ValueKey('nav-$i')));
    await tester.pumpAndSettle();
  }

  testWidgets('همه‌ی صفحه‌ها با داده‌ی v8 بدون خطا باز می‌شوند', (tester) async {
    await boot(tester);
    for (var i = 0; i < labels.length; i++) {
      await go(tester, i);
      debugPrint('✓ ' 'صفحه‌ی ${labels[i]}');
    }
  });

  testWidgets('همه‌ی صفحه‌ها در پنجره‌ی کوچک (۱۲۸۰×۷۶۰، نوار کناری جمع‌شده)', (tester) async {
    await boot(tester, size: const Size(1280, 760));
    for (var i = 0; i < labels.length; i++) {
      await go(tester, i);
      debugPrint('✓ ' 'صفحه‌ی ${labels[i]} (پنجره‌ی کوچک)');
    }
  });

  testWidgets('صفحه‌ها با دیتابیس خالی هم باز می‌شوند', (tester) async {
    await boot(tester, withData: false);
    expect(find.text('ورود داده‌های بانک قیمت v8'), findsOneWidget);
    for (var i = 0; i < labels.length; i++) {
      await go(tester, i);
      debugPrint('✓ ' 'صفحه‌ی ${labels[i]} (خالی)');
    }
  });

  testWidgets('انتخاب روش تعدیل از صفحه‌ی روش‌ها', (tester) async {
    final app = await boot(tester);
    await go(tester, 3);
    final btn = find.text('انتخاب این روش');
    expect(btn, findsWidgets);
    await tester.ensureVisible(btn.first);
    await tester.tap(btn.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ثبت'));
    await tester.pumpAndSettle();
    expect(app.settings.escalationMethod, 'M0');
    await go(tester, 1); // تجهیزات با روش جدید
    await go(tester, 0);
    debugPrint('✓ ' 'تغییر روش به M0 و نمایش صفحه‌ها');
  });

  testWidgets('تخمین: ویرایش ضریب موردی', (tester) async {
    if (!hasFixtures) return;
    await boot(tester);
    await go(tester, 2);
    expect(find.textContaining('۱. قیمت مورد انتظار (یورو)'), findsOneWidget);
    final chip = find.textContaining('× ').first;
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '1.5');
    await tester.tap(find.text('اعمال'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ضریب موردی'), findsWidgets);
    debugPrint('✓ ' 'ضریب موردی در تخمین');
  });

  testWidgets('تجهیزات: فیلتر آب‌بند همه‌ی گزینه‌ها را دارد', (tester) async {
    if (!hasFixtures) return;
    await boot(tester);
    await go(tester, 1);
    await tester.tap(find.text('آب‌بند'));
    await tester.pumpAndSettle();
    expect(find.text('Arr 2 - Dual Unpressurized'), findsWidgets);
    expect(find.text('Arr 3 - Dual Pressurized'), findsWidgets);
    debugPrint('✓ ' 'گزینه‌های فیلتر آب‌بند');
  });

  testWidgets('ساخت جدول نرخ ارز جدید از تنظیمات', (tester) async {
    final app = await boot(tester);
    await go(tester, 9);
    await tester.tap(find.text('جدول جدید'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'نرخ بودجه');
    await tester.pumpAndSettle();
    await tester.tap(find.text('ساخت جدول'));
    await tester.pumpAndSettle();
    expect(app.pb.settingsRepo.fxRateTypes().any((f) => f.nameFa == 'نرخ بودجه'), isTrue);
    debugPrint('✓ ' 'جدول نرخ ارز جدید');
  });

  testWidgets('حذف پروژه با تأیید', (tester) async {
    if (!hasFixtures) return;
    final app = await boot(tester);
    final before = app.pb.docs.projects().length;
    await go(tester, 6);
    await tester.tap(find.byTooltip('حذف پروژه').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'حذف');
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف پروژه').last);
    await tester.pumpAndSettle();
    expect(app.pb.docs.projects().length, before - 1);
    debugPrint('✓ ' 'حذف پروژه');
  });

  testWidgets('جزئیات پمپ: همه‌ی زبانه‌ها و حالت ویرایش', (tester) async {
    if (!hasFixtures) return;
    final app = await boot(tester);
    final id = app.pumps.firstWhere((r) => r.result.eurTarget.isNumber).item.id;
    await tester.pumpWidget(PriceBankApp(state: app));
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(builder: (_) => PumpDetailPage(itemId: id)));
    await tester.pumpAndSettle();
    for (final tab in ['مشخصات', 'محاسبه‌ی قیمت', 'قیمت‌ها و استعلام‌ها', 'تاریخچه']) {
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
      debugPrint('✓ ' 'زبانه‌ی $tab');
    }
    await tester.tap(find.text('ویرایش'));
    await tester.pumpAndSettle();
    debugPrint('✓ ' 'حالت ویرایش');
    // پمپ جدید
    nav.push(MaterialPageRoute<void>(builder: (_) => const PumpDetailPage(itemId: null)));
    await tester.pumpAndSettle();
    debugPrint('✓ ' 'پمپ جدید');
  });
}
