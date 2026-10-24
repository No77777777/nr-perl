use strict;
use warnings;
use Win32::OLE;
use constant FALSE => 0;
use constant TRUE  => 1;
use constant NULL  => 0;

my $HDF = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\10-22.09-19-13-0755gthroughput.hdf';
my @CODES = (0xB885, 0xB888, 0xB8D8, 0xB97F, 0xB8B5, 0xB884, 0xB883,
             0xB8A7, 0xB823, 0xB872, 0xB857, 0xB860, 0xB842, 0xB89B);

my $app = Win32::OLE->new('QCAT6.Application') or die "no QCAT\n";
$app->{Visible} = FALSE;
$app->{UsePCTime} = FALSE;
my $filter = $app->{PacketFilter};
$filter->SetAll(FALSE);
for my $c (@CODES) { $filter->Set($c, TRUE); }
$filter->Commit();
die "OpenLog failed\n" unless $app->OpenLog($HDF);
print "packets: ", $app->{PacketCount}, "\n";
print "start: ", scalar(gmtime($app->{LogStartTime})), " dur: ", $app->{LogDuration}, "s\n";

my (%cnt, %shown);
my $p = $app->{FirstPacket};
my $n = 0;
while ($p) {
    $n++;
    $cnt{$p->{Type}}++;
    if (!$shown{$p->{Type}}) {
        $shown{$p->{Type}} = 1;
        print "===== SAMPLE 0x", sprintf("%X", $p->{Type}), " =====\n";
        my $t = $p->{Text};
        my @lines = split /\r?\n/, $t;
        my $c = 0;
        for my $l (@lines) {
            print $l, "\n";
            last if ++$c >= 55;
        }
        print "\n";
    }
    last unless $p->Next();
}
print "iterated: $n\n";
for my $t (sort { $cnt{$b} <=> $cnt{$a} } keys %cnt) {
    printf "0x%X\t%d\t%s\n", $t, $cnt{$t}, $app->GetPacketTypeName($t);
}
$p = NULL; $filter = NULL; $app = NULL;
