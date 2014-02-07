package Granite::Engine::Controller;
use Moose::Role;


=head1 DESCRIPTION

Controller roles for the engine
Currently includes all userspace
commands originating from user input

=cut
has commands => (
    is => 'ro',
    isa => 'HashRef',
    default => \&_get_commands_hash
);

sub _get_commands_hash {
    { 
        ping            => sub { return 'pong' },
        hello           => sub { return 'what\'s up?' },
        shutdown        => sub { $_[0]->stop },
        server_shutdown => sub { return undef; },
        getnodes        => sub {
            my ($kernel, $heap, $wheel_id) = @_;
            my $engine_session = $kernel->alias_resolve('engine');
            my $server_session = $kernel->alias_resolve('server');
            # Post to engine to run 'get_nodes'. 'get_nodes' posts
            # its data to $server_session => 'reply_client', and
            # $wheel_id is the wheel of the specific client
            $kernel->post( $engine_session , 'get_nodes', $server_session, 'reply_client', $wheel_id );
        }
   }
}

no Moose;

1;
