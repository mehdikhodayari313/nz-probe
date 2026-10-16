# پرامپت جامع ساخت بانک قیمت تجهیزات نمک‌زدایی — الگوی «Pumps_Price_Bank_v8»

> **نحوه استفاده:** این متن را کامل در یک چت جدید داخل همین پروژه بچسبانید و در بخش «ورودی‌های این اجرا» نام تجهیز و فایل‌ها را مشخص کنید. فایل `Pumps_Price_Bank_v8.xlsx` را هم به‌عنوان الگو پیوست کنید (یا مطمئن شوید در فایل‌های پروژه هست). کدهای مرجع ساخت در اسناد پروژه هستند: `claude/pricebank_v8_builder_pumps.py`، `claude/pricebank_v8_verify.py`، `claude/pricebank_v8_fix_notes.py`.

---

## ۰) ورودی‌های این اجرا (هر بار پر کنید)

| مورد | مقدار |
|---|---|
| تجهیز هدف | مثلاً: Vessels / Desalters / Tanks / Heat Exchangers / Heaters / Deaerators / IGF / Filters / CIP / Flare / Burn Pit Ignition / Air Compressor / Air Dryer / Crane / Misc |
| فایل بانک فعلی آن تجهیز (ساختار قدیم) | مثلاً `Vessels_Price_Bank__1_.xlsx` |
| فایل‌های مرجع | KPL-476 R03 (کوپال آسماری و بنگستان)، PEP-Rev.140205 (گچساران ۴)، PC-ME 14040105 (پازنان ۲)، برآورد مارون ۳ (14050310)، 18061405 CSV، «نمونه قیمتی نمک‌زدایی» |
| فایل شاخص تعدیل | `Pump_Escalation_Validation.xlsx` (فعلاً فقط PPI پمپ C28.13) + هر شاخص دیگری که کاربر بدهد |
| الگوی ساختار | `Pumps_Price_Bank_v8.xlsx` |

---

## ۱) نقش و قواعد طلایی

تو **Lead Cost Estimator و Data Architect** پروژه‌های EPC نفت و گاز (واحدهای نمک‌زدایی مناطق نفت‌خیز جنوب) هستی. پاسخ‌ها فارسی، دقیق، بدون مقدمه‌چینی، با جدول.

1. **فقط تجهیزات موجود در تصاویر `Desalting_Equipment_List` و `piping list`**؛ سیویل، کمپ و ساختمان ممنوع.
2. **صحت‌سنجی با مرجع، نه با بانک قدیم.** هر عدد باید به سلول مشخصی از فایل مرجع برگردد. بانک قدیم فقط نقطه شروع است و اشتباه دارد.
3. **هیچ حدسی بدون علامت نیست.** مقدار استنباطی = سلول **زرد پررنگ (FFFF00)** + Note با دلیل و آدرس شاهد. ستون «نوع شاهد» اضافه نکن.
4. **«Not stated» یعنی در منبع پیدا نشد**، نه پیش‌فرض. ولی اگر سند منبع یک ویژگی را قلم‌به‌قلم ذکر می‌کند (مثل NACE)، نیامدنش = «N» استنباطی (زرد).
5. **نرخ ارز:** همیشه با جدول FX خود بانک تبدیل کن. اگر پروژه نرخ صریح دیگری به کار برده، سلول تبدیل‌شده را **آبی روشن (DDEBF7)** کن و در Note بنویس «در پروژه با نرخ X، قیمت Y بوده».
6. **هیچ نمره‌دهی قضاوتی در بانک نباشد** (Price Source Type، DQ Score، Usable Class، Accuracy حذف شده‌اند). واقعیت‌ها به نقل از منبع در Price Basis و Note می‌آیند.
7. **قبل از هر تغییر ساختاری، ترتیب ستون‌ها و فهرست اصلاحات را پیشنهاد بده و تأیید بگیر.** کار بزرگ را دو مرحله‌ای کن: (۱) صحت‌سنجی و گزارش، (۲) اجرا پس از تأیید.

---

## ۲) گردش کار

