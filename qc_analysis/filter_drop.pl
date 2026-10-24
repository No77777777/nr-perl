use strict;
use warnings;
use Win32::OLE;
use constant FALSE => 0;
use constant TRUE  => 1;
use constant NULL  => 0;

# 工具：5G 掉线 / RLF 问题日志过滤（含时间范围筛选）
# 覆盖一条完整的掉线证据链：
#   RRC/RLF 与重建立  : RRC OTA、MIB、Serving Cell、RRC Config、RACH Trigger/Attempt
#   波束与无线链路监控 : RLM Stats(IS/OOS BLER)、Skip UL TX(TX_SUSPEND)、Flow Control、CDRX
#   信号质量          : Serving SNR、Searcher 测量库(RSRP/RSRQ/SINR)、TX 功率分布
#   调度与反馈        : DCI、UL PHY 调度报告、PDSCH Stats、UCI(HARQ ACK/NACK)
#   L2 缓冲/BSR      : UL BSR、PDCP UL/DL Stats、RLC UL/DL Stats、UL TB、L2 DL DATA PDU
# ===================== 配置区（直接改这里） =====================
my $HDF  = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1.hdf';
my $OUT  = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\qc_analysis\\drop_filter.txt';
my $FROM = '07:58:13.251';   # 起始时间 HH:MM:SS.mmm，'' = 日志开头（设备时间，注意时区）
my $TO   = '07:58:40.251';   # 结束时间 HH:MM:SS.mmm，'' = 日志结尾
my $FULL = 1;                # 1 = 输出每条报文的完整解码文本；0 = 只输出事件标记(轻量)
# ================================================================
# 命令行可覆盖配置: perl filter_drop.pl [hdf] [输出] [from] [to] [full]
$HDF  = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$OUT  = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$FROM = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$TO   = shift(@ARGV) if @ARGV && $ARGV[0] ne '';
$FULL = shift(@ARGV) if @ARGV && $ARGV[0] ne '';

my @CORE_RRC_RACH = (
    0xB821, # NR5G RRC OTA Packet（RRC 重配/重建立消息）
    0xB822, # NR5G RRC MIB Info
    0xB823, # NR5G RRC Serving Cell Info（PCI/频点变化）
    0xB825, # NR5G RRC Configuration Info
    0xB889, # NR5G MAC RACH Trigger（触发原因: RLF/BFR/SR_Failure...）
    0xB88A, # NR5G MAC RACH Attempt（成功/失败、Msg1~Msg4）
);
my @RLM_BEAM = (
    0xB959, # NR5G ML1 RLM Stats（IS/OOS BLER、Purpose=BEAM_FAILURE）
    0xB8AE, # NR5G MAC Skip UL TX（TX_SUSPEND/CDRX 丢弃 PUCCH/PUSCH）
    0xB89C, # NR5G MAC Flow Control（PUCCH/UL TX Backoff）
    0xB890, # NR5G MAC CDRX Events Info
);
my @RF_MEAS = (
    0xB8D8, # NR5G LL1 LOG SERVING SNR
    0xB97F, # NR5G ML1 Searcher Measurement Database Update Ext（RSRP/RSRQ/SINR）
    0xB8B5, # NR5G MAC Tx Pwr Dist Stats LOG
);
my @SCHED = (
    0xB885, # NR5G MAC DCI Info（上下行授权是否还存在）
    0xB883, # NR5G MAC UL Physical Channel Schedule Report（PUSCH 是否还被调度）
    0xB888, # NR5G MAC PDSCH Stats（下行 CRC/BLER）
    0xB89B, # NR5G MAC UCI Information（HARQ ACK/NACK）
    0xB896, # NR5G MAC UCI Payload Information
);
my @L2_BUF = (
    0xB873, # NR5G L2 UL BSR（缓冲状态上报）
    0xB860, # NR5G PDCP UL Stats（上行缓冲堆积）
    0xB842, # NR5G PDCP DL Rbs Stats
    0xB868, # NR5G RLC UL Stats
    0xB84D, # NR5G RLC DL Stats
    0xB872, # NR5G L2 UL TB
    0xB857, # NR5G L2 DL DATA PDU
);
# 可选：NAS 层（如需要看注册/业务请求，取消注释）
# my @NAS = (0xB80C, 0xB80D);

my @CODES = (@CORE_RRC_RACH, @RLM_BEAM, @RF_MEAS, @SCHED, @L2_BUF);

