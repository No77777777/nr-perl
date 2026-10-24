use strict;
use warnings;
use Win32::OLE;

my $pat   = shift(@ARGV) // '';
my $OUT   = 'qcat_list_output.txt';   # 输出文本，写在当前目录

open(my $ofh, '>', $OUT) or die "cannot write $OUT: $!\n";
sub tee {
    my $line = shift;
    print $line;
    print $ofh $line;
}

my $app = Win32::OLE->new('QCAT6.Application') or die "no qcat\n";
my $list = $app->{SupportedPackets};
my $n = 0;
for my $type (@$list) {
    my $name = $app->GetPacketTypeName($type);
    next unless $name =~ /$pat/i;
    tee(sprintf("0x%X -- %s\n", $type, $name));
    $n++;
}
tee(sprintf("total: %d types (pattern: '%s')\n", $n, $pat));
close $ofh;
$app = undef;
print "written to $OUT\n";
