package Granite::Component::Server;
use strict;
use warnings;
use Socket;
use Cwd 'getcwd';
use Scalar::Util 'looks_like_number';
use Sys::Hostname;
use Data::Dumper;
use Moose;
use namespace::autoclean;
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
        $client_namespace $host_name $disable_ssl $unix_socket );

before 'run' => sub {
    $port            = $Granite::cfg->{server}->{port}              || 21212;
    $bind            = $Granite::cfg->{server}->{bind}              || '127.0.0.1';
    $max_clients     = $Granite::cfg->{server}->{max_clients}       || 10;
    $host_name       = $Granite::cfg->{server}->{hostname}          || hostname();
    $granite_crt     = $Granite::cfg->{server}->{cert}   ? getcwd . '/' . $Granite::cfg->{server}->{cert}   : undef;
    $granite_key     = $Granite::cfg->{server}->{key}    ? getcwd . '/' . $Granite::cfg->{server}->{key}    : undef;
    $granite_cacrt   = $Granite::cfg->{server}->{cacert} ? getcwd . '/' . $Granite::cfg->{server}->{cacert} : undef;
    $granite_crl     = $Granite::cfg->{server}->{crl}    ? getcwd . '/' . $Granite::cfg->{server}->{crl}    : undef;
    $unix_socket     = $Granite::cfg->{server}->{unix_socket} || undef;

    $granite_cipher  = 'DHE-RSA-AES256-GCM-SHA384:AES256-SHA';
    $ENV{GRANITE_CLIENT_CERTIFICATE} = 1 if $ENV{GRANITE_VERIFY_CLIENT};
    $Granite::cfg->{server}->{client_certificate} ||= $Granite::cfg->{server}->{verify_client}; 
};

sub run {

#    POE::Kernel->stop();
 #   print STDERR "Worker forked\n";

    ($log, $debug) = @_[ ARG0, ARG1 ];
    $log->debug('[ ' . $_[SESSION]->ID() . ' ] Initializing Granite::Component::Server')
        if $debug;

    $disable_ssl = $ENV{GRANITE_DISABLE_SSL} || $Granite::cfg->{server}->{disable_ssl};
    if ( $unix_socket
        && ( $Granite::cfg->{server}->{port} || $Granite::cfg->{server}->{bind} )
    ){
        $log->warn('[ ' . $_[SESSION]->ID() . ' ] Warning: Both unix socket and tcp options are configured.'
                  . ' Unix socket takes precedence.');
        $bind = undef;
        $port = undef;
    }
    

    $log->logcroak("Missing certificate file definition")   if !$disable_ssl && !$granite_crt;
    $log->logcroak("Missing key file definition")           if !$disable_ssl && !$granite_key;

    unless ( $disable_ssl or $unix_socket ){
        $log->debug('[ ' . $_[SESSION]->ID() . ' ] Setting SSLify options') if $debug;
        _sslify_options();
    }

    if ( $unix_socket && -e $unix_socket ){
        $log->logdie("Access denied on '$unix_socket'. Check permissions.")
        	unless -w $unix_socket;
        unlink $unix_socket or $log->logdie("Cannot unlink old socket '$unix_socket': $!");
    }

    my $session = POE::Session->create(
        inline_states => {
            _start => sub {
                my ( $heap, $kernel ) = @_[ HEAP, KERNEL ];
                $_[KERNEL]->alias_set('server');
                $heap->{server_wheel} = POE::Wheel::SocketFactory->new(
                    SocketDomain => $unix_socket ? PF_UNIX : AF_INET,
                    BindAddress  => $unix_socket || $bind,
                    BindPort     => ( $unix_socket ? undef : $port ),
                    ListenQueue  => $max_clients,
                    Reuse        => 'yes',
                    SuccessEvent => 'client_accept',
                    FailureEvent => 'server_error',
                );
            },
            client_accept     => \&_client_accept,
            client_input      => \&_client_input,
            disconnect        => \&_client_disconnect,
            verify_client     => \&_verify_client,
            close_delayed     => \&_close_delayed,
            server_error      => \&_server_error,
            client_error      => \&_client_error,
            _default          => \&Granite::Engine::handle_default,
            _stop             => \&server_error,
        }
    );

    if ( $unix_socket ){ 
        $log->info('[ ' . $_[SESSION]->ID() .  " ] Server started at socket '$unix_socket' with session ID: " . $session->ID() );
    }
    else {
        $log->info('[ ' . $_[SESSION]->ID() .  " ] Server started at $bind:$port with session ID: " . $session->ID() );
    }

}

