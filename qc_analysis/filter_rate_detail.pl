use strict;
use warnings;
use Win32::OLE;
use constant FALSE => 0;
use constant TRUE  => 1;
use constant NULL  => 0;

# 上下行速率分析专用过滤脚本：调度细节 + 信号质量 + 速率/重传/流控
# 调度: DCI(授权/MCS/RB/层数/NDI/RV), UL PHY 信道调度报告, DL TB Report, PDSCH Status/Stats(BLER),
#       UCI Info/Payload(HARQ ACK/NACK, CSI), CSF Report(CQI/PMI/RI), CDRX, Flow Control, Skip UL TX
# 质量: SERVING SNR, Searcher 测量库(RSRP/SINR), RLM Stats(IS/OOS BLER), TX 功率分布, 天线分集
# 速率: L2 UL/DL TB/Data PDU, PDCP UL Stats, PDCP DL Rbs Stats, MAC PDSCH Stats
# ===================== 配置区（直接改这里） =====================
my $HDF  = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1.hdf';
my $OUT  = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\qc_analysis\\rate_detail.txt';
my $CSV  = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\qc_analysis\\rate_metrics.csv';
my $FROM = '07:58:13.251';   # 起始时间，'' = 日志开头
my $TO   = '07:58:40.251';   # 结束时间，'' = 日志结尾
# ================================================================
# 命令行可覆盖配置: perl filter_rate_detail.pl [hdf] [txt] [csv] [from] [to]
$HDF  = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$OUT  = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$CSV  = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$FROM = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$TO   = shift(@ARGV) if @ARGV && $ARGV[0] ne '';

my @CODES = (
    0xB885, 0xB883, 0xB884, 0xB886, 0xB887, 0xB888,   # 调度
    0xB896, 0xB89B, 0xB8A7, 0xB890, 0xB89C, 0xB8AE,   # 反馈/流控/挂起
    0xB8D8, 0xB97F, 0xB959, 0xB8B5, 0xB98F,           # 信号质量/功率
    0xB872, 0xB870, 0xB857, 0xB860, 0xB842,           # 速率计数
);

