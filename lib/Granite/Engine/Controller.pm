package Granite::Engine::Controller;
use Moose::Role;
use Scalar::Util 'looks_like_number';

use constant _DEBUGSHELL_MISSING => 'Error: DebugShell module not loaded';

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
        # Show session aliases
        # ====================
        show_session_aliases => sub {
            my ( $kernel, $heap, $wheel_id, $sessionId ) = @_;
            $poe_api = _get_poe_api($heap) unless $poe_api;
		    my $output = $poe_api
                ? $poe_api->show_sessions_aliases([$sessionId])
                : _DEBUGSHELL_MISSING;
		    $kernel->post(
        		$kernel->alias_resolve('server'),
                'reply_client',
            	$output,
                $wheel_id,
            );
        },
        # Show session stats
        # ==================
        show_session_stats => sub {
            my ( $kernel, $heap, $wheel_id, $sessionId ) = @_;
            $poe_api = _get_poe_api($heap) unless $poe_api;
		    my $output = $poe_api
                ? $poe_api->show_sessions_stats([$sessionId])
                : _DEBUGSHELL_MISSING;
		    $kernel->post(
        		$kernel->alias_resolve('server'),
                'reply_client',
            	$output,
                $wheel_id,
            );
        },
        # Show session queue
        # ==================
        show_sessions_queue => sub {
        	my ( $kernel, $heap, $wheel_id ) = @_;
            $poe_api = _get_poe_api($heap) unless $poe_api;
		    my $output = $poe_api
                ? $poe_api->show_sessions_queue
                : _DEBUGSHELL_MISSING;
		    $kernel->post(
        		$kernel->alias_resolve('server'),
                'reply_client',
            	$output,
                $wheel_id,
            );
        },

        # Show all sessions
        # =================
        show_sessions   => sub {
        	my ( $kernel, $heap, $wheel_id ) = @_;
            $poe_api = _get_poe_api($heap) unless $poe_api;            
            my $output = $poe_api
                ? $poe_api->show_sessions
                : _DEBUGSHELL_MISSING;
		    $kernel->post(
        		$kernel->alias_resolve('server'),
                'reply_client',
            	$output,
                $wheel_id,
            );
	    },
	    is_kernel_running => sub {
        	my ( $kernel, $heap, $wheel_id ) = @_;
            $poe_api = _get_poe_api($heap) unless $poe_api;
            my $state = $poe_api
                ? eval { $poe_api->api->is_kernel_running }
                : _DEBUGSHELL_MISSING;
            $state = 'Error: ' . $@ if $@;
		    $kernel->post(
        		$kernel->alias_resolve('server'),
                'reply_client',
                $state,
                $wheel_id,
            );
        },
        kernel_memory_size => sub {
        	my ( $kernel, $heap, $wheel_id ) = @_;
            $poe_api = _get_poe_api($heap) unless $poe_api;
            my $memory = $poe_api
                ? eval { $poe_api->api->kernel_memory_size() }
                : _DEBUGSHELL_MISSING;
            $memory = 'Error: ' . $@ if $@;
            $memory .= sprintf(" ( %.2f KB, %.2f MB )", $memory/1024, $memory/(1024**2))
                if looks_like_number($memory);            
		    $kernel->post(
        		$kernel->alias_resolve('server'),
                'reply_client',
                $memory,
                $wheel_id,
            );
        },
        event_list          => sub {
           	my ( $kernel, $heap, $wheel_id ) = @_;
            $poe_api = _get_poe_api($heap) unless $poe_api;
            my @events = $poe_api
                ? eval { $poe_api->api->event_list() }
                : _DEBUGSHELL_MISSING;
            @events = 'Error: ' . $@ if $@;
		    $kernel->post(
        		$kernel->alias_resolve('server'),
                'reply_client',
                \@events,
                $wheel_id,
            );
        },
        session_alias_list  => sub {
            my ( $kernel, $heap, $wheel_id ) = @_;
            $poe_api = _get_poe_api($heap) unless $poe_api;
            my @aliases = $poe_api
                ? eval { $poe_api->api->session_alias_list() }
                : _DEBUGSHELL_MISSING;
            @aliases = 'Error: ' . $@ if $@;
            $kernel->post(
                $kernel->alias_resolve('server'),
                'reply_client',
                \@aliases,
                $wheel_id,
            );
        },
        event_queue_dump    => sub {
           	my ( $kernel, $heap, $wheel_id ) = @_;
            $poe_api = _get_poe_api($heap) unless $poe_api;
            my @events = $poe_api
                ? eval { $poe_api->api->event_queue_dump() }
                : _DEBUGSHELL_MISSING;
            @events = 'Error: ' . $@ if $@;
		    $kernel->post(
        		$kernel->alias_resolve('server'),
                'reply_client',
                \@events,
                $wheel_id,
            );
        },
        session_pid_count   => sub {
           	my ( $kernel, $heap, $wheel_id, $sessionId  ) = @_;
            $poe_api = _get_poe_api($heap) unless $poe_api;            
            my $pid_count;
            if ( $sessionId ){
                $pid_count = $poe_api
                    ? eval { $poe_api->api->session_pid_count($sessionId) }
                    : _DEBUGSHELL_MISSING;
                $pid_count = 'Error: ' . $@ if $@;
            }
            else {
                $pid_count = ' ** Error: no session ID provided'
            }
		    $kernel->post(
        		$kernel->alias_resolve('server'),
                'reply_client',
                $pid_count,
                $wheel_id,
            );
        },
        handle_count        => sub {
           	my ( $kernel, $heap, $wheel_id ) = @_;
            $poe_api = _get_poe_api($heap) unless $poe_api;
            my $handles = $poe_api
                ? eval { $poe_api->api->handle_count() }
                : _DEBUGSHELL_MISSING;
            $handles = 'Error: ' . $@ if $@;
		    $kernel->post(
        		$kernel->alias_resolve('server'),
                'reply_client',
                $handles,
                $wheel_id,
            );
        },
        get_safe_signals     => sub {
           	my ( $kernel, $heap, $wheel_id ) = @_;
            $poe_api = _get_poe_api($heap) unless $poe_api;
            my @sigs = _DEBUGSHELL_MISSING;
            if ( $poe_api ){
                eval { @sigs = $poe_api->api->get_safe_signals() };
                @sigs = 'Error: ' . $@ if $@;
            }
		    $kernel->post(
        		$kernel->alias_resolve('server'),
                'reply_client',
                "@sigs",
                $wheel_id,
            );
        },
        session_handle_count => sub {
           	my ( $kernel, $heap, $wheel_id, $sessionId  ) = @_;
            $poe_api = _get_poe_api($heap) unless $poe_api;
            my $handle_count = _DEBUGSHELL_MISSING;
            if ( $sessionId ){
                eval { $handle_count = $poe_api->api->session_handle_count($sessionId) };
                $handle_count = 'Error: ' . $@ if $@;
            }
            else {
                $handle_count = ' ** Error: no session ID provided'
            }
		    $kernel->post(
        		$kernel->alias_resolve('server'),
                'reply_client',
                $handle_count,
                $wheel_id,
            );
        },
        session_memory_size  => sub {
           	my ( $kernel, $heap, $wheel_id, $sessionId  ) = @_;
            $poe_api = _get_poe_api($heap) unless $poe_api;            
            my $memory;
            if ( $sessionId ){
                $memory = $poe_api
                    ? eval { $poe_api->api->session_memory_size($sessionId) }
                    : _DEBUGSHELL_MISSING;
                $memory = 'Error: ' . $@ if $@;
                $memory .= sprintf(" ( %.2f KB, %.2f MB )", $memory/1024, $memory/(1024**2))
                    if looks_like_number($memory);
            }
            else {
                $memory = ' ** Error: no session ID provided'
            }
		    $kernel->post(
        		$kernel->alias_resolve('server'),
                'reply_client',
                $memory,
                $wheel_id,
            );
        },
        session_event_list  => sub {
            my ( $kernel, $heap, $wheel_id, $sessionId  ) = @_;
            $poe_api = _get_poe_api($heap) unless $poe_api;
            my @event_list;
            if ( $sessionId ){
                @event_list = $poe_api
                    ? eval { $poe_api->api->session_event_list([$sessionId]) }
                    : _DEBUGSHELL_MISSING;
                @event_list = 'Error: ' . $@ if $@;
            }
            else {
                @event_list = ' ** Error: no session ID provided'
            }
            $kernel->post(
                $kernel->alias_resolve('server'),
                'reply_client',
                \@event_list,
                $wheel_id,
            );
        },
        exec_func           => sub {
            my ( $kernel, $heap, $wheel_id, $args  ) = @_;
            
            $kernel->post(
                $kernel->alias_resolve('server'),
                'reply_client',
                'work in progress',
                $wheel_id,
            );
        },
        # Shutdown the server session
        # ===========================
        server_shutdown     => sub {
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

  Get detailed hypervisor list from cloud

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

=head4 B<_get_poe_api>

  Returns the DebugShell subclass which includes access to the POE::API::Peek

=cut

sub _get_poe_api {
    my $heap = shift;
    eval {
        $heap->{self}->modules->{debugShell}
                     ->{(keys %{$heap->{self}->modules->{debugShell}})[0]}
                     ->new
    }
}

no Moose; 

=head1 AUTHOR

  Nuriel Shem-Tov
  
=cut

1;
