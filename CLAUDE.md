# راهنمای Claude برای این مخزن

پاسخ‌ها به فارسی. کاربر مهندس است، نه برنامه‌نویس: خلاصه، دقیق، بدون جزئیات فنی غیرلازم.
برنامه‌ی اصلی در `price_bank/` است (Flutter، ویندوز، آفلاین). ریشه‌ی مخزن برنامه‌ی آزمایشی قدیمی (probe) است.

## ارتقای برنامه از نتایج اکسل (کار تکراری اصلی)

درخواست معمول: «موارد pending را اعمال کن».

1. **فقط** `price_bank/spec/pending/*.json` را بخوان. هر سطر یک تغییر کامل است
   (مقدار، فرمول، مقدار سلول‌های ارجاعی، جدول، ورودی‌ها/خروجی آزمون).
   - اکسل‌های `spec/inbox/` و `test/fixtures*/` را باز نکن؛ همه‌ی لازم در json هست.
   - اگر کاربر اکسل را در گفتگو پیوست کرد: `cd price_bank && python3 -I tool/extract_final.py <فایل>`
     و بعد همان json ساخته‌شده را بخوان.
   - فایل‌های بزرگ کد را کامل نخوان؛ با Grep روی کد/عنوان/گزینه جای مصرف را پیدا کن و فقط همان بخش را بخوان.
2. پیش از تغییر کد، فهرست کوتاه «چه چیزی کجا عوض می‌شود» را به کاربر نشان بده و تأیید بگیر —
   مخصوصاً برای `removed`، هر هشدار json، و هر تغییری که آزمون‌های v8 موجود را می‌شکند.
3. محل اعمال (با Grep تأیید کن):
   - ضریب پمپ → `price_bank/assets/seed/factors.json` (و `tool/gen_seed.py` اگر از v8 تولید می‌شود)
   - ضریب/پارامتر سایر رده‌ها → `lib/core/catalog/profiles.dart`، `lib/core/calc/generic_engine.dart`
   - روش تعدیل و ضرایب روش‌ها → `lib/core/calc/methods.dart`؛ موتور پمپ → `lib/core/calc/pump_engine.dart`
   - شاخص‌ها و نرخ‌ها → `assets/seed/indices.json`
   - داده‌ی seed روی دیتابیس موجود کاربر اثر نمی‌گذارد مگر با مهاجرت: `lib/core/db/migrations.dart` (شماره‌ی جدید، بدون حذف داده‌ی کاربر)
4. هر ردیف «آزمون» یک آزمون خودکار می‌شود در `price_bank/test/spec/` که مقدار json را با خروجی موتور مقایسه کند
   (تلورانس نسبی 1e-9 مگر خلاف آن در json آمده باشد). فرمول بدون آزمون را با `value` خود json آزمون کن.
5. پایان: json و md را از `spec/pending/` به `spec/applied/` منتقل کن و نام نسخه‌ی برنامه را به ابتدای md اضافه کن؛
   نسخه را در `pubspec.yaml` و بخش نسخه‌ها در `price_bank/README.md` بالا ببر؛ commit و push روی main.
   ساخت و آزمون‌ها در GitHub Actions (`price_bank.yml`) اجرا می‌شود؛ نتیجه در شاخه‌ی `ci-pb-test`.
   zip ویندوز را کنار نسخه‌های قبلی در شاخه‌ی `price-bank-releases` بگذار.

## قواعد
- **حافظه‌ی پروژه همین فایل است** (در Claude Code تحت وب جای دیگری برای دستورالعمل نیست). بدون اینکه کاربر بخواهد:
  - هر دستور یا ترجیح دائمی که کاربر در گفتگو می‌گوید («از این به بعد…»، «همیشه…»، قاعده‌ی محاسبه، تصمیم طراحی)
    را همان موقع در این فایل (بخش مناسب) ثبت کن.
  - پایان هر کار/نسخه: یک بخش کوتاه به `price_bank/docs/HISTORY.md` اضافه کن، «Open items» را به‌روز کن،
    و commit + push روی **main** (نه شاخه‌ی جدا؛ اگر محیط شاخه‌ی جدا ساخت، در main ادغام کن).
- نیازمندی‌های فنی هر رده (مشخصات، ضرایب، روش تعدیل) که کاربر می‌دهد → خلاصه در
  `price_bank/docs/requirements/<CODE>.md` (مثل DESALTER.md، COMPRESSOR.md) تا گفتگوی بعدی بدون تکرار بداند.
