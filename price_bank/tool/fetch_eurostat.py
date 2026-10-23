"""دریافت شاخص‌های PPI سالانه‌ی یوروستات (sts_inppd_a، EA20، 2021=100) برای صحت‌سنجی و به‌روزرسانی سری‌های برنامه.

اجرا فقط در GitHub Actions (در محیط Claude دسترسی به یوروستات بسته است):
  python3 tool/fetch_eurostat.py out_dir
خروجی: out_dir/eurostat_ppi.json  {nace: {year: [value, flag]}}  + summary.txt
"""
import json
import os
import sys
import urllib.request

NACE = ["C24", "C241", "C242", "C253", "C2410", "C2420", "C2442", "C2444", "C2511", "C2529", "C2530", "C2651", "C2711", "C2712", "C2813", "C2814",
        "C2825", "C2829", "C28",
        # 1405/08/01: price-bank consolidated Excel – cranes, burners/heaters, gas engines, other electrical, cables, electrical equipment total
        "C2811", "C2821", "C2822", "C2790", "C2732", "C27", "C25", "C2599"]
# اگر EA20 خالی بود (محرمانه)، همین سری برای EU27_2020 هم گرفته می‌شود (کلید <nace>_EU27)
FALLBACK_GEO = "EU27_2020"
# برای بازسازی سری‌های محرمانه از داده‌ی کشورها
COUNTRY_SERIES = ["C2410", "C2420", "C2530", "C242", "C253"]
COUNTRIES = ["DE", "FR", "IT", "ES", "AT", "NL", "BE", "FI", "PL", "CZ", "SE"]
URL = ("https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/sts_inppd_a"
       "?format=JSON&geo={g}&nace_r2={n}&unit=I21&lang=EN")


def fetch(n, g="EA20"):
    with urllib.request.urlopen(URL.format(n=n, g=g), timeout=90) as r:
        d = json.load(r)
    time_idx = d["dimension"]["time"]["category"]["index"]
    label = d["dimension"]["nace_r2"]["category"]["label"].get(n, n)
    sizes = d["size"]
    # فقط یک سری انتظار می‌رود؛ اگر ابعاد دیگر بیش از یک مقدار داشتند، اولین ترکیب را برمی‌داریم
    stride_t = 1
    ids = d["id"]
    t_pos = ids.index("time")
    for s in sizes[t_pos + 1:]:
        stride_t *= s
    vals, flags = d.get("value", {}), d.get("status", {})
    out = {}
    for y, i in time_idx.items():
        k = str(i * stride_t)
        if k in vals:
            out[y] = [vals[k], flags.get(k, "")]
    return label, out, {ids[j]: list(d["dimension"][ids[j]]["category"]["index"].keys()) for j in range(len(ids)) if ids[j] != "time"}


def main():
    od = sys.argv[1] if len(sys.argv) > 1 else "out"
    os.makedirs(od, exist_ok=True)
    res, summ = {}, []
    for n in NACE:
        try:
            label, series, dims = fetch(n)
            res[n] = {"label": label, "values": series, "dims": dims}
            ys = sorted(series)
            summ.append(f"{n}\t{label}\t{ys[0] if ys else '-'}..{ys[-1] if ys else '-'}\t{len(ys)} years\t{dims}")
            if not ys:
                label2, series2, dims2 = fetch(n, FALLBACK_GEO)
                res[n + "_EU27"] = {"label": label2, "values": series2, "dims": dims2}
                y2 = sorted(series2)
                summ.append(f"{n}_EU27\t{label2}\t{y2[0] if y2 else '-'}..{y2[-1] if y2 else '-'}\t{len(y2)} years")
        except Exception as e:  # noqa
            res[n] = {"error": str(e)}
            summ.append(f"{n}\tERROR {e}")
    for n in COUNTRY_SERIES:
        for g in COUNTRIES:
            try:
                label, series, dims = fetch(n, g)
                if series:
                    res[f"{n}_{g}"] = {"label": label, "values": series, "dims": dims}
                    ys = sorted(series); summ.append(f"{n}_{g}\t{ys[0]}..{ys[-1]}\t{len(ys)} years")
            except Exception as e:  # noqa
                summ.append(f"{n}_{g}\tERROR {str(e)[:60]}")
    with open(os.path.join(od, "eurostat_ppi.json"), "w", encoding="utf-8") as f:
        json.dump(res, f, ensure_ascii=False, indent=1, sort_keys=True)
    with open(os.path.join(od, "summary.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(summ) + "\n")
    print("\n".join(summ))


if __name__ == "__main__":
    main()
