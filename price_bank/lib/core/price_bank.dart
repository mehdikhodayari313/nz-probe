// نقطه‌ی ورود هسته: همه‌ی مخزن‌های داده و موتور محاسبات در یک جا.
// این فایل به Flutter وابسته نیست؛ هم در برنامه و هم در آزمون‌ها استفاده می‌شود.

import 'calc/estimator.dart';
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
  GenericRow(this.item, this.result, this.quoteEurTargets);
  final ItemRecord item;
  final GenericCalcResult result;

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

  GenericEngine genericEngine({String? fxType, int? targetYear, String? method}) => GenericEngine(
        seriesSnapshot,
        settingsRepo
            .load()
            .toPumpSettings(fxTypeOverride: fxType, targetYearOverride: targetYear, methodOverride: method),
      );

  static GenericInput genericInputFor(PriceObs? o) => GenericInput(
        unitPrice: o?.amountValue,
        currency: o?.currency,
        costYear: o?.costYearValue,
        costMonth: o?.costMonth,
        sourceFxRate: o?.effectiveSourceFx,
      );

  /// همه‌ی اقلام یک رده‌ی غیرپمپ با محاسبه.
  List<GenericRow> computeCategory(int categoryId, {GenericEngine? engine}) {
    final e = engine ?? genericEngine();
    return [
      for (final it in items.loadCategory(categoryId))
        GenericRow(
          it,
          e.calculate(genericInputFor(it.primary)),
          [
            for (final o in it.observations.where((o) => o.kind == 'quote'))
              if (e.calculate(genericInputFor(o)).eurTarget.number case final v?) v,
          ],
        ),
    ];
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
