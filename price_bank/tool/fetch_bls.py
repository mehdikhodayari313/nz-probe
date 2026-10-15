"""دریافت شاخص‌های PPI آمریکا (BLS) — اجرا فقط در GitHub Actions (در محیط Claude بسته است).
  python3 tool/fetch_bls.py out_dir
خروجی: out_dir/bls_ppi.json  {series: {"title":..., "monthly": {"YYYY-MM": value}}} + bls_summary.txt
جایگزین سری‌های محرمانه‌ی یوروستات: C25.30 (دیگ بخار)، C24.10 (فولاد خام)، C24.20 (لوله‌ی فولادی).
"""
import json, os, sys, time, urllib.request

SERIES = {
    "PCU332410332410": "Power boiler and heat exchanger mfg (NAICS 332410) ~ C25.30",
    "PCU3324103324101": "Power boilers and parts (product 332410-1)",
    "PCU3324103324102": "Heat exchangers and steam condensers (product 332410-2)",
    "PCU331110331110": "Iron and steel mills and ferroalloy mfg (NAICS 331110) ~ C24.10",
    "WPU1017": "Steel mill products",
    "PCU331210331210": "Iron and steel pipe and tube mfg from purchased steel (NAICS 331210) ~ C24.20",
    "WPU101706": "Steel pipe and tube (commodity)",
}
WINDOWS = [(2000, 2009), (2010, 2019), (2020, 2026)]


def post(url, payload):
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), headers={
        "Content-Type": "application/json", "User-Agent": "price-bank-ci (github actions)"})
    with urllib.request.urlopen(req, timeout=90) as r:
        return json.load(r)


def main():
    od = sys.argv[1] if len(sys.argv) > 1 else "out"
    os.makedirs(od, exist_ok=True)
    key = os.environ.get("BLS_KEY", "")
    url = "https://api.bls.gov/publicAPI/%s/timeseries/data/" % ("v2" if key else "v1")
    res = {s: {"title": t, "monthly": {}} for s, t in SERIES.items()}
    log = []
    for a, b in WINDOWS:
        p = {"seriesid": list(SERIES), "startyear": str(a), "endyear": str(b)}
        if key:
            p["registrationkey"] = key
        try:
            d = post(url, p)
            log.append(f"{a}-{b}: {d.get('status')} {d.get('message')}")
            for s in d.get("Results", {}).get("series", []):
                for o in s.get("data", []):
                    if o["period"].startswith("M") and o["period"] != "M13":
                        try:
                            res[s["seriesID"]]["monthly"][f"{o['year']}-{o['period'][1:]}"] = float(o["value"])
                        except ValueError:
                            pass
        except Exception as e:  # noqa
            log.append(f"{a}-{b}: ERROR {e}")
        time.sleep(2)
    for s, v in res.items():
        ks = sorted(v["monthly"])
        log.append(f"{s}\t{v['title']}\t{ks[0] if ks else '-'}..{ks[-1] if ks else '-'}\t{len(ks)} months")
    json.dump(res, open(os.path.join(od, "bls_ppi.json"), "w"), indent=1, sort_keys=True)
    open(os.path.join(od, "bls_summary.txt"), "w").write("\n".join(log) + "\n")
    print("\n".join(log))


if __name__ == "__main__":
    main()
