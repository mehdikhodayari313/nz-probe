<!-- بخشی از CLAUDE.md که برای کم کردن حجم بارگذاری هر جلسه جدا شد (۱۴۰۵/۰۸/۰۳). فقط وقتی لازم است بخوان. -->

## Domain essentials
- Default escalation **M6** = EU pump PPI (C28.13) + API 610 price floor (pumps S/D only). For non-pump
  categories M6 ≡ M4 with the category's PPI. **User rule: each equipment has its own escalation method** (the
  top-bar/pump method never applies to other categories); M7 = composite PPI basket per category (`cat_mix_<CODE>`).
- Per-category settings keys: `cat_method_<CODE>`, `cat_ppi_<CODE>`, `cat_n_<CODE>`, `cat_est_<CODE>`, `cat_wexp_<CODE>`,
  M5 uses `defaultCategoryUsPpi(code)` (COMPRESSOR = PPI_US_333912_GREG, others pump 333914).
  Compressor params `cmp_n`, `cmp_fit`, `cmp_kw`, `cmp_bench`, `cmp_min_peers`, `cmp_final`.
  `cat_mix_<CODE>` ("PPI_EU_C2529_GREG:0.7;…"; empty = profile default), `cat_mixrule_<CODE>` (Strict | empty =
  Renormalize). `AppSettings.methodFor(code)` = cat_method else `defaultCategoryMethod` (DESALTER M7, others M4).
  Factor sets `PUMP_ROT`, `GEN_<CODE>`.
- Desalter = user's Desalters_Price_Bank v8.x method (docs/requirements/DESALTER.md); the bank file is the reference.
  User decisions: KPL-476 cost year 1394/10 (corrected on import), Pazanan 1393 R02 and 1404 quotes are separate
  records, MTO desalter with same tag base + same amount = duplicate (archived/skipped). Params keys `des_n_a`,
  `des_fit_a`, `des_n_b`, `des_fit_b`, `des_kva_on`, `des_kva_m`, `des_kva_base`, `des_final`. Desalter keeps the
  empty-weight field but no WEIGHT/PRESS factor.
  v0.9.1: Scope fields + project phase are NOT on desalter records (estimator inputs only; user rule: equipment section
  holds only specs relevant to selection). Equipment filters per category via `EquipmentProfile.filterKeys`.
- Price flow: unit price in source currency → EUR at source year (IRR via document source FX if set) → escalate
  EUR → convert with target-year FX table. CPI/rial inflation is NOT used (validation showed ~50% under-estimate).
- Vessel-type empty weight (`empty_weight_kg`) is optional and neutral until ≥2 items of the category have it;
  then WEIGHT factor = (W/size ÷ median)^0.8 replaces the PRESS factor.
- MTO import: duplicate import blocked per (project, document title); same tag in same project+category from a
  previous import is skipped; duplicates inside one file get " (2)" suffix. Unknown category → MISC_PKG;
  summary tables (no tag & no qty) are unticked by default.

## User decisions 1405/08/02 (Word file of 33 points + answers)
1. Some equipment is domestic, some imported → the pricing method needs a manufacture-location option that offers the
   suitable methods for that choice.
2. Only the important methods; do not clutter.
3. Category settings for multi-PPI equipment must be reachable from that equipment's estimator page and from the methods page.
4. Languages last; Persian only for now.
5. Claude must extract the Iranian industry indices (by any means).
6. Classify/optimize electrical, instrumentation and piping like an expert engineer of that discipline.
