<!-- بخشی از CLAUDE.md که برای کم کردن حجم بارگذاری هر جلسه جدا شد (۱۴۰۵/۰۸/۰۳). فقط وقتی لازم است بخوان. -->

## Open items / next steps (keep this list current)
1. User will send requirements for electrical, instrumentation and remaining mechanical templates. Add profiles
   in `profiles.dart` (new fields of existing MTO items are filled once automatically on startup).
2. Escalation per equipment type: each category has its own method (`methodFor`, default M4; DESALTER M7 composite).
   User may send exact methods/baskets per type → `defaultCategoryMethod` / `defaultCategoryMix` in profiles.dart.
3. HEX (heat exchangers): Excel bank `HeatExchangers_Price_Bank_v8.1` built (docs/requirements/HEX.md, در حال بررسی): per-sub-category
   PPI basket (C28.25; STE 70/15/15 with C24.10≡C24.1 & C24.20≡C24.2; ACH 85/15 Al; CIP C28.13), weights editable. C25.30≡C25.3
   (DE chain-linked <2018). Series only in the PPI CSV / `tool/data/eurostat_ppi_20261015c.json`, NOT yet in the app — add when user says «اعمال کن».
4. Desalter (docs/requirements/DESALTER.md): kVA per transformer, CSV record year, calibration of Factors_DES and
   basket weights are still Provisional. Finding to discuss: Pazanan 1393 estimate escalated ≈3.41 M€ vs 1404 quotes
   1.93 M€ (−43%). Gachsaran PEP year (1402/05) and pump "x bar" meaning still unconfirmed.
5. Air compressor bank (docs/requirements/COMPRESSOR.md): implemented in v0.9. Factors_CMP still Provisional (4 peers only;
   Domestic 0.6 is circular). Next: AIR_DRYER bank — price-less items CMP-00xx-DRY wait for manual prices (estimate in remarks).
6. Pump count (user 1405/07/24): app shows 101 = MTO KPL 40 + PEP G4 26 + MTO Pazanan 21 + catalog sample PUMPS 14
   (user imported project files, never the v8.1 bank). Bank 146 adds 18 Pazanan R02 1393 duplicate-tag records,
   13 KPL package pumps without price (P-113/123 desalter recycle, P-130–134/140–144 IGF, P-148 stripper) and 14 CSV
   18061405 pumps (CSV not importable). Bugs: dashboard hides the pump-bank import once MTO pumps exist; v8 import has no
   MTO dedupe (project names differ). v0.9.4: the user's consolidated price bank (164 pumps + all families) is the reference;
   importing it archives same-tag/same-price MTO duplicates; the import card is always shown (no V8 wording).
7. PIPING (docs/requirements/PIPING.md): consolidated Excel bank delivered 1405/08/02 (2659 items, 31 families, PPI+FX, market sheet).
   Not in app. Calibrated 1405/08/02 (user: lowest error vs his project quotes): NIMA FX, base year 1388 (GLB 1387, TEE/TRD/CRD 1391,
   CAP 1396, FLG 1385), qty factor off. Sheets: my quotes, Gachsaran-4 project prices, calibration. Open: F52 ×1.3, TEE WPHY60 2.5 vs 2.2.
8. Possibly a web version (user asked "web app"; current app is Windows-only) — only if he confirms.
9. SERVICES category (v0.9.2) escalates with the default PPI; a construction/labour index (Iranian or Eurostat construction
   cost) should be chosen with the user. Desalter «Internals & Transformators» rows of an estimate stay separate DESALTER items
   (user may move/merge in preview).
10. Decisions 1–6 above (domestic/foreign methods, methods page, Iranian indices, E/I/P classification) are not implemented yet.
11. APP_CHANGES sessions 1–2 done (v0.9.9). Next: session 3 (#2a–d, #3, #10, #13, #27, #28, #30 — equipment page layout,
    screenshots before applying). #5 open point: quantity of a newer revision is only reported, not applied — ask the user
    if newer quantities should replace old ones.
12. v0.9.10: generic equipment page lost the «فقط دارای استعلام» toggle with the others — restore if the user asks.