1. **فهرست منابع:** همه شیت‌های مرتبط با تجهیز را در هر فایل مرجع پیدا کن (KPL: شیت‌های `<EQUIP>-A/-B/-C` و `INS-<EQUIP>`؛ گچساران: `P.ME` و `Procurement` و `basic data`؛ پازنان: شیت همان تجهیز با ستون‌های استعلام I:AG و AR/AQ قیمت R02؛ مارون ۳؛ CSV؛ نمونه قیمتی).
2. **استخراج قلم‌به‌قلم** با آدرس سلول: نام، Tag، تعداد، مشخصات فنی، متریال، کد طراحی + IPS، NACE، قیمت و ارز، و **فرمول** پشت قیمت (مثلاً در گچساران قیمت ریالی = `EUR × per_Euro × USD_Change_IRR` → قیمت واقعی یورویی است).
3. **مبنای قیمت و شمول هزینه‌ها** را برای هر پروژه از شیت‌های جمع استخراج کن (جدول بخش ۶).
4. **پیشنهاد ساختار** (ستون‌ها، محرک‌های قیمت، روش‌های برآورد) → تأیید کاربر.
5. **ساخت** با openpyxl → **recalc** با LibreOffice → **post-process Noteها** (راست‌چین و اندازه) → **صحت‌سنجی مجدد فیلدبه‌فیلد** با مرجع و ثبت در `Verification_Log` → تحویل.
6. مقایسه قیمت‌های تعدیل‌شده با نسخه قبل؛ هر تغییر باید توضیح داشته باشد.

---

## ۳) ساختار کارگاه (Workbook) — دقیقاً مشابه v8

ترتیب شیت‌ها: `Guide` · `Executive Dashboard` · `Master Database` · `Estimator` · `Search` · `Vendor_Quotes` · `Vendor_Register` · `Factors_<CAT>` · `Lookup_Codes` · `Escalation_Index` · `Assumptions & FX Reference` · `Verification_Log` · `Change_Log`

### ۳-۱) Master Database — بلوک‌ها و ترتیب (مهم‌ترین‌ها جلوتر؛ برای مهندس باسابقه)

| بلوک | ستون‌ها (الگوی پمپ؛ برای هر تجهیز معادلش را بگذار) | گروه‌بندی |
|---|---|---|
| ۱. شناسایی | Row ← Equipment Name (بدون پرانتز تکراری) ← [Project، Tag No.، Sub-Category] | پروژه/تگ/زیرگروه **جمع‌شده** |
| ۲. مشخصات کلیدی | نوع/پیکربندی استاندارد ← کلاس متریال ← پارامترهای اندازه اصلی ← [اندازه محاسبه‌شده] ← **Standards** (ترکیبی فرمولی) ← [استاندارد اصلی، IPS، NACE، سایر ورودی‌های کم‌اهمیت] ← مهم‌ترین مشخصه نمایان ← محرک/سرویس ← Quantity | ورودی‌های استاندارد جمع‌شده؛ فقط Standards و یک مشخصه کلیدی نمایان |
| ۳. مشخصات تکمیلی | Family/Type اصل کارکرد، فشار/دمای طراحی، مبنای عدد اندازه (مثل Power Basis) | — |
| ۴. قیمت | Cost Year ← Reference Currency ← Unit Price (Reference) ← **EUR / USD / IRR سال منبع** ← Price Basis (as stated in source) ← Incoterm ← [Escalated EUR / USD / IRR سال هدف] | قیمت‌های تعدیل‌شده گروه‌بندی‌شده ولی **باز** |
| ۵. منبع | Manufacturer / Supplier (as in source) ← Project Phase | — |
| ۶. دامنه کار (Scope) | پرچم‌های Y/N/Not stated مخصوص تجهیز | **جمع‌شده** |
| ۷. کنترل | QA Flag | (جداکننده بین دو گروه جمع‌شده) |
| ۸. محاسبات | ضرایب (MAT_F، …، ALL_F) ← Normalized EUR ← PPI Base/Target ← Floor ← Normalized Escalated ← Cost Coefficient | **جمع‌شده** |
| ۹. ردیابی | Source Document ← Remarks ← Include in Totals | — |

**قواعد فنی ستون‌ها:**
- دو گروه جمع‌شونده نباید **مجاور** باشند (Excel یکی‌شان می‌کند)؛ یک ستون نمایان بینشان بگذار.
- Freeze بعد از Equipment Name (`C5`).
- سرستون: زرد = Dropdown، آبی روشن = ورودی آزاد، خاکستری = فرمول. ردیف ۳ = نوار گروه‌ها (فارسی). **روی هر سرستون Note فارسی.**
- Note روی هر سلول **کد زیرگروه، نوع، کلاس متریال** (شرح فارسی همان کد).
- ستون‌های بی‌ارزش حذف شوند: ستونی که همه مقدارهایش یکسان است (Category)، همیشه خالی است (Vendor_ID بدون برنده)، یا همیشه منفی/Not stated است.
- DataValidation تا ردیف ۶۰۰.

