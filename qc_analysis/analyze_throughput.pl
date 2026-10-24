use strict;
use warnings;
use Win32::OLE;
use constant FALSE => 0;
use constant TRUE  => 1;
use constant NULL  => 0;

# 工具4：过滤并分析上下行速率（每秒 UL/DL 字节数）
# 数据源：
#   上行  = PDCP UL Stats RB4 的 "Total Num RX Bytes" 累计值差分（应用灌入速率）
#   上行空口 = L2 UL TB 每 TTI "Bytes Built" 逐秒求和（实际 PUSCH 发送速率）
#   下行A = PDCP DL Rbs Stats RB4 的 "Data PDU Bytes Received" 累计值差分（PDCP 层速率）
#   下行B = MAC PDSCH Stats 的 "CRC Pass TB Bytes" 累计值差分（PHY 层速率）
# ===================== 配置区（直接改这里） =====================
my $HDF  = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1.hdf';
my $OUT  = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\qc_analysis\\throughput.csv';
my $FROM = '07:58:13.251';   # 起始时间，'' = 日志开头
my $TO   = '07:58:40.251';   # 结束时间，'' = 日志结尾
# ================================================================
# 命令行可覆盖配置: perl analyze_throughput.pl [hdf] [csv] [from] [to]
$HDF  = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$OUT  = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$FROM = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$TO   = shift(@ARGV) if @ARGV && $ARGV[0] ne '';

my @CODES = (0xB860, 0xB842, 0xB888, 0xB870, 0xB857, 0xB872, 0xB886);

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

my (%prev, %rate);
# prev{ul/dl/phy} = 上一秒结束时的累计值；rate{sec}{ul/dl/phy} = 该秒的字节数

sub fields {
    my $row = shift;
    $row =~ s/^\s*\|\s*//;
    $row =~ s/\|\s*$//;
    return [ map { s/^\s+|\s+$//g; $_ } split /\|/, $row ];
}

my $p = $app->{FirstPacket};
my $n = 0;
while ($p) {
    $n++;
    my $txt = $p->{Text};
    my ($sec) = $txt =~ /(\d\d):(\d\d):(\d\d)\.(\d\d\d)/;
    next unless defined $sec;
    my $t = $1*3600 + $2*60 + $3;
    if ($p->{Type} == 0xB860) {
        # PDCP UL Stats：找 RB4(DRB) 行，取 Total Num RX Bytes
        for my $row ($txt =~ /^\s*\|\s*\d+\|\s*4\|\s*DRB\s*\|[^\n]+/mg) {
            my $f = fields($row);
            next unless @$f >= 14 && $f->[12] =~ /^\d+$/;
            my $v = $f->[12];
            if (exists $prev{ul}) {
                my $d = $v >= $prev{ul} ? $v - $prev{ul} : 0;
                $rate{$t}{ul} = ($rate{$t}{ul} // 0) + $d;
            }
            $prev{ul} = $v;
        }
    } elsif ($p->{Type} == 0xB842) {
        # PDCP DL Rbs Stats：RB Config Index=4 行，取 Data PDU Bytes Received
        for my $row ($txt =~ /^\s*\|\s*\d+\|\s*4\s*\|[^\n]+/mg) {
            my $f = fields($row);
            next unless @$f >= 9 && $f->[8] =~ /^\d+$/;
            my $v = $f->[8];
            if (exists $prev{dl}) {
                my $d = $v >= $prev{dl} ? $v - $prev{dl} : 0;
                $rate{$t}{dl} = ($rate{$t}{dl} // 0) + $d;
            }
            $prev{dl} = $v;
        }
    } elsif ($p->{Type} == 0xB888) {
        # MAC PDSCH Stats：CRC Pass TB Bytes（累计）
        for my $row ($txt =~ /^\s*\|\s*0\s*\|[^\n]+/mg) {
            my $f = fields($row);
            next unless @$f >= 10 && $f->[9] =~ /^\d+$/;
            my $v = $f->[9];
            if (exists $prev{phy}) {
                my $d = $v >= $prev{phy} ? $v - $prev{phy} : 0;
                $rate{$t}{phy} = ($rate{$t}{phy} // 0) + $d;
            }
            $prev{phy} = $v;
        }
    } elsif ($p->{Type} == 0xB872) {
        # L2 UL TB：每 TTI 一行，Bytes Built = 本 TB 实际装入字节
        for my $row ($txt =~ /^\s*\|\s*\d+\|[^\n]+/mg) {
            my $f = fields($row);
            next unless @$f >= 14 && $f->[13] =~ /^\d+$/;
            $rate{$t}{ulair} = ($rate{$t}{ulair} // 0) + $f->[13];
        }
    }
    last unless $p->Next();
}

open(my $fh, '>', $OUT) or die "out: $!";
print $fh "sec,ul_pdcp_bytes,ul_air_bytes,dl_pdcp_bytes,dl_phy_bytes\n";
for my $s (sort { $a <=> $b } keys %rate) {
    my $h = sprintf("%02d:%02d:%02d", int($s/3600), int(($s%3600)/60), $s%60);
    printf $fh "%s,%d,%d,%d,%d\n", $h,
        ($rate{$s}{ul}  // 0),
        ($rate{$s}{ulair} // 0),
        ($rate{$s}{dl}  // 0),
        ($rate{$s}{phy} // 0);
}
close $fh;
print "done, $n packets -> $OUT\n";
$p = NULL; $filter = NULL; $app = NULL;
