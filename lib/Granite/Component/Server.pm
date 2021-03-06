package Granite::Component::Server;
use Moose;
use Moose::Util::TypeConstraints;
use Socket;
use Cwd 'getcwd';
use File::Basename 'dirname';
use Data::Validate::IP qw(is_ipv4 is_ipv6);
use Scalar::Util 'looks_like_number';
use Sys::Hostname;
use Data::Dumper::Concise;
use POE qw/
    Wheel::SocketFactory
    Driver::SysRW
    Filter::Stream
    Wheel::ReadWrite
/;

use namespace::autoclean;


use vars
    qw( $log $granite_key $granite_crt $debug $client_filters
        $granite_cacrt $granite_verify_client $granite_cipher
        $granite_crl $client_namespace $host_name $disable_ssl
        $unix_socket $self );


=head1 DESCRIPTION

  Granite::Component::Server

  features a non-blocking ssl server,

  unix socket or plain tcp server

=head1 SYNOPSIS

  Granite::Component::Server->new()->run( $_[SESSION]->ID() )

  SessionId is the Id of the caller

  See configuration file for more details

=head2 TRAITS

  Load roles belonging to this package

=cut

with 'MooseX::Traits';

has '+_trait_namespace' => (
    default => sub {
        my ( $P, $SP ) = __PACKAGE__ =~ /^(\w+)::(.*)$/;
        return $P . '::TraitFor::' . $SP;
    }
);

=head2 CONSTRAINTS

  Enumeration and type constraints

  via Moose::Util::TypeConstraints

=head4 subtype 'Port'

  B<Port> can be Int range 1025..65535

=cut

subtype 'Port',
    as 'Int',
    where { $_ > 1024 && $_ <= 65535 };


=head4 subtype 'BindAddress'

  B<BindAddress> can be IPv4 or IPv6

=cut

subtype 'BindAddress',
    as 'Str',
    where { is_ipv4($_) || is_ipv6($_) };


=head2 ATTRIBUTES

=over

=item * L<roles>
=cut

has roles => (
    is => 'ro',
    isa => 'Object',
    writer => '_set_roles',
    predicate => '_has_roles',    
);

=item * L<port> 
=cut

has port => (
    is          => 'rw',
    isa         => 'Port',       
    clearer     => '_undef_port',
    predicate   => '_has_port',
    default     => 21212
);

=item * L<bind>
=cut

has bind        => (
    is => 'rw',
    isa => 'BindAddress',
    clearer   => '_undef_bind',
    predicate => '_has_bind',
    default => '127.0.0.1'
);

=item * L<unix_socket>
=cut

has unix_socket => (
    is => 'rw',
    isa => 'Str',
    clearer   => '_undef_unix_socket',
    predicate => '_has_unix_socket',
    required => 0
);

=item * L<max_clients>
=cut

has max_clients => (
    is => 'rw',
    isa => 'Int',
    default => 10,
);

=item * L<host_name>
=cut

has host_name   => (
    is => 'rw',
    isa => 'Str',
    default => hostname() 
);

=item * L<mysession>
=cut

has mysession => (
    is => 'ro',
    isa => 'Object',
    writer => '_set_mysession',
    clearer => '_unset_mysession',
    predicate => '_has_mysession',
    lazy => 1,
    default => sub {{}},
);

=back

=head2 METHODS

=head4 B<BUILD>

  Assign class parameters before 'run'

=cut

