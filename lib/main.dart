import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'probe/probe_controller.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // حالت خودآزمایی بدون رابط کاربری (برای خط ساخت خودکار یا واحد IT):
  //   nz_probe.exe --selftest C:\path\report.txt
  // همه‌ی آزمون‌های خودکار اجرا، گزارش ذخیره و برنامه با کد ۰ (موفق) یا ۱ (ناموفق) بسته می‌شود.
  final i = args.indexOf('--selftest');
  if (i >= 0) {
    final out = i + 1 < args.length ? args[i + 1] : 'nz_probe_selftest.txt';
    final c = ProbeController();
    await c.runAll();
    await File(out).writeAsBytes(utf8.encode('\uFEFF${c.buildReport()}'), flush: true);
    exit(c.failedCount == 0 ? 0 : 1);
  }

  runApp(const ProbeApp());
}

class ProbeApp extends StatelessWidget {
  const ProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'سنجش سازگاری — بانک قیمت نمک‌زدایی',
      debugShowCheckedModeBanner: false,
      // زبان فارسی: کل رابط راست‌به‌چپ می‌شود.
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const HomePage(),
    );
  }
}
