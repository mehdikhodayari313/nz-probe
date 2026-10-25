# Price Bank — decision & feedback history

Concise log of what was built, why, and what the user asked for. Newest last. Source code is the truth;
this file keeps the reasoning and the user's words that are not visible in code.

## Original brief (phase 1)
Windows app (Flutter, offline, SQLite) as a price bank for desalting-unit equipment. Requirements: MTO import,
search, estimation and escalation, editable data with history, multi-user (roles per discipline), offline,
beautiful UI, help panel on every page. Reference data: `Pumps_Price_Bank_v8.xlsx` (146 pumps, 59 fields;
golden tests reproduce every calculated column) and `Pump_Escalation_Validation_2.xlsx` (14 Pazanan-2 pumps,
1393→1404; basis for method statistics). Default escalation M6; FX tables "جدول پیش‌فرض" (v8), free market, NIMA.

## v0.2
Per-project table (source-year vs target-year totals), FX table renamed to «جدول پیش‌فرض», user-defined FX tables,
methods page (M0–M6), seal filter shows all catalog options, removed confusing KPIs, grid cells centered with
dividers and no "Not stated" text, estimator result order EUR → USD → EUR range → Toman → peer range → total,
editable factors, delete project (typed confirmation + automatic backup), redesign.

## v0.3 / v0.3.1
- Gradients render white on the user's machine → all gradients removed (rule kept forever).
- Menus ordered by the dashboard's 4 steps; methods chart gaps fixed; M4/M6 defined on page.
- Estimator: factor-chip pen moved left, pump efficiency input, labeled total band.
- Rates entered as integer percent (stored /100). Day/night mode + palettes. FX table add/delete on indices page.
- v0.3.1: filter toggle chips made clearly visible.

## v0.4 — MTO import (Pazanan 2 format)
Quote blocks «استعلام N» (source, IRR/EUR/USD, date), GOING UNIT PRICE = consultant estimate (primary),
Unit Price (Rials / FOB €) = previous revision (default 1393/11, FX 40530.8). Gregorian/Excel dates → Jalali,
invalid 2/29 clamped. Generic (non-pump) categories enabled with item pages and price tabs.

## v0.5 — per-category profiles
13 profiles (vessel, tank, HEX, heater, desalter, CIP, deaerator, IGF, filter, flare, compressor, air dryer, crane):
structured fields parsed from MTO text, parametric filters with counts, size driver + exponent n, factor groups
(MAT/NACE/PRESS/LUBE), generic estimator (peer coefficient / nearest peer / manual), category settings
(method, PPI, n, default estimation method). User priority: usability first, specialization second.

## v0.6
- Optional empty weight for vessel-type categories (neutral until ≥2 items have it; WEIGHT factor replaces PRESS).
- Factors page per equipment (only relevant factors + estimation params).
- Dashboard covers all equipment, not just pumps.
- «تخمین تجهیزات» tab (pump + others); transfer calculator has category selector and category-aware methods.
- Item counts next to dropdown options everywhere. Fixed Back button (top bar) restoring page + scroll + filters.

## v0.7
- Dropdown text never truncated (DdText).
- Methods page by equipment category: pumps show validation-file stats; other categories show automatic
  back-test from bank items that have both an old price and newer quotes; method chosen per category.
- Universal MTO/PEP import. Real files analysed (not in repo): KPL printed MTO report (one sheet per category,
  multi-row items, merged cells, continuation pages, INS-* installation sheets with weights, revision table on
  cover), Gachsaran-4 PEP (3-row headers, tag split in two columns, Kg unit × rate, sections with sub-items,
  P.EL/P.IN/P.PI/P.PL/P.LAB, C.* construction sheets with unit weights), Maroon-3 update (mostly group-level
  summary tables → unticked; lab and safety items imported). Column roles and per-item category editable in
  preview; manual header row for unread sheets. New categories: WATER_TREAT, HVAC, FIRE_SAFETY, MISC_PKG; enabled
  LAB, VALVE, PIPE_BULK, ELEC_EQ, INST_EQ. Pumps from MTO get capacity/head/material/standard fields.
- Full-structure anonymized fixtures under `test/fixtures/full` + `mto_full_test.dart` print a per-sheet summary
  into CI `test.txt` (KPL 120 items/16 categories; PEP 1209 items; M3 50 items).
- Build published on branch `price-bank-releases`.