sub t2sec {
    my $t = shift;
    return -1 unless $t =~ /^(\d\d):(\d\d):(\d\d)(?:\.(\d+))?$/;
    return $1*3600 + $2*60 + $3 + (($4 // '') eq '' ? 0 : $4/(10**length($4)));
}

my $app = Win32::OLE->new('QCAT6.Application') or die "no QCAT\n";
$app->{Visible} = FALSE;
$app->{UsePCTime} = FALSE;
my $filter = $app->{PacketFilter};
$filter->SetAll(FALSE);
for my $c (@CODES) { $filter->Set($c, TRUE); }
$filter->Commit();
die "OpenLog failed: $app->{LastError}\n" unless $app->OpenLog($HDF);
print "loaded: $app->{PacketCount} packets\n";

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
print $fh "# 5G 掉线/RLF 日志过滤输出\n";
print $fh "# 日志: $HDF\n";
print $fh "# 时间窗: ", ($FROM || '开始'), " -> ", ($TO || '结尾'), "\n";

my (%cnt, %rach_reason, %rach_result, %skip_reason, %serv_cell, $ul_dci, $dl_dci, $bsr_n);
my $p = $app->{FirstPacket};
my $n = 0;
while ($p) {
    $n++;
    my $type = $p->{Type};
    $cnt{$type}++;
    my $txt = $p->{Text};
    $txt =~ s/\r\n/\n/g;
    my ($h, $mi, $s, $ms) = $txt =~ /(\d\d):(\d\d):(\d\d)\.(\d\d\d)/;
    my $ts = defined $h ? "$h:$mi:$s.$ms" : '--:--:--.---';
    printf $fh "=== %08d\t0x%X ===\n", $n, $type;

    if ($type == 0xB889) {                       # RACH 触发原因
        my ($reason) = $txt =~ /Rach Reason\s*=\s*(\w+)/;
        $reason //= '?';
        $rach_reason{$reason}++;
        print $fh ">>> RACH_TRIGGER $ts reason=$reason\n";
    } elsif ($type == 0xB88A) {                  # RACH 结果
        my ($res) = $txt =~ /RACH Result\s*=\s*(\w+)/;
        my ($ssb) = $txt =~ /SSB ID\s*=\s*(\d+)/;
        $res //= '?';
        $rach_result{$res}++;
        print $fh ">>> RACH_ATTEMPT $ts result=$res ssb=", ($ssb // '?'), "\n";
    } elsif ($type == 0xB823) {                  # 服务小区变化
        my ($pci) = $txt =~ /Physical Cell ID\s*=\s*(\d+)/;
        my ($freq)= $txt =~ /DL Frequency\s*=\s*(\d+)/;
        $serv_cell{"pci=$pci"}++ if defined $pci;
        print $fh ">>> SERVING_CELL $ts pci=", ($pci // '?'), " dl_freq=", ($freq // '?'), "\n";
    } elsif ($type == 0xB8AE) {                  # 上行发送被丢弃（TX_SUSPEND 等）
        for my $l (split /\n/, $txt) {
            my $row = $l;
            $row =~ s/^\s*\|\s*//;
            next unless $row =~ /^\d+\|/;         # 只取数据行（# 列为数字）
            my $f = [ map { s/^\s+|\s+$//g; $_ } split /\|/, $row ];
            my $dr = $f->[5] // '';              # Drop Reason
            my $ch = $f->[6] // '';              # Drop Chan Type
            next unless $dr ne '' && $dr =~ /\w/ && $ch =~ /\w/;
            $skip_reason{"$dr/$ch"}++;
        }
        my @top = (sort { $skip_reason{$b} <=> $skip_reason{$a} } keys %skip_reason)[0..2];
        print $fh ">>> SKIP_UL_TX $ts top=[", join(',', grep { defined $_ } @top), "]\n";
    } elsif ($type == 0xB959) {                  # 无线链路监控
        my ($purp) = $txt =~ /Purpose\s*=\s*(\w+)/;
        print $fh ">>> RLM_STATS $ts purpose=", ($purp // '?'), "\n";
    } elsif ($type == 0xB885) {                  # DCI 计数
        $ul_dci++ while $txt =~ /\bUL_\d_\d\b/g;
        $dl_dci++ while $txt =~ /\bDL_\d_\d\b/g;
    } elsif ($type == 0xB873) {                  # BSR
        $bsr_n++;
        print $fh ">>> UL_BSR $ts\n";
    }

    print $fh $txt if $FULL;
    print $fh "\n";
    last unless $p->Next();
}

print $fh "\n# ============ 掉线事件摘要 ============\n";
print $fh "# UL DCI 授权 $ul_dci 次, DL DCI 分配 $dl_dci 次, UL BSR 上报 $bsr_n 次\n";
print $fh "# RACH 触发原因: ", join('  ', map { "$_=$rach_reason{$_}" } keys %rach_reason), "\n";
print $fh "# RACH 结果:     ", join('  ', map { "$_=$rach_result{$_}" } keys %rach_result), "\n";
print $fh "# 上行丢弃:      ", join('  ', map { "$_=$skip_reason{$_}" } sort { $skip_reason{$b} <=> $skip_reason{$a} } keys %skip_reason), "\n";
print $fh "# 服务小区:      ", join('  ', map { "$_=$serv_cell{$_}" } keys %serv_cell), "\n";
print $fh "# 按消息类型统计\n";
for my $t (sort { $cnt{$b} <=> $cnt{$a} } keys %cnt) {
    my $name = $app->GetPacketTypeName($t);
    printf $fh "# 0x%X\t%d\t%s\n", $t, $cnt{$t}, $name;
}
close $fh;

print "done, $n packets -> $OUT\n";
print "UL_DCI=$ul_dci DL_DCI=$dl_dci BSR=$bsr_n\n";
for my $t (sort { $cnt{$b} <=> $cnt{$a} } keys %cnt) {
    my $name = $app->GetPacketTypeName($t);
    printf "0x%X\t%d\t%s\n", $t, $cnt{$t}, $name;
}
$p = NULL; $filter = NULL; $app = NULL;

