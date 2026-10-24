use strict;
use warnings;
use Win32::OLE;
use constant FALSE => 0;
use constant TRUE  => 1;
use constant NULL  => 0;

my $HDF = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1.hdf';
my $OUT = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\qc_analysis\\msg_type_counts.txt';
my $LOG = 'D:\\560\\ITR-8 mobility test sender1\\ITR-8 mobility test sender1\\qc_analysis\\qcat_count_log.txt';  # 运行过程日志

open(my $lfh, '>', $LOG) or die "cannot write $LOG: $!\n";
sub tee {
    my $line = shift;
    print $line;
    print $lfh $line;
}

my $app = Win32::OLE->new('QCAT6.Application') or die "no QCAT\n";
$app->{Visible} = FALSE;

# enable ALL packet types so the iteration sees every packet in the HDF
my $filter = $app->{PacketFilter};
$filter->SetAll(TRUE);
$filter->Commit();

tee("opening HDF...\n");
die "OpenLog failed: $app->{LastError}\n" unless $app->OpenLog($HDF);
tee("packets: $app->{PacketCount}\n");

my %count;
my $p = $app->{FirstPacket};
my $n = 0;
while ($p) {
    $n++;
    $count{$p->{Type}}++;
    tee("processed $n\n") if $n % 1000000 == 0;
    last unless $p->Next();
}

open(my $fh, '>', $OUT) or die "out: $!";
printf $fh "# total packets = %d, distinct types = %d\n", $n, scalar(keys %count);
for my $t (sort { $count{$b} <=> $count{$a} } keys %count) {
    my $name = $app->GetPacketTypeName($t);
    printf $fh "0x%X\t%d\t%s\n", $t, $count{$t}, $name;
}
close $fh;
tee(sprintf("done, %d packets, %d distinct types -> %s\n", $n, scalar(keys %count), $OUT));
close $lfh;
$p = NULL; $filter = NULL; $app = NULL;
