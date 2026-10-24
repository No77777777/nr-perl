import re

src = r'D:\560\ITR-8 mobility test sender1\ITR-8 mobility test sender1\qc_analysis\probe_dci.txt'
lines = open(src, encoding='utf-8', errors='replace').read().splitlines()

# find the DCI block
start = next(i for i, l in enumerate(lines) if '===== SAMPLE 0xB885' in l)
try:
    end = next(i for i, l in enumerate(lines[start+1:], start+1) if '===== SAMPLE' in l)
except StopIteration:
    end = len(lines)
block = lines[start:end]

dashes = [i for i, l in enumerate(block) if re.match(r'^\s*-{20,}', l)]
hdr = [l for l in block[dashes[0]+1:dashes[1]] if '|' in l]
hdr = hdr[-3:]  # last 3 header lines

def cols(line):
    line = re.sub(r'^\s*\|\s*', '', line)
    line = re.sub(r'\|\s*$', '', line)
    return [c.strip() for c in line.split('|')]

hcols = [cols(l) for l in hdr]
width = max(len(c) for c in hcols)
leaf = []
for i in range(width):
    name = ''
    for c in hcols:
        if i < len(c) and c[i]:
            name = c[i]
    leaf.append(name)

for l in block[dashes[1]+1:]:
    if not re.match(r'^\s*\|\s*(\d+)?\|', l):
        continue
    f = cols(l)
    if len(f) < 8 or ('UL_0_1' not in l and 'DL_1_1' not in l):
        continue
    fmt = f[7]
    if 'UL_0_1' in fmt or 'DL_1_1' in fmt:
        pairs = []
        for i in range(min(len(f), len(leaf))):
            if leaf[i]:
                pairs.append('%s=%s' % (leaf[i], f[i]))
        print('---', fmt, '---')
        print('  ' + ' | '.join(pairs))
