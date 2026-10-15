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
