use strict;
use warnings;
use Socket qw(AF_UNIX);
use POE;                          # For base features.
use POE::Wheel::SocketFactory;    # To create sockets.
use POE::Wheel::ReadWrite;        # To read/write lines with sockets.
use POE::Wheel::ReadLine;         # To read/write lines on the console.

my $rendezvous = '/tmp/granited.socket';

POE::Session->create(
    inline_states => {
        _start         => \&client_init,
        sock_connected => \&socket_connected,
        sock_error     => \&socket_error,
        sock_input     => \&socket_input,
        cli_input      => \&console_input,
    },
);


$poe_kernel->run();
exit 0;

sub client_init {
    my $heap = $_[HEAP];
    $heap->{connect_wheel} = POE::Wheel::SocketFactory->new(
        SocketDomain  => AF_UNIX,
        RemoteAddress => $rendezvous,
        SuccessEvent  => 'sock_connected',
        FailureEvent  => 'sock_error',
    );
}

sub socket_connected {
    my ( $heap, $socket ) = @_[ HEAP, ARG0 ];
    delete $heap->{connect_wheel};
    $heap->{io_wheel} = POE::Wheel::ReadWrite->new(
        Handle     => $socket,
        InputEvent => 'sock_input',
        ErrorEvent => 'sock_error',
    );
    $heap->{cli_wheel} = POE::Wheel::ReadLine->new( InputEvent => 'cli_input' );
    $heap->{cli_wheel}->get("=> ");
}

sub socket_input {
    my ( $heap, $input ) = @_[ HEAP, ARG0 ];
    $heap->{cli_wheel}->put("Server Said: $input");
}

sub socket_error {
    my ( $heap, $syscall, $errno, $error ) = @_[ HEAP, ARG0 .. ARG2 ];
    $error = "Normal disconnection." unless $errno;
    warn "Client socket encountered $syscall error $errno: $error\n";
    delete $heap->{connect_wheel};
    delete $heap->{io_wheel};
    delete $heap->{cli_wheel};
}

sub console_input {
    my ( $heap, $input, $exception ) = @_[ HEAP, ARG0, ARG1 ];
    if ( defined $input ) {
        $heap->{cli_wheel}->addhistory($input);
        $heap->{cli_wheel}->put("You Said: $input");
        $heap->{io_wheel}->put($input);
    }
    elsif ( $exception eq 'cancel' ) {
        $heap->{cli_wheel}->put("Canceled.");
    }
    else {
        $heap->{cli_wheel}->put("Bye.");
        delete $heap->{cli_wheel};
        delete $heap->{io_wheel};
        return;
    }

    # Prompt for the next bit of input.
    $heap->{cli_wheel}->get("=> ");
}
