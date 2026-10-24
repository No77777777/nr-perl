import struct, sys, datetime
from collections import defaultdict
from pcap_flow import read_pcap, ipinfo

for path in sys.argv[1:]:
    print('==', path)
    pkts = read_pcap(path)
    hist = defaultdict(lambda: [0,0])
    for t, data in pkts:
        info = ipinfo(data)
        if not info: continue
        v, proto, src, dst, sport, dport = info
        if proto != 17: continue
        hist[int(t)][0] += 1
        hist[int(t)][1] += len(data)
    keys = sorted(hist)
    if not keys: continue
    print(' range:', datetime.datetime.fromtimestamp(keys[0]), '->', datetime.datetime.fromtimestamp(keys[-1]))
    prev = None
    for k in keys:
        gap = '' if prev is None or k - prev <= 2 else '  <== GAP %ds' % (k-prev)
        if prev is None or k - prev > 2 or hist[k][0] > 0:
            print('  %s udp=%d bytes=%d%s' % (datetime.datetime.fromtimestamp(k).strftime('%H:%M:%S'), hist[k][0], hist[k][1], gap))
        prev = k
