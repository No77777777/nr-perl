import sys, re
from collections import defaultdict

def iter_blocks(path):
    cur = None
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            m = re.match(r'=== (\d+)\t(0x[0-9A-F]+) ===', line)
            if m:
                if cur: yield cur
                cur = [int(m.group(1)), m.group(2), []]
            elif cur is not None:
                cur[2].append(line.rstrip('\n'))
        if cur: yield cur

if __name__ == '__main__':
    path = sys.argv[1]
    want = set(sys.argv[2:])
    cnt = 0
    for idx, code, lines in iter_blocks(path):
        if want and code not in want: continue
        print('##### %d %s' % (idx, code))
        for ln in lines[:80]:
            print(ln)
        cnt += 1
        if cnt >= 2: break
