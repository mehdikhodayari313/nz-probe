import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_state.dart';
import 'core/price_bank.dart';
import 'core/xlsx/xlsx_reader.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // آزمون دود بدون رابط کاربری (برای خط ساخت خودکار):
  //   price_bank.exe --smoke <گزارش> <مسیر دیتابیس آزمایشی> [فایل v8] [بانک دیسالتر]
  final si = args.indexOf('--smoke');
  if (si >= 0) {
    await _smoke(args.sublist(si + 1));
    return;
  }

  Object? startupError;
  AppState? state;
  try {
    final seed = await loadSeedAssets();
    final pb = PriceBank.open(await defaultDbPath(), seed);
    state = AppState(pb);
  } catch (e, st) {
    startupError = '$e\n$st';
  }
  runApp(PriceBankApp(state: state, startupError: startupError));
}

/// تم‌های ساخته‌شده (برای هر پالت و حالت یک بار)
final _themes = <String, ThemeData>{};

class PriceBankApp extends StatelessWidget {
  const PriceBankApp({super.key, required this.state, this.startupError});
  final AppState? state;
  final Object? startupError;

  @override
  Widget build(BuildContext context) {
    // AppScope بالای MaterialApp است تا صفحه‌هایی که با Navigator باز می‌شوند هم به وضعیت برنامه دسترسی داشته باشند.
    // ظاهر (روز/شب و رنگ اصلی) از تنظیمات خوانده می‌شود و با هر تغییر دوباره ساخته می‌شود.
    Widget app(String mode, String palette) {
      final dark = mode == 'dark' ||
          (mode == 'system' && WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);
      AppColors.apply(palette, dark: dark);
      final theme = _themes['$palette|$dark'] ??= buildTheme(dark ? Brightness.dark : Brightness.light);
      return MaterialApp(
        title: 'بانک قیمت تجهیزات نمک‌زدایی',
        debugShowCheckedModeBanner: false,
        locale: const Locale('fa'),
        supportedLocales: const [Locale('fa'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: theme,
        darkTheme: theme,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: state == null ? _StartupError(error: startupError) : const AppShell(),
      );
    }

    if (state == null) return app('light', 'mist');
    return AppScope(
      state: state!,
      child: ListenableBuilder(
        listenable: state!,
        builder: (context, _) =>
            app(state!.settings.str('theme_mode', 'light'), state!.settings.str('theme_palette', 'mist')),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({this.error});
  final Object? error;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('برنامه باز نشد', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                const Text('دیتابیس یا داده‌های پایه قابل بارگذاری نبودند. متن زیر را برای پشتیبانی بفرستید:'),
                const SizedBox(height: 12),
                SelectableText('$error', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
        ),
      );
}

Future<void> _smoke(List<String> a) async {
  final out = a.isNotEmpty ? a[0] : 'price_bank_smoke.txt';
  final dbPath = a.length > 1 ? a[1] : '${Directory.systemTemp.path}${Platform.pathSeparator}pb_smoke.db';
  final v8Path = a.length > 2 ? a[2] : null;
  final b = StringBuffer();
  var ok = true;
  try {
    final f = File(dbPath);
    if (f.existsSync()) f.deleteSync();
    final pb = PriceBank.open(dbPath, await loadSeedAssets());
    b.writeln('schema: ${pb.db.schemaVersion}');
    b.writeln('fields(PUMP): ${pb.catalog.fields(pb.pumpCategory.id).length}');
    b.writeln('series: ${pb.indices.series().length}');
    if (v8Path != null && File(v8Path).existsSync()) {
      final rep = pb.v8Importer().run(XlsxWorkbook.openFile(v8Path), fileName: 'v8');
      b.writeln('imported items: ${rep.items}, projects: ${rep.projects}, docs: ${rep.documents}, '
          'vendors: ${rep.vendors}, quotes: ${rep.quotes}, inferred: ${rep.inferredFlags}, notes: ${rep.notes}');
      final rows = pb.computePumps();
      final priced = rows.where((r) => r.result.irrTarget.isNumber).toList();
      final total = priced.where((r) => r.item.include).fold<double>(0, (s, r) => s + r.result.irrTarget.number!);
      b.writeln('computed: ${rows.length}, with IRR target: ${priced.length}, sum IRR (include=Y): $total');
      ok = rep.items == 146 && priced.isNotEmpty;
    }
    final desPath = a.length > 3 ? a[3] : null;
    if (desPath != null && File(desPath).existsSync()) {
      final rep = pb.desalterImporter().run(XlsxWorkbook.openFile(desPath), fileName: 'desalters');
      final cat = pb.catalog.categoryByCode('DESALTER')!;
      final rows = pb.computeCategory(cat.id);
      final priced = rows.where((r) => r.result.eurTarget.isNumber).length;
      b.writeln('desalters: ${rep.items}, quotes: ${rep.quotes}, corrections: ${rep.corrections}, '
          'priced: $priced, method: ${pb.settingsRepo.load().methodFor('DESALTER')}');
      ok = ok && rep.items == 9 && priced >= 7;
    }
    final cmpPath = a.length > 4 ? a[4] : null;
    if (cmpPath != null && File(cmpPath).existsSync()) {
      final rep = pb.compressorImporter().run(XlsxWorkbook.openFile(cmpPath), fileName: 'compressors');
      final cat = pb.catalog.categoryByCode('COMPRESSOR')!;
      final rows = pb.computeCategory(cat.id);
      final peers = rows.where((r) => r.cmp?.isPeer ?? false).length;
      b.writeln('compressors: ${rep.items}, quotes: ${rep.quotes} (${rep.quotesPriced} priced), '
          'corrections: ${rep.corrections}, dryer links: ${rep.dryerLinks}, peers: $peers');
      ok = ok && rep.items == 10 && rep.quotes == 3 && peers == 4;
    }
    pb.close();
    // باز کردن دوباره: مهاجرت تکراری یا داده‌ی پایه‌ی تکراری نباید رخ دهد
    final again = PriceBank.open(dbPath, await loadSeedAssets());
    b.writeln('reopen users: ${again.users.all().length}, items: ${again.items.count(again.pumpCategory.id)}');
    again.close();
  } catch (e, st) {
    ok = false;
    b.writeln('ERROR: $e\n$st');
  }
  b.writeln(ok ? 'RESULT: OK' : 'RESULT: FAILED');
  await File(out).writeAsBytes(utf8.encode(b.toString()), flush: true);
  exit(ok ? 0 : 1);
}
