// آزمون رابط کاربری: برنامه با داده‌ی واقعی v8 ساخته می‌شود و همه‌ی صفحه‌ها باز می‌شوند.
// هر خطای چیدمان (overflow) یا استثنا باعث شکست آزمون می‌شود.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:price_bank/app/app_state.dart';
import 'package:price_bank/core/price_bank.dart';
import 'package:price_bank/core/xlsx/xlsx_reader.dart';
import 'package:price_bank/core/import/mto_importer.dart';
import 'package:price_bank/main.dart';
import 'package:price_bank/ui/pages/equipment_page.dart';
import 'package:price_bank/ui/pages/generic_item_page.dart';
import 'package:price_bank/ui/widgets/mto_import_dialog.dart';
import 'package:price_bank/ui/pages/pump_detail_page.dart';

import 'support.dart';

void main() {
  setUpAll(loadAppFonts);
  const labels = [
    'داشبورد', 'شاخص‌ها و ارز', 'روش‌های تعدیل', 'تجهیزات', 'تخمین و تعدیل', 'ضرایب', 'پروژه‌ها و اسناد',
    'تاریخچه', 'کاربران', 'تنظیمات',
  ];
  const nIndices = 1, nMethods = 2, nEquipment = 3, nEstimator = 4, nDocuments = 6;

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

  testWidgets('همه‌ی صفحه‌ها در پنجره‌ی کوچک (۹۸۰×۷۲۰، نوار کناری باریک با نام منوها)', (tester) async {
    await boot(tester, size: const Size(980, 720));
    expect(find.descendant(of: find.byKey(const Key('sidebar')), matching: find.text('روش‌های تعدیل')), findsOneWidget);
    for (var i = 0; i < labels.length; i++) {
      await go(tester, i);
      debugPrint('✓ ' 'صفحه‌ی ${labels[i]} (پنجره‌ی کوچک)');
    }
  });

  testWidgets('حالت شب و پالت سبز: همه‌ی صفحه‌ها', (tester) async {
    final app = await boot(tester);
    app.setSetting('theme_mode', 'dark');
    app.setSetting('theme_palette', 'green');
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byKey(const Key('sidebar')))).brightness, Brightness.dark);
    for (var i = 0; i < labels.length; i++) {
      await go(tester, i);
      debugPrint('✓ ' 'صفحه‌ی ${labels[i]} (شب)');
    }
    app.setSetting('theme_mode', 'light');
    app.setSetting('theme_palette', 'petrol');
    await tester.pumpAndSettle();
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
    await go(tester, nMethods);
    final btn = find.byKey(const ValueKey('select-M4'));
    await tester.scrollUntilVisible(btn, 300, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.tap(btn);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ثبت'));
    await tester.pumpAndSettle();
    expect(app.settings.escalationMethod, 'M4');
    await go(tester, nEquipment); // تجهیزات با روش جدید
    await go(tester, 0);
    debugPrint('✓ ' 'تغییر روش به M4 و نمایش صفحه‌ها');
  });

  testWidgets('تخمین: ویرایش ضریب موردی', (tester) async {
    if (!hasFixtures) return;
    await boot(tester);
    await go(tester, nEstimator);
    expect(find.textContaining('۱. قیمت مورد انتظار (یورو)'), findsOneWidget);
    expect(find.textContaining('معادل یورویی'), findsOneWidget);
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
    await go(tester, nEquipment);
    await tester.tap(find.ancestor(of: find.text('آب‌بند'), matching: find.byType(DropdownButtonFormField<String?>)));
    await tester.pumpAndSettle();
    expect(find.text('Arr 2 - Dual Unpressurized'), findsWidgets);
    expect(find.text('Arr 3 - Dual Pressurized'), findsWidgets);
    debugPrint('✓ ' 'گزینه‌های فیلتر آب‌بند');
  });

  testWidgets('ساخت و حذف جدول نرخ ارز در صفحه‌ی شاخص‌ها', (tester) async {
    final app = await boot(tester);
    await go(tester, nIndices);
    await tester.tap(find.byKey(const ValueKey('add-fx-table')));
    await tester.pumpAndSettle();
    final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'نرخ بودجه');
    await tester.enterText(fields.at(1), '1200000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('ساخت جدول'));
    await tester.pumpAndSettle();
    final ft = app.pb.settingsRepo.fxRateTypes().firstWhere((f) => f.nameFa == 'نرخ بودجه');
    expect(app.pb.seriesSnapshot.resolve('FX_EUR_${ft.code}', app.settings.targetYear)!.value, 1200000);
    // جدول جدید باز شده؛ حذف از همین صفحه
    await tester.tap(find.text('حذف این جدول نرخ ارز'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف جدول'));
    await tester.pumpAndSettle();
    expect(app.pb.settingsRepo.fxRateTypes().any((f) => f.nameFa == 'نرخ بودجه'), isFalse);
    debugPrint('✓ ' 'ساخت و حذف جدول نرخ ارز');
  });

  testWidgets('ورود نرخ تورم به درصد', (tester) async {
    final app = await boot(tester);
    await go(tester, nIndices);
    await tester.ensureVisible(find.text('تورم ریالی سالانه (CPI)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تورم ریالی سالانه (CPI)'));
    await tester.pumpAndSettle();
    final yearField = find.widgetWithText(TextField, 'سال');
    await tester.enterText(yearField, '1406');
    await tester.enterText(find.widgetWithText(TextField, 'نرخ (درصد)'), '35');
    await tester.tap(find.text('ثبت'));
    await tester.pumpAndSettle();
    expect(app.pb.seriesSnapshot.resolve('INF_IRR', 1406)!.value, closeTo(0.35, 1e-12));
    debugPrint('✓ ' 'نرخ ۳۵٪ به صورت ۰٫۳۵ ذخیره شد');
  });

  testWidgets('حذف پروژه با تأیید', (tester) async {
    if (!hasFixtures) return;
    final app = await boot(tester);
    final before = app.pb.docs.projects().length;
    await go(tester, nDocuments);
    await tester.tap(find.byTooltip('حذف پروژه').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'حذف');
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف پروژه').last);
    await tester.pumpAndSettle();
    expect(app.pb.docs.projects().length, before - 1);
    debugPrint('✓ ' 'حذف پروژه');
  });

  testWidgets('ورود MTO از پیش‌نمایش، فهرست رده‌ی ظرف و صفحه‌ی قلم', (tester) async {
    final app = await boot(tester);
    final a = MtoImporter.analyze(XlsxWorkbook.openFile('test/fixtures/MTO_sample_14040105.xlsx'),
        fileName: 'MTO_sample_14040105.xlsx');
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    showDialog<void>(context: nav.context, builder: (_) => MtoPreviewDialog(analysis: a));
    await tester.pumpAndSettle();
    expect(find.textContaining('ورود ۱۹ قلم'), findsOneWidget);
    await tester.tap(find.textContaining('ورود ۱۹ قلم'));
    await tester.pumpAndSettle();
    expect(find.text('ورود MTO کامل شد'), findsOneWidget);
    await tester.tap(find.text('بسیار خوب'));
    await tester.pumpAndSettle();
    final vessel = app.pb.catalog.categoryByCode('VESSEL')!;
    expect(app.pb.items.count(vessel.id), 4);
    debugPrint('✓ ' 'ورود MTO از پیش‌نمایش');

    // داشبورد: کارت رده‌ها
    await go(tester, 0);
    await tester.dragUntilVisible(find.text('تجهیزات به تفکیک رده'), find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('تجهیزات به تفکیک رده'), findsOneWidget);
    // فهرست ظرف‌ها
    EquipmentPage.selectedCategory = 'VESSEL';
    await go(tester, nEquipment);
    expect(find.text('V-141'), findsWidgets);
    debugPrint('✓ ' 'فهرست ظرف‌ها');
    for (final code in ['DESALTER', 'CIP', 'CRANE', 'HEX', 'TANK']) {
      EquipmentPage.selectedCategory = code;
      await go(tester, 0);
      await go(tester, nEquipment);
      debugPrint('✓ ' 'رده‌ی $code');
    }
    // فیلترهای پارامتریک و تنظیمات رده‌ی ظرف
    EquipmentPage.selectedCategory = 'VESSEL';
    await go(tester, 0);
    await go(tester, nEquipment);
    expect(find.text('جهت نصب'), findsWidgets);
    expect(find.text('کلاس جنس'), findsWidgets);
    await tester.tap(find.text('تنظیمات رده'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    debugPrint('✓ ' 'فیلترهای پارامتریک و تنظیمات رده');
    EquipmentPage.selectedCategory = 'PUMP';

    // تخمین سایر تجهیزات
    await go(tester, nEstimator);
    await tester.tap(find.text('تخمین سایر تجهیزات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('نزدیک‌ترین همتا'));
    await tester.pumpAndSettle();
    expect(find.textContaining('حجم ظرف'), findsWidgets);
    debugPrint('✓ ' 'تخمین سایر تجهیزات');

    // صفحه‌ی قلم
    final id = app.genericRows(vessel.id).firstWhere((r) => r.item.tag == 'V-141').item.id;
    nav.push(MaterialPageRoute<void>(builder: (_) => GenericItemPage(itemId: id)));
    await tester.pumpAndSettle();
    for (final tab in ['مشخصات', 'قیمت‌ها و استعلام‌ها', 'محاسبه‌ی قیمت', 'تاریخچه']) {
      await tester.tap(find.textContaining(tab).first);
      await tester.pumpAndSettle();
      debugPrint('✓ ' 'قلم V-141 — زبانه‌ی $tab');
    }
    await tester.tap(find.textContaining('قیمت‌ها و استعلام‌ها').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('مبنا شود').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ثبت'));
    await tester.pumpAndSettle();
    expect(app.pb.items.get(id)!.primary!.kind, isNot('estimate'));
    await tester.tap(find.text('مشخصات').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ویرایش'));
    await tester.pumpAndSettle();
    debugPrint('✓ ' 'مبنا شدن استعلام و حالت ویرایش');
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
