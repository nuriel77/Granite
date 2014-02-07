package Granite::Engine::Controller;
use Moose::Role;
use Try::Tiny;
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
            my $node_array;
            try { $node_array = $heap->{self}->scheduler->{nodes}->list_nodes }
            catch { $node_array = $_ };

            my @visible_nodes = ref $node_array eq 'ARRAY'
                ? grep defined, @{$node_array}
                : $node_array;

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
            my $instances;
            try { $instances = $heap->{self}->cloud->get_all_instances }
            catch { $instances = $_ };
            $kernel->post(
                $kernel->alias_resolve('server'),
                'reply_client',
                $instances,
                $wheel_id
            );
        },
        # Get cloud's hypervisor list
        # ===========================
        gethypervisors  => sub {
            my ( $kernel, $heap, $wheel_id ) = @_;
            my $hypervisor_list;
            try { $hypervisor_list = $heap->{self}->cloud->get_all_hypervisors }
            catch { $hypervisor_list = $_ };
            $kernel->post(
                $kernel->alias_resolve('server'),
                'reply_client',
                $hypervisor_list,
                $wheel_id,
            );
        },
        # Boot instance 
        # =============
        bootinstance    => sub {
            my ( $kernel, $heap, $wheel_id ) = @_;
            my $status = 'Instance boot request submitted OK';
            try {
                $heap->{self}->cloud->boot_instance({
                    name => 'test01',
                    key_name => $heap->{self}->cloud->{metadata}->{adminkey},
                    imageRef => $heap->{self}->cloud->{metadata}->{default_image},
                    flavorRef => $heap->{self}->cloud->{metadata}->{default_flavor_id},
                })
            }
            catch {
                $Granite::log->error('Error from Cloud API: ' . $_);
                $status = $_;
            };
            $kernel->post(
                $kernel->alias_resolve('server'),
                'reply_client',
                $status,
                $wheel_id,
            );
        },
        # Client disconnect
        # =================
        exit            => sub {
            my ( $kernel, $heap, $wheel_id ) = @_;
            my $server = $kernel->alias_resolve('server');
            my $postback = $server->postback( "disconnect", $wheel_id );
            $kernel->post(
                $server,
                'reply_client',
                'Goodbye! (disconnecting...)',
                $wheel_id,
                $postback
            );
        },
        # Alias callback
        # ==============
        quit => sub { return 'exit' },
    }
}

no Moose;

=head1 AUTHOR

  Nuriel Shem-Tov
  
=cut

1;
