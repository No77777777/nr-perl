import re, sys
src = r'D:\560\ITR-8 mobility test sender1\ITR-8 mobility test sender1\qc_analysis\rate_detail.txt'
lines = open(src, encoding='utf-8', errors='replace').read().splitlines()

def cols(line):
    line = re.sub(r'^\s*\|\s*', '', line)
    line = re.sub(r'\|\s*$', '', line)
    return [c.strip() for c in line.split('|')]

rbs = []
tbs = []
mcs = []
rows = []
ts = ''
for l in lines:
    m = re.match(r'^\d{4} \w{3} +\d+ +(\d\d:\d\d:\d\d\.\d+)', l)
    if m:
        ts = m.group(1)
        continue
    if re.match(r'^\s*\|\s*\d+\|\s*\d+\|', l) and '30kHz' in l:
        f = cols(l)
        if len(f) >= 19 and f[18].strip().isdigit():
            rbs.append(int(f[18]))
            tbs.append(int(f[15]) if f[15].isdigit() else 0)
            mcs.append(int(f[17]) if f[17].isdigit() else -1)
            rows.append((ts, f))

print('0xB887 PDSCH Status records parsed:', len(rbs))
if rbs:
    print('Rbs  min/avg/max =', min(rbs), round(sum(rbs)/len(rbs),1), max(rbs))
    print('TBS  min/avg/max =', min(tbs), round(sum(tbs)/len(tbs),1), max(tbs))
    print('MCS  min/avg/max =', min(mcs), round(sum(mcs)/len(mcs),2), max(mcs))
    big = sorted(rows, key=lambda r: r[1][15].isdigit() and -int(r[1][15]) or 0)[:5]
    print('--- 最大的5条(TB Size) ---')
    for ts_, f in big:
        print(ts_, 'slot=%s frame=%s carrier=%s pci=%s tb=%s mcs=%s rbs=%s mod=%s rx=%s' % (
            f[1], f[3], f[5], f[12], f[15], f[17], f[18], f[40] if len(f)>40 else '?', f[42] if len(f)>42 else '?'))
