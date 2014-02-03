package Granite::Component::Server;
use strict;
use warnings;
use Socket;
use Cwd 'getcwd';
use File::Basename 'dirname';
use Data::Validate::IP qw(is_ipv4 is_ipv6);
use Scalar::Util 'looks_like_number';
use Sys::Hostname;
use Data::Dumper;
use POE
    qw( Wheel::SocketFactory Driver::SysRW Filter::Stream Wheel::ReadWrite );

use Moose::Util::TypeConstraints;
use Moose;
    with 'Granite::Component::Server::SSLify';
use namespace::autoclean;

use vars
    qw( $log $granite_key $granite_crt $debug $client_filters
        $granite_cacrt $granite_verify_client $granite_cipher
        $granite_crl $client_namespace $host_name $disable_ssl
        $unix_socket $self );

=head1 DESCRIPTION

Granite server component
features tcp, unix sockets
and socket SSL 

=head2 CONSTRAINTS

Enumeration and type constraints
via Moose::Util::TypeConstraints

=head3 subtype 'Port'

'Port' can be Int range 1025..65535

=cut

subtype 'Port',
    as 'Int',
    where { $_ > 1024 && $_ <= 65535 };


=head3 subtype 'BindAddress'

'BindAddress' can be IPv4 or IPv6

=cut

subtype 'BindAddress',
    as 'Str',
    where { is_ipv4($_) || is_ipv6($_) };


=head2 ATTRIBUTES

L<port>

L<bind>

L<unix_socket>

L<max_clients>

L<host_name>

=cut

has port        => ( is => 'rw', isa => 'Port',        clearer   => '_undef_port',        predicate => '_has_port', default => 21212 );
has bind        => ( is => 'rw', isa => 'BindAddress', clearer   => '_undef_bind',        predicate => '_has_bind', default => '127.0.0.1' );
has unix_socket => ( is => 'rw', isa => 'UnixSocket',  clearer   => '_undef_unix_socket', predicate => '_has_unix_socket', required => 0);
has max_clients => ( is => 'rw', isa => 'Int', default => 10 );
has host_name   => ( is => 'rw', isa => 'Str', default => hostname() );


=head2 METHODS

=head3 BUILD

Assign class parameters before 'run'

=cut

sub BUILD {

    $self = shift;

    $self->port            ( $Granite::cfg->{server}->{port} );
    $self->bind            ( $Granite::cfg->{server}->{bind} );
    $self->host_name       ( $Granite::cfg->{server}->{hostname}    );
    $self->max_clients     ( $Granite::cfg->{server}->{max_clients} );
    $self->unix_socket     ( $Granite::cfg->{server}->{unix_socket} )
        if $Granite::cfg->{server}->{unix_socket};

    $granite_crt     = $Granite::cfg->{server}->{cert}   ? getcwd . '/' . $Granite::cfg->{server}->{cert}   : undef;
    $granite_key     = $Granite::cfg->{server}->{key}    ? getcwd . '/' . $Granite::cfg->{server}->{key}    : undef;
    $granite_cacrt   = $Granite::cfg->{server}->{cacert} ? getcwd . '/' . $Granite::cfg->{server}->{cacert} : undef;
    $granite_crl     = $Granite::cfg->{server}->{crl}    ? getcwd . '/' . $Granite::cfg->{server}->{crl}    : undef;
    $granite_cipher  = $Granite::cfg->{server}->{cipher}            ||'DHE-RSA-AES256-GCM-SHA384:AES256-SHA';

    $ENV{GRANITE_CLIENT_CERTIFICATE}                = 1 if $ENV{GRANITE_VERIFY_CLIENT};
    $Granite::cfg->{server}->{client_certificate} ||= $Granite::cfg->{server}->{verify_client}; 

    return $self;
};


=head3 __PACKAGE__->run( $parent_sessionId )

Method 'run' will start the server session

=cut

sub run {

    ( $log, $debug ) = ( $Granite::log, $Granite::debug );
    $self = shift;
    my $sessionId  = shift;

    $log->debug('[ ' . $sessionId . ' ] Initializing Granite::Component::Server')
        if $debug;

    # Set the ssl disabled variable
    # =============================
    $disable_ssl = $ENV{GRANITE_DISABLE_SSL} || $Granite::cfg->{server}->{disable_ssl};

    # Display configuration warning
    # =============================
    if ( $self->_has_unix_socket
        && ( $Granite::cfg->{server}->{port} || $Granite::cfg->{server}->{bind} )
    ){
        $log->warn('[ ' . $sessionId . ' ] Warning: Both unix socket and tcp options are configured.'
                  . ' Unix socket takes precedence.');
        $self->undef_bind;
        $self->undef_port;
    }  

    $log->logcroak("Missing certificate file definition")   if !$disable_ssl && !$granite_crt;
    $log->logcroak("Missing key file definition")           if !$disable_ssl && !$granite_key;

    # Set global SSL options
    # ======================
    unless ( $disable_ssl or $self->_has_unix_socket ){
        $log->debug('[ ' . $sessionId . ' ] Setting SSLify options') if $debug;
        sslify_options( $granite_key, $granite_crt, $granite_cacrt );
    }

    # Check access to unix socket
    # ===========================
    if ( $self->_has_unix_socket && -e $unix_socket ){
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
                    SocketDomain => $self->_has_unix_socket ? PF_UNIX : AF_INET,
                    BindAddress  => $self->_has_unix_socket || $self->bind,
                    BindPort     => ( $self->_has_unix_socket ? undef : $self->port ),
                    ListenQueue  => $self->max_clients,
                    Reuse        => 'yes',
                    SuccessEvent => 'client_accept',
                    FailureEvent => 'server_error',
                ) or $log->logcroak('[ ' . $_[SESSION]-ID() .  " ] can't POE::Wheel::SocketFactory->new: $!" );

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
    ) or $log->logcroak('[ ' . $sessionId .  " ] can't POE::Session->create: $!" );

    if ( $self->_has_unix_socket ){ 
        $log->info('[ ' . $sessionId .  " ] Server started at socket '" . $self->unix_socket . "' with session ID: " . $session->ID() );
    }
    else {
        $log->info('[ ' . $sessionId .  ' ] Server started at ' . $self->bind . ':' . $self->port . ' with session ID: ' . $session->ID() );
    }

}



