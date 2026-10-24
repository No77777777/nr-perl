use strict;
use warnings;
use Win32::OLE;
use constant FALSE => 0;
use constant TRUE  => 1;
use constant NULL  => 0;

# ============================================================
# 工具1：过滤分析 5G 上下行速率的日志
# 输出整个日志中的调度/速率/信号质量相关报文，供后续速率分析
# 配置区：只改这两个路径，本脚本不做时间过滤
# ============================================================
my $HDF = 'D:\\logs\\xx.hdf';          # 输入：QCAT 可打开的日志（HDF/QMDL/DLF）
my $OUT = 'D:\\logs\\rate_filter.txt'; # 输出：过滤后的解码文本

my @CODES = (
    0xB885,   # MAC DCI Info（上下行授权/MCS）
    0xB883,   # MAC UL Physical Channel Schedule Report（PUSCH: RB/MCS/TB Size）
    0xB886,   # MAC DL TB Report
    0xB887,   # MAC PDSCH Status（每个 PDSCH 的 RB/MCS/TB Size/层数/调制/CRC）
    0xB888,   # MAC PDSCH Stats（DL CRC 累计/BLER/重传）
    0xB896,   # MAC UCI Payload Information
    0xB89B,   # MAC UCI Information（HARQ ACK/NACK）
    0xB8A7,   # MAC CSF Report（CQI/RI/PMI）
    0xB8D8,   # LL1 SERVING SNR
    0xB8B5,   # MAC Tx Pwr Dist Stats（上行发射功率分布）
    0xB857,   # L2 DL DATA PDU（DL TB Size）
    0xB872,   # L2 UL TB
    0xB842,   # PDCP DL Rbs Stats（PDCP 下行字节）
    0xB860,   # PDCP UL Stats（PDCP 上行字节）
    0xB823,   # RRC Serving Cell Info（PCI/频点/带宽）
);

my $app = Win32::OLE->new('QCAT6.Application') or die "no QCAT\n";
$app->{Visible} = FALSE;
$app->{UsePCTime} = FALSE;
my $filter = $app->{PacketFilter};
$filter->SetAll(FALSE);
for my $c (@CODES) { $filter->Set($c, TRUE); }
$filter->Commit();
die "OpenLog failed: $app->{LastError}\n" unless $app->OpenLog($HDF);
print "loaded: $app->{PacketCount} packets\n";

open(my $fh, '>', $OUT) or die "out: $!";
binmode($fh);
print $fh "# 5G 上下行速率日志过滤输出\n# 日志: $HDF\n";

my (%cnt, $ul_dci, $dl_dci);
my $p = $app->{FirstPacket};
my $n = 0;
while ($p) {
    $n++;
    my $type = $p->{Type};
    $cnt{$type}++;
    my $txt = $p->{Text};
    $txt =~ s/\r\n/\n/g;
    printf $fh "=== %08d\t0x%X ===\n", $n, $type;
    print $fh $txt;
    print $fh "\n";
    if ($type == 0xB885) {
        $ul_dci++ while $txt =~ /\bUL_\d_\d\b/g;
        $dl_dci++ while $txt =~ /\bDL_\d_\d\b/g;
    }
    last unless $p->Next();
}

print $fh "\n# ============ 速率日志摘要 ============\n";
print $fh "# UL DCI 授权 $ul_dci 次, DL DCI 分配 $dl_dci 次\n";
print $fh "# 按消息类型统计\n";
for my $t (sort { $cnt{$b} <=> $cnt{$a} } keys %cnt) {
    my $name = $app->GetPacketTypeName($t);
    printf $fh "# 0x%X\t%d\t%s\n", $t, $cnt{$t}, $name;
}
close $fh;
print "done, $n packets -> $OUT\n";
$p = NULL; $filter = NULL; $app = NULL;
