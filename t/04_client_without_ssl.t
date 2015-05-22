use strict;
use Socket;
use Test::More;
use POE::Test::Helpers;
use POE;


use_ok('IO::Socket::INET');

sub DEBUG { $ENV{GRANITE_DEBUG} }

$| = 1;

my $servername = $ENV{GRANITE_HOSTNAME} || 'localhost';
my $host       = $ENV{GRANITE_BIND}     || '127.0.0.1';
my $port       = $ENV{GRANITE_PORT}     || 21212;
my $password   = 'system';
my $test_connections = $ENV{GRANITE_TEST_MAX_CONNECTIONS} || 1;

our %connection_params = (
    address => $host,
    port => $port,
    timeout => 3,
    autoconnect => 1
);

#
# We plan 7 tests per client connection + 1 base test(s)
#
plan tests => 1 + ( 7 * $test_connections);


$_[HEAP]->{clients} = {};

my $run = sub {
    POE::Session->create(
        inline_states => {
            _start           => \&_init,
            authenticate     => \&_authentication,
            test_readwrite   => \&_test_readwrite,
            test_disconnect  => \&_test_disconnect,
            failed_readwrite => \&_fail,
            _stop            => \&_stop,
        },
    );
};

for (1..$test_connections){
    POE::Test::Helpers->spawn(
        run   => $run,
        tests => {
            # _start is 0
            authenticate         => { order => 1 },
            test_readwrite       => { order => 2 },
            test_disconnect      => { order => 3 },
            _stop                => { order => 4 },
        },
    );
}

$poe_kernel->run();
done_testing();
exit 0;

#
# METHODS
#
sub _fail {
    diag ( 'SessionId ' . $_[SESSION]->ID() . ' failure' );
    delete $_[HEAP]->{clients}->{$_[SESSION]->ID()};
    $_[KERNEL]->delay('_stop'=>1);
}

sub _stop {
    pass ( 'SessionId ' . $_[SESSION]->ID() . ' disconnecting' );
    delete $_[HEAP]->{clients}->{$_[SESSION]->ID()};
    return;
}

sub _init {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    warn "At start...\n" if DEBUG;
    my $err;
    my $socket = new IO::Socket::INET (
        PeerHost => $host,
        PeerPort => $port,
        Proto => 'tcp',
    ) or $err = $!;

    if ( $socket and ref $socket eq 'IO::Socket::INET' ){
        pass('Have new socket connection');
        $_[HEAP]->{clients}->{$_[SESSION]->ID()}->{socket} = $socket;
        $_[KERNEL]->yield('authenticate', $socket);
    }
    else {
        diag ( "Failed to connect to server: $err" );
        $_[KERNEL]->post('failed_readwrite');
    }   
    return;
}

sub _authentication {
    my ( $kernel, $heap, $socket ) = @_[ KERNEL, HEAP, ARG0 ];
    
    print {$socket} "$password\n";  

    if ( my $input = <$socket> ){
        chomp($input);
        if ( $input =~ /^.*Authenticated!/ ){
            $_[KERNEL]->yield('test_readwrite', $socket);
        }
        else {
            diag ( "Auth failed: '$input'\n" );
            $_[KERNEL]->post('failed_readwrite');
        }
    }
    else {
        diag ( "Server did not return a reply\n");
        $_[KERNEL]->post('failed_readwrite');
    }
  
}

sub _test_readwrite {
    my ( $kernel, $heap, $socket ) = @_[ KERNEL, HEAP, ARG0 ];

    pass( $_[STATE] );
    print {$socket} "Hellooo\n";

    if ( my $input = <$socket> ){
        chomp($input);
        if ( $input =~ /^.*Your input: Hellooo$/ ){
            pass('Server replied with expected string');
            $kernel->post('test_disconnect');
        }
        else {
            diag ( "Unexpected reply from server: '$input'" );
            $kernel->post($_[SESSION], 'failed_readwrite');
        }
    }
    else {
        $_[KERNEL]->post($_[SESSION], 'failed_readwrite');
    }

    return;
}

sub _test_disconnect {
    my ( $heap, $state ) = @_[ HEAP, STATE ];
    pass($state);
    $_[KERNEL]->delay('_stop'=>1);
    return;
}