sub BUILD {

    $self = shift;

    $self->port            ( Granite->cfg->{server}->{port} );
    $self->bind            ( Granite->cfg->{server}->{bind} );
    $self->host_name       ( Granite->cfg->{server}->{hostname}    );
    $self->max_clients     ( Granite->cfg->{server}->{max_clients} );
    $self->unix_socket     ( Granite->cfg->{server}->{unix_socket} )
        if Granite->cfg->{server}->{unix_socket};

    $granite_crt     = Granite->cfg->{server}->{cert} ?
        getcwd.'/'.Granite->cfg->{server}->{cert} : undef;
    $granite_key     = Granite->cfg->{server}->{key} ?
        getcwd.'/'.Granite->cfg->{server}->{key} : undef;
    $granite_cacrt   = Granite->cfg->{server}->{cacert} ?
        getcwd.'/'.Granite->cfg->{server}->{cacert} : undef;
    $granite_crl     = Granite->cfg->{server}->{crl} ?
        getcwd.'/'.Granite->cfg->{server}->{crl} : undef;
    $granite_cipher  = Granite->cfg->{server}->{cipher} 
        || 'DHE-RSA-AES256-GCM-SHA384:AES256-SHA';

    $ENV{GRANITE_CLIENT_CERTIFICATE}
        = 1 if $ENV{GRANITE_VERIFY_CLIENT};

    Granite->cfg->{server}->{client_certificate}
        ||= ( Granite->cfg->{server}->{verify_client} ? 'yes' : 'no' ); 

    return $self;
};


=head4 B<run( $parent_sessionId )>

  Method 'run' will start the server session

=cut

sub run {
    ( $log, $debug ) = ( Granite->log, Granite->debug );
    $self = shift;
    my $sessionId  = shift;

    $self->_set_roles (
        $self->new_with_traits(
            traits         => [ qw( SSLify ) ],
        )
    ) unless $self->_has_roles;

    $log->debug('[ ' . $sessionId . ' ] Initializing Granite::Component::Server')
        if $debug;

    # Set the ssl disabled variable
    # =============================
    $disable_ssl = 1 if $ENV{GRANITE_DISABLE_SSL} || Granite->cfg->{server}->{disable_ssl} =~ /yes/i;

    # Display configuration warning
    # =============================
    if ( $self->_has_unix_socket ){
        if ( Granite->cfg->{server}->{port} || Granite->cfg->{server}->{bind} ) {
            $log->warn('[ ' . $sessionId . ' ] Warning: Both unix socket and tcp options are configured.'
                      . ' Unix socket takes precedence.');
            $self->_undef_bind;
            $self->_undef_port;
        }

        if ( -e $self->unix_socket ){
            unlink $self->unix_socket
                or $log->logcroak("Cannot reuse old socket '".$self->unix_socket."': $!");
        }
    }  

    # Set global SSL options
    # ======================
    unless ( $disable_ssl or $self->_has_unix_socket ){
        $log->logcroak("Missing certificate file definition") unless $granite_crt;
        $log->logcroak("Missing key file definition")         unless $granite_key;

        $log->debug('[ ' . $sessionId . ' ] Setting SSLify options') if $debug;
        $self->roles->sslify_options( $granite_key, $granite_crt, $granite_cacrt );
    }

    # Check access to unix socket
    # ===========================
    if ( $self->_has_unix_socket && -e $self->unix_socket ){

        $log->logdie("Access denied on '"
                    . $self->unix_socket . "'. Check permissions."
        ) unless -w $self->unix_socket;
    }

    my $session = POE::Session->create(
        inline_states => {
            _start => sub {
                my ( $heap, $kernel ) = @_[ HEAP, KERNEL ];
                $_[KERNEL]->alias_set('server');
                $heap->{server_wheel} = POE::Wheel::SocketFactory->new(
                    SocketDomain => $self->_has_unix_socket ? PF_UNIX : AF_INET,
                    BindAddress  => $self->_has_unix_socket ? $self->unix_socket : $self->bind,
                    BindPort     => ( $self->_has_unix_socket ? undef : $self->port ),
                    ListenQueue  => $self->max_clients,
                    Reuse        => 'yes',
                    SuccessEvent => 'client_accept',
                    FailureEvent => 'server_session_error',
                ) or $log->logcroak('[ ' . $_[SESSION]-ID()
                                    . " ] can't POE::Wheel::SocketFactory->new: $!" );

                $kernel->sig('TERM' => 'server_shutdown');
            },
            client_accept     => \&_client_accept,
            client_input      => \&_client_input,
            reply_client      => \&_client_reply,
            disconnect        => \&_client_disconnect,
            verify_client     => \&_verify_client,
            close_delayed     => \&_close_delayed,
            server_error      => \&server_error,
            server_shutdown   => \&_terminate_server,
            client_error      => \&_client_error,
            # TODO: Create local default handler, otherwise we kill the engine
            _default          => \&Granite::Engine::handle_default,
            _stop             => \&server_error,
        },
        options => { trace => $Granite::trace, debug => $debug },
    ) or $log->logcroak('[ ' . $sessionId .  " ] can't POE::Session->create: $!" );

    if ( $self->_has_unix_socket ){ 
        $log->info('[ ' . $sessionId .  " ] Server started at socket '"
                    . $self->unix_socket . "' with session ID: " . $session->ID() );
    }
    else {
        $log->info('[ ' . $sessionId .  ' ] Server started at '
                    . $self->bind . ':' . $self->port
                    . ' with session ID: ' . $session->ID() );
    }

    $self->_set_mysession($session);
    return $self;
}




