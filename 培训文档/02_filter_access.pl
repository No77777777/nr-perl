use strict;
use warnings;
use Win32::OLE;
use constant FALSE => 0;
use constant TRUE  => 1;
use constant NULL  => 0;

# ============================================================
# 工具2：过滤分析 5G 接入问题的日志
# 覆盖 RRC 建链 / NAS 注册流程 / 搜索与小区评估 / 随机接入，
# 用于分析 Attach/Registration 失败、搜网慢、无服务等问题。
# 配置区：只改这两个路径，本脚本不做时间过滤
# ============================================================
my $HDF = 'D:\\logs\\xx.hdf';            # 输入：QCAT 可打开的日志
my $OUT = 'D:\\logs\\access_filter.txt'; # 输出：过滤后的解码文本

my @CODES = (
    # RRC / NAS 层（接入信令）
    0xB821,   # RRC OTA Packet（RRC Setup / 重配 / 拒绝，内含 NAS 消息）
    0xB822,   # RRC MIB Info
    0xB823,   # RRC Serving Cell Info（PCI/频点/带宽）
    0xB825,   # RRC Configuration Info
    0xB80C,   # NAS MM5G State（注册状态变化）
    0xB80D,   # NAS MM5G Service Request
    # 随机接入
    0xB889,   # MAC RACH Trigger（触发原因）
    0xB88A,   # MAC RACH Attempt（Msg1~Msg4 与结果）
    # 搜网与小区评估
    0xB970,   # ML1 Searcher Idle S Criteria
    0xB96F,   # ML1 Searcher Conn Eval
    0xB950,   # ML1 DL Common Config
    0xB96D,   # ML1 Searcher ACQ Config And Response
    0xB98F,   # ML1 Antenna Switch Diversity
    0xB9A7,   # ML1 DLM2 CA Metrics Request
    # 辅助确认（DRX / 信令面数据流 / 信号质量）
    0xB890,   # MAC CDRX Events Info
    0xB842,   # PDCP DL Rbs Stats（SRB 信令流量）
    0xB860,   # PDCP UL Stats
    0xB8D8,   # LL1 SERVING SNR
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
print $fh "# 5G 接入问题日志过滤输出\n# 日志: $HDF\n";

my (%cnt, %rach_reason, %rach_result, %serv_cell);
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
    }
    print $fh $txt;
    print $fh "\n";
    last unless $p->Next();
}

print $fh "\n# ============ 接入事件摘要 ============\n";
print $fh "# RACH 触发原因: ", join('  ', map { "$_=$rach_reason{$_}" } keys %rach_reason), "\n";
print $fh "# RACH 结果:     ", join('  ', map { "$_=$rach_result{$_}" } keys %rach_result), "\n";
print $fh "# 服务小区:      ", join('  ', map { "$_=$serv_cell{$_}" } keys %serv_cell), "\n";
print $fh "# 按消息类型统计\n";
for my $t (sort { $cnt{$b} <=> $cnt{$a} } keys %cnt) {
    my $name = $app->GetPacketTypeName($t);
    printf $fh "# 0x%X\t%d\t%s\n", $t, $cnt{$t}, $name;
}
close $fh;
print "done, $n packets -> $OUT\n";
$p = NULL; $filter = NULL; $app = NULL;
