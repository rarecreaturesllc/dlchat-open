import sys,re,heapq,math,itertools
D=sys.argv[1]
def key(w):
    w=w.lower()
    for a,b in [('ph','f'),('ck','k'),('qu','kw'),('wr','r'),('kn','n'),('gh',''),('wh','w'),('tch','ch'),('sh','S'),('ch','C'),('th','T')]:
        w=w.replace(a,b)
    w=re.sub(r'c(?=[eiy])','s',w).replace('c','k').replace('z','s').replace('v','f').replace('d','t').replace('b','p').replace('g','k')
    w=re.sub(r'(.)\1+',r'\1',w)
    return w[0]+re.sub(r'[aeiouy]','',w[1:])
def lev(a,b):
    p=list(range(len(b)+1))
    for i,x in enumerate(a,1):
        c=[i]
        for j,y in enumerate(b,1): c.append(min(p[j]+1,c[-1]+1,p[j-1]+(x!=y)))
        p=c
    return p[-1]
def stats(name,ws):
    kk={}
    for w in ws: kk.setdefault(key(w),[]).append(w)
    coll=[v for v in kk.values() if len(v)>1]
    n1=sum(len(v) for v in coll)
    # edit-distance 1 pairs
    e1=sum(1 for a,b in itertools.combinations(ws,2) if abs(len(a)-len(b))<=1 and lev(a,b)==1)
    print(f"{name}: {len(ws)} words, {math.log2(len(ws)):.2f} bits/word, avg len {sum(map(len,ws))/len(ws):.1f}, avg syll~{sum(len(re.findall(r'[aeiouy]+',w)) for w in ws)/len(ws):.2f}; consonant-skeleton clusters {len(coll)} touching {n1} words; edit-distance-1 pairs {e1}")
    print("   samples:",[v for v in coll[:8]])
bip=[l.strip() for l in open(f'{D}/bip39.txt')]
eff=[l.split()[1] for l in open(f'{D}/eff_short.txt')]
stats('BIP39',bip); stats('EFF short',eff)
# greedy: keep BIP39 words with distinct skeleton and no ed1 neighbour kept, prefer 1-2 syllable
def syl(w): return len(re.findall(r'[aeiouy]+',w))
pool=sorted(set(bip)|set(eff),key=lambda w:(abs(syl(w)-2),len(w),w))
kept=[];seen=set()
for w in pool:
    k=key(w)
    if k in seen or len(w)<4: continue
    if any(abs(len(w)-len(x))<=1 and lev(w,x)<=1 for x in kept): continue
    kept.append(w);seen.add(k)
print('greedy distinct from BIP39+EFF:',len(kept))
# compression estimate: word Huffman using rank-based Zipf over top N + domain words
freq=[l.strip() for l in open(f'{D}/freq10k.txt')][:4096]
weights=[1/(r+1) for r in range(len(freq))]
esc=sum(weights)*0.04
h=[(w,i,None,None) for i,w in enumerate(weights)]+[(esc,len(freq),None,None)]
heapq.heapify(h);c=len(h)+1
while len(h)>1:
    a=heapq.heappop(h);b=heapq.heappop(h);heapq.heappush(h,(a[0]+b[0],c,a,b));c+=1
L={}
def w(n,d):
    if n[2] is None:L[n[1]]=d
    else:w(n[2],d+1);w(n[3],d+1)
w(h[0],0)
ln={t:L[i] for i,t in enumerate(freq)};el=L[len(freq)]
S=["meet at the church at noon","need water at north gate","two men with rifles on maple street heading east","all clear come back to the house after dark","doctor needed at the smith house now bring bandages","generator is out of fuel can you spare five gallons","do not use the radio after nine","yes","road blocked at bridge use river trail","we have food for three more days and need medicine for dad"]
for s in S:
    bits=0;wc=0
    for t in s.split():
        wc+=1
        bits+= ln[t] if t in ln else el+5*len(t)+4
    bits+=6
    for name,bpw in (('10b',10),('11b',11)):
        pass
    hdr=18;tag=64
    tot=bits+hdr+tag
    print(f"{wc:2d} wds {len(s):3d} ch  body {bits:3d}b  total words @11b {math.ceil(tot/11):2d} @10b {math.ceil(tot/10):2d}  raw-utf8 @11b {math.ceil((len(s)*8+hdr+tag)/11):2d} | {s}")
print('sample lengths: the',ln['the'],'water',ln.get('water'),'church',ln.get('church'),'rifles',ln.get('rifles','esc'),'escape',el)