=head3 server_error

Handler for SocketFactory FailureEvent

=cut

sub server_error {
    my ($operation, $errnum, $errstr ) = @_[ARG0..ARG2];
    delete $_[HEAP]->{server};
    $client_namespace = {};
    $log->logdie('[ ' . $_[SESSION]->ID() 
                . " ] Server error from session ID "
                . $_[SENDER]->ID() . ( $errnum ? ": ($errnum) $errstr" : '' ) )
        if looks_like_number($_[SENDER]->ID());
}


=head3 _client_error

Handler for client errors

=cut

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


=head3 _close_delayed

Disconnect a client
call to this handler is typically 
delayed about 1 second

=cut

sub _close_delayed {
    my ( $kernel, $heap, $wheel_id ) = @_[ KERNEL, HEAP, ARG0 ];

    $log->debug('[ ' . $_[SESSION]->ID() . " ]->($wheel_id) At _close_delayed") if $debug;
    delete $heap->{server}->{$wheel_id}->{wheel};
    delete $heap->{server}->{$wheel_id}->{socket};
    delete $client_namespace->{$wheel_id};

    $log->info('[ ' . $_[SESSION]->ID() . ' ]->(' . $wheel_id . ") Client disconnected.");
}


=head3 _client_disconnect

Handler for client disconnect
Will delay termination in
one second and call _close_delayed

=cut

sub _client_disconnect {
    my ( $heap, $kernel, $wheel_id ) = @_[ HEAP, KERNEL, ARG0 ];

    $log->debug('[ ' . $_[SESSION]->ID() . " ]->($wheel_id) At _client_disconnect") if $debug;
    $log->info('[ ' . $_[SESSION]->ID() . ' ]->(' . $wheel_id . ") Client disconnecting (delayed).");

    $kernel->delay( close_delayed => 1, $wheel_id )
      unless ( $heap->{server}->{$wheel_id}->{disconnecting}++ );
}


=head3 _client_input

client input handler for all 
client input data.

If first input for a client:
we run client verification and register
the client if authentication is successful

=cut

sub _client_input {
    my ( $heap, $kernel, $input, $wheel_id ) = @_[ HEAP, KERNEL, ARG0, ARG1 ];

    chomp($input);
    $log->debug('[ ' . $_[SESSION]->ID() . " ]->($wheel_id) At _client_input")
        if $debug;

    # Assign boolean if can write to socket
    # =====================================
    my $canwrite = exists $heap->{server}->{$wheel_id}->{wheel}
      && ( ref( $heap->{server}->{$wheel_id}->{wheel} ) eq 'POE::Wheel::ReadWrite' );

    # Check if client has already
    # been verified and registered
    # ============================ 
    if ( not exists $client_namespace->{$wheel_id} ){
        # Verify client
        # =============
        $kernel->yield( "verify_client", $input, $wheel_id, $canwrite );
    }
    else {
        $input = _sanitize_input($_[SESSION]->ID(), $wheel_id, $input);
        $heap->{server}->{$wheel_id}->{wheel}->put( "[" . $wheel_id . "] Your input: $input\n" )
            if $canwrite;
    }
}


=head3 _client_accept

New socket connection established

=cut

sub _client_accept {
    my ( $heap, $kernel, $socket, $wheel_id ) = @_[ HEAP, KERNEL, ARG0, ARG1 ];

    $log->info('[ ' . $_[SESSION]->ID() .' ] New connection received');

    unless ( $disable_ssl or $self->_has_unix_socket ){
        unless ( $socket = sslify_socket( $socket, $granite_crl, $_[SESSION]->ID()) ){
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


=head3 _verify_client

Verify the client when connected

=cut

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
            unless ( verify_client_ssl($kernel, $heap, $wheel_id, $socket, $canwrite, $_[SESSION]->ID() ) ){
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
    # ===============
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


=head3 _sanitize_input

Do not accept input with invalid characters

=cut

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


=head3 _get_remote_address

Get the IP:Port of the client

=cut

sub _get_remote_address {
    my ($socket, $sessionId, $wheel_id) = @_;

    my $remote_ip;
    my ($remote_port, $addr) = ( 'unknown', 'n/a' );
    eval { 
        ($remote_port, $addr) =
            unpack_sockaddr_in( getpeername ( $disable_ssl ? $socket : sslify_getsocket ($socket) ) );
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

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

=head1 AUTHOR

Nuriel Shem-Tov

=cut

1;
