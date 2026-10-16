# مراجع پروژه (Reference files) — محرمانه

به درخواست کاربر (۱۴۰۵/۰۷/۲۴) فایل‌های مرجع پروژه‌ی Claude «بانک قیمت نمک زدائی» این‌جا هستند تا Claude Code بتواند آن‌ها را بخواند.
**محرمانه:** مخزن باید خصوصی بماند. این فایل‌ها را در `price_bank/test/fixtures*` کپی نکنید و در کد برنامه به آن‌ها ارجاع ندهید. آزمون‌ها همچنان فقط با فیکسچرهای ناشناس‌شده اجرا می‌شوند.
این پوشه بیرون از `price_bank/` است، پس تغییر آن CI را اجرا نمی‌کند.

خواندن: `python3 -I` و `openpyxl` (برای مقدار سلول‌ها `data_only=True`، برای فرمول‌ها بدون آن). فایل‌های بزرگ را با `read_only=True` باز کنید.

## project_files/

| فایل | چیست | شیت‌های مهم |
|---|---|---|
| `91215-KPL-ME-RE-476 R03_MTO and Cost Estimation Report.xlsx` | کوپال (آسماری + بنگستان)، MTO و برآورد FEED، R03 = Jan 2016؛ سال قیمت ۱۳۹۳ استنباطی | `<EQUIP>-A/-B/-C` (مثل PUMPS-A (1)…PUMPS-C (4)، DESALTERS-A/B، AIR COMP.)، `INS-*` (نصب، وزن Kg)، `TOTAL`، `TOTAL (2)` (A29 ضریب ×۱٫۵۸ ارزی، A20 ×۱٫۲۷ ریالی)، `Cover` |
| `PEP-Rev.140205_عزيزيان_Gachsaran 4.xlsx` | گچساران ۴، PEP مرحله Basic، Rev.1402/05 | `P.ME` (قیمت تجهیزات؛ عدد یورویی داخل فرمول H)، `P.EL`، `P.IN`، `P.PI` (پایپینگ)، `basic data` (B1 per_Euro، B2 USD_Change_IRR=420000، C18 USD_Inflation_Factor)، `Procurement`، `C.mECHANICAL` (نصب و وزن) |
| `PC-ME 14040105_Pazanan2_Reconstruction.xlsx` | پازنان ۲، استعلام 1404Q1 + قیمت R02 (Feb 2015 = ۱۳۹۳) | شیت هر تجهیز (`PUMPS`، `DESALTER`، `AIR COMP.`، `EXCHANG.`، …): ستون F قیمت 1404، I:AG استعلام‌ها، AQ ریال R02، AR یورو FOB R02؛ `Spare parts`، `TOTAL`، `Cover` (D65 = R02 date) |
| `برآورد پروژه نمکزدایی مارون 3  بنگستان تاریخ 14050310.xlsx` | مارون ۳ بنگستان، برآورد ۱۴۰۵ از مبنای ۱۳۹۲ | `ME.p.1392`، `ME.P.1405`، `EL.p.1392`، `IN.p&C.1392`، `Inflation` (ضرایب تورم)، `Extra.1405`، `Summary_M3 1405` |
| `نمونه قیمتی نمک زدایی .xlsx` | نمونه کاتالوگ قیمت (USD)، بدون پروژه/سال (۱۳۸۵ فرض) | `PUMPS` (۱۴ پمپ بدون تگ)، `VESSELS`، `HEAT EXCHANGERS`، `AIR COOLERS`، `TANKS`، `packages` |
| `18061405_Pump_only_CSV.csv` | قیمت خرید USD، تاریخ از نام فایل ۱۴۰۵/۰۶/۱۸ | بخش Pumps (۱۴ ردیف؛ ستون J گمرک و حمل) و packages |
| `Pumps_Price_Bank_v8.1.xlsx` | **بانک پمپ مرجع (جدیدترین)**: ۱۴۶ رکورد + لایه اپ (App_Meta، Data_Dictionary، Calc_Spec، Evidence، Test_Cases، ستون Equipment Code) | `Master Database` (ردیف ۴ سرستون، داده از ردیف ۵) |
| `Pumps_Price_Bank_v8.xlsx` | نسخه‌ی قبلی همان بانک (۵۹ ستون) — همان که در `price_bank/test/fixtures_private/` است | |
| `Pump_Escalation_Validation 1.xlsx` | صحت‌سنجی روش تعدیل پمپ (PPI C28.13 + کف ۲۵ هزار یورو) | `Indices`، `Val_EUR_Pumps`، `Val_IRR_Packages`، `Summary` |
| `Misc_Price_Bank_Final_v3.xlsx` | الگوی ساختار بانک «سایر تجهیزات» (طبق شرح نیاز) | `Master Database` |
| `Desalting_Equipment_List.png` | دسته‌بندی تجهیزات واحد نمک‌زدایی (مبنای رده‌ها) | |
| `piping list 1.png`، `piping list 2.png` | فهرست اقلام پایپینگ، شیرآلات و اتصالات | |

### شمار پمپ‌ها در بانک v8.1 (۱۴۶ ردیف)
| پروژه | ردیف | تگ یکتا | توضیح |
|---|---|---|---|
| Pazanan 2 | 39 | 21 | ۲۱ قیمت ۱۴۰۴ (P-163، P-210، P-211 فقط ۱۳۹۳) + ۱۸ ردیف جفت تاریخی R02 ۱۳۹۳ (ردیف‌های ۱۲۹–۱۴۶) |
| Koopal Asmari | 32 | 32 | |
| Gachsaran 4 | 26 | 26 | |
| Koopal Bangestan | 21 | 21 | |
| CSV 18061405 | 14 | — | بدون تگ؛ Include=N (تکراری نمونه قیمتی) |
| نمونه قیمتی (PUMPS) | 14 | — | بدون تگ و تعداد |

## docs/
| فایل | محتوا |
|---|---|
| `sharh_niaz.md` | شرح نیاز بانک قیمتی (متن فایل Word پروژه) |
| `General_Prompt_PriceBank_v8.md` | قواعد ساخت همه‌ی بانک‌ها (ساختار، رنگ‌ها، Price Basis/Incoterm هر پروژه، سال قیمت، شاخص‌ها، لایه اپ) |
| `pump-escalation-method.md` | نتیجه‌ی صحت‌سنجی روش تعدیل پمپ |
| `raw-price-audit-pumps-desalter-aircomp.md` | ممیزی قیمت خام: ضرایب پنهان داخل فرمول‌های منبع، خطاهای ارز، ردیف‌های تکراری |

اسکریپت‌های ساخت بانک‌های اکسل (builder/verify/app_layer) در اسناد پروژه‌ی Claude مانده‌اند و این‌جا نیستند.
