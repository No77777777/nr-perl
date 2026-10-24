import re, sys
from collections import defaultdict
from parse_decoded import iter_blocks

TS = re.compile(r'2026 Oct\s+9\s+(\d\d):(\d\d):(\d\d)\.(\d\d\d)')

def ts(block_lines):
    m = TS.search(block_lines[0]) if block_lines else None
    if not m: return None
    h,mi,s,ms = map(int, m.groups())
    return h*3600+mi*60+s+ms/1000.0

path = 'D:\\560\\decoded.txt'
out = []
for idx, code, lines in iter_blocks(path):
    t = ts(lines)
    if t is None: continue
    txt = '\n'.join(lines)
    if code == '0xB821':
        pdu = re.search(r'--\s+(.+?)\s*$', lines[0])
        pci = re.search(r'Physical Cell ID = (\d+)', txt)
        pci = pci.group(1) if pci else '?'
        out.append((t, code, pci, (pdu.group(1) if pdu else '?')))
    elif code == '0xB822':
        pci = re.search(r'Physical Cell ID = (\d+)', txt)
        out.append((t, code, pci.group(1) if pci else '?', 'MIB'))
    elif code == '0xB823':
        pci = re.search(r'Physical Cell ID = (\d+)', txt)
        out.append((t, code, pci.group(1) if pci else '?', 'ServingCell'))
    elif code == '0xB889':
        r = re.search(r'Rach Reason = (\w+)', txt)
        out.append((t, code, '', r.group(1) if r else '?'))
    elif code == '0xB88A':
        r = re.search(r'RACH Result = (\w+)', txt)
        out.append((t, code, '', r.group(1) if r else '?'))
    elif code == '0xB959':
        r = re.search(r'Purpose = (\w+)', txt)
        out.append((t, code, '', r.group(1) if r else '?'))
    elif code == '0xB8AE':
        # count drop reasons
        reasons = defaultdict(int)
        for m in re.finditer(r'\|\s*([\w:]+)\|(\s*\w+)\|\s*\n?', txt):
            pass
        s = re.findall(r'\|(\s*TX_SUSPEND|TX_BLANKING|\d+)\|\s*([A-Z_]+)\|', txt)
        for reason, ch in s:
            reasons[(reason.strip(), ch)] += 1
        out.append((t, code, '', str(sorted(reasons.items()))))

for row in sorted(out):
    print('%08.3f' % row[0], row[1], row[2], row[3])
