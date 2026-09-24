# Desk probe (Docs/handoff-camera-context-floor.md §6): each committed fixture's
# natural scale levels via single-linkage over its stops. Run from repo root.
# Reads only Tests/Fixtures/trips/*.json (committed, never local dumps).
import json,math,glob,sys
def dist(a,b):
    la=math.radians((a[0]+b[0])/2)
    return math.hypot((a[0]-b[0])*111320,(a[1]-b[1])*111320*math.cos(la))
def span(ps):
    la=[p[0] for p in ps]; lo=[p[1] for p in ps]; c=math.cos(math.radians(sum(la)/len(la)))
    return max((max(la)-min(la))*111320,(max(lo)-min(lo))*111320*c)
for f in sorted(glob.glob('Tests/Fixtures/trips/*.json')):
    d=json.load(open(f)); ps=[(p['lat'],p['lon']) for p in d['photos']]
    # dedupe near-identical photos into stops (<300 m, consecutive)
    stops=[]
    for p in ps:
        if not stops or dist(stops[-1][-1],p)>300: stops.append([p])
        else: stops[-1].append(p)
    pts=[s[0] for s in stops]
    cl=[[i] for i in range(len(pts))]; merges=[]
    while len(cl)>1:
        best=None
        for i in range(len(cl)):
            for j in range(i+1,len(cl)):
                dd=min(dist(pts[a],pts[b]) for a in cl[i] for b in cl[j])
                if best is None or dd<best[0]: best=(dd,i,j)
        dd,i,j=best; new=cl[i]+cl[j]; merges.append((dd,span([pts[k] for k in new]),len(new)))
        cl=[c for k,c in enumerate(cl) if k not in(i,j)]+[new]
    # natural levels: a merge whose link is > 3x the previous largest link
    print(f.split('/')[-1], 'stops',len(pts), 'whole span %.1f km'%(span(pts)/1000))
    mx=0
    for dd,sp,n in merges:
        if mx and dd>3*mx: print('   level break: clusters up to %.1f km, next link %.1f km'%(prev/1000, dd/1000))
        mx=max(mx,dd); prev=sp
