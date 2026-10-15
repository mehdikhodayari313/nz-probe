"""دریافت شاخص‌های PPI سالانه‌ی یوروستات (sts_inppd_a، EA20، 2021=100) برای صحت‌سنجی و به‌روزرسانی سری‌های برنامه.

اجرا فقط در GitHub Actions (در محیط Claude دسترسی به یوروستات بسته است):
  python3 tool/fetch_eurostat.py out_dir
خروجی: out_dir/eurostat_ppi.json  {nace: {year: [value, flag]}}  + summary.txt
"""
import json
import os
import sys
import urllib.request

NACE = ["C2420", "C2511", "C2529", "C2530", "C2651", "C2711", "C2712", "C2813", "C2814", "C2829", "C28"]
URL = ("https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/sts_inppd_a"
       "?format=JSON&geo=EA20&nace_r2={n}&unit=I21&lang=EN")


def fetch(n):
    with urllib.request.urlopen(URL.format(n=n), timeout=90) as r:
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
        except Exception as e:  # noqa
            res[n] = {"error": str(e)}
            summ.append(f"{n}\tERROR {e}")
    with open(os.path.join(od, "eurostat_ppi.json"), "w", encoding="utf-8") as f:
        json.dump(res, f, ensure_ascii=False, indent=1, sort_keys=True)
    with open(os.path.join(od, "summary.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(summ) + "\n")
    print("\n".join(summ))


if __name__ == "__main__":
    main()
