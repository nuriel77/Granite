use Moose;
use Test::More;
use POE;
use IO::Socket::PortState 'check_ports';
use FindBin;
use lib "$FindBin::Bin/../lib";
use Granite;
use Granite::Component::Server;
    with 'Granite::Engine::Logger';
use vars qw/$timeout $g %check/;

plan tests => 3;

&run_test();

sub run_test {
    $timeout = 5;
    %check = ( tcp => { 21212 => { name => 'Granite' } } );
    $g = Granite->new();

    # Disable logging
    silence_logger($Granite::log);

    # Adjust running config for testing purposes
    delete $g->{cfg}->{server}->{cacert};
    $g->{cfg}->{server}->{client_certificate} = 'no';
    $g->{cfg}->{server}->{cert} = 'conf/ssl/granite.default.crt';
    $g->{cfg}->{server}->{key} = 'conf/ssl/granite.default.key';

    # Check TCP server
    my $s = Granite::Component::Server->new()->run( 1 );
    ok ( ( $s->_has_mysession and $s->mysession->ID() == 1),
        'verify server returns session ID 1' );

    &check_tcp($s);

    done_testing();
}

sub check_tcp {
    my $s = shift;

    check_ports('localhost', $timeout, \%check);
    is ( $check{'tcp'}->{'21212'}->{open}, 1,
        'check server port listening');

    $poe_kernel->post($s->mysession,'server_shutdown');
    $s->_unset_mysession;

    # Main event ends here
    # ====================
    $poe_kernel->stop() unless $ENV{GRANITE_KEEP_TEST_SERVER_RUNNING};

    # Main event starts here
    # ======================
    $poe_kernel->run();

    sleep 1;
    %check = ( tcp => { 21212 => { name => 'Granite' } } );
    check_ports('localhost', $timeout, \%check);
    ok ( $check{'tcp'}->{'21212'}->{open} == 0,
        'check server shutdown');
}


