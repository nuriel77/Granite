package Granite::Engine::Controller;
use Moose::Role;
use Data::Dumper;

=head1 DESCRIPTION

  Controller roles for the engine.
  
  Currently includes all userspace
  commands originating from user input

=head1 SYNOPSIS

  This package is a Moose Role:

  use Moose;

  with 'Granite::Enginer::Controller';


=head2 ATTRIBUTES

  * commands
  
=cut

has commands => (
    is => 'ro',
    isa => 'HashRef',
    default => \&_get_commands_hash,
    lazy => 1,
);


=head2 METHODS

=head3 B<_get_commands_hash>

  Return the commands dictionary

=cut

sub _get_commands_hash {
    { 
        ping            => sub {
            my ( $kernel, $heap, $wheel_id ) = @_;
            $kernel->post(
                $kernel->alias_resolve('server'),
                'reply_client',
                'pong',
                $wheel_id
            );
        },
        # Shutdown the server session
        # ===========================
        server_shutdown => sub {
            my ( $kernel, $heap, $wheel_id ) = @_;
            my $server = $kernel->alias_resolve('server');
            my $postback = $server->postback( "server_shutdown", $wheel_id );
            $kernel->post(
                $server,
                'reply_client',
                'Shutting down server. Goodbye.',
                $wheel_id,
                $postback,
            );
        },
        # Get scheduler's node list
        # =========================
        getnodes        => sub {
            my ( $kernel, $heap, $wheel_id ) = @_;           
            my $node_array = $heap->{self}->scheduler->{nodes}->list_nodes;
            my @visible_nodes = grep defined, @{$node_array};
            $kernel->post(
                $kernel->alias_resolve('server'),
                'reply_client',
                \@visible_nodes,
                $wheel_id
            );
        },
        # Get cloud's instance list
        # =========================
        getinstances    => sub {
            my ( $kernel, $heap, $wheel_id ) = @_;
            $kernel->post(
                $kernel->alias_resolve('server'),
                'reply_client',
                'work in progress',
                $wheel_id
            );
        },
        # Get cloud's hypervisor list
        # ===========================
        gethypervisors  => sub {
            my ( $kernel, $heap, $wheel_id ) = @_;
            $kernel->post(
                $kernel->alias_resolve('server'),
                'reply_client',
                'work in progress',
                $wheel_id
            );
        }
    }
}

no Moose;

=head1 AUTHOR

  Nuriel Shem-Tov
  
=cut

1;
