import re, sys
from collections import Counter

src = r'D:\560\ITR-8 mobility test sender1\ITR-8 mobility test sender1\log.txt'
out = r'D:\560\ITR-8 mobility test sender1\ITR-8 mobility test sender1\qc_analysis\msg_type_counts.txt'

pat = re.compile(r'^\[0x([0-9A-F]+)\] LOG \d\d:\d\d:\d\d\.\d{6} ([A-Za-z0-9 _\-]+)')
cnt = Counter()
lines = 0
with open(src, 'r', encoding='utf-8', errors='replace') as f:
    for line in f:
        m = pat.match(line)
        if m:
            cnt[(m.group(1), m.group(2))] += 1
            lines += 1

with open(out, 'w', encoding='utf-8') as f:
    f.write('log.txt 窗口 07:52:26-07:58:44（设备UTC），总报文 %d 条，%d 种消息\n' % (lines, len(cnt)))
    for (code, name), n in cnt.most_common():
        f.write('0x%s\t%d\t%s\n' % (code, n, name))
print('total lines:', lines, 'types:', len(cnt), '->', out)
