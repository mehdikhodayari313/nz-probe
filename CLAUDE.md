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
  - پایان هر کار/نسخه: یک بخش کوتاه به `price_bank/docs/HISTORY.md` اضافه کن، `docs/claude/OPEN_ITEMS.md` و وضعیت بندهای `APP_CHANGES.md` را به‌روز کن،
    و commit + push روی **main** (نه شاخه‌ی جدا؛ اگر محیط شاخه‌ی جدا ساخت، در main ادغام کن).
- نیازمندی‌های فنی هر رده (مشخصات، ضرایب، روش تعدیل) که کاربر می‌دهد → خلاصه در
  `price_bank/docs/requirements/<CODE>.md` (مثل DESALTER.md، COMPRESSOR.md) تا گفتگوی بعدی بدون تکرار بداند.
- **مسیر ساده (پیش‌فرض کاربر، بدون شیت «خروجی_قطعی»):** کاربر اکسل تخمین را پیوست می‌کند و می‌گوید «بررسی کن».
  1. بررسی: روابط تخمین، دقت، داده‌های پرت، ایرادهای فنی و روش تعدیل پیشنهادی را از اکسل دربیاور؛ کد را تغییر نده؛
     نتیجه را در `docs/requirements/<CODE>.md` با وضعیت «در حال بررسی» ذخیره و push کن (تا گفتگوی بعد ادامه دهد).
  2. وقتی کاربر گفت «نهایی است/اعمال کن»: وضعیت را «قطعی» کن، چند نمونه‌ی واقعی همان اکسل را خودت به‌عنوان
     آزمون (ورودی → قیمت مورد انتظار) در `test/spec/` بگذار، فهرست تغییرات را نشان بده، پس از تأیید اعمال و build کن.
  اکسل واقعی را commit نکن؛ فقط اعداد لازم در md/آزمون‌ها.
- **شاخص‌ها (PPI):** مرجع همه‌ی سری‌ها برای بررسی‌ها `price_bank/docs/data/PPI_all_series_14050803.csv`
  (میلادی + معادل سال شمسی ۰٫۷۹×(Y+621)+۰٫۲۱×(Y+622)، پیش‌بینی ۲۰۲۶–۲۷ با +۲٪).
  نرخ ارز: `docs/data/FX_Iran_monthly_14050801.csv` (ماهانه‌ی دلار/یورو آزاد، نیمایی، رسمی بانک مرکزی، tgju) و
  `docs/data/FX_EUR_tables_14050803.csv` (جدول‌های یوروی آزاد/نیمایی ماهانه و جدول سالانه‌ی مرجع). راهنما: `docs/data/README.md`.
  PPI ایران هنوز در داده‌ها نیست (فقط ۶ سطر قدیمی PPI_IR)؛ استخراجش با Claude است (تصمیم کاربر ۱۴۰۵/۰۸/۰۲). یوروستات از محیط Claude بسته است:
  سری جدید → کد NACE را به `tool/fetch_eurostat.py` اضافه و push کن؛ workflow `pb_indices` نتیجه را در شاخه‌ی
  `ci-pb-indices` می‌گذارد (`eurostat_ppi.json`). سری‌ای که برنامه باید داشته باشد → `lib/core/catalog/eurostat_ppi.dart`
  (هنگام باز شدن برنامه با INSERT OR IGNORE اضافه می‌شود؛ مهاجرت لازم نیست).
- اکسل/بانکی که کاربر برای آزمون می‌دهد: فقط نسخه‌ی کوچک (ورودی‌ها + Test_Cases، بدون فرمول) در `test/fixtures_private/`
  (نمونه: `tool/make_desalter_fixture.py`)؛ فایل کامل commit نشود.
