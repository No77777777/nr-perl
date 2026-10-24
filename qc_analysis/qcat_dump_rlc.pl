use strict;
use warnings;
use Win32::OLE;
use constant FALSE => 0;
use constant TRUE  => 1;
use constant NULL  => 0;

my $HDF = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1.hdf';
my $OUT = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\qc_analysis\\rlc_pdcp_detail.txt';

# RLC DL Stats / RLC DL Status PDU (UE 收到的对端状态报告 = UL 数据 ACK/NACK)
# RLC UL Status PDU (UE 发出的状态报告 = DL 数据 ACK/NACK)
# L2 UL Data Pdu / L2 UL TB (RLC->MAC 交付与 TB 组装)
# PDCP UL Stats / RLC UL Stats (PDCP->RLC 交付统计)
my @CODES = (0xB84D, 0xB84E, 0xB869, 0xB870, 0xB872, 0xB860, 0xB868);

my $app = Win32::OLE->new('QCAT6.Application') or die "no QCAT\n";
$app->{Visible} = FALSE;
$app->{UsePCTime} = FALSE;
my $filter = $app->{PacketFilter};
$filter->SetAll(FALSE);
for my $c (@CODES) { $filter->Set($c, TRUE); }
$filter->Commit();

print "opening HDF...\n";
die "OpenLog failed: $app->{LastError}\n" unless $app->OpenLog($HDF);
print "packets: $app->{PacketCount}\n";

open(my $fh, '>', $OUT) or die "out: $!";
binmode($fh);
my $p = $app->{FirstPacket};
my $n = 0;
while ($p) {
    $n++;
    my $txt = $p->{Text};
    $txt =~ s/\r\n/\n/g;
    printf $fh "=== %08d\t0x%X ===\n", $n, $p->{Type};
    print $fh $txt;
    print $fh "\n";
    print STDERR "processed $n\n" if $n % 10000 == 0;
    last unless $p->Next();
}
close $fh;
print "done, wrote $n packets to $OUT\n";
$p = NULL; $filter = NULL; $app = NULL;
