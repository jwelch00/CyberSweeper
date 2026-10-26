# Regenerates palettes.css from palettes.json and prints contrast/distinctness checks.
# usage: python3 gen_palettes.py palettes.json palettes.css
import json, sys, math, itertools
d = json.load(open(sys.argv[1]))
def hex2rgb(h): h=h.lstrip('#'); return tuple(int(h[i:i+2],16)/255 for i in (0,2,4))
def lin(c): return c/12.92 if c<=0.04045 else ((c+0.055)/1.055)**2.4
def lum(h): r,g,b=[lin(c) for c in hex2rgb(h)]; return 0.2126*r+0.7152*g+0.0722*b
def cr(a,b): la,lb=sorted([lum(a),lum(b)],reverse=True); return (la+0.05)/(lb+0.05)
def lab(h):
    r,g,b=[lin(c) for c in hex2rgb(h)]
    x=(0.4124*r+0.3576*g+0.1805*b)/0.95047; y=(0.2126*r+0.7152*g+0.0722*b); z=(0.0193*r+0.1192*g+0.9505*b)/1.08883
    f=lambda t: t**(1/3) if t>0.008856 else 7.787*t+16/116
    return (116*f(y)-16, 500*(f(x)-f(y)), 200*(f(y)-f(z)))
def de(a,b): return math.dist(lab(a),lab(b))
css=["/* GENERATED from palettes.json by gen_palettes.py, do not edit by hand */"]
for p in d['palettes']:
    c=p['colors']; sel = ':root, [data-palette="%s"]'%p['id'] if p['default'] else '[data-palette="%s"]'%p['id']
    lines=[f"  --{k.replace('E','-e').replace('D','-d').lower() if k in ('tileEdge','inkDim') else k}: {v};" for k,v in c.items()]
    lines+= [f"  --n{i+1}: {v};" for i,v in enumerate(p['numbers'])]
    css.append(sel+" {\n"+"\n".join(lines)+"\n}")
    worst_cr=min((cr(n,c['floor']),i+1) for i,n in enumerate(p['numbers']))
    pairs=sorted((de(p['numbers'][i],p['numbers'][j]),i+1,j+1) for i,j in itertools.combinations(range(6),2))[:3]
    print(f"{p['id']:12} min contrast vs floor {worst_cr[0]:.1f} (n{worst_cr[1]}); inkDim {cr(c['inkDim'],c['void']):.1f}; cipher-on-tile {cr(c['cipher'],c['tile']):.2f}; closest pairs n1-6 dE:", ", ".join(f"{a:.0f}(n{i},n{j})" for a,i,j in pairs))
open(sys.argv[2],'w').write("\n\n".join(css)+"\n")
