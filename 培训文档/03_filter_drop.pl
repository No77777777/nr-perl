use strict;
use warnings;
use Win32::OLE;
use constant FALSE => 0;
use constant TRUE  => 1;
use constant NULL  => 0;

# ============================================================
# 工具3：过滤分析 5G 掉线问题的日志
# 覆盖一条完整掉线证据链：RRC/RLF、波束失败与 RLM、
# TX_SUSPEND（上行丢弃）、信号质量、调度反馈、L2 缓冲。
# 配置区：只改这两个路径，本脚本不做时间过滤
# ============================================================
my $HDF = 'D:\\logs\\xx.hdf';           # 输入：QCAT 可打开的日志
my $OUT = 'D:\\logs\\drop_filter.txt';  # 输出：过滤后的解码文本

my @CODES = (
    # RRC / RLF / 重建立
    0xB821,   # RRC OTA Packet
    0xB822,   # RRC MIB Info
    0xB823,   # RRC Serving Cell Info（PCI/频点变化）
    0xB825,   # RRC Configuration Info
    0xB889,   # MAC RACH Trigger（触发原因: RLF / BEAM_FAILURE / SR_Failure）
    0xB88A,   # MAC RACH Attempt
    # 波束与无线链路监控
    0xB959,   # ML1 RLM Stats（IS/OOS BLER、Purpose=BEAM_FAILURE）
    0xB8AE,   # MAC Skip UL TX（TX_SUSPEND / CDRX 丢弃 PUCCH/PUSCH）
    0xB89C,   # MAC Flow Control
    0xB890,   # MAC CDRX Events Info
    # 信号质量
    0xB8D8,   # LL1 SERVING SNR
    0xB97F,   # ML1 Searcher Measurement Database Update Ext（RSRP/RSRQ/SINR）
    0xB8B5,   # MAC Tx Pwr Dist Stats LOG
    # 调度与反馈（判断网络侧是否还在调度）
    0xB885,   # MAC DCI Info
    0xB883,   # MAC UL Physical Channel Schedule Report
    0xB888,   # MAC PDSCH Stats
    0xB89B,   # MAC UCI Information（HARQ ACK/NACK）
    0xB896,   # MAC UCI Payload Information
    # L2 缓冲与 BSR（判断上行数据是否堆积）
    0xB873,   # L2 UL BSR
    0xB860,   # PDCP UL Stats
    0xB842,   # PDCP DL Rbs Stats
    0xB868,   # RLC UL Stats
    0xB84D,   # RLC DL Stats
    0xB872,   # L2 UL TB
    0xB857,   # L2 DL DATA PDU
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
print $fh "# 5G 掉线问题日志过滤输出\n# 日志: $HDF\n";

my (%cnt, %rach_reason, %rach_result, %skip_reason, %serv_cell, $ul_dci, $dl_dci, $bsr_n);
my $p = $app->{FirstPacket};
my $n = 0;
while ($p) {
    $n++;
    my $type = $p->{Type};
    $cnt{$type}++;
    my $txt = $p->{Text};
    $txt =~ s/\r\n/\n/g;
    printf $fh "=== %08d\t0x%X ===\n", $n, $type;
    my ($h,$mi,$s,$ms) = $txt =~ /(\d\d):(\d\d):(\d\d)\.(\d\d\d)/;
    my $ts = defined $h ? "$h:$mi:$s.$ms" : '--:--:--.---';
    if ($type == 0xB889) {
        my ($reason) = $txt =~ /Rach Reason\s*=\s*(\w+)/;
        $reason //= '?';
        $rach_reason{$reason}++;
        print $fh ">>> RACH_TRIGGER $ts reason=$reason\n";
    } elsif ($type == 0xB88A) {
        my ($res) = $txt =~ /RACH Result\s*=\s*(\w+)/;
        $res //= '?';
        $rach_result{$res}++;
        print $fh ">>> RACH_ATTEMPT $ts result=$res\n";
    } elsif ($type == 0xB823) {
        my ($pci) = $txt =~ /Physical Cell ID\s*=\s*(\d+)/;
        $serv_cell{"pci=$pci"}++ if defined $pci;
        print $fh ">>> SERVING_CELL $ts pci=", ($pci // '?'), "\n";
    } elsif ($type == 0xB8AE) {
        $skip_reason{TX_SUSPEND}++ while $txt =~ /TX_SUSPEND/g;
        print $fh ">>> SKIP_UL_TX $ts tx_suspend=", (scalar(() = $txt =~ /TX_SUSPEND/g)), "\n";
    } elsif ($type == 0xB959) {
        my ($purp) = $txt =~ /Purpose\s*=\s*(\w+)/;
        print $fh ">>> RLM_STATS $ts purpose=", ($purp // '?'), "\n";
    } elsif ($type == 0xB885) {
        $ul_dci++ while $txt =~ /\bUL_\d_\d\b/g;
        $dl_dci++ while $txt =~ /\bDL_\d_\d\b/g;
    } elsif ($type == 0xB873) {
        $bsr_n++;
        print $fh ">>> UL_BSR $ts\n";
    }
    print $fh $txt;
    print $fh "\n";
    last unless $p->Next();
}

print $fh "\n# ============ 掉线事件摘要 ============\n";
print $fh "# UL DCI 授权 $ul_dci 次, DL DCI 分配 $dl_dci 次, UL BSR 上报 $bsr_n 次\n";
print $fh "# RACH 触发原因: ", join('  ', map { "$_=$rach_reason{$_}" } keys %rach_reason), "\n";
print $fh "# RACH 结果:     ", join('  ', map { "$_=$rach_result{$_}" } keys %rach_result), "\n";
print $fh "# TX_SUSPEND(上行丢弃): ", ($skip_reason{TX_SUSPEND} // 0), " 次\n";
print $fh "# 服务小区:      ", join('  ', map { "$_=$serv_cell{$_}" } keys %serv_cell), "\n";
print $fh "# 按消息类型统计\n";
for my $t (sort { $cnt{$b} <=> $cnt{$a} } keys %cnt) {
    my $name = $app->GetPacketTypeName($t);
    printf $fh "# 0x%X\t%d\t%s\n", $t, $cnt{$t}, $name;
}
close $fh;
print "done, $n packets -> $OUT\n";
$p = NULL; $filter = NULL; $app = NULL;