- **مسیر ساده (پیش‌فرض کاربر، بدون شیت «خروجی_قطعی»):** کاربر اکسل تخمین را پیوست می‌کند و می‌گوید «بررسی کن».
  1. بررسی: روابط تخمین، دقت، داده‌های پرت، ایرادهای فنی و روش تعدیل پیشنهادی را از اکسل دربیاور؛ کد را تغییر نده؛
     نتیجه را در `docs/requirements/<CODE>.md` با وضعیت «در حال بررسی» ذخیره و push کن (تا گفتگوی بعد ادامه دهد).
  2. وقتی کاربر گفت «نهایی است/اعمال کن»: وضعیت را «قطعی» کن، چند نمونه‌ی واقعی همان اکسل را خودت به‌عنوان
     آزمون (ورودی → قیمت مورد انتظار) در `test/spec/` بگذار، فهرست تغییرات را نشان بده، پس از تأیید اعمال و build کن.
  اکسل واقعی را commit نکن؛ فقط اعداد لازم در md/آزمون‌ها.
- **شاخص‌ها (PPI):** مرجع همه‌ی سری‌ها برای بررسی‌ها `price_bank/docs/data/PPI_all_series_14050723.csv`
  (میلادی + معادل سال شمسی ۰٫۷۹×(Y+621)+۰٫۲۱×(Y+622)، پیش‌بینی ۲۰۲۶–۲۷ با +۲٪). یوروستات از محیط Claude بسته است:
  سری جدید → کد NACE را به `tool/fetch_eurostat.py` اضافه و push کن؛ workflow `pb_indices` نتیجه را در شاخه‌ی
  `ci-pb-indices` می‌گذارد (`eurostat_ppi.json`). سری‌ای که برنامه باید داشته باشد → `lib/core/catalog/eurostat_ppi.dart`
  (هنگام باز شدن برنامه با INSERT OR IGNORE اضافه می‌شود؛ مهاجرت لازم نیست).
- اکسل/بانکی که کاربر برای آزمون می‌دهد: فقط نسخه‌ی کوچک (ورودی‌ها + Test_Cases، بدون فرمول) در `test/fixtures_private/`
  (نمونه: `tool/make_desalter_fixture.py`)؛ فایل کامل commit نشود.
- **همه‌ی استعلام‌های فروشندگان** (قیمت‌دار، بی‌پاسخ، انصراف) برای همه‌ی تجهیزات وارد برنامه می‌شوند، مثل پمپ‌ها.
- پکیجی که چند رده را یکجا قیمت داده (مثل پکیج کامل هوای ابزار دقیق) در همه‌ی رده‌های مربوط دیده شود (یک رکورد، بدون شمارش دوباره).
- `spec/state.json` را دستی ویرایش نکن (فقط اسکریپت).
- فایل‌های واقعی پروژه‌ها محرمانه‌اند؛ مخزن خصوصی است و نباید عمومی شود.

---

# بخش ۲ (English) — Desalting Price Bank (read this first)

The active project is **`price_bank/`** (Flutter Windows desktop app). The root-level `lib/`, `pubspec.yaml`,
`build_*.bat` belong to an older unrelated app — do not touch them.
Full decision history and user feedback: `price_bank/docs/HISTORY.md` (read only when you need background).

## User
- Mafi, power-plant/mechanical engineer at NISOC (oil desalting unit projects). Writes and reads **Persian**.
- Reply in Persian, short and concrete: what changed, what to check, what (if anything) the user must do.
  No step recaps, no code dumps. Deliver every new build as a zip in chat (SendUserFile) — GitHub is often
  unreachable from the user's network.
- Priorities he set: usability first, domain correctness second. Do not change things he did not ask for
  ("به هیچ چیز دیگه دست نزن" was said more than once). Ask before large redesigns.

## App in one paragraph
Offline Windows price bank for desalting-unit equipment: import consultant MTO/PEP Excel files and the v8 pump
bank, store items with full technical specs and every price observation (consultant estimate, vendor quotes,
previous-revision price), escalate prices to a target year (EUR-based methods M0–M6 + FX tables), parametric
search per equipment category, estimate new equipment from peers, multi-user with audit history. RTL Persian
UI (Vazirmatn), Rial/Toman toggle, light/dark + 6 palettes.

## Build / test (no local Flutter — CI only)
- pub.dev and storage.googleapis are blocked in the sandbox. **Every check runs in GitHub Actions**
  (`.github/workflows/price_bank.yml`): Linux analyze + `flutter test`, then Windows build + exe smoke test.
