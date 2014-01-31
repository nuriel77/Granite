package Granite::Component::Server;
use strict;
use warnings;
use Socket;
use Sys::Hostname;
use POE::Component::SSLify qw( SSLify_Options SSLify_GetCTX SSLify_GetCipher SSLify_GetSocket);
use POE::Component::SSLify::NonBlock qw(
  Server_SSLify_NonBlock
  SSLify_Options_NonBlock_ClientCert
  Server_SSLify_NonBlock_ClientCertVerifyAgainstCRL
  Server_SSLify_NonBlock_ClientCertificateExists
  Server_SSLify_NonBlock_ClientCertIsValid
  Server_SSLify_NonBlock_SSLDone );
use POE
  qw( Wheel::SocketFactory Driver::SysRW Filter::Stream Wheel::ReadWrite );

use vars
  qw( $log $port $granite_key $granite_crt $debug
      $bind $max_clients $client_filters $granite_cacrt
      $granite_verify_client $granite_cipher $granite_crl
      $client_namespace $host_name $disable_ssl );


$ENV{GRANITE_CLIENT_CERTIFICATE} = 1 if $ENV{GRANITE_VERIFY_CLIENT};

$port          = 21212;
$bind          = '127.0.0.1';
$max_clients   = 10;
$host_name     = $ENV{GRANITE_HOSTNAME} || $CONF::cfg->{server}->{hostname} || hostname();
$granite_crt    = '/etc/openvpn/easy-rsa/keys/server.crt',;
$granite_key    = '/etc/openvpn/easy-rsa/keys/server.key';
$granite_cacrt  = '/etc/openvpn/easy-rsa/keys/ca.crt';
$granite_cipher = 'DHE-RSA-AES256-GCM-SHA384:AES256-SHA';
$granite_crl    = '';

sub run {
    ($log, $debug) = @_[ ARG0, ARG1 ];

    $disable_ssl = $ENV{GRANITE_DISABLE_SSL} || $CONF::cfg->{server}->{disable_ssl};

    unless ( $disable_ssl ){
        $log->debug('Setting SSLify options');

        eval { SSLify_Options( $granite_key, $granite_crt ) };
        $log->logcroak( "Error setting SSLify_Options with '$granite_key' and '$granite_crt': "
                        . $@ . ' Check file permissions.' ) if ($@);

        eval { SSLify_Options_NonBlock_ClientCert( SSLify_GetCTX(), $granite_cacrt ); };
        $log->logcroak( 'Error setting SSLify_Options_NonBlock_ClientCert: ' . $@ ) if ($@);
    }

    POE::Session->create(
        inline_states => {
            _start => sub {
                my ( $heap, $kernel ) = @_[ HEAP, KERNEL ];
                $heap->{server_wheel} = POE::Wheel::SocketFactory->new(
                    BindAddress  => $bind,
                    BindPort     => $port,
                    ListenQueue  => $max_clients,
                    Reuse        => 'yes',
                    SuccessEvent => 'client_accept',
                    FailureEvent => 'accept_failure',
                );
            },
            client_accept     => \&_client_accept,
            client_input      => \&_client_input,
            disconnect        => \&_client_disconnect,
            verify_client     => \&_verify_client,
            close_delayed     => \&_close_delayed,
            accept_failure    => \&_client_error
        }
    );

    $log->debug("* Server started at $bind:$port *");

}

sub _client_error {
    #my ($operation, $errnum, $errstr, $wheel_id) = @_[ARG0..ARG3];
    my ( $kernel, $heap, $wheel_id ) = @_[ KERNEL, HEAP, ARG0 ];
    $log->debug("[ $wheel_id ] At _client_error ($heap)");
    delete $heap->{server}->{$wheel_id}->{wheel};
}

sub _close_delayed {
    my ( $kernel, $heap, $wheel_id ) = @_[ KERNEL, HEAP, ARG0 ];

    $log->debug("[ $wheel_id ] At _close_delayed");
    delete $heap->{server}->{$wheel_id}->{wheel};
    delete $heap->{server}->{$wheel_id}->{socket};
    delete $client_namespace->{$wheel_id};

    $log->debug("[ " . $wheel_id . " ] Client disconnected.");
}