- **همه‌ی استعلام‌های فروشندگان** (قیمت‌دار، بی‌پاسخ، انصراف) برای همه‌ی تجهیزات وارد برنامه می‌شوند، مثل پمپ‌ها.
- پکیجی که چند رده را یکجا قیمت داده (مثل پکیج کامل هوای ابزار دقیق) در همه‌ی رده‌های مربوط دیده شود (یک رکورد، بدون شمارش دوباره).
- `spec/state.json` را دستی ویرایش نکن (فقط اسکریپت).
- فایل‌های واقعی پروژه‌ها محرمانه‌اند؛ مخزن خصوصی است و نباید عمومی شود.
- **قواعد کاربر ۱۴۰۵/۰۸/۰۳ (دائمی):**
  1. توضیح هر بخش (علامت ❗/ⓘ و راهنمای فیلدها) مستقل و بدون ارجاع به بانک قیمت V8 نوشته شود. **V8 را در کل نرم‌افزار فراموش کن**:
     در متن‌های برنامه نامی از V8 نیاید؛ برنامه فقط با MTOها و بانک‌های قیمتی که کاربر می‌دهد کار می‌کند
     (کد داخلی می‌تواند بماند، اما برچسب، راهنما، نام شاخص/منبع مثل FX_USD_V8 و پیام‌ها نه).
  2. هر صفحه یا مرحله‌ای که طراحی/تغییر ظاهری می‌شود: **پیش از نهایی کردن، تصویرش در گفتگو فرستاده شود** و پس از تأیید کاربر اعمال
     شود (تصویر از آزمون ویجت با فونت واقعی Vazirmatn، `matchesGoldenFile`/`toImage`، در scratchpad و SendUserFile).
  3. خواننده‌ی MTO و بانک‌های قیمت باید هر نوع فایل مشابه آنچه تاکنون داده شده — و تغییرات بیشتر از آن — را بخواند
     (بخش «File readers» پایین).
  4. نرخ ارز ماهانه و PPIهای داخل و خارج ایران را کاربر در GitHub به‌روز می‌کند؛ پیش از کار روی شاخص‌ها آخرین نسخه را از
     همان‌جا بخوان (شاخه‌های `ci-pb-fx`، `ci-pb-indices` و هر مسیری که کاربر بگوید).
- **مراجع پروژه در `refs/`** (تصمیم کاربر ۱۴۰۵/۰۷/۲۴): فایل‌های اصلی MTO/PEP، بانک پمپ v8.1، اعتبارسنجی تعدیل، شرح نیاز و اسناد کلیدی؛
  فهرست و شیت‌های مهم هر فایل در `refs/README.md`. برای تصمیم‌های داده‌ای (شمار رکوردها، مبنای قیمت، سال، ضرایب پنهان) اول همین‌جا را ببین.
  این فایل‌ها را به `price_bank/test/fixtures*` کپی نکن و در کد برنامه ارجاع نده؛ آزمون‌ها با فیکسچرهای ناشناس می‌مانند.

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

## Build / test / release (details: `price_bank/docs/claude/BUILD_CI.md`)
- Local first: `cd price_bank && flutter pub get && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test`;
  then `git checkout analysis_options.yaml` and delete `pubspec.lock`. Push to `main` → CI (`ci-pb-test`, `ci-pb-windows`,
  `ci-pb-dist`; check `commit.txt` == pushed SHA). Zip → branch `price-bank-releases` + README row, and SendUserFile in chat.
- Current released version: **0.9.5** (1405/08/03, session 1 + feedback: «نامشخص» filter option, project comparison removed). Bump `pubspec.yaml`, `lib/ui/shell.dart` label and README header per release.
- Commit trailer (always): `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` + `Claude-Session: <session url>`.

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
- Real client files (MTOs, PEPs) are committed **only** under `refs/` (user decision 1405/07/24, see `refs/README.md`), never in `price_bank/`. `test/fixtures_private/` holds the user's v8 bank and
  validation workbook (repo is private). `test/fixtures/*` and `test/fixtures/full/*` are anonymized copies
  (project names replaced, numbers randomized) — regenerate the same way if needed.
