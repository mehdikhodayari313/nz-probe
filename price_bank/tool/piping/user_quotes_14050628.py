import json, math
I = json.load(open('../build/out/indices.json'))
def G(s, y):
    p = I['ppi'][s]['values']; y = str(y)
    if y in p: return p[y]
    last = max(int(k) for k in p); return p[str(last)] * 1.02 ** (int(y) - last)
def PJ(s, y): return 0.79 * G(s, y + 621) + 0.21 * G(s, y + 622)
def fx(t, y, m=None):
    d = I['fx'][t][str(y)]
    if m and str(m) in d['months']: return d['months'][str(m)]
    if d['months']: return sum(d['months'].values()) / len(d['months'])
    return d['annual']
def esc(t, s, Y): return fx(t, 1405, 6) / fx(t, Y) * PJ(s, 1405) / PJ(s, Y)
# (no, desc, unit, market rial, bank k-rial per unit, private factor, factor note, series, proposed Y, match note)
L = [
 (1, 'لوله 8" WT 8.18، X52 PSL2 بدون درز ترش', 'm', 127650000, 5118/12, 1.1*1.15*1.3, 'X52 1.1 × PSL2 1.15 × NACE 1.3', 'C242', 1385, 'بانک ERW، WT 8.2'),
 (2, 'لوله 6" WT 7.1، X52 PSL2 بدون درز ترش', 'm', 84780000, 3380/12, 1.1*1.15*1.3, 'X52 1.1 × PSL2 1.15 × NACE 1.3', 'C242', 1385, 'بانک ERW، WT 7.1'),
 (3, 'لوله 4" WT 6.02، X52 PSL2 بدون درز ترش', 'm', 48000000, 1922/12, 1.1*1.15*1.3, 'X52 1.1 × PSL2 1.15 × NACE 1.3', 'C242', 1385, 'بانک ERW، WT 6.0'),
 (4, 'لوله 4" SCH30 (WT 4.78) ساپورت', 'm', 20160000, 1555/12, 1.0, '—', 'C242', 1385, 'بانک ERW GR.B، WT 4.8'),
 (5, 'شیر توپی 8" کلاس 300، API 6D', 'no', 6745600000, 25550, 1.05, 'Trunnion 1.05', 'C2814', 1388, ''),
 (6, 'شیر توپی 8" کلاس 150، API 6D', 'no', 4216000000, 21230, 1.05, 'Trunnion 1.05', 'C2814', 1388, ''),
 (7, 'شیر کشویی 6" API 3000 RTJ، بدنه A487', 'no', 12065612934, 40000, 1.1, 'بدنه آلیاژی 1.1', 'C2814', 1388, 'بانک 3000 RJ'),
 (8, 'شیر کشویی 4" API 3000 RTJ، بدنه A487', 'no', 6655712934, 19000, 1.1, 'بدنه آلیاژی 1.1', 'C2814', 1388, 'بانک 3000 RJ'),
 (9, 'فلنج WN 8" کلاس 300 RF A105', 'no', 135654463, 556, 1.0, '—', 'C255', 1385, ''),
 (10, 'فلنج WN 8" کلاس 150 RF A105', 'no', 90436309, 310, 1.0, '—', 'C255', 1385, ''),
 (11, 'فلنج WN 6" API 3000 RTJ، A694 F52', 'no', 248849393, 1500, 1.3*1.1, 'F52 1.3 × RTJ 1.1', 'C255', 1385, 'بانک کلاس 900 (هم‌ابعاد API 3000)'),
 (12, 'فلنج WN 4" API 3000 RTJ، A694 F52', 'no', 120134190, 650, 1.3*1.1, 'F52 1.3 × RTJ 1.1', 'C255', 1385, 'بانک کلاس 900 (هم‌ابعاد API 3000)'),
 (13, 'سه‌راهی مساوی 6" SCH40، WPHY60 ترش', 'no', 115000000, 392.5, 2.5, 'WPHY60 2.5', 'C242', 1390, ''),
 (14, 'زانو 90 4" SCH40، WPHY60 ترش', 'no', 50000000, 116.4, 2.2, 'WPHY60 2.2 (فایل زانو)', 'C242', 1390, ''),
 (15, 'زانو 90 6" SCH40، WPHY60 ترش', 'no', 100000000, 212.0, 2.2, 'WPHY60 2.2 (فایل زانو)', 'C242', 1390, ''),
]
rows = []
for no, d, u, mk, bk, pf, pfn, s, Yp, note in L:
    b = bk * 1000 * pf
    a = b * esc('FREE', s, 1385)          # workbook today (default) without general factors
    c = b * esc('NIMA', s, 1385)
    p = b * esc('NIMA', s, Yp)
    # implied base year (NIMA): ratio by Y
    scan = {Y: mk / (b * esc('NIMA', s, Y)) for Y in range(1385, 1397)}
    bestY = min(scan, key=lambda Y: abs(math.log(scan[Y])))
    rows.append((no, mk / a, mk / c, mk / p, bestY, scan[bestY]))
    print(f'{no:2d} {d[:38]:38s} bank1385F={a:>16,.0f} r={mk/a:5.2f} | N1385 r={mk/c:5.2f} | prop({Yp}) {p:>16,.0f} r={mk/p:5.2f} | bestY {bestY} {scan[bestY]:.2f}')
import statistics as st
print('median ratios: free1385', round(st.median(r[1] for r in rows), 2), 'nima1385', round(st.median(r[2] for r in rows), 2), 'proposal', round(st.median(r[3] for r in rows), 2))
print('---')
for t in ('NIMA','FREE'):
    for Y in (1385,1386,1387,1388,1389,1390,1391):
        rs=[mk/(bk*1000*pf*esc(t,s,Y)) for no,d,u,mk,bk,pf,pfn,s,Yp,note in L]
        print(t,Y,'median',round(st.median(rs),2),'min',round(min(rs),2),'max',round(max(rs),2))
