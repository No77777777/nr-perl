# -*- coding: utf-8 -*-
import csv, os, sys
sys.path.insert(0, r'D:\560\ITR-8 mobility test sender1\ITR-8 mobility test sender1\qc_analysis\pylibs')
import matplotlib
matplotlib.use('Agg')
from matplotlib import pyplot as plt
from matplotlib import font_manager

OUT = r'D:\560\ITR-8 mobility test sender1\ITR-8 mobility test sender1\qc_analysis\phy_rate_out'
for f in [r'C:/Windows/Fonts/msyh.ttc', r'C:/Windows/Fonts/simhei.ttf']:
    if os.path.exists(f):
        font_manager.fontManager.addfont(f)
        plt.rcParams['font.sans-serif'] = ['Microsoft YaHei', 'SimHei']
        break
plt.rcParams['axes.unicode_minus'] = False

def col(name, key):
    with open(os.path.join(OUT, name + '.csv'), encoding='utf-8', newline='') as fh:
        rd = list(csv.reader(fh))
    h = rd[0]; i = h.index(key)
    return [r[0] for r in rd[1:]], [r[1] for r in rd[1:]], [float(r[i]) if r[i] != '' else None for r in rd[1:]]

fig, axes = plt.subplots(2, 2, figsize=(13, 8), dpi=110)
for ax, (name, key, label, unit, color) in zip(axes.flat, [
    ('dl_rate', 'rate_mbps', 'DL 调度速率', 'Mbps', '#1f77b4'),
    ('ul_rate', 'rate_mbps', 'UL 调度速率', 'Mbps', '#d62728'),
    ('dl_rb',   'rb_usage_pct', 'DL RB 占用率', '%', '#2ca02c'),
    ('ul_rb',   'rb_usage_pct', 'UL RB 占用率', '%', '#9467bd'),
]):
    xs, times, ys = col(name, key)
    ax.plot([int(x) for x in xs], ys, color=color, lw=2, marker='o', ms=4)
    ax.set_title(label)
    ax.set_ylabel(unit)
    ax.grid(True, ls='--', alpha=0.5)
    step = max(1, len(xs)//8)
    ax.set_xticks([int(x) for x in xs][::step])
    ax.set_xticklabels([times[j] for j in range(0, len(times), step)], rotation=45, fontsize=8)
    ax.set_xlabel('时间')

fig.suptitle('上下行速率测试总览（物理层, 1s 粒度, PCI=404 N78 100MHz）', fontsize=13)
fig.tight_layout(rect=[0, 0, 1, 0.97])
p = os.path.join(OUT, 'charts', 'overview.png')
fig.savefig(p)
print('saved', p)