sub _client_disconnect {
    my ( $heap, $kernel, $wheel_id ) = @_[ HEAP, KERNEL, ARG0 ];

    $log->debug("[ $wheel_id ] At _client_disconnect");
    $log->info("[ " . $wheel_id . " ] Client disconnecting (delayed).");

    $kernel->delay( close_delayed => 1, $wheel_id )
      unless ( $heap->{server}->{$wheel_id}->{disconnecting}++ );
}

sub _client_input {
    my ( $heap, $kernel, $input, $wheel_id ) = @_[ HEAP, KERNEL, ARG0, ARG1 ];

    chomp($input);
    $log->debug('At _client_input');

    # Assign boolean if can write to socket
    my $canwrite = exists $heap->{server}->{$wheel_id}->{wheel}
      && ( ref( $heap->{server}->{$wheel_id}->{wheel} ) eq "POE::Wheel::ReadWrite" );

    # Check if client has already been verified and registered
    if ( not exists $client_namespace->{$wheel_id} ){
        # Verify client
        $kernel->yield( "verify_client", $input, $wheel_id, $canwrite );
    }
    else {
        $input = _sanitize_input($wheel_id, $input);
        $heap->{server}->{$wheel_id}->{wheel}->put( "[" . $wheel_id . "] Your input: $input\n" )
            if $canwrite;
    }

}

sub _client_accept {
    my ( $heap, $kernel, $socket, $wheel_id ) = @_[ HEAP, KERNEL, ARG0, ARG1 ];

    $log->debug('At _client_accept');

    unless ( $disable_ssl ){
        $log->info('[ ' . $wheel_id .' ] Starting up SSLify on socket');
        eval {
            $socket = Server_SSLify_NonBlock(
                SSLify_GetCTX(),
                $socket,
                {
                    clientcertrequest    => $ENV{GRANITE_CLIENT_CERTIFICATE},
                    noblockbadclientcert => $ENV{GRANITE_VERIFY_CLIENT},
                    getserial            => $granite_crl ? 1 : 0,
                    debug                => $debug
                }
            );
        };
        if ($@) {
            $log->error('_client_accept: SSL Failed:' . $@);
            delete $heap->{server}->{$wheel_id}->{wheel};
            return undef;
        }
    }

    my $io_wheel = POE::Wheel::ReadWrite->new(
        Handle     => $socket,
        Driver     => POE::Driver::SysRW->new,
        Filter     => POE::Filter::Stream->new,
        InputEvent => 'client_input'
    );

    my ( $remote_ip, $remote_port ) = _get_remote_address($socket);
 
    $log->info( '[ ' . $io_wheel->ID() . ' ] Remote Addr: ' . $remote_ip . ':' . $remote_port );
    
    $heap->{server}->{ $io_wheel->ID() }->{remote_ip} = $remote_ip;
    $heap->{server}->{ $io_wheel->ID() }->{remote_port} = $remote_port;
    $heap->{server}->{ $io_wheel->ID() }->{wheel}  = $io_wheel;
    $heap->{server}->{ $io_wheel->ID() }->{socket} = $socket;
}

