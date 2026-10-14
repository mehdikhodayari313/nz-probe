// نقطه‌ی ورود هسته: همه‌ی مخزن‌های داده و موتور محاسبات در یک جا.
// این فایل به Flutter وابسته نیست؛ هم در برنامه و هم در آزمون‌ها استفاده می‌شود.

import 'dart:math' as math;

import 'calc/estimator.dart';
import 'calc/generic_estimator.dart';
import 'catalog/profiles.dart';
import 'calc/generic_engine.dart';
import 'calc/pump_engine.dart';
import 'calc/series.dart';
import 'db/db.dart';
import 'import/mto_importer.dart';
import 'import/v8_importer.dart';
import 'repo/audit.dart';
import 'repo/catalog_repo.dart';
import 'repo/docs_repo.dart';
import 'repo/generic_templates.dart';
import 'repo/indices_repo.dart';
import 'repo/items_repo.dart';
import 'repo/seed.dart';
import 'repo/settings_repo.dart';
import 'repo/users_repo.dart';

class PumpRow {
  const PumpRow(this.item, this.result);
  final ItemRecord item;
  final PumpCalcResult result;
}

/// یک قلم غیرپمپ با نتیجه‌ی محاسبه‌ی قیمت اصلی و آمار استعلام‌ها (همه به یوروی سال هدف).
class GenericRow {
  GenericRow(this.item, this.result, this.quoteEurTargets, {this.size, this.allF = 1, this.coef});
  final ItemRecord item;
  final GenericCalcResult result;

  /// پارامتر اندازه‌ی قالب رده (حجم، توان حرارتی، دبی، …)
  final double? size;

  /// ضریب کل پیکربندی (جنس، NACE، فشار، …)
  final double allF;

  /// ضریب هزینه = یورو نرمال‌شده‌ی تعدیل‌شده ÷ اندازه^n
  final double? coef;

  /// قیمت هر استعلام فروشنده، تعدیل‌شده به یوروی سال هدف
  final List<double> quoteEurTargets;

  int get quoteCount => item.observations.where((o) => o.kind == 'quote').length;
  double? get quoteMin => quoteEurTargets.isEmpty ? null : quoteEurTargets.reduce((a, b) => a < b ? a : b);
  double? get quoteMax => quoteEurTargets.isEmpty ? null : quoteEurTargets.reduce((a, b) => a > b ? a : b);
  double? get quoteAvg =>
      quoteEurTargets.isEmpty ? null : quoteEurTargets.reduce((a, b) => a + b) / quoteEurTargets.length;
}

class PriceBank {
  PriceBank._(this.db) {
    audit = Audit(db, null);
    catalog = CatalogRepo(db);
    items = ItemsRepo(db, audit, catalog);
    docs = DocsRepo(db, audit);
    indices = IndicesRepo(db, audit);
    settingsRepo = SettingsRepo(db, audit);
    users = UsersRepo(db, audit);
  }

  final Db db;
  late final Audit audit;
  late final CatalogRepo catalog;
  late final ItemsRepo items;
  late final DocsRepo docs;
  late final IndicesRepo indices;
  late final SettingsRepo settingsRepo;
  late final UsersRepo users;

  static const pumpFactorSet = 'PUMP_ROT';

  static PriceBank open(String path, SeedData seed) => _init(Db.open(path), seed);

  static PriceBank memory(SeedData seed) => _init(Db.memory(), seed);

  static PriceBank _init(Db db, SeedData seed) {
    seedDatabase(db, seed);
    ensureGenericTemplates(db);
    final pb = PriceBank._(db);
    pb.audit.userId = pb.users.defaultUser().id;
    return pb;
  }

  void close() => db.close();

  V8Importer v8Importer() => V8Importer(db, audit, catalog, items, docs);

  MtoImporter mtoImporter() => MtoImporter(db, audit, catalog, items, docs);

  // ---------------------------------------------------------------------------
  // محاسبات

  MemorySeries? _seriesCache;
  FactorTable? _factorCache;

  /// بعد از هر تغییر در شاخص‌ها یا ضرایب صدا زده شود.
  void invalidateCalc() {
    _seriesCache = null;
    _factorCache = null;
  }

  MemorySeries get seriesSnapshot => _seriesCache ??= indices.snapshot();
  FactorTable get factorTable => _factorCache ??= indices.factorTable(pumpFactorSet);

  PumpEngine pumpEngine({String? fxType, int? targetYear, String? method}) => PumpEngine(
        seriesSnapshot,
        settingsRepo
            .load()
            .toPumpSettings(fxTypeOverride: fxType, targetYearOverride: targetYear, methodOverride: method),
        factorTable,
      );

  /// موتور تعدیل غیرپمپ؛ با [categoryCode] روش و شاخص اختصاصی همان رده اعمال می‌شود.
  GenericEngine genericEngine({String? fxType, int? targetYear, String? method, String? categoryCode}) {
    final st = settingsRepo.load();
    return GenericEngine(
      seriesSnapshot,
      st.toPumpSettings(
        fxTypeOverride: fxType,
        targetYearOverride: targetYear,
        methodOverride: method ?? (categoryCode == null ? null : st.catMethod(categoryCode)),
        ppiOverride: categoryCode == null ? null : st.catPpi(categoryCode),
      ),
    );
  }

  /// توان اندازه‌ی رده (تنظیمات رده، وگرنه پیش‌فرض قالب).
  double exponentOf(String categoryCode) =>
      settingsRepo.load().catExponent(categoryCode) ?? equipmentProfiles[categoryCode]?.driver.n ?? 0.6;

