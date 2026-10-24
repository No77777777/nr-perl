import re

src = r'D:\560\ITR-8 mobility test sender1\ITR-8 mobility test sender1\ENL2.txt'
pat = re.compile(r'QTRACE (\d\d):(\d\d):(\d\d)\.(\d{6}) \S+ \[\s*([\w./]+)\s+(\d+)\s*\] (.*?) 1 0x')

T0, T1 = 28693.251, 28720.251   # 07:58:13.251 - 07:58:40.251
rows = []
with open(src, 'r', encoding='utf-8', errors='replace') as f:
    for line in f:
        m = pat.search(line)
        if not m:
            continue
        h, mi, s, us = int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))
        t = h*3600 + mi*60 + s + us/1e6
        if T0 <= t <= T1:
            rows.append((t, m.group(5), m.group(6), m.group(7).strip()))

rows.sort()
print('窗口内 ENL2 事件数:', len(rows))
print()
print('===== RB4 UL 侧收到的 STATUS（ACK_SN/NACK）序列 =====')
for t, f, l, txt in rows:
    if 'Received status pdu' in txt:
        print('%.3f  %s  %s' % (t, txt[:90], ''))
print()
print('===== 窗口内其它事件（非 status 接收） =====')
for t, f, l, txt in rows:
    if 'Received status pdu' not in txt:
        print('%.3f  %s:%s  %s' % (t, f, l, txt[:110]))
