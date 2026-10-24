use strict;
use warnings;
use Win32::OLE;
use constant FALSE => 0;
use constant TRUE  => 1;
use constant NULL  => 0;

# 上下行速率测试指标聚合工具（物理层指标平均/聚合）
# 用法: perl throughput_metrics.pl [hdf] [报告txt] [csv]
# ===================== 配置区（直接改这里） =====================
my $HDF  = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\10-22.09-19-13-0755gthroughput.hdf';
my $OUT  = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\qc_analysis\\throughput_metrics_report.txt';
my $CSV  = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\qc_analysis\\throughput_metrics_series.csv';
my $FROM = '01:17:51.499589';   # 起始时间（设备时钟），'' = 日志开头
my $TO   = '01:18:16.501324';   # 结束时间，'' = 日志结尾
# ================================================================
$HDF  = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$OUT  = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$CSV  = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$FROM = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$TO   = shift(@ARGV) if @ARGV && $ARGV[0] ne '';

my @CODES = (
    0xB885,   # DCI（MCS/NDI/RV/HARQ）
    0xB883,   # UL 物理信道调度报告（PUSCH: MCS/调制/RB/TB Size/TX Mode/TX Type）
    0xB888,   # PDSCH Stats（DL BLER/TB 字节/重传）
    0xB8D8,   # 服务小区 SNR
    0xB97F,   # 搜索器测量库（RSRP/RSRQ）
    0xB8A7,   # CSF Report（RI/CQI/PMI）
    0xB89B,   # UCI（HARQ ACK/NACK 反馈）
    0xB857,   # L2 DL DATA PDU（DL TB Size）
    0xB823,   # RRC Serving Cell Info（PCI/频点/带宽）
    0xB860,   # PDCP UL Stats（应用层上行字节）
    0xB842,   # PDCP DL Rbs Stats（PDCP 下行字节）
    0xB8B5,   # 上行发射功率分布
);

