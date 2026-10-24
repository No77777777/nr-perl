use strict;
use warnings;
use Win32::OLE;
use constant FALSE => 0;
use constant TRUE  => 1;
use constant NULL  => 0;

# 工具1：过滤只包含上下行 RLC/PDCP 的日志
# ===================== 配置区（直接改这里） =====================
my $HDF  = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1.hdf';
my $OUT  = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\qc_analysis\\rlc_pdcp_only.txt';
my $FROM = '07:58:13.251';   # 起始时间 HH:MM:SS.mmm，改成 '' 表示从日志开头
my $TO   = '07:58:40.251';   # 结束时间 HH:MM:SS.mmm，改成 '' 表示到日志结尾
# ================================================================
# 命令行可覆盖配置（依次为 hdf、输出、from、to）: perl filter_rlc_pdcp.pl [hdf] [输出] [from] [to]
$HDF  = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$OUT  = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$FROM = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$TO   = shift(@ARGV) if @ARGV && $ARGV[0] ne '';

my @CODES = (
    0xB840, # PDCP DL Data Pdu
    0xB841, # PDCP DL Control Pdu
    0xB842, # PDCP DL Rbs Stats
    0xB844, # PDCP DL SRB PDU
    0xB847, # PDCP DL ROHC RB Stats
    0xB848, # PDCP DL Debug PDU LOG
    0xB860, # PDCP UL Stats
    0xB861, # PDCP UL Control Pdu
    0xB863, # PDCP UL ROHC Stats
    0xB866, # PDCP UL UDC Stats
    0xB84D, # RLC DL Stats
    0xB84E, # RLC DL Status PDU
    0xB868, # RLC UL Stats
    0xB869, # RLC UL Status PDU
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
my %cnt;
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
    last unless $p->Next();
}

print $fh "\n# 按消息类型统计\n";
for my $t (sort { $cnt{$b} <=> $cnt{$a} } keys %cnt) {
    my $name = $app->GetPacketTypeName($t);
    printf $fh "# 0x%X\t%d\t%s\n", $t, $cnt{$t}, $name;
}
close $fh;
print "done, $n packets -> $OUT\n";
for my $t (sort { $cnt{$b} <=> $cnt{$a} } keys %cnt) {
    my $name = $app->GetPacketTypeName($t);
    printf "0x%X\t%d\t%s\n", $t, $cnt{$t}, $name;
}
$p = NULL; $filter = NULL; $app = NULL;
