import re, sys
sys.path.insert(0, r'D:\560\ITR-8 mobility test sender1\ITR-8 mobility test sender1\qc_analysis')
from parse_decoded import iter_blocks

TS = re.compile(r'2026 Oct\s+9\s+(\d\d):(\d\d):(\d\d)\.(\d\d\d)')

def ts(lines):
    m = TS.search(lines[0]) if lines else None
    if not m: return None
    h, mi, s, ms = map(int, m.groups())
    return h*3600 + mi*60 + s + ms/1000.0

def value_rows(lines):
    last_dash = -1
    for i, ln in enumerate(lines):
        if re.match(r'^\s*-{20,}', ln):
            last_dash = i
    if last_dash < 0: return []
    return [[f.strip() for f in ln.strip().strip('|').split('|')]
            for ln in lines[last_dash+1:] if ln.strip().startswith('|')]

src = r'D:\560\ITR-8 mobility test sender1\ITR-8 mobility test sender1\qc_analysis\decoded.txt'
raw_out = r'D:\560\ITR-8 mobility test sender1\ITR-8 mobility test sender1\qc_analysis\pdcp_rlc_raw.txt'
sum_out = r'D:\560\ITR-8 mobility test sender1\ITR-8 mobility test sender1\qc_analysis\pdcp_rlc_summary.txt'

n_pdcp = n_rlc = 0
with open(raw_out, 'w', encoding='utf-8') as fraw, open(sum_out, 'w', encoding='utf-8') as fsum:
    for idx, code, lines in iter_blocks(src):
        if code not in ('0xB860', '0xB868'):
            continue
        t = ts(lines)
        if t is None:
            continue
        if code == '0xB860':
            n_pdcp += 1
            fraw.write('=== %08d\t0xB860 ===\n' % idx)
            fraw.write('\n'.join(lines) + '\n\n')
            for f in value_rows(lines):
                if len(f) >= 14 and f[2] == 'DRB':
                    fsum.write('PDCP\t%.3f\tRB%s\tcount=%s\tdiscard=%s/%sB\tRXpkt=%s\tRXbytes=%s\tWMpkt=%s\tWMbytes=%s\tstate=%s\n'
                               % (t, f[1], f[6], f[7], f[8], f[11], f[12], f[9], f[13], f[21] if len(f) > 21 else '?'))
        else:
            n_rlc += 1
            fraw.write('=== %08d\t0xB868 ===\n' % idx)
            fraw.write('\n'.join(lines) + '\n\n')
            for f in value_rows(lines):
                if len(f) >= 13 and f[1] == '5':
                    fsum.write('RLC\t%.3f\tLCID5\ttxNextAck=%s\ttxNext=%s\twinPDU=%s\ttxWinBytes=%s\ttotalTxBytes=%s\tpoll=%s\n'
                               % (t, f[5], f[6], f[7], f[9], f[11], f[12]))

print('PDCP blocks:', n_pdcp, ' RLC blocks:', n_rlc)
print('raw ->', raw_out)
print('summary ->', sum_out)
