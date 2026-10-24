use strict;
use warnings;
use Win32::OLE;
use constant FALSE => 0;
use constant TRUE  => 1;
use constant NULL  => 0;

# ===================== 配置区（直接改这里，或命令行覆盖） =====================
my $HDF  = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\10-22.09-19-13-0755gthroughput.hdf';
my $OUT  = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\qc_analysis\\dl_rb_report.txt';
my $CSV  = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\qc_analysis\\dl_rb_series.csv';
my $FROM = '01:17:51.5';   # DL 相
my $TO   = '01:18:04.0';
# ==============================================================================
$HDF  = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$OUT  = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$CSV  = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$FROM = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$TO   = shift(@ARGV) if @ARGV && $ARGV[0] ne '';

sub t2sec {
    my $t = shift;
    $t =~ /(\d+):(\d+):(\d+)\.(\d+)/ or return 0;
    return $1*3600 + $2*60 + $3 + $4/(10**length($4));
}
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
$filter->Set(0xB887, TRUE);
$filter->Commit();
die "OpenLog failed\n" unless $app->OpenLog($HDF);
my $t0 = t2sec($FROM); my $t1 = t2sec($TO);
my $base = int($app->{LogStartTime} / 86400) * 86400;
$app->SetTimeWindow(($base + $t0) - $app->{LogStartTime}, $t1 - $t0);

my ($nrec, $npass, $nfail, $rbs_sum, $rbs_min, $rbs_max, $tb_sum) = (0,0,0,0,1e9,0,0);
my (%mcs, %mod, %layer, %rv, %sec_tb, %sec_rb, %sec_rec, %sec_crcfail);
my $p = $app->{FirstPacket};
while ($p) {
    my $txt = $p->{Text};
    my ($h,$mi,$s,$frac) = $txt =~ /(\d\d):(\d\d):(\d\d)\.(\d+)/;
    my $t = defined $h ? $h*3600+$mi*60+$s+$frac/(10**length($frac)) : 0;
    for my $l (split /\r?\n/, $txt) {
        next unless $l =~ /^\s*\|\s*\d+\|\s*\d+\|/;
        my $f = fields($l);
        next unless @$f >= 43 && $f->[18] =~ /^\d+$/;
        my $rbs = $f->[18]; my $tb = $f->[15] =~ /^\d+$/ ? $f->[15] : 0;
        $nrec++; $rbs_sum += $rbs; $tb_sum += $tb;
        $rbs_min = $rbs if $rbs < $rbs_min; $rbs_max = $rbs if $rbs > $rbs_max;
        my $k = int($t);
        $sec_tb{$k} += $tb; $sec_rb{$k} += $rbs; $sec_rec{$k}++;
        if ($f->[26] eq 'PASS') { $npass++; } else { $nfail++; $sec_crcfail{$k}++; }
        $mcs{$f->[17]}++   if $f->[17] ne '';
        $mod{$f->[40]}++   if $f->[40] ne '';
        $layer{$f->[24]}++ if $f->[24] ne '';
        $rv{$f->[19]}++    if $f->[19] ne '';
    }
    last unless $p->Next();
}
$p = NULL; $filter = NULL; $app = NULL;

open(my $fh, '>', $OUT) or die "out: $!";
print $fh "下行 PDSCH RB 分析 (0xB887 NR5G MAC PDSCH Status)\n";
print $fh "窗口: $FROM ~ $TO, PDSCH 记录数: $nrec\n";
printf $fh "DL RB 数: avg %.1f, min %d, max %d (小区 100MHz/273RB)\n", $nrec ? $rbs_sum/$nrec : 0, $rbs_min, $rbs_max;
printf $fh "DL TB 字节合计(含重传/CRC失败): %d bytes (%.2f Mbps)\n", $tb_sum, $tb_sum*8/($t1-$t0)/1e6;
printf $fh "CRC: PASS %d / FAIL %d = BLER %.2f%%\n", $npass, $nfail, $nrec ? 100*$nfail/$nrec : 0;
print $fh "MCS 分布: ", join(' ', map { "$_=$mcs{$_}" } sort { $a <=> $b } keys %mcs), "\n";
print $fh "调制方式: ", join(' ', map { "$_=$mod{$_}" } sort keys %mod), "\n";
print $fh "层数(RI): ", join(' ', map { "$_层=$layer{$_}" } sort keys %layer), "\n";
print $fh "RV 分布: ", join(' ', map { "$_=$rv{$_}" } sort { $a <=> $b } keys %rv), "\n";
close $fh;

open(my $cs, '>', $CSV) or die "csv: $!";
print $cs "sec,records,tb_bytes,avg_rb,crc_fail\n";
for my $k (sort { $a <=> $b } keys %sec_rec) {
    printf $cs "%d,%d,%d,%.1f,%d\n", $k, $sec_rec{$k}, $sec_tb{$k},
        $sec_rec{$k} ? $sec_rb{$k}/$sec_rec{$k} : 0, ($sec_crcfail{$k} // 0);
}
close $cs;
print "done: $nrec records\n";