- Dart regex `\b` is ASCII-only; Persian word boundaries need `(^|\s)…(\s|$)`.
- **UI libraries (added 1405/08/02, not yet used in pages):** `fl_chart` (charts), `data_table_2` (tables with fixed
  header/columns, sorting), `flex_color_scheme` (themes), `flutter_animate` + `animations` (effects, page/container
  transitions), `lucide_icons_flutter` (icons). Verified in `test/ui_libs_test.dart` (RTL). **Version pins matter:**
  newer flex_color_scheme 9.x, data_table_2 3.x and animations 3.x depend on the new standalone `material_ui`
  package whose `ThemeData`/`DataRow` types differ from `package:flutter/material.dart` → compile errors. Keep
  ^8.4.0 / ^2.8.0 / ^2.2.0 until the whole app migrates to `material_ui`. Using them in pages = UI redesign → show
  the user a mockup/screenshot and get approval first; the no-gradient rule applies to chart/theme options too.
- Bank importers must read **cached values** of input columns: some inputs are formulas (e.g. desalter capacity
  `=ROUND(536*BPD_per_m3h,0)`); skipping formula cells silently lost them.
- The indices page series list is lazy; adding series pushes others off-screen → UI tests must `scrollUntilVisible`.
- `_reparseExisting` fills new template fields only once per template change (app_meta `profile_fields_<CODE>`).

## Code map → `price_bank/docs/claude/CODE_MAP.md` (read the part you need)

## Domain essentials → `price_bank/docs/claude/DOMAIN.md` (escalation methods, settings keys, desalter/compressor decisions, price flow)

## File readers (user 1405/08/02: «very important», a file failed in front of his boss)
- Every MTO/estimate/bank file must load without errors and without dropping any item: raw prices, overhead and other
  coefficients extracted; anything assumed or unmatched goes to the control report (`MtoAnalysis.notes`, bank `report.warnings`),
  never silently skipped. Missing source values = «در منبع وجود نداشت».
- MTO: `mto_generic.dart` `_reconcile` (unit / rate×weight / length / row total), total rows (SUM, NOTES, serial-only,
  formula-less running sum), orphans, overhead column; categories per item in multi-category sheets; SERVICES category for
  installation/civil/mobilization/machinery/salary (not equipment). Reference test: `test/mto_estimate_test.dart`
  (anonymized estimate, formula + values-only copies). New odd file → make an anonymized fixture with
  `tool/make_estimate_fixture.py` and add assertions there.
- **No column may be dropped** (user 1405/08/03, ROTARY «DIFF PRESS.» was lost): every spec that has no template field,
  or whose rule extracted nothing, is stored as an `mto_*` spec field; unheaded data columns, duplicate weight/qty columns
  and extra bank input columns are stored too. Pump ΔP → `diff_pressure_bar`; head inferred ΔP × 10.2 (SG 1) as in the v8 bank.
- Consolidated price bank (one sheet per family + Vendor_Quotes): `price_bank_importer.dart`; it is the reference (same
  category + tag + price elsewhere → archived). Test `test/price_bank_import_test.dart` (+ messy fixture).
- Banks: always map columns through `bank_headers.dart` (`findSheetHeaders`, `BankTable`), never fixed header rows/columns.
  Messy-bank test: `test/bank_flex_test.dart`.


## Open items → `price_bank/docs/claude/OPEN_ITEMS.md` (keep current at the end of every version)

## App change plan → `price_bank/docs/requirements/APP_CHANGES.md` (29 items from the user's Word file, sessions 1–8, status per item)

## Working method that saves tokens
- Read only the files the task touches (use `docs/claude/CODE_MAP.md`). Prefer targeted `grep`/`sed -n` over whole files.
- Make edits with small exact replacements; push once per coherent change; wait for CI; fix; then build.
- Add/extend tests for every behavior change (fixtures are in `test/fixtures`), keep all tests green.
- At the end of each version: update `docs/HISTORY.md` (one short section), `docs/claude/OPEN_ITEMS.md` and item status in `APP_CHANGES.md`.
