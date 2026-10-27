// بند ۱۲: در تخمین سایر تجهیزات، قلم مبنا از جدولی مثل جستجو انتخاب و مشخصاتش در فرم وارد می‌شود؛ همتاها جدول دارند.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:price_bank/app/app_state.dart';
import 'package:price_bank/core/import/mto_importer.dart';
import 'package:price_bank/core/price_bank.dart';
import 'package:price_bank/core/xlsx/xlsx_reader.dart';
import 'package:price_bank/main.dart';
import 'package:price_bank/ui/pages/equipment_page.dart';

import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('انتخاب ظرف از جدول، پر شدن قطر و جدول همتاها', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final pb = PriceBank.memory(loadSeed());
    pb.mtoImporter().run(
        MtoImporter.analyze(XlsxWorkbook.openFile('test/fixtures/Estimate_sample_K.xlsx'), fileName: 'Estimate_sample_K.xlsx'),
        projectName: 'Sample K',
        oldFx: null);
    final prev = EquipmentPage.selectedCategory;
    addTearDown(() => EquipmentPage.selectedCategory = prev);
    EquipmentPage.selectedCategory = 'VESSEL';
    await tester.pumpWidget(PriceBankApp(state: AppState(pb)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-4')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('estimator-pick')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-picker-search')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('item-picker-search')), 'fuel gas');
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('V-120')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.widgetWithText(TextField, '800'), findsOneWidget, reason: 'قطر داخلی V-120 در فرم');
    expect(find.descendant(of: find.byKey(const Key('estimator-pick')), matching: find.textContaining('V-120')), findsOneWidget);
    await tester.dragFrom(const Offset(700, 700), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('ضریب\nهزینه'), findsOneWidget, reason: 'جدول همتاها با سرستون');
  });
}
