use strict;
use warnings;
use Win32::OLE;
use constant FALSE => 0;
use constant TRUE  => 1;
use constant NULL  => 0;

my $HDF = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1.hdf';
my $OUT = 'D:\\560\\decoded.txt';

my @CODES = (0xB873, 0xB870, 0xB872, 0xB889, 0xB88A, 0xB8AE, 0xB959, 0xB823,
             0xB890, 0xB885, 0xB89B, 0xB896, 0xB860, 0xB868, 0xB8A7, 0xB8D8,
             0xB883, 0xB825, 0xB871, 0xB89C,
             0xB880, 0xB884, 0xB891, 0xB8A0,
             0xB821, 0xB822,
             0xB975, 0xB9A4, 0xB9A5, 0xBA03,
             0xB981, 0xB950, 0xB97F);

my $app = new Win32::OLE 'QCAT6.Application';
die "no QCAT object\n" unless $app;
print "QCAT $app->{AppVersion}\n";
$app->{Visible} = FALSE;
$app->{UsePCTime} = FALSE;

my $filter = $app->{PacketFilter};
die "no filter\n" unless $filter;
$filter->SetAll(FALSE);
for my $c (@CODES) { $filter->Set($c, TRUE); }
$filter->Commit();

print "opening HDF...\n";
if(!$app->OpenLog($HDF)) {
    print "OpenLog failed: $app->{LastError}\n";
    exit 1;
}
print "loaded. packets: $app->{PacketCount}\n";
print "start: ", scalar(gmtime($app->{LogStartTime})), " end: ", scalar(gmtime($app->{LogEndTime})), " dur: $app->{LogDuration}s\n";

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
    if ($n % 10000 == 0) { print STDERR "processed $n\n"; }
    last unless $p->Next();
}
close $fh;
print "done, wrote $n packets to $OUT\n";
$p = NULL;
$filter = NULL;
$app = NULL;
