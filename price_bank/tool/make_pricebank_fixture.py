# اجرا: python3 -I tool/make_pricebank_fixture.py <PriceBank_Desalting.xlsx> test/fixtures_private/PriceBank_test.xlsx
"""نسخه‌ی کوچک بانک قیمت تجمیعی برای آزمون: شیت‌های خانواده (فقط ستون‌های ورودی، بدون فرمول، حداکثر ۱۲ رکورد هر شیت)
و استعلام‌های همان رکوردها."""
import re, sys, openpyxl, warnings
warnings.simplefilter('ignore')
src, dst = sys.argv[1], sys.argv[2]
wv = openpyxl.load_workbook(src, data_only=True)
wf = openpyxl.load_workbook(src)
COMPUTED = re.compile(r'^(unit price (eur|usd|irr) \(source|escalated|f [a-z_ ]+$|all_f$|normalized|index (base|target)|size value|cost coefficient|search key|key specs|qa flag)', re.I)
out = openpyxl.Workbook(); out.remove(out.active)
keep_rids = set()
for ws in wv.worksheets:
    hdr = [ws.cell(4, c).value for c in range(1, ws.max_column + 1)]
    if 'RID' not in hdr or 'Unit Price (Reference)' not in hdr: continue
    o = out.create_sheet(ws.title)
    o.cell(1, 1, ws.cell(1, 1).value)
    cols = [c for c, h in enumerate(hdr, 1) if h and not COMPUTED.search(str(h))]
    for j, c in enumerate(cols, 1): o.cell(4, j, hdr[c - 1])
    n = 0
    for r in range(5, ws.max_row + 1):
        rid = ws.cell(r, 1).value
        if not rid: continue
        n += 1
        if n > 12: break
        keep_rids.add(rid)
        for j, c in enumerate(cols, 1): o.cell(4 + n, j, ws.cell(r, c).value)
q = wv['Vendor_Quotes']; oq = out.create_sheet('Vendor_Quotes')
oq.cell(1, 1, q.cell(1, 1).value)
for c in range(1, q.max_column + 1): oq.cell(4, c, q.cell(4, c).value)
k = 5
for r in range(5, q.max_row + 1):
    if q.cell(r, 1).value in keep_rids:
        for c in range(1, q.max_column + 1): oq.cell(k, c, q.cell(r, c).value)
        k += 1
out.save(dst)
print(len(keep_rids), 'records,', k - 5, 'quotes')