## v0.8 (1405/07/23)
- Desalter bank from user's `Desalters_Price_Bank_v8.1.xlsx` (Calc_Spec/Test_Cases): `core/calc/desalter.dart`
  (factors TECH/MAT/NACE/STAGE/SC_*, KVA_F dormant, NormEsc, Coef A/B, ln-ln fit, estimator A/B/C + weighted final),
  `import/desalter_importer.dart` (Master by header text, vendors, quotes), `ui/pages/desalter_estimator_tab.dart`.
  Golden test vs reduced fixture `test/fixtures_private/Desalters_bank_test.xlsx` (261 values + 2 scenarios, 1e-9).
- User decisions: KPL-476 cost year 1394/10 (bank file says 1393; corrected on import, audited); Pazanan 1404 and
  1393 R02 stay separate records; desalter bank is the reference (MTO desalter with same tag base + same amount is
  archived on bank import and skipped on later MTO import); **each category has its own escalation method**
  (`AppSettings.methodFor`: cat_method_X else `defaultCategoryMethod` — DESALTER M7, others M4; pump method only pumps).
- M7 composite PPI basket (`cat_mix_<CODE>` "SERIES:w;…", `cat_mixrule_<CODE>`=Strict) — Gregorian series blended
  0.79/0.21, null if either year missing; renormalize missing. Eurostat series fetched by CI workflow `pb_indices`
  (branch `ci-pb-indices`): C25.29/C27.11 identical to the workbook; also C27.12, C28.14, C26.51, C25.11 added
  (`catalog/eurostat_ppi.dart`, inserted on startup with INSERT OR IGNORE).
- `_reparseExisting` now fills new template fields once per template change (app_meta `profile_fields_<CODE>`).
- Finding: Pazanan R02 1393 (2.5 M€) escalated to 1404 ≈ 3.41 M€ vs 1404 quotes avg 1.93 M€ (−43%).
- Delivered to user: v0.8 zip (chat + `price-bank-releases`) and `docs/data/PPI_all_series_14050723.csv` (all PPI
  series, Gregorian + Jalali blend, status official/imputed/forecast); later extended by the HEX session.
- User statement: "روش تعدیل هر تجهیز جدا باشه" (each equipment its own escalation method) — standing rule.

## User statements worth remembering
- Templates/parameters for electrical, instrumentation and remaining mechanical equipment will come later; the
  reader must not need rewriting when parameters are added (design: reader → "label: value" specs; profiles map).
- He is working on exact escalation methods per equipment type and will provide them.
- He asked to keep real MTO files off GitHub; anonymized derivatives are used for tests (he may ask to remove).

## Review: air compressor bank v8.2 (1405/07/23)
- Reviewed user's `Air_Compressor_Price_Bank_v8_2.xlsx` (10 records, 4 peers, methods A/A2/B/C/E). No code change.
  FX and C28.13 match the app; BLS PCU333912 missing. Findings and open questions in `docs/requirements/COMPRESSOR.md`.


## 1405/07/23 – HEX price bank (Excel) + PPI series
- PPI CSV: added C28.25, C24/C24.1(≡C24.10), C24.2(≡C24.20), C25.3(≡C25.30, DE chain-linked <2018), C24.42, C24.44 (Eurostat) and US BLS 331110/331210/332410(-1) as check-only alternatives.
- Workflow pb_indices now also runs tool/fetch_bls.py; fetch_eurostat.py fetches group-level and country series.
- HeatExchangers_Price_Bank_v8.1.xlsx built (17 records, basket escalation); H-CAT-OIL moved to heater bank. App code unchanged.

## v0.9 (1405/07/23) — air compressor bank
- User's `Air_Compressor_Price_Bank_v8.2.xlsx` (+ JSON export) implemented exactly (Calc_Spec): `core/calc/compressor.dart`
  (TYPE/STD/ORIGIN/DRV + 8 scope factors, per-compressor NormEsc, Coef A/B, ln-ln fit, estimator A/A2/B/C/E + weighted final),
  `import/compressor_importer.dart`, `catalog/compressor_profile.dart`, `ui/pages/compressor_estimator_tab.dart`.
- User decisions: KPL-476 year 1394/10; **all vendor quotes imported for every equipment** (incl. no-reply/declined, amount
  empty, status in notes); complete IA/PA package shown in COMPRESSOR and as a price-less AIR_DRYER item (estimate +
  reasoning in remarks; price to be entered manually when the dryer bank is built); dryer×receiver×filter scope = 1.53
  (SC_DRY|Y = 1.53/1.071; Excel 1.10); BLS PCU333912 added (`catalog/us_ppi.dart`), M5 uses a per-category US series
  (`defaultCategoryUsPpi`, `MethodFactors.usPpiSeries`).
