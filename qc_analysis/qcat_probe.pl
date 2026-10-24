use strict;
use warnings;
use Win32::OLE;
use constant FALSE => 0;
use constant TRUE  => 1;
use constant NULL  => 0;

my $HDF = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1.hdf';
my $OUT = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\qc_analysis\\probe_samples.txt';
my @CODES = (0xB842, 0xB888, 0xB886, 0xB857, 0xB880, 0xB8A0, 0xB84D, 0xB840, 0xB847);

my $app = Win32::OLE->new('QCAT6.Application') or die "no QCAT\n";
$app->{Visible} = FALSE;
$app->{UsePCTime} = FALSE;
my $filter = $app->{PacketFilter};
$filter->SetAll(FALSE);
for my $c (@CODES) { $filter->Set($c, TRUE); }
$filter->Commit();
die "OpenLog failed\n" unless $app->OpenLog($HDF);

my %shown;
open(my $fh, '>', $OUT) or die $!;
my $p = $app->{FirstPacket};
my $n = 0;
while ($p && $n < 200) {
    $n++;
    my $t = $p->{Type};
    if (!$shown{$t}) {
        $shown{$t} = 1;
        printf $fh "=== 0x%X ===\n", $t;
        print $fh $p->{Text};
        print $fh "\n\n";
    }
    last unless $p->Next();
}
close $fh;
print "wrote samples to $OUT\n";
$p = NULL; $filter = NULL; $app = NULL;