  /// توان ضریب وزن رده (تنظیمات رده، وگرنه ۰٫۸).
  double weightExponentOf(String categoryCode) =>
      settingsRepo.load().catWeightExp(categoryCode) ?? defaultWeightExponent;

  /// میانه‌ی «وزن ÷ اندازه» اقلام فعال رده که وزن دارند (مرجع ضریب وزن)؛ کمتر از دو قلم = null.
  double? weightRefOf(String categoryCode) {
    final p = equipmentProfiles[categoryCode];
    final cat = catalog.categoryByCode(categoryCode);
    if (p?.weightKey == null || cat == null) return null;
    final n = db.scalar(
      "SELECT COUNT(*) FROM item_values v JOIN items i ON i.id = v.item_id "
      "WHERE i.category_id = ? AND i.status = 'active' AND v.field_key = ? AND v.value_num > 0",
      [cat.id, p!.weightKey],
    ) as int;
    if (n < 2) return null;
    return medianWeightDensity(p, items.loadCategory(cat.id).map((it) => it.values));
  }

  GenericEstimator genericEstimator(String categoryCode, {Map<String, double> overrides = const {}, double? weightRef}) {
    final e = genericEngine(categoryCode: categoryCode);
    return GenericEstimator(
      profile: equipmentProfiles[categoryCode]!,
      factors: indices.factorTable(factorSetOf(categoryCode)).withOverrides(overrides),
      n: exponentOf(categoryCode),
      eurRate: e.eurRateTarget,
      usdRate: e.usdRateTarget,
      weightRef: weightRef ?? weightRefOf(categoryCode),
      weightExp: weightExponentOf(categoryCode),
    );
  }

  /// همتاهای تخمین از اقلام محاسبه‌شده‌ی یک رده.
  List<GenericPeer> genericPeers(String categoryCode, List<GenericRow> rows) {
    final est = genericEstimator(categoryCode);
    return [
      for (final r in rows)
        if (r.item.include)
          if (est.peerOf(
            itemId: r.item.id,
            tag: r.item.tag ?? '',
            name: r.item.name,
            project: r.item.projectName ?? '',
            values: r.item.values,
            eurTarget: r.result.eurTarget.number,
          )
              case final p?)
            p,
    ];
  }

  static GenericInput genericInputFor(PriceObs? o) => GenericInput(
        unitPrice: o?.amountValue,
        currency: o?.currency,
        costYear: o?.costYearValue,
        costMonth: o?.costMonth,
        sourceFxRate: o?.effectiveSourceFx,
      );

  /// همه‌ی اقلام یک رده‌ی غیرپمپ با محاسبه.
  List<GenericRow> computeCategory(int categoryId, {GenericEngine? engine}) {
    final cat = catalog.categories().firstWhere((c) => c.id == categoryId);
    final e = engine ?? genericEngine(categoryCode: cat.code);
    final profile = equipmentProfiles[cat.code];
    final all = items.loadCategory(categoryId);
    final est = profile == null
        ? null
        : genericEstimator(cat.code, weightRef: medianWeightDensity(profile, all.map((it) => it.values)));
    final rows = <GenericRow>[];
    for (final it in all) {
      final res = e.calculate(genericInputFor(it.primary));
      double? size, coef;
      var allF = 1.0;
      if (profile != null && est != null) {
        size = profile.sizeOf(it.values);
        allF = est.configFactor(it.values).$1;
        final eur = res.eurTarget.number;
        if (size != null && eur != null) coef = eur / allF / math.pow(size, est.n);
      }
      rows.add(GenericRow(
        it,
        res,
        [
          for (final o in it.observations.where((o) => o.kind == 'quote'))
            if (e.calculate(genericInputFor(o)).eurTarget.number case final v?) v,
        ],
        size: size,
        allF: allF,
        coef: coef,
      ));
    }
    return rows;
  }

  static PumpInput inputFor(ItemRecord item) {
    final o = item.primary;
    return PumpInput(
      spec: item.values,
      unitPrice: o?.amountValue,
      currency: o?.currency,
      costYear: o?.costYearValue,
      costMonth: o?.costMonth,
      sourceFxRate: o?.effectiveSourceFx,
      quantity: item.quantity,
    );
  }

  Category get pumpCategory => catalog.categoryByCode('PUMP')!;

  /// تعداد اقلام فعال هر رده (شناسه‌ی رده ← تعداد)
  Map<int, int> categoryCounts() => {
        for (final r in db.query("SELECT category_id, COUNT(*) AS n FROM items WHERE status = 'active' GROUP BY category_id"))
          r['category_id'] as int: r['n'] as int,
      };

  /// رده‌های قابل تخمین/تعدیل: پمپ + رده‌های دارای قالب تخصصی
  List<Category> estimableCategories() => [
        pumpCategory,
        for (final c in catalog.categories())
          if (c.enabled && equipmentProfiles.containsKey(c.code)) c,
      ];

  List<PumpRow> computePumps({PumpEngine? engine}) {
    final e = engine ?? pumpEngine();
    return [for (final it in items.loadCategory(pumpCategory.id)) PumpRow(it, e.calculate(inputFor(it)))];
  }

  List<PeerRecord> peersFrom(List<PumpRow> rows) => [
        for (final r in rows)
          PeerRecord(
            itemId: r.item.id,
            subCategory: asText(r.item.values['sub_category']),
            family: asText(r.item.values['pump_family']),
            standard: asText(r.item.values['pump_standard']),
            include: r.item.include,
            costCoef: r.result.costCoef.number,
            tag: r.item.tag ?? '',
            name: r.item.name,
          ),
      ];
}
