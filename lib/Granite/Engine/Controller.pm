package Granite::Engine::Controller;
use Moose::Role;
use Data::Dumper;

use vars qw/$poe_api/;

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
    writer  => '_set_client_commands',
    lazy => 1,
);

has engine_commands => (
    is => 'ro',
    isa => 'HashRef',
    default => \&_get_engine_commands,
    lazy => 1,
);

=head2 METHODS

=head4 B<_get_client_commands>

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
        # Get scheduler's reservation queue
        # =================================
        getresqueue     => sub {
            my ( $kernel, $heap, $wheel_id ) = @_;
            my $output = _get_scheduler_res_q($heap->{self}->scheduler);
            $kernel->post(
                $kernel->alias_resolve('server'),
                'reply_client',
                $output,
                $wheel_id
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
        # Alias hook
        # ==============
        quit => sub { return 'exit' },
        q    => sub { return 'exit' },
    }
}


=head4 B<_get_engine_commands>

  Return the engine command dictionary

=cut

sub _get_engine_commands {
    {
        ping => sub { return 'pong' },
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
        show_session_aliases => sub {
            my ( $kernel, $heap, $wheel_id, $sessionId ) = @_;
 	   		$poe_api = $heap->{self}->modules->{debugShell}
                            ->{(keys %{$heap->{self}->modules->{debugShell}})[0]}->new
                unless $poe_api;
		    my $output = $poe_api->show_sessions_aliases([$sessionId]);
		    $kernel->post(
        		$kernel->alias_resolve('server'),
                'reply_client',
            	$output,
                $wheel_id,
            );
        },
        show_session_stats => sub {
            my ( $kernel, $heap, $wheel_id, $sessionId ) = @_;
 	   		$poe_api = $heap->{self}->modules->{debugShell}
                            ->{(keys %{$heap->{self}->modules->{debugShell}})[0]}->new
                unless $poe_api;
		    my $output = $poe_api->show_sessions_stats([$sessionId]);
		    $kernel->post(
        		$kernel->alias_resolve('server'),
                'reply_client',
            	$output,
                $wheel_id,
            );
        },
        show_sessions_queue => sub {
        	my ( $kernel, $heap, $wheel_id ) = @_;
 	   		$poe_api = $heap->{self}->modules->{debugShell}
                            ->{(keys %{$heap->{self}->modules->{debugShell}})[0]}->new
                unless $poe_api;
		    my $output = $poe_api->show_sessions_queue;
		    $kernel->post(
        		$kernel->alias_resolve('server'),
                'reply_client',
            	$output,
                $wheel_id,
            );
        },
        show_sessions   => sub {
        	my ( $kernel, $heap, $wheel_id ) = @_;
 	   		$poe_api = $heap->{self}->modules->{debugShell}
                            ->{(keys %{$heap->{self}->modules->{debugShell}})[0]}->new
                unless $poe_api;
		    my $output = $poe_api->show_sessions;
		    $kernel->post(
        		$kernel->alias_resolve('server'),
                'reply_client',
            	$output,
                $wheel_id,
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
    }
}

=head4 B<_get_instances>

  Get instnaces list from cloud

=cut

sub _get_instances {
    my $cloud = shift;
    my $instances;
    eval { $instances = $cloud->get_all_instances };
    return $@ ? $@ : $instances;
}

=head4 B<_get_scheduler_res_q>

  Get scheduler's reservation queue

=cut

sub _get_scheduler_res_q {
    my $scheduler = shift;
    my $queue;
    my $sched_api = $scheduler->{(keys %{$scheduler})[0]};
    eval { $queue = $sched_api->get_queue };
    return $@ ? $@ : $queue;
}


=head4 B<_get_scheduler_nodes>

  Get all (visible) scheduler nodes

=cut

sub _get_scheduler_nodes {
    my $scheduler = shift;
    my $node_array;
    eval { $node_array = $scheduler->{nodes}->list_nodes };
    return $@ if $@;
    my @visible_nodes = ref $node_array eq 'ARRAY'
        ? grep defined, @{$node_array}
        : $node_array;
    return wantarray ? @visible_nodes : \@visible_nodes;
}


=head4 B<_get_hypervisor_list>

  Get hypervisor list from cloud

=cut

sub _get_hypervisor_list {
    my $cloud = shift;
    my $hypervisor_list;
    eval { $hypervisor_list = $cloud->get_all_hypervisors };
    return $@ ? $@ : $hypervisor_list;
}


=head4 B<_boot_instance>

  Boot an instance

=cut

sub _boot_instance {
    my $cloud = shift;
    $Granite::log->debug('At _boot_instance');
    eval {
        $cloud->boot_instance({
            name => 'test01',
            key_name => $cloud->{metadata}->{adminkey},
            imageRef => $cloud->{metadata}->{default_image},
            flavorRef => $cloud->{metadata}->{default_flavor_id},
        })
    };
    return $@ ? $@ : 1;
}

no Moose; 

=head1 AUTHOR

  Nuriel Shem-Tov
  
=cut

1;
