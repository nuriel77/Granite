use Moose;
use Test::More;
use POE;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Granite;
use Granite::Component::Server;
    with 'Granite::Engine::Logger';

use vars qw/$g/;
plan tests => 2;

BEGIN { $g = Granite->new(); }

# Disable logging
silent_logger($Granite::log);

# Adjust running config for testing purposes
$g->{cfg}->{server}->{unix_socket} = '/tmp/granited.socket';

# Check TCP server
my $s = Granite::Component::Server->new()->run( 1 );
ok ( ( $s->_has_mysession and $s->mysession->ID() == 1),
    'verify server returns session ID 1' );

&check_socket($s);

done_testing();

sub check_socket {
    my $s = shift;

    ok ( -e $g->{cfg}->{server}->{unix_socket}, 'check socket' );

    $poe_kernel->post($s->mysession,'server_shutdown');
    $s->_unset_mysession;
    
    $poe_kernel->run();
}