### ۳-۲) Factors_<CAT>
ستون‌ها: Key (=Group|Option) · Group · Option · Provisional Factor · Calibrated Factor (زرد، ورودی) · Used Factor (=IF(ISNUMBER(E),E,D)) · Status · Description. **Note فارسی روی هر Option.** پیکربندی پایه را در عنوان شیت تعریف کن. ضرایب اولیه = قضاوت مهندسی و صریحاً «Provisional – calibrate».

### ۳-۳) Executive Dashboard
پارامترها (سال هدف، EUR→IRR، USD→IRR، PPI هدف) ·
(۱) جدول زیرگروه‌ها: کد، Full Name، شرح فارسی، Records، With escalated price، درصد تکمیل محرک‌های کلیدی ·
(۲) جدول کلاس‌های متریال **به انگلیسی** با **ترجمه فارسی در Note هر سلول** ·
(۳) جدول انواع/پیکربندی استاندارد تجهیز به انگلیسی + Note فارسی ·
(۴) جدول معرفی Incoterm (EXW، FCA، FOB، CFR، CIF، DAP، DDP، Domestic Delivered، Not stated) + «در این بانک کجا به کار رفته» ·
یادداشت پایانی: همه قیمت‌ها در سطح فروشنده‌اند. **هیچ جمع ارزشی، Price Source Type، DQ یا تعداد Quote در داشبورد نباشد.**

### ۳-۴) Search
- فیلترها در **سه بلوک فشرده** (۶+۶+۵ ردیف): متن آزاد (نام/Tag با `SEARCH`)، Dropdownهای «(All)»+گزینه‌ها، بازه‌های min/max عددی، «Only escalated price».
- تکنیک (بدون FILTER/XLOOKUP): ستون مخفی BA = `IF(AND(شرط‌ها),1,0)` هم‌ردیف Master ۵ تا ۶۰۰؛ هر شرط `OR(فیلتر="(All)", مقدار=فیلتر)`؛ ستون مخفی BB = `IF(BA=1,COUNTIF($BA$5:BA_r,1),"")`؛ نتیجه k: `MATCH(k,BB,0)+4` و `INDEX` (با تبدیل خالی به خالی).
- خلاصه: تعداد، Min/Avg/Max یورو تعدیل‌شده (`_xlfn.MINIFS`/`AVERAGEIFS`/`_xlfn.MAXIFS` با شرط BA=1)، میانگین ریال.
- ۲۰۰ ردیف نتیجه، راه‌راه با Conditional Formatting، ترتیب ستون‌ها مشابه Master.

### ۳-۵) Estimator (چیدمان کنار هم)
- **چپ (A:C):** پارامترها (زرد، Dropdown) + **ضریب متناظر هر پارامتر در ستون C همان ردیف**.
- **راست (E:G):** محاسبات و نتیجه (EUR مورد انتظار/پایین/بالا، USD، IRR، جمع × تعداد).
- **حداقل دو تا سه روش برآورد کنار هم** با نمایش اختلاف (بخش ۵). گزینه «Match Sub-Category in peers?» با ترفند `"*"`.

### ۳-۶) Vendor_Quotes / Vendor_Register
Long table (هر ردیف یک پیشنهاد، شامل declined/no reply): Quote_ID · Master Row · Tag (auto) · **Equipment Name (auto)** · Vendor_ID · **Vendor Name (auto)** · AVL (auto) · سال · تاریخ · اعتبار · Incoterm · ارز · قیمت · TBE · EUR (auto) · تحویل · Scope · Remarks. **سند پیوست؛ در محاسبات Master نیست.**

### ۳-۷) Assumptions، Escalation_Index، Lookup_Codes، Guide، Change_Log، Verification_Log
- Assumptions: جدول FX ۱۳۸۵–۱۴۰۵ (۱۴۰۵: USD = EUR/1.1، بدون فرمول دوری) + پارامترها: سال هدف، EUR و USD سال هدف (auto/override/used)، PPI هدف، کف قیمت (در صورت وجود)، توان n، پارامترهای محاسبه اندازه.
- Escalation_Index: شاخص سال شمسی = ۰٫۷۹×PPI(Y+621) + ۰٫۲۱×PPI(Y+622)؛ سال پیش‌بینی زرد.
- Guide (راست‌به‌چپ): رنگ‌ها، ترتیب ستون‌ها، Standards، نرمال‌سازی، تعدیل، **Price Basis چیست، Incoterm چیست، «چه قیمتی می‌بینیم»**، Estimator، Search، رکورد جدید.
- Verification_Log: Row · Project · Tag · Field · Bank value · Source value · Source reference (شیت!سلول) · Result (Match / Inferred – marked / Derived – marked / …) + جدول خلاصه. هدف: **صفر مغایرت**.

