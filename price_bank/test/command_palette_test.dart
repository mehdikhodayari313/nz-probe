// جست‌وجوی سراسری (Ctrl+K): صفحه‌ها و اقلام پیدا می‌شوند؛ Enter صفحه یا قلم را باز می‌کند.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:price_bank/app/app_state.dart';
import 'package:price_bank/core/price_bank.dart';
import 'package:price_bank/core/xlsx/xlsx_reader.dart';
import 'package:price_bank/main.dart';
import 'package:price_bank/ui/pages/pump_detail_page.dart';
import 'package:price_bank/ui/widgets/command_palette.dart';

import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  test('یکسان‌سازی متن جست‌وجو: ی/ک عربی، ارقام فارسی و نیم‌فاصله', () {
    expect(paletteNorm('پمپ‌هاي P-۱۰۱ ك'), 'پمپ های p-101 ک');
  });

  testWidgets('Ctrl+K: رفتن به صفحه و باز کردن قلم', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final pb = PriceBank.memory(loadSeed());
    if (hasFixtures) pb.v8Importer().run(XlsxWorkbook.openFile(v8Path), fileName: 'v8');
    final state = AppState(pb);
    await tester.pumpWidget(PriceBankApp(state: state));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('palette-input')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('palette-input')), 'ضرایب');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('palette-input')), findsNothing);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('ضرایب')).evaluate().isNotEmpty ||
        find.text('ضرایب').evaluate().length > 1, isTrue);

    if (!hasFixtures) return;
    final pump = state.pumps.first.item;
    await tester.tap(find.byKey(const Key('global-search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('palette-input')), pump.name);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(PumpDetailPage), findsOneWidget);
  });

  testWidgets('Dock: با رسیدن نشانگر به لبه‌ی پایین ظاهر می‌شود و صفحه را عوض می‌کند', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(PriceBankApp(state: AppState(PriceBank.memory(loadSeed()))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mac-dock')), findsNothing);
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: const Offset(700, 500));
    await tester.pump();
    await g.moveTo(tester.getCenter(find.byKey(const Key('dock-handle'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mac-dock')), findsOneWidget);
    await g.moveTo(tester.getCenter(find.byKey(const ValueKey('dock-5'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dock-5')));
    await tester.pumpAndSettle();
    expect(find.text('ضرایب'), findsWidgets);
    await g.moveTo(const Offset(700, 300));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mac-dock')), findsNothing);
    await g.removePointer();
  });
}
