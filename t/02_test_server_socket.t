
use Moose;
use Test::More;
use Socket qw(AF_UNIX);
use POE;
use POE::Wheel::SocketFactory;
use POE::Wheel::ReadWrite;
use POE::Wheel::ReadLine;
use Data::Dumper;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Granite;
use Granite::Component::Server;
    with 'Granite::Engine::Logger';

use vars qw/$g $s $password/;
plan tests => 4;

BEGIN { $g = Granite->new(); }

$password = 'system';

# Disable logging
silence_logger($Granite::log);

# Adjust running config for testing purposes
$g->{cfg}->{server}->{unix_socket} = '/tmp/granited.socket';

# Check server
&start_client_test;

$poe_kernel->post($s->mysession,'server_shutdown');
$s->_unset_mysession;

$poe_kernel->run();

sleep 1;
ok ( ( not -S $g->{cfg}->{server}->{unix_socket} ), 'socket stopped' );

done_testing();

sub start_server{
    my $sessionId = $_[SESSION]->ID();
    $s = Granite::Component::Server->new()->run( $sessionId );
    my $server_session = $s->_has_mysession ? $s->mysession->ID() : 0;
    ok ( $server_session == ( $sessionId + 1 ), 'check server started' );
    $_[KERNEL]->yield('server_started');
}

sub check_socket {
    ok (
        ( -e $g->{cfg}->{server}->{unix_socket} && -S $g->{cfg}->{server}->{unix_socket}),
        'check socket created'
    );

}

sub start_client_test {
    POE::Session->create(
        inline_states => {
            _start         => \&start_server,
            server_started => \&client_init,
            sock_connected => \&socket_connected,
            sock_error     => \&socket_error,
            sock_input     => \&socket_input,
            stop_server    => \&stop_server,
            send_auth      => \&authenticate,
            _stop          => sub {
                my ( $heap, $kernel ) = @_[ HEAP, KERNEL ];
                delete $heap->{connect_wheel};
                delete $heap->{io_wheel};
                delete $heap->{cli_wheel};
                $kernel->post($s, '_stop' );
                $kernel->stop();
            },
        },
    );
}

sub client_init {
    &check_socket;
    my $heap = $_[HEAP];
    $heap->{connect_wheel} = POE::Wheel::SocketFactory->new(
        SocketDomain  => AF_UNIX,
        RemoteAddress => $g->{cfg}->{server}->{unix_socket},
        SuccessEvent  => 'sock_connected',
        FailureEvent  => 'sock_error',
    ) or die $!;
}

sub socket_connected {
    my ( $heap, $socket ) = @_[ HEAP, ARG0 ];
    delete $heap->{connect_wheel};
    $heap->{io_wheel} = POE::Wheel::ReadWrite->new(
        Handle     => $socket,
        InputEvent => 'sock_input',
        ErrorEvent => 'sock_error',
    );
    $_[KERNEL]->yield('send_auth');
}

sub socket_input {
    my $input = $_[ARG0];
    chomp($input);
    ok ( $input =~ /^.*Authenticated!$/, 'server authentication ok' );
    $_[KERNEL]->post($_[SESSION], 'stop_server');

}

sub stop_server {
    $_[HEAP]->{io_wheel}->put('server_shutdown');
    $_[KERNEL]->delay('_stop'=>2);
}


sub socket_error {
    my ( $heap, $syscall, $errno, $error ) = @_[ HEAP, ARG0 .. ARG2 ];
    warn "Client socket encountered $syscall error $errno: $error\n" if $errno;
    delete $heap->{connect_wheel};
    delete $heap->{io_wheel};
    delete $heap->{cli_wheel};
}

sub authenticate {
    my $heap = $_[HEAP];
    $heap->{io_wheel}->put($password);
}