=head4 B<server_error>

  Handler for server's parent session error event

=cut

sub server_error {
    my ($operation, $errnum, $errstr ) = @_[ARG0..ARG2];

    $log->error('[ ' . $_[SESSION]->ID() 
                . " ] Server error from session ID "
                . $_[SENDER]->ID() . ( $errnum && $errstr ? ": ($errnum) $errstr" : '' ) )
        if looks_like_number($_[SENDER]->ID());
}


=head4 B<server_session_error>

  Handler for SocketFactory FailureEvent

=cut    

sub server_session_error {
    my ($operation, $errnum, $errstr ) = @_[ARG0..ARG2];
    delete $_[HEAP]->{server};
    $client_namespace = {};
    $log->logdie('[ ' . $_[SESSION]->ID() 
                . " ] SocketFactory FailureEvent from session ID "
                . $_[SENDER]->ID() . ( $errnum && $errstr ? ": ($errnum) $errstr" : '' ) )
        if looks_like_number($_[SENDER]->ID());
}


=head4 B<_terminate_server>

  Shut down the server

=cut

sub _terminate_server {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    $log->warn('Server shutdown');
    delete $_[HEAP]->{server};
    $client_namespace = {};
    if ( $self->_has_unix_socket and -e $self->unix_socket ){
        unlink $self->unix_socket
            or $log->warn("Cannot remove socket '".$self->unix_socket."': $!");
    }
}


=head4 B<_client_error>

  Handler for client errors

=cut

sub _client_error {
    my ( $kernel, $heap, $operation ) = @_[ KERNEL, HEAP, ARG0 ];
    my ($errnum, $errstr, $wheel_id) = @_[ARG1..ARG3];
    if ( $errnum > 0 ){
        $log->warn('[ ' . $_[SESSION]->ID()
                    . " ]->($wheel_id) client_error: ($errnum) $errstr");
    }
    else {
        $log->info('[ ' . $_[SESSION]->ID()
                    . " ]->($wheel_id) Client disconnected");
    }
    delete $heap->{server}->{$wheel_id}->{wheel};
    delete $_[HEAP]{wheels}{$wheel_id};
}


=head4 B<_close_delayed>

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


=head4 B<_client_disconnect>

  Handler for client disconnect
  Will delay termination in
  one second and call _close_delayed

=cut

sub _client_disconnect {
    my ( $heap, $kernel, $args ) = @_[ HEAP, KERNEL, ARG0 ];

    my $wheel_id = ref $args eq 'ARRAY' ? shift @{$args} : $args;

    $log->debug('[ ' . $_[SESSION]->ID() . " ]->($wheel_id) At _client_disconnect" )
        if $debug;

    $log->info('[ ' . $_[SESSION]->ID() . ' ]->(' . $wheel_id . ") Client disconnecting (delayed).");

    $kernel->delay( close_delayed => 0.2, $wheel_id )
      unless ( $heap->{server}->{$wheel_id}->{disconnecting}++ );
}