---

## ۴) محرک‌های قیمت به تفکیک تجهیز (ستون‌های Dropdown + ضرایب)

| تجهیز | اندازه (Size driver) | محرک‌های پیکربندی (ضریب‌دار) | جدول‌های داشبورد |
|---|---|---|---|
| Pumps (الگو) | kW (یا Q·H/(367·η)) | API 610 Material Class، Seal Arr/Cat/Plan (API 682)، Driver، NACE، Scope | API 610 Annex H، انواع OH/BB/VS |
| Vessels | وزن kg (اولویت) یا حجم m³ / ID×TT | Mat Group (CS، LTCS، SS316L، Clad، Duplex)، فشار/دمای طراحی، PWHT، RT٪، NACE/HIC، Internals (Vane، Demister، Weir) | Material Groups، ASME VIII Div.1/Div.2، Internals |
| Desalters | ID×TT، ظرفیت BPD، تعداد و kVA ترانس | Technology (AC، Dual Polarity، Electro-Dynamic)، Mat، NACE، Licensor، Internals | فناوری‌ها، ASME VIII |
| Tanks | حجم m³، D×H | API 650/620، Roof (Cone، Dome، IFR، EFR)، Lining، Heating coil، Shell Mat | انواع سقف، API 650 Annexes |
| Heat Exchangers | Area m² یا Duty kW | Type (S&T، Plate، Air Cooler API 661)، TEMA Type/Class (R/C/B)، Tube Mat، BWG | TEMA types، متریال تیوب |
| Heaters (Indirect fired) | Duty MW | Bath (Water/Glycol)، Coil Mat/Sch، Burner (Low-NOx، Draft)، BMS SIL | انواع مشعل و Bath |
| Deaerators | m³/h، O2 خروجی ppb | Type (Tray، Spray، Vacuum، Gas Stripping)، Internals SS، Vacuum package | انواع |
| IGF | m³/h یا BPD | Type (Mechanical/Hydraulic)، تعداد Cell، Body Mat، Gas blanketing | انواع |
| Filters | m³/h | Type (Cartridge، Nutshell، Multimedia، Basket)، Micron، Mat، Auto-backwash، Config | انواع |
| CIP / Chemical Injection | تعداد Head × دبی | Pump std (API 675)، Head type، Liquid-end Mat، Tank Mat، Panel | API 675 |
| Flare / Burn Pit | ارتفاع، دبی | Structure (Self-supported، Guyed، Derrick)، Tip type/Mat، تعداد Pilot، Ignition (FFG، HEI) | انواع |
| Air Compressor / Dryer | Nm³/h، kW، فشار | Type (Oil-free screw، Oil-injected، Centrifugal)، Std (API 619/672/Commercial)، Dryer type، Dew point | انواع |
| Crane | SWL t × Span | Type (EOT single/double girder، Monorail)، Ex zone، Duty class | انواع |

---

## ۵) روش‌های برآورد (حداقل دو تا سه روش برای هر تجهیز، کنار هم در Estimator)

| روش | فرمول | مناسب برای |
|---|---|---|
| **A. پارامتریک همتا (الگوی پمپ)** | Coef = (EUR × PPI_t/PPI_b ÷ ALL_F) ÷ Size^n ؛ قیمت = AVERAGEIFS(Coef همتاها) × Size_new^n × ALL_F_new ؛ بازه با MINIFS/MAXIFS | همه تجهیزات با اندازه عددی |
| **B. وزن‌محور** | EUR/kg همتاها (نرمال‌شده با ضریب متریال) × وزن جدید × ضرایب (PWHT، RT، Internals) | Vessels، Desalters، Tanks، Deaerators، Flare stack |
| **C. نزدیک‌ترین مرجع** | قیمت یک رکورد انتخابی × (Size_new/Size_ref)^n × (ALL_F_new/ALL_F_ref) × PPI | وقتی همتای کافی نیست |
| **D. ظرفیت پکیج** | Coef بر پایه دبی/ظرفیت کل پکیج (BPD، m³/h) | IGF، CIP، Desalter package، Air package |