- Push to `main` (paths `price_bank/**`) triggers CI. Results are pushed to branches (artifact download is blocked):
  - `ci-pb-test`: `commit.txt`, `analyze.txt`, `test.txt`
  - `ci-pb-windows`: `smoke.txt` (`RESULT: OK`)
  - `ci-pb-dist`: `price_bank_windows.zip` + `commit.txt`
  Read with `git clone -q --depth 1 -b <branch> https://github.com/mehdikhodayari313/nz-probe <dir>`;
  check `commit.txt` == pushed SHA (test ≈4 min, Windows build ≈8–10 min after push).
- Quick failure scan: `grep -E " error |warning" analyze.txt; grep -n "\[E\]\|All tests\|Some tests" test.txt`.
- `gh` works in the sandbox (`gh run list/view/rerun`). Two pushes a few minutes apart run in parallel and both
  force-push the ci-pb-* branches; the OLDER run can finish last. Always compare `commit.txt` with the released SHA;
  if it differs, `gh run rerun <run-id>` of the final commit before taking the zip.
- Exe smoke test: `price_bank.exe --smoke <report> <db> [pumps v8 xlsx] [desalter bank xlsx]` (CI passes both
  fixtures; expects 146 pumps and 9 desalters).
- Current released version: **0.8** (1405/07/23, commit 852156f; zip on `price-bank-releases`).
- Releases/tags cannot be created from Claude sessions (403). Published builds live on branch
  **`price-bank-releases`** (`price_bank_vX.Y_windows.zip` + README table) — add each new version there.
