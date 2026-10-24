use strict;
use warnings;
use Win32::OLE;
use constant FALSE => 0;
use constant TRUE  => 1;
use constant NULL  => 0;

my $HDF = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\10-22.09-19-13-0755gthroughput.hdf';
my @CODES = (0xB885);

my $app = Win32::OLE->new('QCAT6.Application') or die "no QCAT\n";
$app->{Visible} = FALSE;
$app->{UsePCTime} = FALSE;
my $filter = $app->{PacketFilter};
$filter->SetAll(FALSE);
for my $c (@CODES) { $filter->Set($c, TRUE); }
$filter->Commit();
die "OpenLog failed\n" unless $app->OpenLog($HDF);

# 时间窗 01:17:51.499589 - 01:18:16.501324（设备时钟）
my $t0 = 1*3600 + 17*60 + 51 + 0.499589;
my $t1 = 1*3600 + 18*60 + 16 + 0.501324;
my $base = int($app->{LogStartTime} / 86400) * 86400;
my $offset = ($base + $t0) - $app->{LogStartTime};
$app->SetTimeWindow($offset, $t1 - $t0);

my %shown;
my $p = $app->{FirstPacket};
my $n = 0;
while ($p && $n < 200000) {
    $n++;
    if (!$shown{$p->{Type}}) {
        $shown{$p->{Type}} = 1;
        print "===== SAMPLE 0x", sprintf("%X", $p->{Type}), " =====\n";
        my $t = $p->{Text};
        my @lines = split /\r?\n/, $t;
        my $c = 0;
        for my $l (@lines) {
            print $l, "\n";
            last if ++$c >= 70;
        }
        print "\n";
    }
    last unless $p->Next();
}
print "window packets: $n\n";
$p = NULL; $filter = NULL; $app = NULL;