- Golden test vs reduced fixture (270 Master values + TC1–TC3 at 1e-9 with Excel factors). Smoke test takes a 5th arg (compressor bank).

## v0.9.1 (1405/07/23) — desalter cleanup
- Estimator «سه روش تخمین» table broke in narrow windows (fixed columns ≈ 570 px left 0 px for the method name →
  vertical text). Now: ≥ 720 px table, narrower = two-line rows; peers table scrolls horizontally below 760 px;
  inputs/results side by side only from 1240 px. UI test at 980×720 and 1600×1000.
- User: Scope (transformers, recycle pumps, piping, instruments, customs & transport) and project phase are not
  equipment specs (absent from MTOs or identical for all, irrelevant to selection) → removed from the DESALTER
  template and filters (field_defs cleanup; stored values untouched, all were base = factor 1, so results unchanged).
  They remain estimator inputs («دامنه‌ی قیمت») and factors SC_*. Equipment filters curated like pumps (`filterKeys`).


## 1405/08/02 — Piping/valves consolidated Excel bank (outside the app)
- 31 piping/valve price lists from Final_Piping.zip were merged into one workbook, delivered in two versions (365 and 2016): 2659 items with search, a calculator, an inquiry list and a market-price sheet.
- Escalation uses PPI+FX (v8, free market or NIMA), with base year and base price editable per family and per calculation. The summary is in docs/requirements/PIPING.md.
- Not yet in the app; open item: confirm the base year, since market comparison points to about 1394–95 rather than 1385.

## 1405/08/02 — UI libraries
- User asked to install the best modern UI libraries. Added fl_chart, data_table_2, flex_color_scheme,
  flutter_animate, animations, lucide_icons_flutter (pub.dev 160/160 or 150/160 points, actively maintained;
  rejected: fluent_ui / shadcn_ui = full redesign, syncfusion = commercial license, google_fonts = needs internet).
  Pinned to pre-`material_ui` versions (see CLAUDE.md). No page uses them yet.


## 1405/08/02 — Piping Excel bank: calibration (outside the app)
- Base year, FX table and quantity factor were calibrated against three sources: 15 user project quotes (1405/06/28), Gachsaran-4 PEP (209 matched items) and market prices (842). The chosen setup is the one with the lowest error vs the user quotes (17%): NIMA FX; base year 1388 for all families except GLB 1387, TEE/TRD/CRD 1391, CAP 1396 and FLG 1385; quantity factor off by default.
- New sheets: my quotes, project prices (Gachsaran 4) and base-year calibration. The calculator gained an evidence panel and item selection is now cascading. Details in docs/requirements/PIPING.md; scripts in tool/piping/.

## v0.9.2 (1405/08/02) — flexible file readers (Karanj estimate failed in front of the user's boss)
- MTO/estimate reader (`mto_generic.dart`, `mto_importer.dart`): new column roles rate (€/kg, €/m) and overhead; length/
  total-weight/duration headers are not prices; header merge no longer swallows item rows; desc column = densest text column;
  price fallback/reconcile (`_reconcile`): unit price → row total ÷ qty → rate × weight/length; unit×qty vs total mismatch
  (unit ≤ 1 or far off) → lump sum from row total with warning; length qty → one lot; SUM rows, NOTES rows, serial-only rows and
  formula-less total rows (= running sum) are totals; orphan text+amount outside the desc column → item + note; unheaded unit
  column beside qty; outlier check price vs rate × weight. Control report `MtoAnalysis.notes` (dialog card + document notes):
  cover cross-references, in-sheet totals (✓, × factor), coefficient sheets (Insurance), row overheads, letter revisions (REV. C;
  latest dated revision used with a note).
- Categories: per-item choice in multi-category sheets (`sheetCategoryCandidates`), new category SERVICES
  («ساختمان، سازه، نصب و خدمات») + `serviceCategoryFromText` (head noun only: «HVAC for Accommodation» stays HVAC);
  packages in vessel/tank sheets keep their own category; INST words (F&G, BMS, metering, sampling, CCR), ELEC (power, MCC, …).
- Banks: `bank_headers.dart` (normalized/unit-less/synonym/token header matching, header row and sheet found automatically,
  missing columns reported, «در منبع وجود نداشت» in remarks for key fields, shared Vendor_Register import, `BankTable` for
  quotes); compressor, desalter and v8 importers use it (v8 maps fields by label_en, letter fallback only if that header is empty).