sub fields {
    my $row = shift;
    $row =~ s/^\s*\|\s*//;
    $row =~ s/\|\s*$//;
    return [ map { s/^\s+|\s+$//g; $_ } split /\|/, $row ];
}

my $app = Win32::OLE->new('QCAT6.Application') or die "no QCAT\n";
$app->{Visible} = FALSE;
$app->{UsePCTime} = FALSE;
my $filter = $app->{PacketFilter};
$filter->SetAll(FALSE);
for my $c (@CODES) { $filter->Set($c, TRUE); }
$filter->Commit();
die "OpenLog failed: $app->{LastError}\n" unless $app->OpenLog($HDF);

sub t2sec {
    my $t = shift;
    return -1 unless $t =~ /^(\d\d):(\d\d):(\d\d)(?:\.(\d+))?$/;
    return $1*3600 + $2*60 + $3 + ($4 // 0)/1000;
}
if ($FROM ne '' || $TO ne '') {
    my $t0 = $FROM ne '' ? t2sec($FROM) : 0;
    my $t1 = $TO   ne '' ? t2sec($TO)   : ($t0 + $app->{LogDuration});
    die "bad time format (use HH:MM:SS.mmm)\n" if $t0 < 0 || $t1 < 0 || $t1 <= $t0;
    my $base   = int($app->{LogStartTime} / 86400) * 86400;
    my $offset = ($base + $t0) - $app->{LogStartTime};
    $app->SetTimeWindow($offset, $t1 - $t0);
    print "time window: $FROM -> $TO\n";
}

open(my $fh, '>', $OUT) or die "out: $!";
binmode($fh);

my (%cnt, %m);   # m{sec}{k} = 逐秒指标
my $prev_dl = -1;
my $p = $app->{FirstPacket};
my $n = 0;
while ($p) {
    $n++;
    $cnt{$p->{Type}}++;
    my $txt = $p->{Text};
    $txt =~ s/\r\n/\n/g;
    printf $fh "=== %08d\t0x%X ===\n", $n, $p->{Type};
    print $fh $txt;
    print $fh "\n";

    my ($h, $mi, $s) = $txt =~ /(\d\d):(\d\d):(\d\d)\.\d\d\d/;
    if (defined $h) {
        my $t = $h*3600 + $mi*60 + $s;
        if ($p->{Type} == 0xB885) {
            for my $row ($txt =~ /^\s*\|\s*\d+\|[^\n]+/mg) {
                my $f = fields($row);
                next unless @$f >= 15 && $f->[7] =~ /^[UD]L_/;
                if ($f->[7] =~ /^UL/ && $f->[14] =~ /^\d+$/) { $m{$t}{ul_mcs} = $f->[14]; }
                if ($f->[7] =~ /^DL/ && $f->[14] =~ /^\d+$/) { $m{$t}{dl_mcs} = $f->[14]; }
            }
        } elsif ($p->{Type} == 0xB872) {
            for my $row ($txt =~ /^\s*\|\s*\d+\|[^\n]+/mg) {
                my $f = fields($row);
                next unless @$f >= 14 && $f->[13] =~ /^\d+$/;
                $m{$t}{ul_tb_bytes} = ($m{$t}{ul_tb_bytes} // 0) + $f->[13];
            }
        } elsif ($p->{Type} == 0xB888) {
            for my $row ($txt =~ /^\s*\|\s*0\s*\|[^\n]+/mg) {
                my $f = fields($row);
                next unless @$f >= 15 && $f->[9] =~ /^\d+$/;
                if ($prev_dl >= 0) {
                    my $d = $f->[9] >= $prev_dl ? $f->[9] - $prev_dl : 0;
                    $m{$t}{dl_tb_bytes} = ($m{$t}{dl_tb_bytes} // 0) + $d;
                }
                $prev_dl = $f->[9];
                $m{$t}{dl_bler} = $f->[14] if $f->[14] =~ /^\d+\.?\d*$/;
            }
        } elsif ($p->{Type} == 0xB8D8) {
            my @snr = $txt =~ /SNR = ([-0-9.]+) dB/g;
            if (@snr) {
                my $sum = 0; $sum += $_ for @snr;
                my $avg = $sum / @snr;
                $m{$t}{snr_cnt} = ($m{$t}{snr_cnt} // 0) + @snr;
                $m{$t}{snr_sum} = ($m{$t}{snr_sum} // 0) + $sum;
            }
        }
    }
    print STDERR "processed $n\n" if $n % 20000 == 0;
    last unless $p->Next();
}

print $fh "\n# 按消息类型统计\n";
for my $t (sort { $cnt{$b} <=> $cnt{$a} } keys %cnt) {
    my $name = $app->GetPacketTypeName($t);
    printf $fh "# 0x%X\t%d\t%s\n", $t, $cnt{$t}, $name;
}
close $fh;

open(my $cfh, '>', $CSV) or die "csv: $!";
print $cfh "sec,ul_tb_bytes,dl_tb_bytes,dl_bler,snr_avg_dB,ul_mcs,dl_mcs\n";
for my $t (sort { $a <=> $b } keys %m) {
    my $hh = sprintf("%02d:%02d:%02d", int($t/3600), int(($t%3600)/60), $t%60);
    my $snr = ($m{$t}{snr_cnt} // 0) ? $m{$t}{snr_sum} / $m{$t}{snr_cnt} : '';
    printf $cfh "%s,%d,%d,%s,%s,%s,%s\n", $hh,
        ($m{$t}{ul_tb_bytes} // 0),
        ($m{$t}{dl_tb_bytes} // 0),
        ($m{$t}{dl_bler} // ''),
        ($snr eq '' ? '' : sprintf("%.2f", $snr)),
        ($m{$t}{ul_mcs} // ''),
        ($m{$t}{dl_mcs} // '');
}
close $cfh;

print "done, $n packets -> $OUT, metrics -> $CSV\n";
for my $t (sort { $cnt{$b} <=> $cnt{$a} } keys %cnt) {
    my $name = $app->GetPacketTypeName($t);
    printf "0x%X\t%d\t%s\n", $t, $cnt{$t}, $name;
}
$p = NULL; $filter = NULL; $app = NULL;