sub server_error {
    my ($operation, $errnum, $errstr ) = @_[ARG0..ARG2];
    delete $_[HEAP]->{server};
    $client_namespace = {};
    $log->logdie('[ ' . $_[SESSION]->ID() 
                . " ] Server error from session ID "
                . $_[SENDER]->ID() . ( $errnum ? ": ($errnum) $errstr" : '' ) )
        if looks_like_number($_[SENDER]->ID());
}

sub _client_error {
    my ( $kernel, $heap, $operation ) = @_[ KERNEL, HEAP, ARG0 ];
    my ($errnum, $errstr, $wheel_id) = @_[ARG1..ARG3];
    if ( $errnum > 0 ){
        $log->warn('[ ' . $_[SESSION]->ID() . " ]->($wheel_id) client_error: ($errnum) $errstr");
    }
    else {
        $log->info('[ ' . $_[SESSION]->ID() . " ]->($wheel_id) Client disconnected");
    }
    delete $heap->{server}->{$wheel_id}->{wheel};
    delete $_[HEAP]{wheels}{$wheel_id};
}

sub _close_delayed {
    my ( $kernel, $heap, $wheel_id ) = @_[ KERNEL, HEAP, ARG0 ];

    $log->debug('[ ' . $_[SESSION]->ID() . " ]->($wheel_id) At _close_delayed") if $debug;
    delete $heap->{server}->{$wheel_id}->{wheel};
    delete $heap->{server}->{$wheel_id}->{socket};
    delete $client_namespace->{$wheel_id};

    $log->info('[ ' . $_[SESSION]->ID() . ' ]->(' . $wheel_id . ") Client disconnected.");
}

sub _client_disconnect {
    my ( $heap, $kernel, $wheel_id ) = @_[ HEAP, KERNEL, ARG0 ];

    $log->debug('[ ' . $_[SESSION]->ID() . " ]->($wheel_id) At _client_disconnect") if $debug;
    $log->info('[ ' . $_[SESSION]->ID() . ' ]->(' . $wheel_id . ") Client disconnecting (delayed).");

    $kernel->delay( close_delayed => 1, $wheel_id )
      unless ( $heap->{server}->{$wheel_id}->{disconnecting}++ );
}

sub _client_input {
    my ( $heap, $kernel, $input, $wheel_id ) = @_[ HEAP, KERNEL, ARG0, ARG1 ];

    chomp($input);
    $log->debug('[ ' . $_[SESSION]->ID() . " ]->($wheel_id) At _client_input")
        if $debug;

    # Assign boolean if can write to socket
    my $canwrite = exists $heap->{server}->{$wheel_id}->{wheel}
      && ( ref( $heap->{server}->{$wheel_id}->{wheel} ) eq 'POE::Wheel::ReadWrite' );

    # Check if client has already been verified and registered
    if ( not exists $client_namespace->{$wheel_id} ){
        # Verify client
        $kernel->yield( "verify_client", $input, $wheel_id, $canwrite );
    }
    else {
        $input = _sanitize_input($_[SESSION]->ID(), $wheel_id, $input);
        $heap->{server}->{$wheel_id}->{wheel}->put( "[" . $wheel_id . "] Your input: $input\n" )
            if $canwrite;
    }
}