sub t2sec {
    my $t = shift;
    return -1 unless $t =~ /^(\d\d):(\d\d):(\d\d)(?:\.(\d+))?$/;
    my $frac = defined $4 ? $4 / (10 ** length($4)) : 0;
    return $1*3600 + $2*60 + $3 + $frac;
}
sub fields {
    my $row = shift;
    $row =~ s/^\s*\|\s*//;
    $row =~ s/\|\s*$//;
    return [ map { s/^\s+|\s+$//g; $_ } split /\|/, $row ];
}
sub header_leafs {
    my ($lines) = @_;
    my @d = grep { $lines->[$_] =~ /^\s*-{20,}/ } 0..$#$lines;
    return {} unless @d >= 2;
    my @h = grep { $lines->[$_] =~ /\|/ } ($d[0]+1)..($d[1]-1);
    my @hcols;
    for my $i (@h) {
        my $l = $lines->[$i];
        $l =~ s/^\s*\|\s*//; $l =~ s/\|\s*$//;
        my @c = map { s/^\s+|\s+$//g; $_ } split /\|/, $l;
        push @hcols, \@c;
    }
    my $w = 0; for my $c (@hcols) { $w = @$c if @$c > $w; }
    my @leaf = ('') x $w;
    for my $c (@hcols) {
        for my $i (0..$#$c) { $leaf[$i] = $c->[$i] if $c->[$i] ne ''; }
    }
    return \@leaf;
}

my $app = Win32::OLE->new('QCAT6.Application') or die "no QCAT\n";
$app->{Visible} = FALSE;
$app->{UsePCTime} = FALSE;
my $filter = $app->{PacketFilter};
$filter->SetAll(FALSE);
for my $c (@CODES) { $filter->Set($c, TRUE); }
$filter->Commit();
die "OpenLog failed: $app->{LastError}\n" unless $app->OpenLog($HDF);

my ($t0, $t1) = (t2sec($FROM), t2sec($TO));
$t0 = 0 if $FROM eq '';
$t1 = $t0 + 3600 if $TO eq '';
die "bad time\n" if $t0 < 0 || $t1 <= $t0;
my $base = int($app->{LogStartTime} / 86400) * 86400;
my $offset = ($base + $t0) - $app->{LogStartTime};
$app->SetTimeWindow($offset, $t1 - $t0);
print "time window: $FROM -> $TO\n";

# 累计器
my (%n, %sum, %min, %max);      # UL 指标
my ($ul_tb_bytes, $dl_tb_bytes) = (0, 0);
my (%dl);                        # DL 指标
my (%pwr);
my $pwr_n = 0;
my (@snr_all, @snr_rx);
my (%rsrp, %rsrq);
my ($prev_pass, $prev_fail, $prev_retx, $prev_pass_bytes) = (-1, -1, -1, -1);
my ($d_pass, $d_fail, $d_retx, $d_pass_bytes) = (0, 0, 0, 0);
my ($pdcp_ul, $pdcp_dl, $pdcp_ul_prev, $pdcp_dl_prev) = (0, 0, -1, -1);
my ($uci_harq, $uci_ack) = (0, 0);
my (%series, $serv_pci, %cell_vote, %cell_info);
my $dci_leaf = [];

sub acc {
    my ($k, $v) = @_;
    return unless $v =~ /^-?\d+(\.\d+)?$/;
    $n{$k}++;
    $sum{$k} += $v;
    $min{$k} = $v if !defined $min{$k} || $v < $min{$k};
    $max{$k} = $v if !defined $max{$k} || $v > $max{$k};
}
sub avg { my ($k) = @_; return $n{$k} ? $sum{$k} / $n{$k} : undef; }

my $p = $app->{FirstPacket};
my $n = 0;
while ($p) {
    $n++;
    my $txt = $p->{Text};
    my ($h, $mi, $s, $frac) = $txt =~ /(\d\d):(\d\d):(\d\d)\.(\d+)/;
    my $t = defined $h ? $h*3600 + $mi*60 + $s + $frac/(10**length($frac)) : undef;
    if ($p->{Type} == 0xB885) {
        my @lines = split /\r?\n/, $txt;
        $dci_leaf = header_leafs(\@lines);
        my ($ul_mcs_idx, $dl_mcs_idx) = (-1, -1);
        for my $i (0..$#$dci_leaf) {
            if ($dci_leaf->[$i] eq 'MCS') { $ul_mcs_idx = $i if $ul_mcs_idx < 0; $dl_mcs_idx = $i; }
        }
        for my $l (@lines) {
            next unless $l =~ /\|.*(?:UL_\d_\d|DL_\d_\d)/;
            my $f = fields($l);
            next unless @$f >= 8;
            next unless $f->[7] =~ /^(UL|DL)_\d_\d$/;
            if ($f->[7] =~ /^UL/ && $ul_mcs_idx >= 0 && $f->[$ul_mcs_idx] =~ /^\d+$/) {
                acc('ul_mcs', $f->[$ul_mcs_idx]);
                $series{int($t)}{ul_mcs} = $f->[$ul_mcs_idx];
            } elsif ($f->[7] =~ /^DL/ && $dl_mcs_idx >= 0 && $f->[$dl_mcs_idx] =~ /^\d+$/) {
                acc('dl_mcs', $f->[$dl_mcs_idx]);
                $series{int($t)}{dl_mcs} = $f->[$dl_mcs_idx];
            }
        }
    } elsif ($p->{Type} == 0xB883) {
        for my $l (split /\r?\n/, $txt) {
            next unless $l =~ /\|\s*PUSCH\s*\|/;
            my $f = fields($l);
            next unless @$f >= 27;
            acc('ul_rb', $f->[18]);
            acc('ul_tbs', $f->[21]);
            $ul_tb_bytes += $f->[21] if $f->[21] =~ /^\d+$/;
            $series{int($t)}{ul_tb_bytes} += $f->[21];
            $n{'ul_mcs_table'}{$f->[15]}++ if $f->[15] ne '';
            $n{'ul_txmode'}{$f->[24]}++ if $f->[24] ne '';
            $n{'ul_txtype'}{$f->[26]}++ if $f->[26] ne '';
        }
    } elsif ($p->{Type} == 0xB888) {
        for my $l (split /\r?\n/, $txt) {
            next unless $l =~ /^\s*\|\s*0\s*\|/;
            my $f = fields($l);
            next unless @$f >= 15 && $f->[4] =~ /^\d+$/;
            my $pass = $f->[4]; my $fail = $f->[5]; my $retx = $f->[6];
            my $pb = $f->[9] =~ /^\d+$/ ? $f->[9] : 0;
            if ($prev_pass >= 0) {
                $d_pass += $pass >= $prev_pass ? $pass - $prev_pass : $pass;
                $d_fail += $fail >= $prev_fail ? $fail - $prev_fail : $fail;
                $d_retx += $retx >= $prev_retx ? $retx - $prev_retx : $retx;
                $d_pass_bytes += $pb >= $prev_pass_bytes ? $pb - $prev_pass_bytes : $pb;
            }
            $prev_pass = $pass; $prev_fail = $fail; $prev_retx = $retx;
            $prev_pass_bytes = $pb;
        }
    } elsif ($p->{Type} == 0xB8D8) {
        my @snr = $txt =~ /SNR = ([-0-9.]+) dB/g;
        if (@snr) {
            push @snr_all, @snr;
            $snr_rx[$_] += $snr[$_] for 0..$#snr;
            $n{'snr_samples'}++;
            my $s = 0; $s += $_ for @snr;
            $series{int($t)}{snr_avg} = $s / @snr;
        }
        if ($txt =~ /Cell Id = (\d+)/) { $cell_vote{$1}++; }
    } elsif ($p->{Type} == 0xB97F) {
        for my $l (split /\r?\n/, $txt) {
            next unless $l =~ /^\s*\|\s*\d+\|\s*\d+\|/;
            my $f = fields($l);
            next unless @$f >= 6 && $f->[4] =~ /^-?\d+(\.\d+)?$/;
            push @{$rsrp{$f->[1]}}, $f->[4];
            push @{$rsrq{$f->[1]}}, $f->[5];
        }
    } elsif ($p->{Type} == 0xB8A7) {
        my @rows = grep { /^\s*\|\s*\d+\|/ } split /\r?\n/, $txt;
        for my $l (@rows) {
            my $f = fields($l);
            next unless @$f >= 20 && $f->[5] =~ /CRI/;
            acc('ri', $f->[18]);
            acc('cqi', $f->[19]);
            $series{int($t)}{ri} = $f->[18];
        }
    } elsif ($p->{Type} == 0xB89B) {
        for my $l (split /\r?\n/, $txt) {
            next unless $l =~ /^\s*\|\s*\d+\|/;
            my $f = fields($l);
            next unless @$f >= 14 && $f->[10] =~ /^\d+$/;
            $uci_harq += $f->[10];
            $uci_ack  += $f->[13] if $f->[13] =~ /^\d+$/;
        }
    } elsif ($p->{Type} == 0xB857) {
        my $in = 0;
        for my $l (split /\r?\n/, $txt) {
            if ($l =~ /TB Data Agg/) { $in = 1; next; }
            next unless $in && $l =~ /^\s*\|\s*\d+\|\s*\d+\|/;
            my $f = fields($l);
            next unless @$f >= 2 && $f->[1] =~ /^\d+$/;
            $dl_tb_bytes += $f->[1];
            $series{int($t)}{dl_tb_bytes} += $f->[1];
        }
    } elsif ($p->{Type} == 0xB823) {
        if ($txt =~ /Physical Cell ID = (\d+)/) { $serv_pci = $1; }
        $cell_info{pci} = $1 if $txt =~ /Physical Cell ID = (\d+)/;
        $cell_info{freq} = $1 if $txt =~ /DL Frequency = (\d+)/;
        $cell_info{bw} = $1 if $txt =~ /DL Bandwidth = (\d+)/;
    } elsif ($p->{Type} == 0xB860) {
        for my $l (split /\r?\n/, $txt) {
            next unless $l =~ /\|\s*DRB\s*\|/;
            my $f = fields($l);
            next unless @$f >= 14 && $f->[12] =~ /^\d+$/;
            if ($pdcp_ul_prev >= 0) {
                my $d = $f->[12] >= $pdcp_ul_prev ? $f->[12] - $pdcp_ul_prev : $f->[12];
                $pdcp_ul += $d;
            }
            $pdcp_ul_prev = $f->[12];
        }
    } elsif ($p->{Type} == 0xB842) {
        for my $l (split /\r?\n/, $txt) {
            next unless $l =~ /^\s*\|\s*\d+\|/;
            my $f = fields($l);
            next unless @$f >= 9 && ($f->[6] // '') eq '1' && $f->[8] =~ /^\d+$/;
            if ($pdcp_dl_prev >= 0) {
                my $d = $f->[8] >= $pdcp_dl_prev ? $f->[8] - $pdcp_dl_prev : $f->[8];
                $pdcp_dl += $d;
            }
            $pdcp_dl_prev = $f->[8];
        }
    } elsif ($p->{Type} == 0xB8B5) {
        for my $l (split /\r?\n/, $txt) {
            next unless $l =~ /^\s*\|\s*\d+\|/;
            my $f = fields($l);
            next unless @$f >= 5;
            for my $i (1..4) {
                $pwr{$i} += $f->[$i] if $f->[$i] =~ /^\d+(\.\d+)?$/;
            }
            $pwr_n++;
        }
    }
    last unless $p->Next();
}

my $dur = $t1 - $t0;
my @srv_pci = sort { $cell_vote{$b} <=> $cell_vote{$a} } keys %cell_vote;
my $spci = $serv_pci // ($srv_pci[0] // '?');
my $sr = $rsrp{$spci} ? (eval { my $s=0; $s+=$_ for @{$rsrp{$spci}}; $s/@{$rsrp{$spci}} }) : undef;
my $sq = $rsrq{$spci} ? (eval { my $s=0; $s+=$_ for @{$rsrq{$spci}}; $s/@{$rsrq{$spci}} }) : undef;

sub mcs2mod {
    my ($m) = @_;
    return 'QPSK' if $m <= 4;
    return '16QAM' if $m <= 11;
    return '64QAM' if $m <= 19;
    return '256QAM';
}
my $snr_avg = @snr_all ? (eval { my $s=0; $s+=$_ for @snr_all; $s/@snr_all }) : undef;

open(my $fh, '>', $OUT) or die $!;
binmode($fh);
print $fh "========== 上下行速率测试指标聚合报告 ==========\n";
printf $fh "窗口: %s ~ %s (%.2f s), 解析报文 %d 条\n", $FROM, $TO, $dur, $n;
print $fh "服务小区: PCI=$spci", ($cell_info{freq} ? " ARFCN=$cell_info{freq}" : ''), ($cell_info{bw} ? " 带宽=$cell_info{bw}MHz" : ''), "\n\n";

print $fh "--- 上行 ---\n";
printf $fh "PUSCH TB 字节合计: %d bytes -> %.2f Mbps\n", $ul_tb_bytes, $ul_tb_bytes*8/$dur/1e6;
printf $fh "PDCP 上行接收(应用层): %.2f Mbps\n", $pdcp_ul*8/$dur/1e6;
printf $fh "UL MCS: avg %.2f, min %d, max %d\n", avg('ul_mcs')//0, $min{'ul_mcs'}//'-', $max{'ul_mcs'}//'-';
print $fh "UL 调制方式分布: ", join(' ', map { "$_=$n{'ul_mcs_table'}{$_}" } sort keys %{$n{'ul_mcs_table'}}), "\n";
printf $fh "UL RB 数: avg %.1f, max %d\n", avg('ul_rb')//0, $max{'ul_rb'}//'-';
printf $fh "UL TB Size: avg %.0f bytes, max %d\n", avg('ul_tbs')//0, $max{'ul_tbs'}//'-';
print $fh "UL TX Mode(层数): ", join(' ', map { "$_=$n{'ul_txmode'}{$_}" } sort keys %{$n{'ul_txmode'}}), "\n";
my ($newtx, $retx) = ($n{'ul_txtype'}{'NEW_TX'}//0, 0);
for my $k (keys %{$n{'ul_txtype'}}) { $retx += $n{'ul_txtype'}{$k} if $k =~ /RETX|RE_TX|RE_?TX/i; }
printf $fh "UL HARQ 重传率: %d/%d = %.2f%%\n", $retx, ($newtx+$retx), ($newtx+$retx) ? $retx/($newtx+$retx)*100 : 0;
printf $fh "UL TX Power 分布: <6dBm %.1f%%, 6-12dBm %.1f%%, 12-18dBm %.1f%%, >18dBm %.1f%%\n",
    $pwr_n ? $pwr{1}/$pwr_n : 0, $pwr_n ? $pwr{2}/$pwr_n : 0, $pwr_n ? $pwr{3}/$pwr_n : 0, $pwr_n ? $pwr{4}/$pwr_n : 0;

print $fh "\n--- 下行 ---\n";
printf $fh "DL TB 字节合计(L2): %d bytes -> %.2f Mbps\n", $dl_tb_bytes, $dl_tb_bytes*8/$dur/1e6;
printf $fh "PDSCH CRC Pass TB 字节: %.2f Mbps\n", $d_pass_bytes*8/$dur/1e6;
printf $fh "PDCP 下行字节: %.2f Mbps\n", $pdcp_dl*8/$dur/1e6;
printf $fh "DL MCS: avg %.2f, min %d, max %d -> 调制 %s\n", avg('dl_mcs')//0, $min{'dl_mcs'}//'-', $max{'dl_mcs'}//'-', mcs2mod(avg('dl_mcs')//0);
printf $fh "DL RI(层数): avg %.2f\n", avg('ri')//0;
printf $fh "DL CQI: avg %.2f\n", avg('cqi')//0;
my $bler = ($d_pass+$d_fail) ? $d_fail/($d_pass+$d_fail)*100 : 0;
printf $fh "DL BLER: %d/%d = %.2f%%\n", $d_fail, ($d_pass+$d_fail), $bler;
printf $fh "DL HARQ 重传率: %.2f%%\n", ($d_pass+$d_fail) ? $d_retx/($d_pass+$d_fail)*100 : 0;
my $ackr = $uci_harq ? ($uci_ack > $uci_harq ? 100 : $uci_ack/$uci_harq*100) : 0;
printf $fh "DL HARQ ACK 率(UCI 反馈): %d/%d = %.2f%%\n", $uci_ack, $uci_harq, $ackr;

print $fh "\n--- 射频 ---\n";
printf $fh "SINR(SSB): 平均 %.2f dB, 天线0..3: ", $snr_avg//0;
for my $i (0..3) {
    printf $fh "RX%d=%.2f ", $i, ($n{'snr_samples'} ? $snr_rx[$i]/$n{'snr_samples'} : 0);
}
print $fh "\n";
printf $fh "服务小区 RSRP: %s dBm, RSRQ: %s dB\n", (defined $sr ? sprintf('%.1f', $sr) : 'NA'), (defined $sq ? sprintf('%.1f', $sq) : 'NA');
close $fh;

open(my $cfh, '>', $CSV) or die $!;
print $cfh "sec,ul_tb_bytes,dl_tb_bytes,ul_mcs,dl_mcs,snr_avg,ri\n";
for my $t (sort { $a <=> $b } keys %series) {
    my $hh = sprintf("%02d:%02d:%02d", int($t/3600), int(($t%3600)/60), $t%60);
    printf $cfh "%s,%d,%d,%s,%s,%s,%s\n", $hh,
        ($series{$t}{ul_tb_bytes} // 0),
        ($series{$t}{dl_tb_bytes} // 0),
        ($series{$t}{ul_mcs} // ''),
        ($series{$t}{dl_mcs} // ''),
        (defined $series{$t}{snr_avg} ? sprintf("%.2f", $series{$t}{snr_avg}) : ''),
        ($series{$t}{ri} // '');
}
close $cfh;
print "done, $n packets -> $OUT, $CSV\n";
$p = NULL; $filter = NULL; $app = NULL;
