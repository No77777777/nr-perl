import struct, sys, datetime
from collections import defaultdict

def read_pcap(path):
    with open(path, 'rb') as f:
        hdr = f.read(24)
        magic, = struct.unpack('<I', hdr[:4])
        endian = '<' if magic == 0xa1b2c3d4 else '>'
        pkts = []
        while True:
            b = f.read(16)
            if len(b) < 16: break
            ts_sec, ts_usec, incl, orig = struct.unpack(endian + 'IIII', b)
            data = f.read(incl)
            if len(data) < incl: break
            pkts.append((ts_sec + ts_usec/1e6, data))
    return pkts

def ipinfo(data):
    off = -1
    for cand in range(0, min(64, len(data)-20)):
        if data[cand] >> 4 == 6 and len(data) >= cand + 40 and data[cand+6] in (17, 58):
            off = cand; break
        if data[cand] == 0x45 and len(data) >= cand + 20 and data[cand+9] in (17, 58):
            off = cand; break
    if off < 0: return None
    d = data[off:]
    if len(d) < 20: return None
    v = d[0] >> 4
    if v == 4:
        ihl = (d[0] & 0xF) * 4
        proto = d[9]
        src = '.'.join(map(str, d[12:16]))
        dst = '.'.join(map(str, d[16:20]))
        sport = dport = None
        if proto == 17 and len(d) >= ihl+8:
            sport, dport = struct.unpack('>HH', d[ihl:ihl+4])
        return v, proto, src, dst, sport, dport
    if v == 6:
        proto = d[6]
        src = d[8:24]; dst = d[24:40]
        sport = dport = None
        if proto == 17 and len(d) >= 40+8:
            sport, dport = struct.unpack('>HH', d[40:44])
        return v, proto, src.hex(), dst.hex(), sport, dport
    return None

for path in sys.argv[1:]:
    print('==', path)
    pkts = read_pcap(path)
    shown = 0
    protos = defaultdict(int)
    for t, data in pkts:
        info = ipinfo(data)
        if info: protos[info[1]] += 1
        else: protos['?'] += 1
        if shown < 4:
            print('  sample:', data[:40].hex(' '))
            shown += 1
    print('  proto histogram:', dict(protos))
    flows = defaultdict(lambda: [0,0,0])
    for t, data in pkts:
        info = ipinfo(data)
        if not info: continue
        v, proto, src, dst, sport, dport = info
        if proto != 17: continue
        key = (src, sport, dst, dport)
        flows[key][0]+=1; flows[key][1]+=len(data); flows[key][2]=t
    for k in sorted(flows, key=lambda k:-flows[k][0])[:10]:
        print(' ', k, 'pkts=%d bytes=%d last=%s' % (flows[k][0], flows[k][1], datetime.datetime.fromtimestamp(flows[k][2])))