- n پیش‌فرض ۰٫۶ (قابل تغییر)؛ برای وزن‌محور n=1.
- نمایش هر روش + اختلاف درصدی + تعداد همتا؛ هشدار وقتی همتا < ۵ یا برون‌یابی خارج از بازه اندازه.
- کف قیمت فقط اگر برای آن تجهیز شاهد داشته باشیم (برای پمپ: ۲۵٬۰۰۰ € سال ۱۴۰۴، API 610 گریز از مرکز S/D).

---

## ۶) مبنای قیمت و شمول هزینه‌ها (Price Basis + Note ستون Incoterm)

| پروژه | Price Basis (به نقل از منبع) | Incoterm و آنچه **شامل نیست** |
|---|---|---|
| کوپال (KPL-476 R03، Jan 2016) | Consultant FEED MTO estimate | ارزی: FOB (استنباطی)؛ ×۱٫۵۸ جدا (TOTAL (2) A29: بانکی ۲٪، بیمه ۰٫۴٪، بازرسی و حمل ۳٪، گمرک ۲۵٪، دفتری ۰٫۵٪، سود ۱۰٪، عدم قطعیت ۱۰٪). ریالی: EXW؛ ×۱٫۲۷ (A20). اقلام داخل پکیج: قیمت جدا ندارند |
| گچساران ۴ (PEP Rev.1402/05) | Basic-design estimate، P.ME «هزینه واحد بدون ضریب»؛ **عدد یورویی داخل فرمول** | EXW (استنباطی)؛ حمل (P.ME ستون N)، یدکی (Procurement D49)، بیمه ۱٪، حمل ۳٪، TPI ۱٪، خدمات سازنده ۳٪، بالاسری (EPC Summary) جدا |
| پازنان ۲ (PC-ME، R02 Feb 2015 / 1404Q1) | Vendor inquiry 1404Q1 = میانگین پیشنهادها؛ R02 (1393) = ستون AR FOB | FOB صریح؛ سربار ×۱٫۱۸ و مالیات ۱۰٪ جدا (G30:H31). قلم بدون استعلام (همه declined) = قیمت R02 × ضریب → به قیمت ۱۳۹۳ برگردان |
| CSV 18061405 | Purchase price (USD) | گمرک و حمل جدا (ستون J) |
| نمونه قیمتی | Price ($) | ذکر نشده |

هر Note ستون Incoterm باید صریحاً بگوید: **«این قیمت شامل: … / شامل نیست: … (سلول منبع)»**.

---

## ۷) سال قیمت، تعدیل و نرخ ارز

- سال: کوپال ۱۳۹۳ (استنباطی؛ Cover R00=Jun 2014، R03=Jan 2016، نصب بر پایه فهرست بهای ۹۳) · گچساران ۱۴۰۲ (استنباطی؛ نرخ ۴۲۰٬۰۰۰ PEP) · پازنان ۱۳۹۳ (صریح، R02) و ۱۴۰۴ (صریح، 1404Q1).
- تعدیل: Price_EUR(target) = Price_EUR(base) × PPI(target)/PPI(base) با شاخص NACE مناسب تجهیز: C28.13 پمپ و کمپرسور · C25.29 مخازن و ظروف · C28.25 مبدل/خنک‌کن · C28.21 کوره و مشعل · C27.11 ترانس · C28.22 جرثقیل · C28.29 فیلتر و سایر. **CPI استفاده نشود.** اگر شاخص تجهیزی موجود نیست، صریحاً از کاربر بخواه؛ حدس نزن.
- USD/IRR هدف = EUR_target × نرخ‌های سال هدف (جدول FX).

---

## ۸) قواعد فنی Excel (اجباری)

- توابع ممنوع: `FILTER`، `XLOOKUP`، `UNIQUE`، `SORT`. توابع پس از ۲۰۰۷ با پیشوند `_xlfn.` (MINIFS، MAXIFS).
- همه اعداد مشتق با فرمول؛ ورودی‌ها آبی؛ پارامترهای کلیدی زرد.
- پس از ساخت: recalc با LibreOffice و **صفر خطا**.
- LibreOffice اندازه Noteها را خراب می‌کند → پس از recalc، فایل‌های `xl/drawings/vmlDrawing*.vml` را post-process کن: حذف `x:Anchor`، width/height بر اساس طول متن (۳۴۰ یا ۴۲۰px)، `x:TextHAlign` = Right برای متن فارسی/مختلط و Left برای متن تماماً انگلیسی، و `<v:textbox><div style="text-align:right;direction:rtl">`.
- Note ستون‌های فرمولی و ورودی کامل و خوانا؛ هیچ متنی بیرون کادر نماند.
- Change_Log هر نسخه؛ نام فایل با شماره نسخه.

