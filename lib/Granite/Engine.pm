package Granite::Engine;
use Granite::Engine::Daemonize;
use Granite::Component::Server;
use Granite::Component::Scheduler::Queue;
use Granite::Component::Scheduler::Nodes;
use Granite::Component::Scheduler::Queue::Watcher;
use Cwd 'getcwd';
use POE;
use POE::Wheel::Run;
use Data::Dumper::Concise;
use Moose;
    with 'Granite::Engine::Logger',
         'Granite::Engine::Controller',
         'Granite::Utils::ModuleLoader';

use namespace::autoclean;
use vars qw($log $debug $daemon);

=head1 NAME

Granite::Engine

=head1 DESCRIPTION

  Used as the controller of the application

=head1 SYNOPSIS

  use Granite;
  my $g = Granite->new();
  $g->init;

  (Loaded by granite main script)

=head2 ATTRIBUTES

=over

=item * L<modules> 
=cut

has modules    => (
    is => 'rw',
    isa => 'HashRef',
    default => sub {{}},
    lazy => 1,
);

=item * L<scheduler> 
=cut

has scheduler  => (
    is => 'rw',
    isa => 'HashRef',
    lazy => 1,
    default => sub {{}},
);

=item * L<cloud> 
=cut

has cloud      => (
    is => 'ro',
    isa => 'Object',
    writer => '_set_cloud',
    predicate => '_has_cloud',
    lazy => 1,
    default => sub {{}},
);

=item * L<debug> 
=cut

has debug      => (
    is => 'ro',
    isa => 'Bool'
);

=item * L<logger> 
=cut

has logger     => (
    is => 'ro',
    isa => 'Object',
    required => 1
);


=back

=head2 METHODS

=head3 B<run>

 Runs the engine

=cut

sub run {
    my $self = shift;
    ( $log, $debug ) = ($self->logger, $self->debug);

    if ( !$ENV{GRANITE_FOREGROUND} && $Granite::cfg->{main}->{daemonize} =~ /yes/i ){
        # Daemonize
        # =========
        Granite::Engine::Daemonize->new(
            logger   => $log,
            debug    => $debug,
            poe_kernel => $poe_kernel,
            workdir  => $ENV{GRANITE_WORK_DIR} || getcwd(),
            pid_file => $ENV{GRANITE_PID_FILE}
                || $Granite::cfg->{main}->{pid_file}
                || '/var/run/granite/granite.pid'
        )
    }
    else {
        # set logger output to 
        # stdout if not daemonizing
        # ===========================
        set_logger_stdout($log) if $debug;
    }

    $self->_init;
}

=head3 B<_init>

  Engine initialize all components
  and modules then start main session
  and run children sessions

=cut

sub _init {
    my $self = shift;

    $log->debug('At Granite::Engine::init') if $debug;

    # Load modules
    # ============
    $self->_init_modules();
 
    #warn Dumper $cloud->get_all_instances;
    #warn Dumper $cloud->get_all_hypervisors;

    $log->info('Starting POE sessions');

    # Start main session
    # ==================
    my $session = POE::Session->create(
        inline_states => {
            _start          => sub {
                my ($heap, $kernel, $sender, $session ) = @_[ HEAP, KERNEL, SENDER, SESSION ];

                $log->debug('[ ' . $session->ID() . ' ] Sender: ' . $sender);
                $heap->{parent} = $sender;
                $kernel->alias_set('engine');

                # Queue watcher
                # =============
                $kernel->yield("watch_queue", $log, $debug, $self->modules->{scheduler} );

                # Server
                # ======
                unless ( $ENV{GRANITE_NO_TCP} or $Granite::cfg->{server}->{disable} =~ /yes/i ){
                    $kernel->yield("init_server", $log, $debug );
                }

            },
            _child          => \&child_sessions,
            init_server     => sub {
                Granite::Component::Server->new()->run( $_[SESSION]->ID() )
            },
            process_res_q   => sub {
                $self->scheduler->{queue}->process_queue( $_[HEAP], $_[SESSION]->ID() )
            },
            client_commands => \&init_controller,
            get_nodes       => \&_get_node_list,
            watch_queue     => \&Granite::Component::Scheduler::Queue::Watcher::run,
            _default        => \&handle_default,
            _stop           => \&terminate,
        },
        heap => { scheduler => $self->scheduler, self => $self }
    ) or $log->logcroak('[ ' . $_[SESSION]->ID() .  " ] can't POE::Session->create: $!" );

    $poe_kernel->run();

}

=head3 B<_terminate>

  If termination signal arrives

=cut

