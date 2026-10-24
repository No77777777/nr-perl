import re
from parse_decoded import iter_blocks

TS = re.compile(r'2026 Oct\s+9\s+(\d\d):(\d\d):(\d\d)\.(\d\d\d)')

def ts(lines):
    m = TS.search(lines[0]) if lines else None
    if not m: return None
    h,mi,s,ms = map(int, m.groups())
    return h*3600+mi*60+s+ms/1000.0

for idx, code, lines in iter_blocks('D:\\560\\decoded.txt'):
    t = ts(lines)
    if t is None: continue
    txt = '\n'.join(lines)
    if code == '0xB821':
        pci = re.search(r'Physical Cell ID = (\d+)', txt)
        pdu = re.search(r'--\s+(.+?)\s*$', lines[0])
        if pci:
            print('%08.3f' % t, code, pci.group(1), (pdu.group(1) if pdu else ''))
    elif code == '0xB822':
        pci = re.search(r'Physical Cell ID = (\d+)', txt)
        if pci:
            print('%08.3f' % t, code, pci.group(1), 'MIB')
    elif code == '0xB823':
        pci = re.search(r'Physical Cell ID = (\d+)', txt)
        if pci:
            print('%08.3f' % t, code, pci.group(1), 'ServingCellInfo')
