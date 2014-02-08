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

  * client_commands
  * engine_commands
  
=cut

has client_commands => (
    is => 'ro',
    isa => 'HashRef',
    default => \&_get_client_commands,
    lazy => 1,
);

has engine_commands => (
    is => 'ro',
    isa => 'HashRef',
    default => \&_get_engine_commands,
    lazy => 1,
);

no Moose; 

=head2 METHODS

=head3 B<_get_client_commands>

  Return the user space command dictionary

=cut

sub _get_client_commands {
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
        # Opens debug shell on server side
        # TODO: 'exit' method does not exists
        # contrary to what is claimed in the 
        # docs of POE::Component::DebugShell
        debugshell      => sub {
            my ( $kernel, $heap, $wheel_id ) = @_;
            unless ( $ENV{GRANITE_FOREGROUND} ) {
                $kernel->post(
                    $kernel->alias_resolve('server'),
                    'reply_client',
                    'Cannot open debug console when daemonized',
                    $wheel_id
                );
            }
            else {
                $kernel->post(
                    $kernel->alias_resolve('engine'),
                    'debug_shell',
                );
            }
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
            my $nodes = _get_scheduler_nodes($heap->{self}->scheduler);
            $kernel->post(
                $kernel->alias_resolve('server'),
                'reply_client',
                $nodes,
                $wheel_id
            );
        },
        # Get cloud's instance list
        # =========================
        getinstances    => sub {
            my ( $kernel, $heap, $wheel_id ) = @_;
            my $instances = &_get_instances($heap->{self}->cloud);
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
            my $hypervisor_list = &_get_hypervisor_list($heap->{self}->cloud);
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
            my $status = &_boot_instance($heap->{self}->cloud);
            $status = 'Instance boot request submitted OK'
                if $status == 1;
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


=head3 B<_get_engine_commands>

  Return the engine command dictionary

=cut

sub _get_engine_commands {
    {
        ping        => sub { return 'pong' }
    }
}

=head3 B<_get_instances>

  Get instnaces list from cloud

=cut

sub _get_instances {
    my $cloud = shift;
    my $instances;
    try { $instances = $cloud->get_all_instances }
    catch { $instances = $_ };
    return $instances;
}

=head3 B<_get_scheduler_nodes>

  Get all (visible) scheduler nodes

=cut

sub _get_scheduler_nodes {
    my $scheduler = shift;
    my $node_array;
    try { $node_array = $scheduler->{nodes}->list_nodes }
    catch { $node_array = $_ };
    my @visible_nodes = ref $node_array eq 'ARRAY'
        ? grep defined, @{$node_array}
        : $node_array;
    return wantarray ? @visible_nodes : \@visible_nodes;
}


=head3 B<_get_hypervisor_list>

  Get hypervisor list from cloud

=cut

sub _get_hypervisor_list {
    my $cloud = shift;
    my $hypervisor_list;
    try { $hypervisor_list = $cloud->get_all_hypervisors }
    catch { $hypervisor_list = $_ };
    return $hypervisor_list;
}


=head3 B<_boot_instance>

  Boot an instance

=cut

sub _boot_instance {
    my $cloud = shift;
    try {    
        $cloud->boot_instance({
            name => 'test01',
            key_name => $cloud->{metadata}->{adminkey},
            imageRef => $cloud->{metadata}->{default_image},
            flavorRef => $cloud->{metadata}->{default_flavor_id},
        })
    }
    catch { return $_ }

    return 1;
}

=head1 AUTHOR

  Nuriel Shem-Tov
  
=cut

1;
