<!-- بخشی از CLAUDE.md که برای کم کردن حجم بارگذاری هر جلسه جدا شد (۱۴۰۵/۰۸/۰۳). فقط وقتی لازم است بخوان. -->

## Code map (`price_bank/lib`)
- `core/` (pure Dart, used by tests): `price_bank.dart` (facade: repos, engines, `computeCategory`,
  `bankCategories()` all enabled leaf cats, `estimableCategories()` pump + profiled cats, `backtestCategory`,
  weight ref), `db/` (sqlite3, `migrations.dart`, EAV `item_values`, `price_obs`, `audit_log`),
  `repo/` (catalog, items, docs, indices, settings, users, `seed.dart`, `generic_templates.dart` = enables
  generic categories, creates profile fields, factor seeds, re-parses older MTO items/pumps on startup).
- `core/calc/`: `pump_engine.dart` (v8-exact pump calc, golden-tested on 146 records), `methods.dart`
  (M0–M6 definitions/stats, `MethodFactors`, `methodLabelFor`), `generic_engine.dart` (non-pump escalation),
  `estimator.dart` (pump estimator + transfer calculator), `generic_estimator.dart` (CAP/NEAR/MANUAL,
  config factor incl. optional WEIGHT factor), `backtest.dart` (method accuracy from bank: old price vs quotes),
  `compressor.dart` (air compressor bank = Calc_Spec of Air_Compressor v8: per-compressor NormEsc, estimator A/A2/B/C/E;
  `computeCategory('COMPRESSOR')` puts `GenericRow.cmp`), `desalter.dart` (desalter bank = Calc_Spec of Desalters_Price_Bank v8: factors, NormEsc, Coef A/B, ln-ln fit,
  estimator A/B/C + weighted final; `computeCategory('DESALTER')` uses it and puts `GenericRow.des`).
  `methods.dart` also has M7 composite basket (`MixPart`, `MethodFactors.compositeIndex`, `mixLabel`).
- `core/catalog/profiles.dart`: per-category templates (fields, MTO label rules, size driver + n, factor groups,
  `weightKey`), `parseMtoDescription`, `extractPumpSpecs`, `extractFreeSpecs` (free text like
  "ID=5300 mm, 19.5 bar D.P."), `suggestCategoryFromText` (+priority words), `defaultCategoryMethod` /
  `defaultCategoryMix`, `factorOption(g, v, code:)`; part file `desalter_profile.dart` (desalter fields, Factors_DES
  seeds, lists DES_*, `inferDesalter` from MTO text); part file `compressor_profile.dart` (Factors_CMP seeds, lists CMP_*,
  `inferCompressor`); `us_ppi.dart` (BLS PCU333912 seeded on startup); `eurostat_ppi.dart` (PPI series seeded on startup).
- `core/import/`: `mto_importer.dart` (Pazanan quote-block format + orchestration, `run()` writes items and
  observations, doc info, revision date, filename info), `mto_generic.dart` (any other layout: sheet kind
  items/install/skip, header detection incl. multi-row/merged headers, column roles, multi-row items,
  sections, Kg units, continuation pages, install-sheet weights), `v8_importer.dart`, `desalter_importer.dart`
  (Desalters bank: columns by header text, cached values, vendors/quotes, KPL year correction, MTO duplicates),
  `compressor_importer.dart` (air compressor bank: all quotes incl. no-reply, KPL fix, price-less AIR_DRYER item per IA/PA package).
- `core/xlsx/xlsx_reader.dart`: own xlsx reader (merges, comments, fills).
- `app/app_state.dart`: AppState (revision-cached pumps / genericRows / allRows), AppScope.
- `ui/`: `shell.dart` (sidebar, top bar: target year, FX table, method chip, Rial/Toman, Back button),
  `pages/` (dashboard, indices, methods, equipment + generic_equipment + item pages, estimator +
  generic_estimator_tab + desalter_estimator_tab, factors, documents, history, users, settings), `widgets/` (common, data_grid,
  field_editor, factor_dialog, mto_import_dialog, category_picker), `theme.dart`, `format.dart`.
- Outside `lib/`: `spec/` (Excel «خروجی_قطعی» → `pending/*.json` via `tool/extract_final.py` and the
  `spec_extract` workflow; see Part 1 above), `tool/` (gen_seed, extract_final, make_export_template),
  `docs/HISTORY.md`, `docs/requirements/<CODE>.md` (per-category decisions; DESALTER قطعی, HEX در حال بررسی),
  `docs/data/` (PPI CSV), `tool/fetch_eurostat.py` + `.github/workflows/pb_indices.yml`, `tool/data/` (raw Eurostat JSON),
  `test/fixtures*/` (anonymized MTO fixtures; real client files are never committed).
