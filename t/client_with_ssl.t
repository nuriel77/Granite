use strict;
use Test::More;

sub DEBUG { $ENV{GRANITE_DEBUG} }

BEGIN {
    use_ok( 'POE::Test::Helpers');
    use_ok( 'IO::Socket::SSL');
    use_ok( 'POE' );
}


local $| = 1;



my $pid = fork();
if( $pid == 0 ){
    $poe_kernel->stop();
    $ENV{GRANITE_KEEP_TEST_SERVER_RUNNING} = 1;
    exec 'GRANITE_KEEP_TEST_SERVER_RUNNING=1 perl t/01_test_server_tcp.t';
}

sleep 2;


#
# Todo: Setup server startup from here
# and see how to use default certificates
#

my $servername = $ENV{GRANITE_HOSTNAME} || 'nova.clustervision.com';
my $host   = $ENV{GRANITE_BIND}         || '127.0.0.1';
my $port   = $ENV{GRANITE_PORT}         || 21212;
my $capath = $ENV{GRANITE_CA_PATH}      || 'conf/ssl';
my $cacert = $ENV{GRANITE_CA_CERT}      || $capath.'/ca.crt';
my $crt    = $ENV{GRANITE_CERT}         || 'conf/ssl/client01.crt';
my $key    = $ENV{GRANITE_KEY}          || 'conf/ssl/client01.key';
my $password = 'system';

my $test_connections = $ENV{GRANITE_TEST_MAX_CONNECTIONS} || 10;

#
# We plan 6 tests per client connection + 3 base tests
#
plan tests => 3 + ( 6 * $test_connections);

$_[HEAP]->{clients} = {};

#
# IO::Socket::SSL - see http://search.cpan.org/~sullr/IO-Socket-SSL-1.966/lib/IO/Socket/SSL.pm
#
my $run = sub { 
    return POE::Session->create(
        inline_states => {
            _start        => sub {
                my $socket = IO::Socket::SSL->new(
                    # where to connect
                    PeerHost => $host,
                    PeerPort => $port,

                    # Client certificate/key
                    SSL_cert_file => $crt,
                    SSL_key_file => $key,

                    # certificate verification
                    #SSL_ca_path => $capath,
                    SSL_ca_file => $cacert,
                    SSL_verify_mode => SSL_VERIFY_PEER,
                    #SSL_verify_mode => SSL_VERIFY_NONE,

                    # easy hostname verification
                    SSL_verifycn_name => $servername,
                    #SSL_verifycn_scheme => 'http',

                    # SNI support
                    SSL_hostname => $servername,
                );
                my $err = "$!, $SSL_ERROR" if $SSL_ERROR;

                if ( $socket and ref $socket eq 'IO::Socket::SSL' ){
                    $_[HEAP]->{clients}->{$_[SESSION]->ID()}->{socket} = $socket;
                    $_[KERNEL]->yield('start_io_socket_ssl', $socket);
                }
                else {
                    diag ( $err );
                }
            },
            start_io_socket_ssl       => sub { 
                my ($kernel, $heap, $socket ) = @_[ KERNEL, HEAP, ARG0 ];
                pass ( "Session " . $_[SESSION]->ID() . " is active" );

                print {$socket} "$password\n";
                if ( my $input = <$socket> ){
                    chomp($input);
                    if ( $input =~ /^.*Authenticated!/ ){ 
                        $_[KERNEL]->yield('client_is_authenticated', $socket)
                    }
                    else {
                        diag ( "Server returned '$input'\n" );
                        $_[KERNEL]->post($_[SESSION], '_stop', $socket);
                    }
                }
                else {
                    diag ( "Server did not return a reply\n");
                }
            },
            client_is_authenticated => sub {
                my ($kernel, $heap, $socket ) = @_[ KERNEL, HEAP, ARG0 ];
                pass ( "Authentication successful" );
                $_[KERNEL]->yield('client_server_can_readwrite', $socket );
            },
            client_server_can_readwrite     => sub {
                my $socket = $_[ARG0];
                my $sessionId = $_[SESSION]->ID();
                print {$socket} "Test readwrite ".$sessionId."\n";
                if ( my $reply = <$socket> ){
                    chomp($reply);
                    if ( $reply =~ /^.*Your input: Test readwrite $sessionId$/ ){
                        $_[KERNEL]->delay('_stop' => 1, $_[SESSION]->ID() );
                    }
                    else {
                        diag ( "Unexpected reply from server: '$reply'" );
                        $_[KERNEL]->post($_[SESSION], 'failed_readwrite');
                    }
                }
                else {
                    $_[KERNEL]->post($_[SESSION], 'failed_readwrite');
                }
            },
            failed_readwrite => sub { $_[KERNEL]->delay('_stop'=>1) },
            _stop         => sub { delete $_[HEAP]->{clients}->{ $_[ARG0] } },
        }
    )
};



for (1..$test_connections){
    POE::Test::Helpers->spawn(
        run   => $run,
        tests => {
            # _start is 0
            start_io_socket_ssl         => { order => 1 },
            client_is_authenticated     => { order => 2 },
            client_server_can_readwrite => { order => 3 },
            _stop                       => { order => 4 },
        },
    );
}

kill INT => -$pid;
kill 9, $pid;


$poe_kernel->run();

done_testing();

__END__
