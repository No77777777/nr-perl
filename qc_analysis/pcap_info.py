import struct, sys, datetime

def read_pcap(path):
    with open(path, 'rb') as f:
        hdr = f.read(24)
        magic, = struct.unpack('<I', hdr[:4])
        endian = '<' if magic == 0xa1b2c3d4 else '>'
        if magic not in (0xa1b2c3d4, 0xa1b23c4d):
            raise ValueError('bad magic %x' % magic)
        # ts_sec, ts_usec, incl_len, orig_len
        pkts = []
        while True:
            b = f.read(16)
            if len(b) < 16:
                break
            ts_sec, ts_usec, incl_len, orig_len = struct.unpack(endian + 'IIII', b)
            data = f.read(incl_len)
            if len(data) < incl_len:
                break
            pkts.append((ts_sec, ts_usec, incl_len, data))
    return pkts

for path in sys.argv[1:]:
    pkts = read_pcap(path)
    print('==', path, 'packets:', len(pkts))
    if not pkts:
        continue
    t0 = pkts[0][0] + pkts[0][1]/1e6
    t1 = pkts[-1][0] + pkts[-1][1]/1e6
    print(' first:', datetime.datetime.fromtimestamp(t0), 'last:', datetime.datetime.fromtimestamp(t1), 'dur: %.1fs' % (t1-t0))
    # per-second UDP traffic histogram
    hist = {}
    for ts_sec, ts_usec, incl_len, data in pkts:
        # IP header: version in first nibble
        if len(data) < 20:
            continue
        v = data[0] >> 4
        if v == 4:
            proto = data[9]
            ihl = (data[0] & 0xF) * 4
            if proto == 17 and len(data) >= ihl + 8:
                hist[ts_sec] = hist.get(ts_sec, 0) + 1
        elif v == 6:
            proto = data[6]
            if proto == 17 and len(data) >= 40 + 8:
                hist[ts_sec] = hist.get(ts_sec, 0) + 1
    for sec in sorted(hist):
        print('  udp/s  %s  %d' % (datetime.datetime.fromtimestamp(sec).strftime('%H:%M:%S'), hist[sec]))
