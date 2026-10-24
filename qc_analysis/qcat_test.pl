use strict;
use Win32::OLE;
my $app = Win32::OLE->new('QCAT6.Application');
if ($app) {
    print "OK ver=", $app->{AppVersion}, "\n";
    $app->{Visible} = 0;
    $app = undef;
} else {
    print "FAIL ", Win32::OLE->LastError(), "\n";
}
