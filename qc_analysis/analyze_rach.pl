use strict;
use warnings;
use Win32::OLE;
use constant FALSE => 0;
use constant TRUE  => 1;
use constant NULL  => 0;

# 工具3：过滤并分析随机接入日志（RACH Trigger/Attempt + RRC OTA + Serving Cell + Skip UL TX）
# ===================== 配置区（直接改这里） =====================
my $HDF  = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1.hdf';
my $OUT  = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\qc_analysis\\rach_analysis.txt';
my $FROM = '07:58:13.251';   # 起始时间，'' = 日志开头
my $TO   = '07:58:40.251';   # 结束时间，'' = 日志结尾
# ================================================================
# 命令行可覆盖配置: perl analyze_rach.pl [hdf] [输出] [from] [to]
$HDF  = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$OUT  = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$FROM = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$TO   = shift(@ARGV) if @ARGV && $ARGV[0] ne '';

my @CODES = (0xB889, 0xB88A, 0xB821, 0xB823, 0xB8AE);

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
print $fh "# 随机接入事件时间线（时间=RACH Trigger/Attempt/OTA日志时刻）\n";

my $p = $app->{FirstPacket};
my $n = 0;
while ($p) {
    $n++;
    my $txt = $p->{Text};
    $txt =~ s/\r\n/\n/g;
    printf $fh "=== %08d\t0x%X ===\n", $n, $p->{Type};
    my ($h, $mi, $s, $ms) = $txt =~ /(\d\d):(\d\d):(\d\d)\.(\d\d\d)/;
    $h = '' unless defined $h;
    $mi = '' unless defined $mi;
    $s = '' unless defined $s;
    $ms = '' unless defined $ms;
    my $line = ($txt =~ /^(.+)$/m)[0];
    if ($p->{Type} == 0xB889) {
        my ($reason) = $txt =~ /Rach Reason = (\w+)/;
        print $fh ">>> RACH_TRIGGER $h:$mi:$s.$ms reason=$reason $line\n";
    } elsif ($p->{Type} == 0xB88A) {
        my ($res)  = $txt =~ /RACH Result = (\w+)/;
        my ($ssb)  = $txt =~ /SSB ID = (\d+)/;
        print $fh ">>> RACH_ATTEMPT $h:$mi:$s.$ms result=$res ssb=$ssb\n";
    } elsif ($p->{Type} == 0xB823) {
        my ($pci) = $txt =~ /Physical Cell ID = (\d+)/;
        print $fh ">>> SERVING_CELL $h:$mi:$s.$ms pci=$pci\n";
    }
    print $fh $txt;
    print $fh "\n";
    last unless $p->Next();
}
close $fh;
print "done, $n packets -> $OUT\n";
$p = NULL; $filter = NULL; $app = NULL;
