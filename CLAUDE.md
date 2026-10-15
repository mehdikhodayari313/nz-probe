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

## Code map (`price_bank/lib`)
- `core/` (pure Dart, used by tests): `price_bank.dart` (facade: repos, engines, `computeCategory`,
  `bankCategories()` all enabled leaf cats, `estimableCategories()` pump + profiled cats, `backtestCategory`,
  weight ref), `db/` (sqlite3, `migrations.dart`, EAV `item_values`, `price_obs`, `audit_log`),
  `repo/` (catalog, items, docs, indices, settings, users, `seed.dart`, `generic_templates.dart` = enables
  generic categories, creates profile fields, factor seeds, re-parses older MTO items/pumps on startup).
- `core/calc/`: `pump_engine.dart` (v8-exact pump calc, golden-tested on 146 records), `methods.dart`
  (M0–M6 definitions/stats, `MethodFactors`, `methodLabelFor`), `generic_engine.dart` (non-pump escalation),
  `estimator.dart` (pump estimator + transfer calculator), `generic_estimator.dart` (CAP/NEAR/MANUAL,
  config factor incl. optional WEIGHT factor), `backtest.dart` (method accuracy from bank: old price vs quotes).
- `core/catalog/profiles.dart`: per-category templates (fields, MTO label rules, size driver + n, factor groups,
  `weightKey`), `parseMtoDescription`, `extractPumpSpecs`, `extractFreeSpecs` (free text like
  "ID=5300 mm, 19.5 bar D.P."), `suggestCategoryFromText` (+priority words).
- `core/import/`: `mto_importer.dart` (Pazanan quote-block format + orchestration, `run()` writes items and
  observations, doc info, revision date, filename info), `mto_generic.dart` (any other layout: sheet kind
  items/install/skip, header detection incl. multi-row/merged headers, column roles, multi-row items,
  sections, Kg units, continuation pages, install-sheet weights), `v8_importer.dart`.
- `core/xlsx/xlsx_reader.dart`: own xlsx reader (merges, comments, fills).
- `app/app_state.dart`: AppState (revision-cached pumps / genericRows / allRows), AppScope.
- `ui/`: `shell.dart` (sidebar, top bar: target year, FX table, method chip, Rial/Toman, Back button),
  `pages/` (dashboard, indices, methods, equipment + generic_equipment + item pages, estimator +
  generic_estimator_tab, factors, documents, history, users, settings), `widgets/` (common, data_grid,
  field_editor, factor_dialog, mto_import_dialog, category_picker), `theme.dart`, `format.dart`.
- Outside `lib/`: `spec/` (Excel «خروجی_قطعی» → `pending/*.json` via `tool/extract_final.py` and the
  `spec_extract` workflow; see Part 1 above), `tool/` (gen_seed, extract_final, make_export_template),
  `docs/HISTORY.md`, `test/fixtures*/` (anonymized MTO fixtures; real client files are never committed).

## Domain essentials
- Default escalation **M6** = EU pump PPI (C28.13) + API 610 price floor (pumps S/D only). For non-pump
  categories M6 ≡ M4 with the category's PPI. Per-category settings keys: `cat_method_<CODE>`, `cat_ppi_<CODE>`,
  `cat_n_<CODE>`, `cat_est_<CODE>`, `cat_wexp_<CODE>`. Factor sets `PUMP_ROT`, `GEN_<CODE>`.
- Price flow: unit price in source currency → EUR at source year (IRR via document source FX if set) → escalate
  EUR → convert with target-year FX table. CPI/rial inflation is NOT used (validation showed ~50% under-estimate).
- Vessel-type empty weight (`empty_weight_kg`) is optional and neutral until ≥2 items of the category have it;
  then WEIGHT factor = (W/size ÷ median)^0.8 replaces the PRESS factor.
- MTO import: duplicate import blocked per (project, document title); same tag in same project+category from a
  previous import is skipped; duplicates inside one file get " (2)" suffix. Unknown category → MISC_PKG;
  summary tables (no tag & no qty) are unticked by default.

## Open items / next steps (keep this list current)
1. User will send requirements for electrical, instrumentation and remaining mechanical templates. Add profiles
   in `profiles.dart`, and change `_reparseExisting` so it also fills **new** fields of items that already have
   some profile values (from stored `mto_description`), so no re-import is needed.
2. User is preparing exact escalation methods per equipment type → plug into the methods page / per-category
   method lists (`PriceBank.genericMethodCodes`, `methodLabelFor`).
3. Ask the user to confirm: KPL price year (taken from cover revision R03 = JAN 2016 → 1394/10), Gachsaran PEP
   year (from filename 1402/05), and whether Gachsaran pump "x bar" is discharge or differential pressure.
4. Possibly a web version (user asked "web app"; current app is Windows-only) — only if he confirms.

## Working method that saves tokens
- Read only the files the task touches (use the code map). Prefer targeted `grep`/`sed -n` over whole files.
- Make edits with small exact replacements; push once per coherent change; wait for CI; fix; then build.
- Add/extend tests for every behavior change (fixtures are in `test/fixtures`), keep all tests green.
- At the end of each version: update `docs/HISTORY.md` (one short section) and the open-items list above.
