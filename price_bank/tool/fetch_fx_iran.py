"""دریافت تاریخچه نرخ ارز ایران (آزاد، نیمایی، سنا/رسمی) از tgju.org برای بانک قیمت.
اجرا فقط در GitHub Actions: python3 tool/fetch_fx_iran.py out_dir
خروجی: out_dir/<id>.json (پاسخ خام API) و out_dir/<id>_profile.html و summary.txt
"""
import json, os, sys, urllib.request, re, time
IDS = ["bank_usd", "bank_eur", "price_dollar", "price_dollar_dt", "price_dollar_rl", "price_eur", "nima_sell_usd", "nima_buy_usd", "nima_sell_eur", "nima_buy_eur",
       "sana_sell_usd", "sana_buy_usd", "sana_sell_eur", "sana_buy_eur"]
API = ("https://api.tgju.org/v1/market/indicator/summary-table-data/{i}?lang=fa&order_dir=asc&start=0&length=20000"
       "&from=&to=&convert_to_ad=1")
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124 Safari/537.36",
      "Accept": "application/json, text/html", "Referer": "https://www.tgju.org/"}
def get(u):
    req = urllib.request.Request(u, headers=UA)
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()
def main():
    od = sys.argv[1] if len(sys.argv) > 1 else "out"; os.makedirs(od, exist_ok=True); summ = []
    for i in IDS:
        for kind, u in (("api", API.format(i=i)), ("profile", f"https://www.tgju.org/profile/{i}/history")):
            try:
                b = get(u); fn = f"{i}.json" if kind == "api" else f"{i}_profile.html"
                open(os.path.join(od, fn), "wb").write(b)
                n = ""
                if kind == "api":
                    try: n = f"records={len(json.loads(b).get('data', []))}"
                    except Exception as e: n = f"json-err {e}"
                summ.append(f"{i}\t{kind}\tOK\t{len(b)} bytes\t{n}")
            except Exception as e:
                summ.append(f"{i}\t{kind}\tERR\t{e}")
            time.sleep(1)
    for extra in ("https://www.tgju.org/currency", "https://www.tgju.org/nima"):
        try:
            b = get(extra); open(os.path.join(od, re.sub(r'\W', '_', extra[8:]) + ".html"), "wb").write(b); summ.append(f"{extra}\tOK\t{len(b)}")
        except Exception as e: summ.append(f"{extra}\tERR\t{e}")
    open(os.path.join(od, "fx_summary.txt"), "w").write("\n".join(summ)); print("\n".join(summ))
if __name__ == "__main__": main()
