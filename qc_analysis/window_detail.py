import re
from parse_decoded import iter_blocks

TS = re.compile(r'2026 Oct\s+9\s+(\d\d):(\d\d):(\d\d)\.(\d\d\d)')

def ts(lines):
    m = TS.search(lines[0]) if lines else None
    if not m: return None
    h,mi,s,ms = map(int, m.groups())
    return h*3600+mi*60+s+ms/1000.0

def value_rows(lines):
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

T0, T1 = 28770, 28780  # 07:59:30-07:59:40  (adjust per need)
# device window of interest: 07:58:04.5 - 07:58:40 => 28684.5 - 28720
T0, T1 = 28684.0, 28721.0

for idx, code, lines in iter_blocks('D:\\560\\decoded.txt'):
    t = ts(lines)
    if t is None or not (T0 <= t <= T1):
        continue
    txt = '\n'.join(lines)
    if code == '0xB8AE':
        for f in value_rows(lines):
            if len(f) >= 7:
                reason, chan = f[5], f[6]
                if chan in ('PUCCH', 'PUSCH', 'PUSCH_PUCCH_SRS_PRACH', 'PRACH', 'SRS') or reason not in ('', 'N/A: Zero Chan Mask'):
                    print('%08.3f SKIP reason=%s chan=%s' % (t, reason, chan))
    elif code == '0xB959':
        m = re.search(r'Purpose = (\w+)', txt)
        if m: print('%08.3f RLM %s' % (t, m.group(1)))
    elif code == '0xB889':
        m = re.search(r'Rach Reason = (\w+)', txt)
        if m: print('%08.3f RACH_TRIG %s' % (t, m.group(1)))
    elif code == '0xB88A':
        m = re.search(r'RACH Result = (\w+)', txt)
        ssb = re.search(r'SSB ID = (\d+)', txt)
        if m: print('%08.3f RACH_ATT %s ssb=%s' % (t, m.group(1), ssb.group(1) if ssb else '?'))
    elif code == '0xB89B':
        for f in value_rows(lines):
            # [0]# [1]Slot [2]Num [3]Frame [4]? [5]Channel [6]CarrierID [7]StartSym [8]NumSym [9]ReqBMask
            # [10]NumHARQ [11]NumSR [12]NumCSF [13]AckBits [14..21]HARQ [22]SRId [23]SRReq [24]CSFCarr [25]ReportId
            if len(f) >= 12 and f[11] == '1':
                srreq = f[23] if len(f) > 23 else '?'
                print('%08.3f UCI SR ch=%s bm=%s srreq=%s' % (t, f[5], f[9], srreq))
    elif code == '0xB896':
        for f in value_rows(lines):
            if len(f) >= 14:
                srbits = f[11] if len(f) > 11 else '?'
                print('%08.3f UCI_PAYLOAD ch=%s srbits=%s srpayload=%s' % (t, f[5], srbits, f[12] if len(f) > 12 else '?'))
    elif code == '0xB885':
        for f in value_rows(lines):
            if len(f) >= 8:
                print('%08.3f DCI %s' % (t, f[7]))
    elif code == '0xB873':
        for f in value_rows(lines):
            if len(f) >= 6:
                bm = f[6] if len(f) > 6 else ''
                print('%08.3f BSR trig=%s bm=%s' % (t, f[5], bm))
    elif code == '0xB860':
        for f in value_rows(lines):
            if len(f) >= 2 and f[1] == '4':
                print('%08.3f PDCP_RB4 wmbytes=%s rxbytes=%s rxpkt=%s count=%s' % (t, f[14], f[12], f[11], f[6]))
    elif code == '0xB868':
        for f in value_rows(lines):
            if len(f) >= 2 and f[1] == '4':
                print('%08.3f RLC_LC4 txbytes=%s win=%s retx=%s' % (t, f[12] if len(f)>12 else '?', f[9] if len(f)>9 else '?', f[8] if len(f)>8 else '?'))
    elif code == '0xB890':
        for f in value_rows(lines):
            if len(f) >= 13 and f[12].strip() in ('SR_ACTIVE', 'RA_ACTIVE', 'RA_IN_PROGRESS'):
                print('%08.3f CDRX %s' % (t, f[12]))
    elif code == '0xB821':
        m = re.search(r'--\s+(.+?)\s*$', lines[0])
        pci = re.search(r'Physical Cell ID = (\d+)', txt)
        if m: print('%08.3f RRC %s pci=%s' % (t, m.group(1).strip(), pci.group(1) if pci else '?'))
    elif code == '0xB823':
        pci = re.search(r'Physical Cell ID = (\d+)', txt)
        if pci: print('%08.3f SERVING_CELL %s' % (t, pci.group(1)))