=head4 B<_client_input>

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
    my $canwrite = _canwrite($heap, $wheel_id);

    # Check if client has already
    # been verified and registered
    # ============================ 
    if ( not exists $client_namespace->{$wheel_id} ){
        $kernel->yield( "verify_client", $input, $wheel_id, $canwrite );
    }
    else {
        $input = _sanitize_input($_[SESSION]->ID(), $wheel_id, $input);

        # For tests only we return a reply here
        # =====================================
        if ( $canwrite and $input eq 'test' ){
            $heap->{server}->{$wheel_id}->{wheel}->put(
                "[" . $wheel_id . "] Test OK for wheel ID $wheel_id\n"
            );
        }
        # For other input we send to the controller
        # =========================================
        else {
	        $log->debug('[ ' . $_[SESSION]->ID() . " ] Sanitized input and left with: '$input'" );            
	        my $engine_session = $_[KERNEL]->alias_resolve('engine');
	        $_[KERNEL]->post( $engine_session , 'client_commands', "$input", $wheel_id )
                unless $input eq '';
        }
    }
}


=head4 B<_client_reply>

  Reply to client

=cut

sub _client_reply {
    my ( $heap, $kernel, $reply, $wheel_id, $postback ) = @_[ HEAP, KERNEL, ARG0, ARG1, ARG2 ];

    $log->debug('[ ' . $_[SESSION]->ID() . " ]->($wheel_id) At _client_reply")
        if $debug;

    my $canwrite = _canwrite($heap, $wheel_id);
    my $output = '[' . $wheel_id . '] ';

    if ( $reply ){
        $output .= ref $reply ? Dumper $reply : $reply;
        if ( ref $reply eq 'ARRAY' ){
            $output .= "\nTotal: " . ( scalar @{$reply} );
        }
        elsif ( ref $reply eq 'HASH' ){
            $output .= "\nTotal: " . ( scalar keys %{$reply} );
        }
    }

    $heap->{server}->{$wheel_id}->{wheel}->put( $output . "\n" )
        if $canwrite;

    if ( $postback && ref $postback eq 'POE::Session::AnonEvent' ){
        $postback->();
    }
}

=head4 B<_client_accept>

  New socket connection established

=cut

sub _client_accept {
    my ( $heap, $kernel, $socket, $wheel_id ) = @_[ HEAP, KERNEL, ARG0, ARG1 ];

    $log->info('[ ' . $_[SESSION]->ID() .' ] New connection received');

    # SSLify the new socket if ssl enabled
    # ====================================
    unless ( $disable_ssl or $self->_has_unix_socket ){
        unless ( $socket = $self->roles->sslify_socket( $socket, $granite_crl, $_[SESSION]->ID()) ){
            delete $heap->{server}->{$wheel_id}->{wheel};
            return undef;
        }
    }

    # Create a new RW wheel for this socket
    # =====================================
    my $io_wheel = POE::Wheel::ReadWrite->new(
        Handle     => $socket,
        Driver     => POE::Driver::SysRW->new,
        Filter     => POE::Filter::Stream->new,
        InputEvent => 'client_input',
        ErrorEvent => 'client_error'
    );

    # If TCP, save remote address details
    # ===================================
    unless ( $self->_has_unix_socket ) {
         my ( $remote_ip, $remote_port ) = _get_remote_address($socket, $_[SESSION]->ID(), $io_wheel->ID());
        if ( $remote_ip and $remote_port ){ 

	        $heap->{server}->{ $io_wheel->ID() } = {
	            remote_ip => $remote_ip,
	            remote_port => $remote_port
	        };
	
	        $log->info( '[ ' . $_[SESSION]->ID() . ' ]->(' . $io_wheel->ID()
	                    . ') Remote Addr: ' . $remote_ip . ':' . $remote_port );    
    
        }
        else {
        	$log->error('[ ' . $_[SESSION]->ID() . ' ]->(' . $io_wheel->ID()
                        . ') Failed to get remote address:port');
        }
    }

    # Store the wheel ID and the
    # socket in the server heap
    # ==========================
    $heap->{server}->{ $io_wheel->ID() }->{wheel}  = $io_wheel;
    $heap->{server}->{ $io_wheel->ID() }->{socket} = $socket;
}


=head4 B<_verify_client>

  Verify the client when connected

=cut

