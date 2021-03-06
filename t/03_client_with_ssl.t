use Moose;
use Test::More;
sub POE::Kernel::ASSERT_EVENTS  () { 0 }
sub POE::Kernel::ASSERT_DEFAULT () { 0 }
sub POE::Kernel::TRACE_EVENTS  () { 0 }
sub POE::Kernel::TRACE_DEFAULT  () { 0 }
sub POE::Kernel::CATCH_EXCEPTIONS () { 0 }
use POE::Kernel;
use POE;
use POE::Wheel::Run;
use IO::Socket::PortState 'check_ports';
use FindBin;
use lib "$FindBin::Bin/../lib";
use Granite;
use Granite::Component::Server;
    with 'Granite::Engine::Logger';
use vars qw/$timeout $g $s %check $server_started
            $client_connections $server $server_session
            $server_killed $socket/;

sub DEBUG { $ENV{GRANITE_DEBUG} }

BEGIN {
    use_ok( 'POE::Test::Helpers');
    use_ok( 'IO::Socket::SSL');
    use_ok( 'POE' );
}

use File::Touch;
    
$SIG{INT} = \&DEAD;
    

local $| = 1;


#
# Todo: Setup server startup from here
# and see how to use default certificates
#

our $servername = $ENV{GRANITE_HOSTNAME} || 'Granite HPC Cloud Scheduler';
our $host   = $ENV{GRANITE_BIND}         || '127.0.0.1';
our $port   = $ENV{GRANITE_PORT}         || 21212;
our $capath = $ENV{GRANITE_CA_PATH}      || 'conf/ssl';
our $cacert = $ENV{GRANITE_CA_CERT}      || $capath.'/ca.crt';
our $crt    = $ENV{GRANITE_CERT}         || 'conf/ssl/client01.crt';
our $key    = $ENV{GRANITE_KEY}          || 'conf/ssl/client01.key';
our $password = 'system';
$timeout = 5;
our $n = 0;
my $test_connections = $ENV{GRANITE_TEST_MAX_CONNECTIONS} || 10;
%check = ( tcp => { $port => { name => 'Granite' } } );
$client_connections = 0;

#
# We plan 7 tests per client connection + 5 base tests
#
plan tests => 5 + ( 7 * $test_connections);

$_[HEAP]->{clients} = {};

