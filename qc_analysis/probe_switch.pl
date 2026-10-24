use strict;
use warnings;
use Win32::OLE;
use constant FALSE => 0;
use constant TRUE  => 1;
use constant NULL  => 0;

my $HDF = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\10-22.09-19-13-0755gthroughput.hdf';
my @CODES = (0xB857, 0xB883);

sub fields {
    my $row = shift;
    $row =~ s/^\s*\|\s*//;
    $row =~ s/\|\s*$//;
    return [ map { s/^\s+|\s+$//g; $_ } split /\|/, $row ];
}

my $app = Win32::OLE->new('QCAT6.Application') or die "no QCAT\n";
$app->{Visible} = FALSE;
$app->{UsePCTime} = FALSE;
my $filter = $app->{PacketFilter};
$filter->SetAll(FALSE);
for my $c (@CODES) { $filter->Set($c, TRUE); }
$filter->Commit();
die "OpenLog failed\n" unless $app->OpenLog($HDF);

# 窗口 01:18:02.0 - 01:18:08.0
my $t0 = 1*3600 + 18*60 + 2.0;
my $t1 = 1*3600 + 18*60 + 8.0;
my $base = int($app->{LogStartTime} / 86400) * 86400;
my $offset = ($base + $t0) - $app->{LogStartTime};
$app->SetTimeWindow($offset, $t1 - $t0);

my $p = $app->{FirstPacket};
while ($p) {
    my $txt = $p->{Text};
    my ($h,$mi,$s,$frac) = $txt =~ /(\d\d):(\d\d):(\d\d)\.(\d+)/;
    my $t = defined $h ? $h*3600+$mi*60+$s+$frac/(10**length($frac)) : 0;
    if ($p->{Type} == 0xB857) {
        my $in = 0; my $mx = 0;
        for my $l (split /\r?\n/, $txt) {
            if ($l =~ /TB Data Agg/) { $in = 1; next; }
            next unless $in && $l =~ /^\s*\|\s*\d+\|\s*\d+\|/;
            my $f = fields($l);
            next unless @$f >= 2 && $f->[1] =~ /^\d+$/;
            $mx = $f->[1] if $f->[1] > $mx;
        }
        printf "DL_TB %.3f max_tb=%d\n", $t, $mx;
    } else {
        my $mx = 0;
        for my $l (split /\r?\n/, $txt) {
            next unless $l =~ /\|\s*PUSCH\s*\|/;
            my $f = fields($l);
            next unless @$f >= 27;
            $mx = $f->[21] if $f->[21] =~ /^\d+$/ && $f->[21] > $mx;
        }
        printf "UL_TB %.3f max_tbs=%d\n", $t, $mx;
    }
    last unless $p->Next();
}
$p = NULL; $filter = NULL; $app = NULL;