sub _client_accept {
    my ( $heap, $kernel, $socket, $wheel_id ) = @_[ HEAP, KERNEL, ARG0, ARG1 ];

    $log->info('[ ' . $_[SESSION]->ID() .' ] New connection received');

    unless ( $disable_ssl or $unix_socket ){
        $log->info('[ ' . $_[SESSION]->ID() .' ] Starting up SSLify on socket');
        eval {
            $socket = Server_SSLify_NonBlock(
                SSLify_GetCTX(),
                $socket,
                {
                    clientcertrequest    => $ENV{GRANITE_REQUEST_CLIENT_CERTIFICATE} || $Granite::cfg->{server}->{client_certificate},
                    noblockbadclientcert => $ENV{GRANITE_VERIFY_CLIENT} || $Granite::cfg->{server}->{verify_client},
                    getserial            => $granite_crl ? 1 : 0,
                    debug                => 0 #$debug
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
        InputEvent => 'client_input',
        ErrorEvent => 'client_error'
    );

    unless ( $unix_socket ) {
        my ( $remote_ip, $remote_port ) = _get_remote_address($socket, $_[SESSION]->ID(), $io_wheel->ID()); 
        $heap->{server}->{ $io_wheel->ID() }->{remote_ip} = $remote_ip;
        $heap->{server}->{ $io_wheel->ID() }->{remote_port} = $remote_port;
        $log->info( '[ ' . $_[SESSION]->ID() . ' ]->(' . $io_wheel->ID() . ') Remote Addr: ' . $remote_ip . ':' . $remote_port );    
    }

    $heap->{server}->{ $io_wheel->ID() }->{wheel}  = $io_wheel;
    $heap->{server}->{ $io_wheel->ID() }->{socket} = $socket;
}

sub _verify_client {
    my ( $heap, $kernel, $input, $wheel_id, $canwrite ) 
        = @_[ HEAP, KERNEL, ARG0, ARG1, ARG2 ];

    $log->debug('[ ' . $_[SESSION]->ID() . " ]->($wheel_id) At _verify_client") if $debug;
    my $socket = $heap->{server}->{$wheel_id}->{socket};
    my ( $remote_ip, $remote_port );
    
    # If not a socket, get remote ip+port
    # ===================================
    unless ( $unix_socket ){
        $remote_ip = $heap->{server}->{$wheel_id}->{remote_ip};
        $remote_port = $heap->{server}->{$wheel_id}->{remote_port};

        # Check SSL if enabled
        # =====================
        unless ( $disable_ssl ) {
            # Verify client ssl
            # =================
            unless ( _verify_client_ssl($kernel, $heap, $wheel_id, $socket, $canwrite, $_[SESSION]->ID() ) ){
                $kernel->yield( "disconnect" => $wheel_id );
                return;
            }
        }
    }

    $log->info('[ ' . $_[SESSION]->ID() . " ]->($wheel_id) Verifying password\n");

    # TODO: Add authentication module
    if ( $input ne 'system'  ){
        $heap->{server}->{$wheel_id}->{wheel}->put( "[" . $wheel_id . "] Password authentication failure.\n" )
            if $canwrite;
            $kernel->yield( "disconnect" => $wheel_id );
            return;
    }

    # Register client
    $client_namespace->{$wheel_id} = $unix_socket
        ? { registered => time() }
        : { remote_ip => $remote_ip,
            remote_ip => $remote_port,
            registered => time(),
          };

    $log->info('[ ' . $_[SESSION]->ID() . ' ]->(' . $wheel_id . ") Client authenticated");

    $heap->{server}->{$wheel_id}->{wheel}->put( "[" . $wheel_id . "] Authenticated!\n" )
        if $canwrite;

}

sub _sanitize_input {
    my ($sessionId, $wheel_id, $input) = @_;

    return $input if $input eq '';

    unless ($input =~ /^[a-zA-Z0-9_\-\.,\!\%\$\^\&\(\)\[\]\{\}\+\=\@\?]+$/){
        $log->warn( '[ '. $sessionId . ' ]->(' . $wheel_id . ') Client input contains invalid characters, erasing content.' );
        $input = '';
    }
    else {
        $log->info('[ '. $sessionId . ' ]->(' . $wheel_id . ") Got client input: '" . $input . "'");
    }
    return $input;
}

sub _get_remote_address {
    my ($socket, $sessionId, $wheel_id) = @_;

    my $remote_ip;
    my ($remote_port, $addr) = ( 'unknown', 'n/a' );
    eval { 
        ($remote_port, $addr) =
            unpack_sockaddr_in( getpeername ( $disable_ssl ? $socket : SSLify_GetSocket( $socket ) ) );
    };
    if ( $@ ) {
        $log->logcluck('[ '. $sessionId . ' ]->(' . $wheel_id . ") Error getting remote peer name: $@");
    }
    else {
        eval { $remote_ip = inet_ntoa( $addr ) };
        $log->logcluck('[ '. $sessionId . ' ]->(' . $wheel_id . ") Error getting ip address: $@") if $@;
    }
    return wantarray ? ( $remote_ip, $remote_port ) : "$remote_ip:$remote_port";
}

sub _verify_client_ssl {
    my ( $kernel, $heap, $wheel_id, $socket, $canwrite, $sessionId ) = @_;

    $log->info('[ '. $sessionId . ' ]->(' . $wheel_id . ') Verifying Server_SSLify_NonBlock_SSLDone on socket');

    my $test;
    eval { $test = Server_SSLify_NonBlock_SSLDone($socket); };
    if ( $@ or !$test ){
        $log->error('[ ' . $wheel_id . ' ] SSL Handshake failed ' . ( $@ ? $@ : '' ));
        return undef;
    }

    # Check certificate provided by client
    if ( $ENV{GRANITE_CLIENT_CERTIFICATE} ){
        my $test;
        eval { $test = Server_SSLify_NonBlock_ClientCertificateExists($socket); };
        if ( $@ or !$test ) {
            $heap->{server}->{$wheel_id}->{wheel}->put( "[" . $wheel_id . "] NoClientCertExists\n" )
                if $canwrite;
            $log->error('[ '. $sessionId . ' ]->(' . $wheel_id . ') NoClientCertExists');
            return undef;
        }
    }
    # check certificate valid
    if ( $ENV{GRANITE_VERIFY_CLIENT} ){
        my $test;
        eval { $test = Server_SSLify_NonBlock_ClientCertIsValid($socket); };
        if ( $@ or !$test ){
            $heap->{server}->{$wheel_id}->{wheel}->put( "[" . $wheel_id . "] ClientCertInvalid\n" )
                if $canwrite;
            $log->error( '[ '. $sessionId . ' ]->(' . $wheel_id . ') ClientCertInvalid ' . ($@ ? $@ : '') );
            return undef;
        }

    }
	# TODO: Patch Net::SSLeay or try dump certificate and verify via openssl class
    # check certificate against CRL
    #elsif ( $granite_crl and !( Server_SSLify_NonBlock_ClientCertVerifyAgainstCRL( $socket, $granite_crl ) ) ) {
    #    $heap->{server}->{$wheel_id}->{wheel}->put( "[" . $wheel_id . "] CRL Error\n" )
    #        if $canwrite;
    #    $log->error("[ " . $wheel_id . " ] CRL Error");
    #    $kernel->yield( "disconnect" => $wheel_id );
    #    return;
    #}
    #warn "XXXXXXX " . Server_SSLify_NonBlock_GetClientCertificateIDs($socket) . "\n";

    return 1;
}

sub _sslify_options {

    for ( $granite_key, $granite_crt ){
        $log->logcroak("Cannot find '$_'. Verify existance and permissions.") unless -f $_;
    }

    if ( $Granite::cfg->{server}->{client_certificate}
        && ( !$granite_cacrt or ! -f $granite_cacrt ) 
    ){
        $log->logcroak("Missing CA certificate. Verify existance and permissions.");
    }

    eval { SSLify_Options( $granite_key, $granite_crt ) };
    $log->logcroak( "Error setting SSLify_Options with '$granite_key' and '$granite_crt': "
                    . $@ . ' Check file permissions.' ) if ($@);

    eval { SSLify_Options_NonBlock_ClientCert( SSLify_GetCTX(), $granite_cacrt ); } if $granite_cacrt;
    $log->logcroak( 'Error setting SSLify_Options_NonBlock_ClientCert: ' . $@ ) if ($@);

}   

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;