- Commit trailer (always):
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` + `Claude-Session: <session url>`.
- Bump the version label in `lib/ui/shell.dart` (`نسخه‌ی ۰٫X · آفلاین`) and the README header per release.

## Hard-won rules (breaking these caused real bugs)
- **No gradients anywhere** — they render white on the user's GPU (blank sidebar). Solid colors + BoxShadow only.
- `AppColors.*` (petrol, navy, amberSoft, headerBg, zebra, strong, …) are **mutable getters** set by
  `AppColors.apply(palette, dark:)`; never use them in `const` expressions. Const-safe: amber, eur, usd, irr.
- Dropdown items use `DdText` / `CountedLabel` (common.dart) + `itemHeight: null` + `isExpanded: true`:
  full wrapped text in the open menu, one line + tooltip in the field. `menuWidth` does NOT exist in this
  Flutter version. Item-filter dropdowns show item counts (`CountedLabel`).
- Shell keeps visited pages alive (Offstage stack + history) for the fixed Back button; each page is wrapped in
  `PrimaryScrollController.none`. Widget-tree structure of a page must not change between active/inactive.
- Tests: lazy ListViews need `scrollUntilVisible`/`dragUntilVisible`; scope `find.byType(Scrollable)` with
  `find.ancestor(...)` (the sidebar is also a Scrollable). `EquipmentPage.selectedCategory` is static and
  persists across UI tests.
- Real client files (MTOs, PEPs) are **never** committed. `test/fixtures_private/` holds the user's v8 bank and
  validation workbook (repo is private). `test/fixtures/*` and `test/fixtures/full/*` are anonymized copies
  (project names replaced, numbers randomized) — regenerate the same way if needed.
- Dart regex `\b` is ASCII-only; Persian word boundaries need `(^|\s)…(\s|$)`.
- Bank importers must read **cached values** of input columns: some inputs are formulas (e.g. desalter capacity
  `=ROUND(536*BPD_per_m3h,0)`); skipping formula cells silently lost them.
- The indices page series list is lazy; adding series pushes others off-screen → UI tests must `scrollUntilVisible`.
- `_reparseExisting` fills new template fields only once per template change (app_meta `profile_fields_<CODE>`).

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
  `desalter.dart` (desalter bank = Calc_Spec of Desalters_Price_Bank v8: factors, NormEsc, Coef A/B, ln-ln fit,
  estimator A/B/C + weighted final; `computeCategory('DESALTER')` uses it and puts `GenericRow.des`).
  `methods.dart` also has M7 composite basket (`MixPart`, `MethodFactors.compositeIndex`, `mixLabel`).
- `core/catalog/profiles.dart`: per-category templates (fields, MTO label rules, size driver + n, factor groups,
  `weightKey`), `parseMtoDescription`, `extractPumpSpecs`, `extractFreeSpecs` (free text like
  "ID=5300 mm, 19.5 bar D.P."), `suggestCategoryFromText` (+priority words), `defaultCategoryMethod` /
  `defaultCategoryMix`, `factorOption(g, v, code:)`; part file `desalter_profile.dart` (desalter fields, Factors_DES
  seeds, lists DES_*, `inferDesalter` from MTO text); `eurostat_ppi.dart` (PPI series seeded on startup).
- `core/import/`: `mto_importer.dart` (Pazanan quote-block format + orchestration, `run()` writes items and
  observations, doc info, revision date, filename info), `mto_generic.dart` (any other layout: sheet kind
  items/install/skip, header detection incl. multi-row/merged headers, column roles, multi-row items,
  sections, Kg units, continuation pages, install-sheet weights), `v8_importer.dart`, `desalter_importer.dart`
  (Desalters bank: columns by header text, cached values, vendors/quotes, KPL year correction, MTO duplicates).
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

## Domain essentials
- Default escalation **M6** = EU pump PPI (C28.13) + API 610 price floor (pumps S/D only). For non-pump
  categories M6 ≡ M4 with the category's PPI. **User rule: each equipment has its own escalation method** (the
  top-bar/pump method never applies to other categories); M7 = composite PPI basket per category (`cat_mix_<CODE>`).
- Per-category settings keys: `cat_method_<CODE>`, `cat_ppi_<CODE>`, `cat_n_<CODE>`, `cat_est_<CODE>`, `cat_wexp_<CODE>`,
  `cat_mix_<CODE>` ("PPI_EU_C2529_GREG:0.7;…"; empty = profile default), `cat_mixrule_<CODE>` (Strict | empty =
  Renormalize). `AppSettings.methodFor(code)` = cat_method else `defaultCategoryMethod` (DESALTER M7, others M4).
  Factor sets `PUMP_ROT`, `GEN_<CODE>`.
- Desalter = user's Desalters_Price_Bank v8.x method (docs/requirements/DESALTER.md); the bank file is the reference.
  User decisions: KPL-476 cost year 1394/10 (corrected on import), Pazanan 1393 R02 and 1404 quotes are separate
  records, MTO desalter with same tag base + same amount = duplicate (archived/skipped). Params keys `des_n_a`,
  `des_fit_a`, `des_n_b`, `des_fit_b`, `des_kva_on`, `des_kva_m`, `des_kva_base`, `des_final`. Desalter keeps the
  empty-weight field but no WEIGHT/PRESS factor.
- Price flow: unit price in source currency → EUR at source year (IRR via document source FX if set) → escalate
  EUR → convert with target-year FX table. CPI/rial inflation is NOT used (validation showed ~50% under-estimate).
- Vessel-type empty weight (`empty_weight_kg`) is optional and neutral until ≥2 items of the category have it;
  then WEIGHT factor = (W/size ÷ median)^0.8 replaces the PRESS factor.
- MTO import: duplicate import blocked per (project, document title); same tag in same project+category from a
  previous import is skipped; duplicates inside one file get " (2)" suffix. Unknown category → MISC_PKG;
  summary tables (no tag & no qty) are unticked by default.

## Open items / next steps (keep this list current)
1. User will send requirements for electrical, instrumentation and remaining mechanical templates. Add profiles
   in `profiles.dart` (new fields of existing MTO items are filled once automatically on startup).
2. Escalation per equipment type: each category has its own method (`methodFor`, default M4; DESALTER M7 composite).
   User may send exact methods/baskets per type → `defaultCategoryMethod` / `defaultCategoryMix` in profiles.dart.
3. HEX (heat exchangers): draft in `docs/requirements/HEX.md` (در حال بررسی) — proposed C28.25 + optional M7 baskets
   (C24.1 steel, C24.44 copper, C24.42 aluminium); fired heater → HEATER. Those series are only in the PPI CSV /
   `tool/data/eurostat_ppi_20261015b.json`, NOT yet in the app (`eurostat_ppi.dart`) — add when the user approves.
4. Desalter (docs/requirements/DESALTER.md): kVA per transformer, CSV record year, calibration of Factors_DES and
   basket weights are still Provisional. Finding to discuss: Pazanan 1393 estimate escalated ≈3.41 M€ vs 1404 quotes
   1.93 M€ (−43%). Gachsaran PEP year (1402/05) and pump "x bar" meaning still unconfirmed.
5. Air compressor bank (docs/requirements/COMPRESSOR.md): FINAL (user decisions in md: KPL 1394/10, all quotes,
   IA/PA package in COMPRESSOR + AIR_DRYER, BLS PCU333912 + method E). Waiting user OK on package/dryer report, then implement.
6. Possibly a web version (user asked "web app"; current app is Windows-only) — only if he confirms.

## Working method that saves tokens
- Read only the files the task touches (use the code map). Prefer targeted `grep`/`sed -n` over whole files.
- Make edits with small exact replacements; push once per coherent change; wait for CI; fix; then build.
- Add/extend tests for every behavior change (fixtures are in `test/fixtures`), keep all tests green.
- At the end of each version: update `docs/HISTORY.md` (one short section) and the open-items list above.