- Tests: `mto_estimate_test.dart` (anonymized estimate, formula and values-only copies: 120 items, prices, categories,
  totals), `bank_flex_test.dart` (messy compressor/desalter banks = reference). Tools: `make_estimate_fixture.py`,
  `make_messy_bank_fixture.py`.
- Spec extraction (user asked: aggregated specs with units): «ID x T/T: 800mm x 2350 mm» / «ID x HEIGHT» pairs, two-level
  headers («TEMP./DESIGN (MAX)», «PRESS./DESIGN (BARG)») → design temp/pressure, «DIMENSION» → ID/TL, «TUBE/BATH: 16/3.5»
  → coil/shell, «200 SM3/HR», stack «16" & 8"» / «10000 mm», HEX type; fixed «Overhead» read as pump head, −0.005 bar as full
  vacuum, numeric REMARKS as scope, «#NAME?» and «_» placeholders.
- User decisions recorded (CLAUDE.md): domestic/foreign manufacture option with suitable methods; only important methods;
  multi-PPI category settings in the estimator and methods pages; Persian only for now; Iranian industry indices to be extracted
  by Claude; expert classification of electrical/instrument/piping.

## v0.9.3 (1405/08/03) — no source column is lost
- User: ROTARY «DIFF PRESS.» was not stored. Cause: pump specs were stored only when a template field existed; everything
  else stayed in the remarks text. Now: pump field `diff_pressure_bar` (ensured on startup, sort next to head); diff head
  inferred ΔP × 10.2 (SG 1, field_meta inferred, same rule as the v8 bank) when the source has no head; one-time backfill
  for earlier MTO pumps (`pump_diff_pressure_v1`).
- Same class of bugs fixed: unmapped pump specs → `mto_*` spec fields; non-pump specs whose rule matched but extracted
  nothing (`EquipmentProfile.leftovers`) are kept as spec fields (also on startup re-parse); unheaded data columns
  (`_unheaded`: unit beside qty, unit price when qty × col = row total, else «ستون X»); second weight/qty column and
  ratio/%/avg price columns → spec instead of ignored; bank importers store extra non-formula input columns as spec
  fields and report them (`extraInputColumns`, `storeExtraColumns`). Tests extended (pump ΔP/head/meta, unheaded
  columns, extra bank column «Site Altitude (m)» in messy fixtures).

## v0.9.4 (1405/08/03) — session 1 of APP_CHANGES (#2f, #6, #20)
- #2f: filter dropdowns (pumps `equipment_page`, other categories `generic_equipment`, project filter) count with
  `countValues` (common.dart) and offer «خالی (در منبع نیست)» / «بدون پروژه» (`kEmptyOption`); each filter's counts are
  faceted on the other active filters, so «همه» = shown rows = sum of options. Test `docs_counts_test.dart`.
- #6: `price_bank_importer.dart` reads the user's consolidated bank (PriceBank_Desalting: one sheet per family + Vendor_Quotes):
  family sheet = header row with name/tag + unit price + cost year + RID/Record Type (found anywhere, fuzzy headers);
  category from title code/sheet name/item name; columns → category fields (labelEn, key, `_fieldSynonyms`), other
  technical columns through the category's MTO rules (`profile.extract`/`extractPumpSpecs`), leftovers → spec fields;
  computed bank columns skipped; Record Type/Parent Package kept (package tree #22); month → cost_month; doc FX → source fx;
  all quotes by Linked RID (deduped); re-import skips existing RIDs. User decision: bank is the reference → active item
  of the same category + tag + price from another source is archived. Dashboard dispatch first; card/dialog texts
  without V8. Fixtures `PriceBank_test.xlsx` (+ messy) via `tool/make_pricebank_fixture.py` / `make_messy_pricebank_fixture.py`.
  Piping bank (2656 items) deferred to session 4 (user).
- #20: `DocsRepo.deleteDocument` (prices of the doc + its «قیمت‌های بازنگری قبلی» doc; items left without any price
  removed; backup + typed confirmation in UI), `sameTitle`/`normTitle` (same doc with extension/punctuation/longer title),
  `ensureDocument` dedupes, one-time `mergeDuplicateDocuments` on startup (`docs_merged_v1`), `sourceDocumentCount`
  (no auxiliary docs, one doc shared by several projects counted once) on documents page and dashboard.
  User decision (option A): counts are exact without duplicates; each document listed under its project.

