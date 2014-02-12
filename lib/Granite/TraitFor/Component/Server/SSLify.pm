package Granite::TraitFor::Component::Server::SSLify;
use POE::Component::SSLify qw( SSLify_Options SSLify_GetCTX SSLify_GetCipher SSLify_GetSocket);
use POE::Component::SSLify::NonBlock qw(
    Server_SSLify_NonBlock
    SSLify_Options_NonBlock_ClientCert
    Server_SSLify_NonBlock_ClientCertVerifyAgainstCRL
    Server_SSLify_NonBlock_ClientCertificateExists
    Server_SSLify_NonBlock_ClientCertIsValid
    Server_SSLify_NonBlock_SSLDone );
use Moose::Role;

=head1 DESCRIPTION

  Socket SSLifier for POE SocketFactory

=head1 SYNOPSIS

  package MyPackage;
  use Moose;
  with 'Granite::TraitFor::Component::Server::SSLify';
  
  Or load via MooseX::Traits as done by Granite::Component::Server  

=head2 METHODS

=head4 B<sslify_options>

  Set global server SSL ctx options 

=cut

sub sslify_options {
    shift;
    my ( $granite_key, $granite_crt,  $granite_cacrt ) = @_;

    for ( $granite_key, $granite_crt ){
        Granite->log->logcroak("Cannot find '$_'. Verify existance and permissions.") unless -f $_;
    }
    if ( Granite->cfg->{server}->{client_certificate} =~ /yes/i ){
        Granite->log->logcroak("Missing CA certificate. Verify existance and permissions.")
            if ( !$granite_cacrt or ! -f $granite_cacrt );
    }

    eval { SSLify_Options( $granite_key, $granite_crt ) };
    Granite->log->logcroak( "Error setting SSLify_Options with '$granite_key' and '$granite_crt': "
                    . $@ . ' Check file permissions.' ) if ($@);

    eval { SSLify_Options_NonBlock_ClientCert( SSLify_GetCTX(), $granite_cacrt ); } if $granite_cacrt;
    Granite->log->logcroak( 'Error setting SSLify_Options_NonBlock_ClientCert: ' . $@ ) if ($@);

}

=head4 B<sslify_socket>

  SSLify a provided socket
  
=cut 

sub sslify_socket {
	shift;
    my ( $socket, $granite_crl, $sessionId ) = @_;

    Granite->log->info('[ ' . $sessionId .' ] Starting up SSLify on socket');

    eval {
        $socket = Server_SSLify_NonBlock(
            SSLify_GetCTX(),
            $socket,
            {
                clientcertrequest    => $ENV{GRANITE_REQUEST_CLIENT_CERTIFICATE}
                    || ( Granite->cfg->{server}->{client_certificate} =~ /yes/i ? 1 : 0 ),
                noblockbadclientcert => $ENV{GRANITE_VERIFY_CLIENT}
                    || ( Granite->cfg->{server}->{verify_client} =~ /yes/i ? 1 : 0 ),
                getserial            => $granite_crl ? 1 : 0,
                debug                => 0 #$debug
            }
        );
    };

    if ($@) {
        Granite->log->logcluck('_client_accept: SSL Failed:' . $@);
        return undef;
    }
    else {
        return $socket;
    }

}

=head4 B<verify_client_ssl>

  Verify client's SSL cerificate

=cut

sub verify_client_ssl {
    shift;
    my ( $kernel, $heap, $wheel_id, $socket, $canwrite, $sessionId ) = @_;

    Granite->log->info('[ '. $sessionId . ' ]->(' . $wheel_id . ') Verifying Server_SSLify_NonBlock_SSLDone on socket');

    my $test;
    eval { $test = Server_SSLify_NonBlock_SSLDone($socket); };
    if ( $@ or !$test ){
        Granite->log->error('[ ' . $wheel_id . ' ] SSL Handshake failed: ' . $@ );
        return undef;
    }

    # Check certificate provided by client
    # ====================================
    if ( $ENV{GRANITE_CLIENT_CERTIFICATE} ){
        my $test;
        eval { $test = Server_SSLify_NonBlock_ClientCertificateExists($socket); };
        if ( $@ or !$test ) {
            $heap->{server}->{$wheel_id}->{wheel}->put( "[" . $wheel_id . "] NoClientCertExists\n" )
                if $canwrite;
            Granite->log->error('[ '. $sessionId . ' ]->(' . $wheel_id . ') NoClientCertExists');
            return undef;
        }
    }
    # check certificate valid
    # =======================
    if ( $ENV{GRANITE_VERIFY_CLIENT} ){
        my $test;
        eval { $test = Server_SSLify_NonBlock_ClientCertIsValid($socket); };
        if ( $@ or !$test ){
            $heap->{server}->{$wheel_id}->{wheel}->put( "[" . $wheel_id . "] ClientCertInvalid\n" )
                if $canwrite;
            Granite->log->error( '[ '. $sessionId . ' ]->(' . $wheel_id . ') ClientCertInvalid: ' . $@ );
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

=head4 B<sslify_getsocket>

  Get the socket from SSLify
  
=cut

sub sslify_getsocket { shift; SSLify_GetSocket( shift ) }

no Moose;

=head1 AUTHOR

  Nuriel Shem-Tov
  
=cut

1;