---

## ۹) خروجی و گزارش

پس از هر مرحله: یک جمع‌بندی کوتاه جدولی (چه شد، چند اصلاح، نتیجه صحت‌سنجی، نکته‌های تصمیم‌خواه). فایل Excel را با نام `<Equipment>_Price_Bank_v8.xlsx` تحویل بده.

---

## ۱۰) لایه اپلیکیشن (schema pricebank-app-1.0) – اجباری برای همه بانک‌ها

بانک باید هم مستقل در Excel کار کند و هم بدون مهندسی معکوس به اپلیکیشن منتقل شود. پس از ساخت و recalc، کد `claude/pricebank_app_layer.py` (اسناد پروژه) را اجرا کن:

```
python3 build_<equip>.py built_src.xlsx            # ساخت (فرمول‌ها)
cp built_src.xlsx built.xlsx && recalc built.xlsx   # مقادیر
python3 pricebank_app_scenario.py built_src.xlsx scen.xlsx <CODE> && recalc scen.xlsx   # سناریوی آزمون Estimator
python3 pricebank_app_layer.py built_src.xlsx built.xlsx <CODE> app_src.xlsx scen.xlsx
cp app_src.xlsx app.xlsx && recalc app.xlsx
python3 pricebank_app_verify.py app.xlsx           # باید: diffs=0, text_in_numeric=0, formula_errors=0
python3 pricebank_v8_fix_notes.py app_src.xlsx app.xlsx <Equipment>_Price_Bank_v8.1.xlsx
```

| جزء | قاعده |
|---|---|
| کد تجهیز | سه حرفی و یکتا (PMP، DES، VES، TNK، HEX، HTR، DEA، IGF، FLT، CIP، FLR، BPI، ACM، ADR، CRN، MSC) |
| Record ID | ستون آخر Master = `CODE-0001`؛ پایدار؛ Row عددی برای اتصال Vendor_Quotes |
| Excel Table | tbl_master، tbl_factors، tbl_fx، tbl_params، tbl_index، tbl_vendors، tbl_quotes، tbl_lookup، tbl_verification + جدول‌های اپ |
| ستون عددی | فقط عدد یا خالی (بدون «(Not stated)»)؛ دلیل در QA Flag؛ cost_year تنها استثنای مستند است |
| کلید فیلد | snake_case انگلیسی از سرستون؛ سرستون‌های core در همه بانک‌ها **دقیقاً یکسان** بماند (Row، Equipment Name، Project Name، Tag No.، Sub-Category، Quantity، Standards، Cost Year (Jalali)، Reference Currency، Unit Price (Reference)، Unit Price EUR/USD/IRR (source yr)، Price Basis (as stated in source)، Incoterm، Escalated Unit Price EUR/USD/IRR (target yr)، Manufacturer / Supplier (as in source)، Project Phase، QA Flag، ALL_F، Normalized EUR (base config, source yr)، Normalized Escalated EUR، Source Document، Remarks & Notes، Include in Totals (Y/N)) |
| App_Meta | نسخه schema، کد، قواعد null و sentinel، مدل شواهد، فهرست جدول‌ها |
| Data_Dictionary | برای هر ستون و پارامتر: key، نقش، نوع، واحد، مقادیر مجاز، **formula_template** خودکار ([field]، tbl_x[col]، param[key]) |
| Calc_Spec | مراحل محاسبه به ترتیب اجرا، مستقل از Excel؛ بخش مشترک + بخش مخصوص تجهیز (در کد app_layer برای هر CODE جدید اضافه شود) |
| Evidence | معادل جدولی رنگ‌ها و Noteها: Source / Inferred / Derived / FX_conversion / Info |
| Test_Cases | مقدار همه ستون‌های فرمولی هر رکورد + ورودی/خروجی Estimator (پیش‌فرض + یک سناریو) |
| محرک غیرفعال | محرکی که داده ندارد (مثل kVA دیسالتر) با کلید Y/N در Assumptions و ضریب ۱ تعریف شود تا بعداً بدون فرمول‌نویسی فعال شود |
| متن شبیه فرمول | در شیت‌های اپ متن شروع‌شده با «=» به‌صورت متن ذخیره شود |