sub _verify_client {
    my ( $heap, $kernel, $input, $wheel_id, $canwrite ) 
        = @_[ HEAP, KERNEL, ARG0, ARG1, ARG2 ];

    $log->debug('At _verify_client');
    my $socket = $heap->{server}->{$wheel_id}->{socket};
    my $remote_ip = $heap->{server}->{$wheel_id}->{remote_ip};
    my $remote_port = $heap->{server}->{$wheel_id}->{remote_port};

    # Check SSL if enabled
    unless ( $disable_ssl ) {

        $log->info('Verifying Server_SSLify_NonBlock_SSLDone on socket');
        unless ( Server_SSLify_NonBlock_SSLDone($socket) ) {
            $log->error('[ ' . $wheel_id . ' ] SSL Handshake failed');
            $kernel->yield( "disconnect" => $wheel_id );
            return;
        }

        my $ctx = SSLify_GetCTX( $socket ); 

        $log->debug('[ '. $wheel_id  .' ] Have global CTX: ' . SSLify_GetCTX() );
        $log->debug('[ '. $wheel_id  .' ] Got client CTX: ' . $ctx);
        $log->debug('[ '. $wheel_id  .' ] Got client cipher: ' . SSLify_GetCipher($socket) );

        # Check certificate provided by client
        if ( $ENV{GRANITE_CLIENT_CERTIFICATE} and !( Server_SSLify_NonBlock_ClientCertificateExists($socket) ) ) {
            $heap->{server}->{$wheel_id}->{wheel}->put( "[" . $wheel_id . "] NoClientCertExists\n" )
                if $canwrite;
            $log->error("[ " . $wheel_id . " ] NoClientCertExists");
            $kernel->yield( "disconnect" => $wheel_id );
            return;
        }
        # check certificate valid
        elsif ( $ENV{GRANITE_VERIFY_CLIENT} and !( Server_SSLify_NonBlock_ClientCertIsValid($socket) ) ) {
            $heap->{server}->{$wheel_id}->{wheel}->put( "[" . $wheel_id . "] ClientCertInvalid\n" )
                if $canwrite;
            $log->error("[ " . $wheel_id . " ] ClientCertInvalid");
            $kernel->yield( "disconnect" => $wheel_id );
            return;
        }
        # check certificate against CRL
        elsif ( $granite_crl and !( Server_SSLify_NonBlock_ClientCertVerifyAgainstCRL( $socket, $granite_cacrt ) ) ) {
            $heap->{server}->{$wheel_id}->{wheel}->put( "[" . $wheel_id . "] CRL Error\n" )
                if $canwrite;
            $log->error("[ " . $wheel_id . " ] CRL Error");
            $kernel->yield( "disconnect" => $wheel_id );
            return;
        }
    }

    $log->info('[ ' . $wheel_id . " ] Verifying password\n");
    if ( $input ne 'system'  ){
        $heap->{server}->{$wheel_id}->{wheel}->put( "[" . $wheel_id . "] Password authentication failure.\n" )
            if $canwrite;
            $kernel->yield( "disconnect" => $wheel_id );
            return;
    }

    # Register client
    $client_namespace->{$wheel_id} = {
        remote_ip => $remote_ip,
        remote_ip => $remote_port,
        registered => time(),
    };

    $log->info("[ " . $wheel_id . " ] Client authenticated");

    $heap->{server}->{$wheel_id}->{wheel}->put( "[" . $wheel_id . "] Authenticated!\n" )
        if $canwrite;

}

sub _sanitize_input {
    my ($wheel_id, $input) = @_;

    return $input if $input eq '';

    unless ($input =~ /^[a-zA-Z0-9_\-\.,\!\%\$\^\&\(\)\[\]\{\}\+\=\@\?]+$/){
        $log->warn( '[ ' . $wheel_id . ' ] Client input contains invalid characters, erasing content.' );
        $input = '';
    }
    else {
        $log->debug("[ $wheel_id ] Got client input: '" . $input . "'");
    }
    return $input;
}

sub _get_remote_address {
    my $socket = shift;
    my $remote_ip;
    my ($remote_port, $addr) = ( 'unknown', 'n/a' );
    eval { 
        ($remote_port, $addr) =
            unpack_sockaddr_in( getpeername ( $disable_ssl ? $socket : SSLify_GetSocket( $socket ) ) );
    };
    if ( $@ ) {
        $log->logcluck("Error getting remote peer name: $@");
    }
    else {
        eval { $remote_ip = inet_ntoa( $addr ) };
        $log->logcluck("Error getting ip address: $@") if $@;
    }
    return wantarray ? ( $remote_ip, $remote_port ) : "$remote_ip:$remote_port";
}


1;
