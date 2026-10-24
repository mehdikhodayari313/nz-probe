import json, math, statistics as st, collections, sys
sys.path.insert(0, '../build')
from meta import FAMILIES
I = json.load(open('../build/out/indices.json'))
R = json.load(open('../build/out/records.json', encoding='utf-8'))
MK = json.load(open('../build/out/market.json', encoding='utf-8'))
G4 = json.load(open('g4.json', encoding='utf-8'))
SER = {f[0]: f[4] for f in FAMILIES}
FN = {f[0]: f[1] for f in FAMILIES}
EURUSD_1392 = 1.34   # ECB avg Mar-2013..Mar-2014 (approx.)
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
YS = list(range(1385, 1401))
obs = []   # (fam, src, bank_rial, obs_rial_func(t,Y)) -> ratio(t,Y)
seen = set()
for o in G4:
    if o['rid'] is None: continue
    k = (o['rid'], o['usd92'])
    if k in seen: continue
    seen.add(k)
    fam = o['fam']; s = SER[fam]; bank = o['bank_k'] * 1000
    eur92 = o['usd92'] / EURUSD_1392
    obs.append(dict(fam=fam, src='G4', f=lambda t, Y, e=eur92, s=s, b=bank: e * PJ(s, Y) / PJ(s, 1392) * fx(t, Y) / b))
for o in MK:
    if o['rid'] is None: continue
    rec = R[o['rid']]; fam = rec['fam']; s = SER[fam]
    if rec['price'] is None: continue
    y, m = [int(x) for x in o['date'].split('/')[:2]]
    rial = o['price'] * (10 if o['cur'] == 'تومان' else 1) * o['lenfix']
    bank = rec['price'] * 1000
    src = 'MK'
    obs.append(dict(fam=fam, src=src, f=lambda t, Y, r=rial, s=s, b=bank, y=y, m=m: r / (b * fx(t, y, m) / fx(t, Y) * PJ(s, y) / PJ(s, Y))))

def med(lst): return st.median(lst) if lst else None
def best(vals):  # vals: {Y: median ratio}; choose Y with |log| min
    v = {Y: r for Y, r in vals.items() if r}
    return min(v, key=lambda Y: abs(math.log(v[Y]))) if v else None
res = {}
fams = [f[0] for f in FAMILIES]
print('fam | n_G4 | G4 ratio@1385 | G4 bestY (ratio) | n_MK | MK FREE @1385 | bestY FREE | MK NIMA @1385 | bestY NIMA')
for fam in fams + ['ALL']:
    row = {}
    for src in ('G4', 'MK'):
        L = [o for o in obs if (o['fam'] == fam or fam == 'ALL') and o['src'] == src]
        for t in ('FREE', 'NIMA'):
            vals = {Y: med([o['f'](t, Y) for o in L]) for Y in YS}
            row[(src, t)] = (len(L), vals, best(vals))
    res[fam] = row
    g = row[('G4', 'FREE')]; gn = row[('G4', 'NIMA')]; mf = row[('MK', 'FREE')]; mn = row[('MK', 'NIMA')]
    if g[0] == 0 and mf[0] == 0: continue
    fmt = lambda x: f'{x:.2f}' if x else '-'
    print(fam, '|', g[0], '|', fmt(g[1][1385]), '|', g[2], fmt(g[1].get(g[2])) if g[2] else '', '| nima', gn[2], '|', mf[0], '|', fmt(mf[1][1385]), '|', mf[2], fmt(mf[1].get(mf[2])) if mf[2] else '', '|', fmt(mn[1][1385]), '|', mn[2], fmt(mn[1].get(mn[2])) if mn[2] else '')
json.dump({f: {f'{a}|{b}': [v[0], v[1], v[2]] for (a, b), v in r.items()} for f, r in res.items()}, open('calib.json', 'w'), ensure_ascii=False)

# extra checks
def sv(s):
    s=s.split(' / ')[0].split(' x ')[0]; t=0
    for p in s.split():
        t+= eval(p) if '/' in p else float(p)
    return t
for src in ('G4','MK'):
    for big in (False,True):
        L=[]
        if src=='G4':
            for o in G4:
                if o['fam']=='BAL' and o['rid'] is not None and (sv(o['b1'])>=6)==big:
                    L.append(o['usd92']/EURUSD_1392*PJ('C2814',1388)/PJ('C2814',1392)*fx('NIMA',1388)/(o['bank_k']*1000))
        else:
            for o in MK:
                if o['rid'] is None: continue
                rec=R[o['rid']]
                if rec['fam']=='BAL' and (sv(rec['size'])>=6)==big:
                    y,m=[int(x) for x in o['date'].split('/')[:2]]
                    rial=o['price']*(10 if o['cur']=='تومان' else 1)
                    L.append(rial/(rec['price']*1000*fx('NIMA',y,m)/fx('NIMA',1388)*PJ('C2814',y)/PJ('C2814',1388)))
        print('BAL',src,'>=6in' if big else '<6in', len(L), round(st.median(L),2) if L else '-')
b=25550e3
for Y in (1385,1387,1388,1389):
    for t in ('NIMA','FREE'):
        v=b*fx(t,1405,6)/fx(t,Y)*PJ('C2814',1405)/PJ('C2814',Y)
        print('8in ball',Y,t,f'{v:,.0f}', f'trunnion {v*1.05:,.0f}', 'mk/bank', round(6745600000/(v*1.05),2))
