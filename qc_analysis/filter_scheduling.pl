use strict;
use warnings;
use Win32::OLE;
use constant FALSE => 0;
use constant TRUE  => 1;
use constant NULL  => 0;

# 工具2：过滤只包含上下行调度的日志（DCI/UCI/PDSCH/PUSCH/CSF/CDRX）
# ===================== 配置区（直接改这里） =====================
my $HDF  = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1.hdf';
my $OUT  = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\qc_analysis\\scheduling_only.txt';
my $FROM = '07:58:13.251';   # 起始时间，'' = 日志开头
my $TO   = '07:58:40.251';   # 结束时间，'' = 日志结尾
# ================================================================
# 命令行可覆盖配置: perl filter_scheduling.pl [hdf] [输出] [from] [to]
$HDF  = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$OUT  = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$FROM = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$TO   = shift(@ARGV) if @ARGV && $ARGV[0] ne '';

my @CODES = (
    0xB885, # MAC DCI Info（上下行授权）
    0xB883, # MAC UL Physical Channel Schedule Report
    0xB884, # MAC UL Physical Channel Power Control
    0xB886, # MAC DL TB Report
    0xB887, # MAC PDSCH Status
    0xB888, # MAC PDSCH Stats
    0xB896, # MAC UCI Payload Information
    0xB89B, # MAC UCI Information
    0xB8A7, # MAC CSF Report
    0xB890, # MAC CDRX Events Info
    0xB89C, # MAC Flow Control
    0xB880, # MAC UL TB
    0xB8A0, # MAC LL1 PUSCH Tx
);

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
my (%cnt, $ul_dci, $dl_dci);
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
    if ($p->{Type} == 0xB885) {
        $ul_dci++ while $txt =~ /\bUL_\d_\d\b/g;
        $dl_dci++ while $txt =~ /\bDL_\d_\d\b/g;
    }
    last unless $p->Next();
}

print $fh "\n# 调度摘要：UL DCI 授权 $ul_dci 次，DL DCI 分配 $dl_dci 次\n";
print $fh "# 按消息类型统计\n";
for my $t (sort { $cnt{$b} <=> $cnt{$a} } keys %cnt) {
    my $name = $app->GetPacketTypeName($t);
    printf $fh "# 0x%X\t%d\t%s\n", $t, $cnt{$t}, $name;
}
close $fh;
print "done, $n packets, UL_DCI=$ul_dci DL_DCI=$dl_dci -> $OUT\n";
for my $t (sort { $cnt{$b} <=> $cnt{$a} } keys %cnt) {
    my $name = $app->GetPacketTypeName($t);
    printf "0x%X\t%d\t%s\n", $t, $cnt{$t}, $name;
}
$p = NULL; $filter = NULL; $app = NULL;
