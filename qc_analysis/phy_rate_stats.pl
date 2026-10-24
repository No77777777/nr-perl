use strict;
use warnings;
use Win32::OLE;
use constant FALSE => 0;
use constant TRUE  => 1;
use constant NULL  => 0;

# 物理层上下行速率指标分桶统计工具（最小时间粒度，默认1秒，可改 $BIN）
# 输出：每个指标一个 CSV（相当于一个 sheet）+ 一个全指标汇总 CSV
# 用法: perl phy_rate_stats.pl [hdf] [输出目录] [from] [to] [bin秒]
# ===================== 配置区（直接改这里） =====================
my $HDF   = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\10-22.09-19-13-0755gthroughput.hdf';
my $OUTDIR= 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\qc_analysis\\phy_rate_out';
my $FROM  = '01:17:51.499589';   # 起始时间（设备时钟），'' = 日志开头
my $TO    = '01:18:16.501324';   # 结束时间，'' = 日志结尾
my $BIN   = 1;                   # 统计粒度（秒），可改 0.5 / 0.1 等
# ================================================================
$HDF    = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$OUTDIR = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$FROM   = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$TO     = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$BIN    = shift(@ARGV) if @ARGV && $ARGV[0] ne '';

my @CODES = (
    0xB885,   # DCI Info（上下行授权/MCS）
    0xB883,   # UL PHY Channel Schedule Report（PUSCH: RB/MCS/TB Size/新传重传）
    0xB887,   # PDSCH Status（DL: RB/MCS/TB Size/层数/调制/CRC）
    0xB888,   # PDSCH Stats（DL 累计 CRC/重传/BLER）
    0xB89B,   # UCI Information（HARQ ACK/NACK）
    0xB8A7,   # CSF Report（CQI/RI/PMI）
    0xB8D8,   # SERVING SNR
    0xB8B5,   # TX 功率分布（整体直方图）
    0xB823,   # Serving Cell Info（PCI/频点/带宽）
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
    return [] unless @d >= 2;
    my @hcols;
    for my $i (($d[0]+1)..($d[1]-1)) {
        next unless $lines->[$i] =~ /\|/;
        my $l = $lines->[$i];
        $l =~ s/^\s*\|\s*//; $l =~ s/\|\s*$//;
        push @hcols, [ map { s/^\s+|\s+$//g; $_ } split /\|/, $l ];
    }
    my $w = 0; for my $c (@hcols) { $w = @$c if @$c > $w; }
    my @leaf = ('') x $w;
    for my $c (@hcols) {
        for my $i (0..$#$c) { $leaf[$i] = $c->[$i] if $c->[$i] ne ''; }
    }
    return \@leaf;
}
sub hms { my ($t) = @_; return sprintf("%02d:%02d:%02d.%03d", int($t/3600), int(($t%3600)/60), int($t%60), int(($t-int($t))*1000)); }
sub m_avg { my ($b,$k) = @_; return $b->{$k}{n} ? $b->{$k}{s}/$b->{$k}{n} : ''; }
sub m_min { my ($b,$k) = @_; return exists $b->{$k}{mn} ? $b->{$k}{mn} : ''; }
sub m_max { my ($b,$k) = @_; return exists $b->{$k}{mx} ? $b->{$k}{mx} : ''; }
sub acc {
    my ($b,$k,$v) = @_;
    $b->{$k}{n}++; $b->{$k}{s} += $v;
    $b->{$k}{mn} = $v if !exists $b->{$k}{mn} || $v < $b->{$k}{mn};
    $b->{$k}{mx} = $v if !exists $b->{$k}{mx} || $v > $b->{$k}{mx};
}

my $app = Win32::OLE->new('QCAT6.Application') or die "no QCAT\n";
$app->{Visible} = FALSE;
$app->{UsePCTime} = FALSE;
my $filter = $app->{PacketFilter};
$filter->SetAll(FALSE);
for my $c (@CODES) { $filter->Set($c, TRUE); }
$filter->Commit();
die "OpenLog failed: $app->{LastError}\n" unless $app->OpenLog($HDF);

my $t0 = $FROM ne '' ? t2sec($FROM) : 0;
my $t1 = $TO   ne '' ? t2sec($TO)   : ($t0 + $app->{LogDuration});
die "bad time format (HH:MM:SS.mmm)\n" if $t0 < 0 || $t1 <= $t0;
die "bad bin\n" if $BIN <= 0;
my $base = int($app->{LogStartTime} / 86400) * 86400;
$app->SetTimeWindow(($base + $t0) - $app->{LogStartTime}, $t1 - $t0);
print "window: $FROM -> $TO, bin=$BIN s\n";

mkdir $OUTDIR unless -d $OUTDIR;
my (%B, %pwr, $pwr_n, %mod_all, %cell, @snr_bin);
my ($prev_pass, $prev_fail, $prev_retx, $prev_pb) = (-1,-1,-1,-1);
my (%seen_harq);   # DL 重传启发式: harq_id|ndi 首次=新传, 重复=重传
my $bins = 0;

my $p = $app->{FirstPacket};
my $n = 0;
while ($p) {
    $n++;
    my $type = $p->{Type};
    my $txt = $p->{Text};
    my ($h,$mi,$s,$frac) = $txt =~ /(\d\d):(\d\d):(\d\d)\.(\d+)/;
    my $t = defined $h ? $h*3600+$mi*60+$s+$frac/(10**length($frac)) : $t0;
    my $bi = int(($t - $t0)/$BIN);
    $bi = 0 if $bi < 0;
    $bins = $bi if $bi > $bins;
    my $b = $B{$bi} ||= {};
    my @lines = split /\r?\n/, $txt;

    if ($type == 0xB885) {
        my $leaf = header_leafs(\@lines);
        my ($ul_m, $dl_m) = (-1, -1);
        for my $i (0..$#$leaf) {
            next unless $leaf->[$i] eq 'MCS';
            $ul_m = $i if $ul_m < 0;
            $dl_m = $i;
        }
        for my $l (@lines) {
            next unless $l =~ /\|.*(?:UL_\d_\d|DL_\d_\d)/;
            my $f = fields($l);
            next unless @$f >= 8 && $f->[7] =~ /^(UL|DL)_\d_\d$/;
            if ($f->[7] =~ /^UL/) {
                $b->{ul_dci}++;
                acc($b,'ul_mcs',$f->[$ul_m]) if $ul_m >= 0 && $f->[$ul_m] =~ /^\d+$/;
            } else {
                $b->{dl_dci}++;
                acc($b,'dl_mcs',$f->[$dl_m]) if $dl_m >= 0 && $f->[$dl_m] =~ /^\d+$/;
            }
        }
    } elsif ($type == 0xB883) {
        for my $l (@lines) {
            next unless $l =~ /\|\s*PUSCH\s*\|/;
            my $f = fields($l);
            next unless @$f >= 27;
            next unless $f->[21] =~ /^\d+$/;
            $b->{ul_tb} += $f->[21];
            acc($b,'ul_rb', $f->[18]) if $f->[18] =~ /^\d+$/;
            acc($b,'ul_tbs',$f->[21]);
            if ($f->[26] =~ /RETX|RE_TX|RE_?TX/i) { $b->{ul_retx}++; }
            else { $b->{ul_newtx}++; }
        }
    } elsif ($type == 0xB887) {
        for my $l (@lines) {
            next unless $l =~ /^\s*\|\s*\d+\|\s*\d+\|/;
            my $f = fields($l);
            next unless @$f >= 43 && $f->[18] =~ /^\d+$/ && $f->[15] =~ /^\d+$/;
            my $tb = $f->[15];
            $b->{dl_tb} += $tb;
            if ($f->[26] eq 'PASS') { $b->{dl_pass}++; $b->{dl_pass_bytes} += $tb; }
            else { $b->{dl_fail}++; }
            acc($b,'dl_rb',$f->[18]);
            acc($b,'dl_layers',$f->[24]) if $f->[24] =~ /^\d+$/;
            $b->{dl_mod}{$f->[40]}++ if $f->[40] ne '';
            $mod_all{$f->[40]}++ if $f->[40] ne '';
            my $hk = ($f->[20] // '?') . '|' . ($f->[28] // '?');
            if ($seen_harq{$hk}++) { $b->{dl_retx}++; } else { $b->{dl_newtx}++; }
        }
    } elsif ($type == 0xB888) {
        for my $l (@lines) {
            next unless $l =~ /^\s*\|\s*0\s*\|/;
            my $f = fields($l);
            next unless @$f >= 15 && $f->[4] =~ /^\d+$/;
            my ($pass,$fail,$retx,$pb) = ($f->[4],$f->[5],$f->[6],$f->[9]);
            $pb = 0 unless $pb =~ /^\d+$/;
            if ($prev_pass >= 0) {
                $b->{crc_pass} += $pass >= $prev_pass ? $pass - $prev_pass : $pass;
                $b->{crc_fail} += $fail >= $prev_fail ? $fail - $prev_fail : $fail;
                $b->{crc_retx} += $retx >= $prev_retx ? $retx - $prev_retx : $retx;
                $b->{crc_pb}   += $pb   >= $prev_pb   ? $pb   - $prev_pb   : $pb;
            }
            ($prev_pass,$prev_fail,$prev_retx,$prev_pb) = ($pass,$fail,$retx,$pb);
        }
    } elsif ($type == 0xB89B) {
        for my $l (@lines) {
            next unless $l =~ /^\s*\|\s*\d+\|/;
            my $f = fields($l);
            next unless @$f >= 14 && $f->[10] =~ /^\d+$/;
            $b->{uci_harq} += $f->[10];
            $b->{uci_ack}  += $f->[13] if $f->[13] =~ /^\d+$/;
        }
    } elsif ($type == 0xB8A7) {
        for my $l (@lines) {
            next unless $l =~ /^\s*\|\s*\d+\|/;
            my $f = fields($l);
            next unless @$f >= 20 && $f->[5] =~ /CRI/;
            acc($b,'ri', $f->[18]) if $f->[18] =~ /^\d+$/;
            acc($b,'cqi',$f->[19]) if $f->[19] =~ /^\d+$/;
        }
    } elsif ($type == 0xB8D8) {
        my @snr = $txt =~ /SNR = ([-0-9.]+) dB/g;
        if (@snr) {
            $b->{snr_n}++;
            my $s = 0; $s += $_ for @snr;
            $b->{snr_sum} += $s / @snr;
            $b->{snr_rx}[$_] += $snr[$_] for 0..$#snr;
        }
        $cell{$1}++ if $txt =~ /Cell Id = (\d+)/;
    } elsif ($type == 0xB8B5) {
        for my $l (@lines) {
            next unless $l =~ /^\s*\|\s*\d+\|/;
            my $f = fields($l);
            next unless @$f >= 5;
            for my $i (1..4) { $pwr{$i} += $f->[$i] if $f->[$i] =~ /^\d+(\.\d+)?$/; }
            $pwr_n++;
        }
    } elsif ($type == 0xB823) {
        $cell{pci}  = $1 if $txt =~ /Physical Cell ID = (\d+)/;
        $cell{freq} = $1 if $txt =~ /DL Frequency = (\d+)/;
        $cell{bw}   = $1 if $txt =~ /DL Bandwidth = (\d+)/;
    }
    last unless $p->Next();
}
$p = NULL; $filter = NULL; $app = NULL;

my @metric_files;
sub outcsv {
    my ($name, @cols) = @_;
    my $path = "$OUTDIR/$name.csv";
    open(my $fh, '>', $path) or die "$path: $!";
    print $fh join(',', @cols), "\n";
    push @metric_files, [$name, $path, \@cols];
    return $fh;
}

my $f_master = outcsv('bins_master',
    'sec','time','ul_tb_bytes','ul_rate_mbps','ul_rb_avg','ul_rb_max','ul_mcs_avg',
    'ul_tbs_avg','ul_retx_pct','dl_tb_bytes','dl_rate_mbps','dl_pass_bytes','dl_pass_rate_mbps',
    'dl_rb_avg','dl_rb_max','dl_rb_usage_pct','dl_mcs_avg','dl_layers_avg','dl_bler_pct',
    'dl_retx_pct','dl_harq_ack_pct','cqi_avg','ri_avg','snr_avg','ul_dci','dl_dci');
my $f_dlrate = outcsv('dl_rate','sec','time','tb_bytes','pass_bytes','fail_bytes','rate_mbps','pass_rate_mbps');
my $f_ulrate = outcsv('ul_rate','sec','time','tb_bytes','rate_mbps');
my $f_dlrb   = outcsv('dl_rb','sec','time','rb_avg','rb_max','rb_usage_pct');
my $f_ulrb   = outcsv('ul_rb','sec','time','rb_avg','rb_max','rb_usage_pct');
my $f_dlmcs  = outcsv('dl_mcs','sec','time','mcs_avg','mcs_min','mcs_max');
my $f_ulmcs  = outcsv('ul_mcs','sec','time','mcs_avg','mcs_min','mcs_max');
my $f_bler   = outcsv('dl_bler','sec','time','crc_pass','crc_fail','bler_pct','retx_pct');
my $f_ulharq = outcsv('ul_harq','sec','time','new_tx','retx','retx_pct');
my $f_cqi    = outcsv('cqi_ri','sec','time','cqi_avg','ri_avg');
my $f_snr    = outcsv('snr','sec','time','snr_avg','rx0','rx1','rx2','rx3');
my $f_dci    = outcsv('dci','sec','time','ul_dci','dl_dci');
my $f_dlmod  = outcsv('dl_mod','sec','time','qpsk','qam16','qam64','qam256');

my $pci_vote = (sort { $cell{$b} <=> $cell{$a} } keys %cell)[0];
$cell{pci} //= $pci_vote if defined $pci_vote;
my $rb_total = ($cell{bw} // 100) == 100 ? 273 : 0;
for my $i (0..$bins) {
    my $b = $B{$i} || {};
    my $tsec = $t0 + $i*$BIN;
    my $tm = hms($tsec);
    my $ul_tb = $b->{ul_tb} // 0;
    my $dl_tb = $b->{dl_tb} // 0;
    my $dpass = $b->{dl_pass} // 0; my $dfail = $b->{dl_fail} // 0;
    my $dnew = $b->{dl_newtx} // 0; my $dretx = $b->{dl_retx} // 0;
    my $unew = $b->{ul_newtx} // 0; my $uret = $b->{ul_retx} // 0;
    my $dtot = $dpass + $dfail;
    my $dl_bler  = $dtot ? sprintf("%.2f", 100*$dfail/$dtot) : '';
    my $dl_retxp = ($dnew+$dretx) ? sprintf("%.2f", 100*$dretx/($dnew+$dretx)) : '';
    my $ul_retxp = ($unew+$uret) ? sprintf("%.2f", 100*$uret/($unew+$uret)) : '';
    my $ack_raw = ($b->{uci_harq} // 0) ? 100*($b->{uci_ack}//0)/($b->{uci_harq}) : 0;
    my $ackp = ($b->{uci_harq} // 0) ? sprintf("%.2f", $ack_raw > 100 ? 100 : $ack_raw) : '';
    my $snr_avg = ($b->{snr_n} // 0) ? sprintf("%.2f", $b->{snr_sum}/$b->{snr_n}) : '';
    my @rx;
    for my $k (0..3) { push @rx, ($b->{snr_n}//0) ? sprintf("%.2f", ($b->{snr_rx}[$k]//0)/($b->{snr_n})) : ''; }
    my $rb_usage = $rb_total ? sprintf("%.1f", 100*(m_avg($b,'dl_rb')||0)/$rb_total) : '';
    my $ul_rb_usage = $rb_total ? sprintf("%.1f", 100*(m_avg($b,'ul_rb')||0)/$rb_total) : '';

    printf $f_master "%d,%s,%d,%.4f,%s,%s,%s,%s,%s,%d,%.4f,%d,%.4f,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%d,%d\n",
        $i,$tm,$ul_tb,$ul_tb*8/$BIN/1e6,
        (m_avg($b,'ul_rb') eq '' ? '' : sprintf("%.1f",m_avg($b,'ul_rb'))),
        (m_max($b,'ul_rb') eq '' ? '' : m_max($b,'ul_rb')),
        (m_avg($b,'ul_mcs') eq '' ? '' : sprintf("%.2f",m_avg($b,'ul_mcs'))),
        (m_avg($b,'ul_tbs') eq '' ? '' : sprintf("%.0f",m_avg($b,'ul_tbs'))),
        $ul_retxp,
        $dl_tb,$dl_tb*8/$BIN/1e6,($b->{dl_pass_bytes}//0),($b->{dl_pass_bytes}//0)*8/$BIN/1e6,
        (m_avg($b,'dl_rb') eq '' ? '' : sprintf("%.1f",m_avg($b,'dl_rb'))),
        (m_max($b,'dl_rb') eq '' ? '' : m_max($b,'dl_rb')), $rb_usage,
        (m_avg($b,'dl_mcs') eq '' ? '' : sprintf("%.2f",m_avg($b,'dl_mcs'))),
        (m_avg($b,'dl_layers') eq '' ? '' : sprintf("%.2f",m_avg($b,'dl_layers'))),
        $dl_bler,$dl_retxp,$ackp,
        (m_avg($b,'cqi') eq '' ? '' : sprintf("%.2f",m_avg($b,'cqi'))),
        (m_avg($b,'ri') eq '' ? '' : sprintf("%.2f",m_avg($b,'ri'))),
        $snr_avg,($b->{ul_dci}//0),($b->{dl_dci}//0);
    printf $f_dlrate "%d,%s,%d,%d,%d,%.4f,%.4f\n", $i,$tm,$dl_tb,$b->{dl_pass_bytes}//0,$dfail,$dl_tb*8/$BIN/1e6,($b->{dl_pass_bytes}//0)*8/$BIN/1e6;
    printf $f_ulrate "%d,%s,%d,%.4f\n", $i,$tm,$ul_tb,$ul_tb*8/$BIN/1e6;
    printf $f_dlrb "%d,%s,%s,%s,%s\n", $i,$tm,(m_avg($b,'dl_rb') eq '' ? '' : sprintf("%.1f",m_avg($b,'dl_rb'))),(m_max($b,'dl_rb') eq '' ? '' : m_max($b,'dl_rb')),$rb_usage;
    printf $f_ulrb "%d,%s,%s,%s,%s\n", $i,$tm,(m_avg($b,'ul_rb') eq '' ? '' : sprintf("%.1f",m_avg($b,'ul_rb'))),(m_max($b,'ul_rb') eq '' ? '' : m_max($b,'ul_rb')),$ul_rb_usage;
    printf $f_dlmcs "%d,%s,%s,%s,%s\n", $i,$tm,(m_avg($b,'dl_mcs') eq '' ? '' : sprintf("%.2f",m_avg($b,'dl_mcs'))),(m_min($b,'dl_mcs') eq '' ? '' : m_min($b,'dl_mcs')),(m_max($b,'dl_mcs') eq '' ? '' : m_max($b,'dl_mcs'));
    printf $f_ulmcs "%d,%s,%s,%s,%s\n", $i,$tm,(m_avg($b,'ul_mcs') eq '' ? '' : sprintf("%.2f",m_avg($b,'ul_mcs'))),(m_min($b,'ul_mcs') eq '' ? '' : m_min($b,'ul_mcs')),(m_max($b,'ul_mcs') eq '' ? '' : m_max($b,'ul_mcs'));
    printf $f_bler "%d,%s,%d,%d,%s,%s\n", $i,$tm,$dpass,$dfail,$dl_bler,$dl_retxp;
    printf $f_ulharq "%d,%s,%d,%d,%s\n", $i,$tm,$unew,$uret,$ul_retxp;
    printf $f_cqi "%d,%s,%s,%s\n", $i,$tm,(m_avg($b,'cqi') eq '' ? '' : sprintf("%.2f",m_avg($b,'cqi'))),(m_avg($b,'ri') eq '' ? '' : sprintf("%.2f",m_avg($b,'ri')));
    printf $f_snr "%d,%s,%s,%s,%s,%s,%s\n", $i,$tm,$snr_avg,@rx;
    printf $f_dci "%d,%s,%d,%d\n", $i,$tm,($b->{ul_dci}//0),($b->{dl_dci}//0);
    printf $f_dlmod "%d,%s,%d,%d,%d,%d\n", $i,$tm,($b->{dl_mod}{QPSK}//0),($b->{dl_mod}{'16_QAM'}//0),($b->{dl_mod}{'64_QAM'}//0),($b->{dl_mod}{'256_QAM'}//0);
}
close $f_master; close $f_dlrate; close $f_ulrate; close $f_dlrb; close $f_ulrb;
close $f_dlmcs; close $f_ulmcs; close $f_bler; close $f_ulharq; close $f_cqi;
close $f_snr; close $f_dci; close $f_dlmod;

open(my $fp, '>', "$OUTDIR/ul_txpower_hist.csv") or die $!;
print $fp "bucket,share_pct\n";
for my $i (1..4) {
    printf $fp "%d,%.1f\n", $i, $pwr_n ? 100*$pwr{$i}/$pwr_n : 0;
}
close $fp;
open(my $fc, '>', "$OUTDIR/cell_info.txt") or die $!;
print $fc "PCI=$cell{pci} DL_ARFCN=$cell{freq} BW=$cell{bw}MHz\n";
close $fc;

print "done: $n packets, $bins+1 bins -> $OUTDIR\n";
print "bins_master.csv + ", scalar(@metric_files), " 个分指标 CSV + ul_txpower_hist.csv\n";
print "cell: PCI=$cell{pci} ARFCN=$cell{freq} BW=$cell{bw}MHz\n";
