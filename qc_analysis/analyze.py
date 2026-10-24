import re, sys
from collections import defaultdict
from parse_decoded import iter_blocks

TS = re.compile(r'2026 Oct\s+9\s+(\d\d):(\d\d):(\d\d)\.(\d\d\d)')

def ts(lines):
    m = TS.search(lines[0]) if lines else None
    if not m: return None
    h,mi,s,ms = map(int, m.groups())
    return h*3600+mi*60+s+ms/1000.0

def value_rows(lines):
    # find last dashed separator line, then rows after it
    last_dash = -1
    for i, ln in enumerate(lines):
        if re.match(r'^\s*-{20,}', ln):
            last_dash = i
    if last_dash < 0: return []
    rows = []
    for ln in lines[last_dash+1:]:
        ln = ln.strip()
        if not ln.startswith('|'): continue
        fields = [f.strip() for f in ln.strip('|').split('|')]
        rows.append(fields)
    return rows

events = defaultdict(list)
first = None
last = None
for idx, code, lines in iter_blocks('D:\\560\\decoded.txt'):
    t = ts(lines)
    if t is None: continue
    first = t if first is None else min(first, t)
    last = t if last is None else max(last, t)
    txt = '\n'.join(lines)
    if code == '0xB8AE':
        for f in value_rows(lines):
            if len(f) >= 8:
                reason, ch = f[6], f[7]
                events[int(t)].append('SKIP %s %s' % (reason, ch))
    elif code == '0xB959':
        m = re.search(r'Purpose = (\w+)', txt)
        if m: events[int(t)].append('RLM ' + m.group(1))
    elif code == '0xB889':
        m = re.search(r'Rach Reason = (\w+)', txt)
        if m: events[int(t)].append('RACH_TRIG ' + m.group(1))
    elif code == '0xB88A':
        m = re.search(r'RACH Result = (\w+)', txt)
        if m: events[int(t)].append('RACH_ATTEMPT ' + m.group(1))
    elif code == '0xB89B':
        sr = 0
        for f in value_rows(lines):
            if len(f) >= 25 and f[24] == '1':
                sr += 1
        if sr: events[int(t)].append('UCI_SR=%d' % sr)
    elif code == '0xB885':
        ulfmt = defaultdict(int)
        dl = 0
        for f in value_rows(lines):
            if len(f) >= 8 and f[7].startswith('UL'):
                ulfmt[f[7]] += 1
            elif len(f) >= 8 and f[7].startswith('DL'):
                dl += 1
        if ulfmt: events[int(t)].append('ULGRANT ' + str(dict(ulfmt)))
        if dl: events[int(t)].append('DLDCI=%d' % dl)
    elif code in ('0xB872', '0xB870'):
        events[int(t)].append('ULTX_' + code)
    elif code == '0xB873':
        hi = 0; lcg1 = 0
        for f in value_rows(lines):
            if len(f) >= 6 and 'HIGH_DATA_ARRIVAL' in f[5]:
                hi += 1
                if len(f) >= 8 and '1' in f[6]: lcg1 += 1
        events[int(t)].append('BSR_HIGH=%d(L1=%d)' % (hi, lcg1))
    elif code == '0xB890':
        sr = sum(1 for f in value_rows(lines) if len(f) >= 13 and f[12].strip() == 'SR_ACTIVE')
        if sr: events[int(t)].append('CDRX_SR_ACTIVE=%d' % sr)
    elif code == '0xB860':
        for f in value_rows(lines):
            if len(f) >= 3 and f[1] == '4' and f[2] == 'DRB':
                # Current Num WM Bytes is field 16-ish; print whole row compact
                events[int(t)].append('PDCP_DRB4 ' + '|'.join(f[:20]))
    elif code == '0xB821':
        m = re.search(r'--\s+(.+?)\s*$', lines[0])
        pci = re.search(r'Physical Cell ID = (\d+)', txt)
        if m and ('Reconfig' in m.group(1) or 'Reestablish' in m.group(1) or 'Setup' in m.group(1) or 'Release' in m.group(1) or 'Fail' in m.group(1)):
            events[int(t)].append('RRC ' + m.group(1).strip() + ' PCI' + (pci.group(1) if pci else '?'))
    elif code == '0xB823':
        pci = re.search(r'Physical Cell ID = (\d+)', txt)
        if pci: events[int(t)].append('SERVING_CELL PCI' + pci.group(1))

def hms(x):
    return '%02d:%02d:%02d' % (x//3600, (x%3600)//60, x%60)

for sec in sorted(events):
    for e in events[sec]:
        print(hms(sec), e)
