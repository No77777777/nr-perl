import re, sys
from collections import Counter

src = r'D:\560\ITR-8 mobility test sender1\ITR-8 mobility test sender1\ENL2.txt'
pat = re.compile(r'QTRACE (\d\d):(\d\d):(\d\d)\.(\d{6}) \S+ \[\s*([\w./]+)\s+(\d+)\s*\] (.*?) 1 0x')
kind = Counter()
samples = {}
lines = 0
first = last = None
with open(src, 'r', encoding='utf-8', errors='replace') as f:
    for line in f:
        m = pat.search(line)
        if not m:
            continue
        lines += 1
        h, mi, s, us = int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))
        t = h*3600 + mi*60 + s + us/1e6
        first = t if first is None else min(first, t)
        last = t if last is None else max(last, t)
        key = (m.group(5), m.group(6))
        kind[key] += 1
        if key not in samples:
            samples[key] = (m.group(7).strip(), '%02d:%02d:%02d.%06d' % (h, mi, s, us))

print('total QTRACE lines:', lines)
print('first: %.3f  last: %.3f  dur: %.1fs' % (first, last, last-first))
print()
print('%-46s %6s  %s' % ('source file:line', 'count', 'sample text (first occurrence time)'))
for (fname, lnum), cnt in kind.most_common(80):
    text, t0 = samples[(fname, lnum)]
    print('%-46s %6d  [%s] %s' % ('%s:%s' % (fname, lnum), cnt, t0, text[:80]))
