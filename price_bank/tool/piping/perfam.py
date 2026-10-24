import json, math, statistics as st, sys
exec(open('calib.py').read().split('def med(')[0])   # reuse obs/G4/MK loaders
exec(open('user1.py').read().split("rows = []")[0])  # L list + esc
fammap = {1:'PIPE',2:'PIPE',3:'PIPE',4:'PIPE',5:'BAL',6:'BAL',7:'GAT',8:'GAT',9:'FLG',10:'FLG',11:'FLG',12:'FLG',13:'TEE',14:'E90',15:'E90'}
for no,d,u,mk,bk,pf,pfn,s,Yp,note in L:
    obs.append(dict(fam=fammap[no], src='US', f=lambda t,Y,mk=mk,b=bk*1000*pf,s=s: mk/(b*esc(t,s,Y))))
YS=list(range(1385,1397))
fams=[f[0] for f in FAMILIES]
print('fam  | n G4/MK/US | best Y per source (NIMA) | combined Y | combined ratio')
choice={}
for fam in fams:
    srcs={}
    for src in ('G4','MK','US'):
        Lx=[o for o in obs if o['fam']==fam and o['src']==src]
        if Lx: srcs[src]=(len(Lx),{Y:st.median([o['f']('NIMA',Y) for o in Lx]) for Y in YS})
    if not srcs: continue
    comb={Y: math.exp(st.mean(math.log(v[1][Y]) for v in srcs.values())) for Y in YS}
    by=min(comb,key=lambda Y:abs(math.log(comb[Y])))
    bests={k:min(v[1],key=lambda Y:abs(math.log(v[1][Y]))) for k,v in srcs.items()}
    choice[fam]=by
    print(f"{fam:5s}|", '/'.join(str(srcs[k][0]) if k in srcs else '-' for k in ('G4','MK','US')), '|', ' '.join(f'{k}:{bests[k]}({srcs[k][1][bests[k]]:.2f})' for k in bests), '|', by, f'{comb[by]:.2f}')
# evaluate: single 1388 vs per-family choice on each source
for name,fn in (('single1388',lambda f:1388),('perfam',lambda f:choice.get(f,1388))):
    for src in ('G4','MK','US'):
        rs=[o['f']('NIMA',fn(o['fam'])) for o in obs if o['src']==src]
        lg=[abs(math.log(r)) for r in rs]
        print(name,src,'n',len(rs),'median',round(st.median(rs),2),'typical error',f'{(math.exp(st.median(lg))-1)*100:.0f}%')
json.dump(choice,open('perfam.json','w'))