sub _terminate {
    my ($heap, $kernel, $sender, $session ) = @_[ HEAP, KERNEL, SENDER, SESSION ];
    $log->info('[ ' . $session->ID() . '] Terminating...(caller: ' . $sender . ')');
    delete $heap->{server};
    unlink $Granite::cfg->{server}->{unix_socket}
        if -e $Granite::cfg->{server}->{unix_socket};
    $kernel->stop();
    Granite->QUIT;
}

=head3 B<_init_modules>

  Initialize pluggable modules
  Configuration example:

  modules:
    scheduler:
      name: Slurm
      meta:
        - '/opt/slurm/etc/slurm.conf'
  
=cut

sub _init_modules {
    my $self = shift;


    for my $module ( keys %{$Granite::cfg->{modules}} ){
        my $package = 'Granite::Modules::' . ucfirst($module)
                    . '::' . $Granite::cfg->{modules}->{$module}->{name};
        if ( my $error = load_module( $package ) ){
            $log->logcroak("Failed to load module '" . $package . "': $error" );
        }
        else {
            $self->modules->{$module}->{$package} =
                $package->new(
                    name => $package,
                    metadata => $Granite::cfg->{modules}->{$module}->{metadata}
                );
            $log->debug("Loaded module '" . $package . "'") if $debug;
        }
    }    

    # Set scheduler
    # =============
    $self->scheduler ( $self->modules->{scheduler} )
        && delete $self->modules->{scheduler};    

    # Set scheduler queue
    # ====================
    $self->scheduler->{queue} = Granite::Component::Scheduler::Queue->new;
    
    # Set scheduler  nodes
    # ====================
    $self->scheduler->{nodes} = Granite::Component::Scheduler::Nodes->new(
        scheduler => $self->scheduler,
        logger => $log,
        debug => $debug 
    );

    # Set cloud
    # =========
    $self->_set_cloud ( $self->modules->{cloud}->{ (keys %{$self->modules->{cloud}})[0] } )
        && delete $self->modules->{cloud};

}

=head3 B<child_sessions>

  Used to maintain state of children sessions

=cut

sub child_sessions {
    my ($heap, $kernel, $operation, $child) = @_[HEAP, KERNEL, ARG0, ARG1];
    if ($operation eq 'create' or $operation eq 'gain') {
        $heap->{child_count}++;
    }
    elsif ($operation eq 'lose') {
        $heap->{child_count}--;
    }
}

=head3 B<init_controller>

  Initialize Engine's controller

=cut

sub init_controller {
    my ($kernel, $heap, $cmd, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

    my $output = '';
    
    $log->debug('[' . $_[SESSION]->ID(). " ] At init_controller with command: '$cmd'");
    
    # Get all known commands
    # ======================
    my @commands = keys $heap->{self}->commands;
    
    # Check if use command exists.
    # Return the list of commands to user
    # if user's command is unrecognized.
    # Otherwise, perform closure to exec
    # the configured command method and pass
    # the POE variables + client's wheel_id
    # =====================================
    unless ( $cmd ~~ @commands ) {
        $output = "Commands: " . ( join ', ', @commands );
        my $server_session = $kernel->alias_resolve('server');
        $kernel->post( $server_session , 'reply_client', $output, $wheel_id );
    }
    else {
        $heap->{self}->commands->{"$cmd"}->( $kernel, $heap, $wheel_id );
    }

}


=head3

  Default method to capture unrecognized POE requests

=cut

sub handle_default {
    my ($event, $args) = @_[ARG0, ARG1];
    $log->logconfess(
      'Session [ ' . $_[SESSION]->ID .
      " ] caught unhandled event '$event' with " . Dumper @{$args}
    );
}


#
#   Temporarily here:
#
sub _get_node_list {
    my ( $heap, $kernel ) = @_[ HEAP, KERNEL ];
    my ( $session, $next_event, $wheel_id ) = @_[ ARG0..ARG2 ];

    my $node_array = $heap->{self}->scheduler->{nodes}->list_nodes;
    my @visible_nodes = grep defined, @{$node_array};

    if ( $debug ){
        $log->debug( '[ ' . $_[SESSION]->ID() . ' ] Defined Node: ' . Dumper $_ ) for @visible_nodes;
    }

    $log->debug( '[ ' . $_[SESSION]->ID() . ' ] Number of visible scheduler nodes: ' . scalar @visible_nodes );
    $kernel->post($session, $next_event, \@visible_nodes, $wheel_id);
}



__PACKAGE__->meta->make_immutable(inline_constructor => 0);

=head1 AUTHOR

  Nuriel Shem-Tov

=cut

1;