#
# IO::Socket::SSL - see http://search.cpan.org/~sullr/IO-Socket-SSL-1.966/lib/IO/Socket/SSL.pm
#
my $run = sub { 

    return POE::Session->create(
        inline_states => {
            _start        => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                unless ( $server_started || $_[HEAP]->{server_started} ){
                    $heap->{worker} = POE::Wheel::Run->new(
                        Program     => \&run_test,
                    ) or die "$0: can't POE::Wheel::Run->new";
                    $server = $heap->{worker};
                }
                $kernel->sig_child($server->PID, "got_sig");
                $kernel->yield('watch_client');
                $kernel->delay('client_is_next'=>1);           
            },
            watch_client => sub {
                if ( -e '/tmp/clients_busy' ){
                    $n++;
                    print STDERR '.';
                    if ( $n == ( $test_connections * 10 ) ){
                        $socket->close() if $socket;
                        $server->kill();
                        delete $_[HEAP]->{readwrite};
                        delete $_[HEAP]->{wheel};
                        $poe_kernel->sig_child( $server->PID, '_stop');
                        $poe_kernel->stop();
                    }
                    else {
                        $_[KERNEL]->delay('watch_client'=>1);
                    }
                }
            },
            got_sig => sub { $_[KERNEL]->post('_stop'); },
            client_is_next => sub {
                $client_connections++;
                my ($err);
                eval {
                    local $SIG{ALRM} = sub { die "TIMEOUT\n" };
                    alarm 2;
                    $socket = IO::Socket::SSL->new(
                        # where to connect
                        PeerHost => $host,
                        PeerPort => $port,
    
                        # Client certificate/key
                        SSL_cert_file => $crt,
                        SSL_key_file => $key,
    
                        # certificate verification
                        #SSL_ca_path => $capath,
                        #SSL_ca_file => $cacert,
                        #SSL_verify_mode => SSL_VERIFY_PEER,
                        SSL_use_cert => 1,
                        SSL_verify_mode => SSL_VERIFY_NONE,
    
                        # easy hostname verification
                        SSL_verifycn_name => $servername,
                        #SSL_verifycn_scheme => 'http',
    
                        # SNI support
                        SSL_hostname => $servername,
                    );
                    $err = $SSL_ERROR if $SSL_ERROR;
                    alarm 0;
                };

                $err ||= $SSL_ERROR || $@;

                if ($err){
                    diag ( $err );
                    &DEAD;
                    return;
                }

                if ( $socket and ref $socket eq 'IO::Socket::SSL' ){
                    $_[HEAP]->{clients}->{$_[SESSION]->ID()}->{socket} = $socket;
                    $_[KERNEL]->yield('start_io_socket_ssl', $socket);
                    return;
                }
                
            },
            start_io_socket_ssl       => sub { 
                my ($kernel, $heap, $socket ) = @_[ KERNEL, HEAP, ARG0 ];
                pass ( "Session " . $_[SESSION]->ID() . " is active" );

                print {$socket} "$password\n";
                if ( my $input = <$socket> ){
                    chomp($input);
                    if ( $input =~ /^\[(\d+)\] Authenticated!/ ){ 
                        $_[KERNEL]->yield('client_is_authenticated', $socket, $1);
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
                my ($kernel, $heap, $socket, $wheel_id ) = @_[ KERNEL, HEAP, ARG0, ARG1 ];
                pass ( "Authentication successful" );
                $_[KERNEL]->yield('client_server_can_readwrite', $socket, $wheel_id );
            },
            client_server_can_readwrite     => sub {               
                my $socket = $_[ARG0];
                my $server_wheel_id = $_[ARG1];
                my $sessionId = $_[SESSION]->ID();
                my $expected_string = '\['.$server_wheel_id.'\] Test OK for wheel ID '.$server_wheel_id; 
                
                print {$socket} "test\n";
                if ( my $reply = <$socket> ){
                    chomp($reply);
                    # example reply: [11] Test OK for wheel ID 11
                    if ( $reply =~ /^$expected_string/ ){
                        pass ('Expected reply from server OK');
                        $_[KERNEL]->post($_[SESSION], '_stop' );
                    }
                    else {
                        diag ( "Unexpected reply from server: '$reply', we expected: '$expected_string'" );
                        $_[KERNEL]->post($_[SESSION], 'failed_readwrite');
                    }
                }
                else {
                    $_[KERNEL]->post($_[SESSION], 'failed_readwrite');
                }
            },
            failed_readwrite => sub { $_[KERNEL]->delay('_stop' => 1 ) },
            _stop            => sub {
                my ($kernel, $session, $heap) = @_[KERNEL, SESSION, HEAP];
                delete $heap->{clients}->{ $session->ID() };
                $socket->close();
                if ( $server->kill() ){
                    $poe_kernel->sig_child( $server->PID, '_stop');
                    delete $heap->{readwrite};
                    delete $heap->{wheel};
                    $server_killed = 1;
                }
                if ( $client_connections >= $test_connections ){
                    unlink ('/tmp/clients_busy');
                    $poe_kernel->stop();
                    sleep 1;
                    check_ports($host, $timeout, \%check);
                    is ( $check{'tcp'}->{$port}->{open}, 0,
                        'check server is really down');
                    pass ('Done testing');
                    done_testing();
                    exit;
                }
            },
        }
    )
};

touch ('/tmp/client_done');
for (1..$test_connections){
    POE::Test::Helpers->spawn(
        run   => $run,
        tests => {
            # _start is 0
            start_io_socket_ssl         => { order => 1 },
            client_is_next              => { order => 2 },
            client_is_authenticated     => { order => 3 },
            client_server_can_readwrite => { order => 4 },
            _stop                       => { order => 5 },
        },
    );
    $server_started++;
}



$poe_kernel->run();
exit 0;


sub run_test {
    $SIG{__DIE__} = \&DEAD;
    $SIG{INT} = sub { exit; };
    $SIG{TERM} = sub { exit; };

    $_[HEAP]->{server_started} = 1;

    POE::Kernel->stop();

    %check = ( tcp => { 21212 => { name => 'Granite' } } );
    $g = Granite->new();

    # Disable logging
    silence_logger(Granite->log) unless $ENV{GRANITE_KEEP_LOGGING};

    # Adjust running config for testing purposes
    delete Granite->cfg->{server}->{cacert};
    delete Granite->cfg->{server}->{unix_socket};
    Granite->cfg->{server}->{client_certificate} = 'no';
    Granite->cfg->{server}->{verify_client} = 'no';
    Granite->cfg->{server}->{cert} = 'conf/ssl/granite.default.crt';
    Granite->cfg->{server}->{key} = 'conf/ssl/granite.default.key';

    
    $server_session = POE::Session->create(
        inline_states => {
            _start => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                # Check TCP server
                $s = Granite::Component::Server->new()->run( $_[SESSION]->ID() );
                ok ( ( $s->_has_mysession and $s->mysession->ID() == ($_[SESSION]->ID()+1) ),
                    'verify server returns session ID ' . $s->mysession->ID() );

                check_ports($host, $timeout, \%check);
                is ( $check{'tcp'}->{$port}->{open}, 1,
                    'check server port listening');
                $kernel->sig(TERM => '_stop');
            },
            _stop  => sub {
                unless ( $server_killed ){
                    $server_killed = 1;
                    #exit;
                }
            },
        }
    );

    $poe_kernel->run();
    return;

}

sub DEAD {
    return unless defined $^S and $^S == 0; # Ignore errors in eval
    $socket->close() if $socket;
    $server->kill();
    $poe_kernel->sig_child( $server->PID, '_stop');
    delete $_[HEAP]->{readwrite};
    delete $_[HEAP]->{wheel};
    $poe_kernel->stop();
    exit 1;
}
