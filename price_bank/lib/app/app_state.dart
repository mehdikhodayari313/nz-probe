import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../core/price_bank.dart';
import '../core/repo/seed.dart';
import '../core/repo/settings_repo.dart';
import '../core/repo/users_repo.dart';
import '../ui/format.dart';

/// بارگذاری داده‌های پایه از assets.
Future<SeedData> loadSeedAssets() async {
  Future<Map<String, dynamic>> j(String n) async =>
      jsonDecode(await rootBundle.loadString('assets/seed/$n')) as Map<String, dynamic>;
  return SeedData(
    lists: await j('lists.json'),
    pumpTemplate: await j('pump_template.json'),
    factors: await j('factors.json'),
    indices: await j('indices.json'),
    settings: await j('settings.json'),
  );
}

/// محل پیش‌فرض دیتابیس: پوشه‌ی داده‌ی برنامه‌ی کاربر.
Future<String> defaultDbPath() async {
  final dir = await getApplicationSupportDirectory();
  return '${dir.path}${Platform.pathSeparator}price_bank.db';
}

/// وضعیت سراسری برنامه. هر تغییری در داده، [revision] را بالا می‌برد تا صفحه‌ها دوباره بخوانند.
class AppState extends ChangeNotifier {
  AppState(this.pb) {
    _reloadSettings();
    user = pb.users.defaultUser();
  }

  final PriceBank pb;
  late AppSettings settings;
  late AppUser user;
  int revision = 0;

  MoneyUnit get unit => moneyUnitFrom(settings.displayUnit);

  void _reloadSettings() => settings = pb.settingsRepo.load();

  /// بعد از هر ویرایش داده صدا زده شود.
  void dataChanged({bool calcInputs = false}) {
    if (calcInputs) pb.invalidateCalc();
    _reloadSettings();
    revision++;
    notifyListeners();
  }

  void setSetting(String key, String? value, {String? reason}) {
    pb.settingsRepo.set(key, value, reason: reason);
    dataChanged(calcInputs: true);
  }

  void toggleUnit(MoneyUnit u) => setSetting('display_unit', u == MoneyUnit.toman ? 'IRT' : 'IRR');

  bool canEdit(String discipline) => pb.users.canEdit(user, discipline);

  // کش محاسبه‌ی رده‌های غیرپمپ برای همان revision
  int _genRev = -1;
  final Map<int, List<GenericRow>> _gen = {};
  List<GenericRow> genericRows(int categoryId) {
    if (_genRev != revision) {
      _gen.clear();
      _genRev = revision;
    }
    return _gen[categoryId] ??= pb.computeCategory(categoryId);
  }

  // کش محاسبه‌ی پمپ‌ها برای همان revision
  int _pumpRev = -1;
  List<PumpRow> _pumps = const [];
  List<PumpRow> get pumps {
    if (_pumpRev != revision) {
      _pumps = pb.computePumps();
      _pumpRev = revision;
    }
    return _pumps;
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<AppScope>()!.widget as AppScope).notifier!;
}