sub _verify_client {
    my ( $heap, $kernel, $input, $wheel_id, $canwrite ) 
        = @_[ HEAP, KERNEL, ARG0, ARG1, ARG2 ];

    $log->debug('[ ' . $_[SESSION]->ID() . " ]->($wheel_id) At _verify_client")
        if $debug;

    my $socket = $heap->{server}->{$wheel_id}->{socket};
    my ( $remote_ip, $remote_port );
    
    # If not a socket, get remote ip+port
    # ===================================
    unless ( $self->_has_unix_socket ){
        $remote_ip = $heap->{server}->{$wheel_id}->{remote_ip};
        $remote_port = $heap->{server}->{$wheel_id}->{remote_port};

        # Check SSL if enabled
        # =====================
        unless ( $disable_ssl ) {
            # Verify client ssl
            # =================
            unless (
                $self->roles->verify_client_ssl(
                    $kernel, $heap, $wheel_id, $socket, $canwrite, $_[SESSION]->ID()
                )
            ){
                $kernel->yield( "disconnect" => $wheel_id );
                return;
            }
        }
    }

    $log->info('[ ' . $_[SESSION]->ID()
            . " ]->($wheel_id) Verifying password\n");
    $input =~ s/\n$|\r//g;
    if ( $input ne Granite->cfg->{main}->{auth_token} ){
        $heap->{server}->{$wheel_id}->{wheel}->put(
            "[" . $wheel_id . "] Password authentication failure.\n"
        ) if $canwrite;
        $log->warn( '[ ' . $wheel_id . ' ] Client authentication failure.');
        $kernel->yield( "disconnect" => $wheel_id );
        return;
    }

    # Register client
    # ===============
    $client_namespace->{$wheel_id} = $self->_has_unix_socket
        ? { registered => time() }
        : { remote_ip => $remote_ip,
            remote_ip => $remote_port,
            registered => time(),
          };

    $log->info('[ ' . $_[SESSION]->ID() . ' ]->('
                . $wheel_id . ") Client authenticated");

    $heap->{server}->{$wheel_id}->{wheel}->put(
        "[". $wheel_id . "] Authenticated!\n"
    ) if $canwrite;

}


=head4 B<_sanitize_input>

  Do not accept input with invalid characters

=cut

sub _sanitize_input {
    my ($sessionId, $wheel_id, $input) = @_;

    # Remove new line
    $input =~ s/\n$|\r//g;
    # Remove leading/trailing spaces
    $input =~ s/^\s+|\s+$//g ; 
    return '' if $input eq '';

    unless ($input =~ /^[a-z0-9_\-\.,\!\%\$\^\&\(\)\[\]\{\}\+\=\@\?\ ]+$/i){
        $log->warn( '[ '. $sessionId . ' ]->(' . $wheel_id
                . ') Client input contains invalid characters, erasing content.' );
        return '';
    }
    else {
        $log->info('[ '. $sessionId . ' ]->(' . $wheel_id
                    . ") Got client input: '" . $input . "'");
    }
    return $input;
}

=head4 B<_canwrite>

  Check if can write to client's socket.

=cut

sub _canwrite {
    my ($heap, $wheel_id) = @_;
    exists $heap->{server}->{$wheel_id}->{wheel}
      && ( ref( $heap->{server}->{$wheel_id}->{wheel} ) eq 'POE::Wheel::ReadWrite' );
}


=head4 B<_get_remote_address>

  Get the IP:Port of the client

=cut

sub _get_remote_address {
    my ($socket, $sessionId, $wheel_id) = @_;

    my $remote_ip;
    my ($remote_port, $addr) = ( 'unknown', 'n/a' );
    eval { 
        ($remote_port, $addr) =
            unpack_sockaddr_in(
                getpeername (
                    $disable_ssl ? $socket : $self->roles->sslify_getsocket ($socket)                    
                )
            );
    };
    if ( $@ ) {
        $log->logcluck('[ '. $sessionId . ' ]->('
                        . $wheel_id . ") Error getting remote peer name: $@");
    }
    else {
        eval { $remote_ip = inet_ntoa( $addr ) };
        $log->logcluck('[ '. $sessionId . ' ]->('
                        . $wheel_id . ") Error getting ip address: $@") if $@;
    }
    return wantarray ? ( $remote_ip, $remote_port ) : "$remote_ip:$remote_port";
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

=head1 AUTHOR

  Nuriel Shem-Tov

=cut

1;
