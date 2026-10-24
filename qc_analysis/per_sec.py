import re
from collections import defaultdict

counts = defaultdict(lambda: [0,0,0,0,0,0,0])  # grant, sr, bsrhigh, skip, rach, ultx, dldci
cur = None
with open('D:\\560\\events.txt') as f:
    for line in f:
        m = re.match(r'(\d\d:\d\d:\d\d) (.+)', line.strip())
        if not m: continue
        sec = m.group(1)
        ev = m.group(2)
        if 'ULGRANT' in ev: counts[sec][0] += 1
        elif 'UCI_SR' in ev: counts[sec][1] += 1
        elif 'BSR_HIGH' in ev: counts[sec][2] += 1
        elif 'SKIP' in ev: counts[sec][3] += 1
        elif 'RACH' in ev: counts[sec][4] += 1
        elif 'ULTX_' in ev: counts[sec][5] += 1
        elif 'DLDCI' in ev: counts[sec][6] += 1

prev = None
for sec in sorted(counts):
    gap = ''
    if prev:
        p = prev
        c = sec
        dt = (int(c[:2])*3600+int(c[3:5])*60+int(c[6:8])) - (int(p[:2])*3600+int(p[3:5])*60+int(p[6:8]))
        if dt > 2: gap = ' GAP'
    print(sec, 'grant=%d sr=%d bsr=%d skip=%d rach=%d ultx=%d dldci=%d%s' % tuple(counts[sec] + [gap]))
    prev = sec
