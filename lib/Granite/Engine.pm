package Granite::Engine;
use Moose;
use Granite::Engine::Daemonize;
use Granite::Component::Server;
use Granite::Component::Scheduler::Queue;
use Granite::Component::Scheduler::Nodes;
use Granite::Component::Scheduler::Queue::Watcher;
use Coro;
use Cwd 'getcwd';
use POE;
use POE::Wheel::Run;
use Data::Dumper;
with 'Granite::Engine::Logger',
     'Granite::Engine::Controller',
     'Granite::Utils::ModuleLoader';

use namespace::autoclean;
use vars qw($log $debug $engine_session);

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

=item * L<cache> 
=cut

has cache      => (
    is => 'ro',
    isa => 'HashRef',
    writer => '_set_cache_obj',
    predicate => '_has_cache_obj',
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

=item * L<client_privmode>
=cut

has client_privmode => (
    is => 'rw',
    isa => 'HashRef',
    lazy => 1,
    default => sub {{}},
);

=back

=head2 METHODS

=head4 B<run>

  Runs the engine

=cut

sub run {
    my $self = shift;
    ( $log, $debug ) = ($self->logger, $self->debug);

    if ( !$ENV{GRANITE_FOREGROUND} && $Granite::cfg->{main}->{daemonize} =~ /yes/i ){
        # Daemonize
        # =========
        my $daemon = Granite::Engine::Daemonize->new(
            logger   => $log,
            debug    => $debug,
            poe_kernel => $poe_kernel,
            workdir  => $ENV{GRANITE_WORK_DIR} || getcwd(),
            pid_file => $ENV{GRANITE_PID_FILE}
                || $Granite::cfg->{main}->{pid_file}
                || '/var/run/granite/granite.pid'
        );
        $poe_kernel->has_forked if $daemon;
    }
    else {
        # set logger output to 
        # stdout if not daemonizing
        # ===========================
        set_logger_stdout($log) if $debug;
    }

    $self->_init;
}

=head4 B<_init>

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
    $engine_session = POE::Session->create(
        inline_states => {
            _start          => sub {
                my ($heap, $kernel, $sender, $session ) = @_[ HEAP, KERNEL, SENDER, SESSION ];
    
                # At this stage we replace the INT
                # with a new termination handler
                # ================================
                $SIG{INT} = sub { Coro::State->join() };

                $log->debug('[ ' . $session->ID() . ' ] Engine session started.');
                $heap->{parent} = $sender;
                $kernel->alias_set('engine');

                # Queue watcher
                # =============
                $kernel->yield("init_granite_queue", $log, $debug );
                $kernel->yield("watch_queue", $log, $debug, $self->modules->{scheduler} );

                # Server
                # ======
                unless ( $ENV{GRANITE_NO_TCP} or $Granite::cfg->{server}->{disable} =~ /yes/i ){
                    $kernel->yield("init_server", $log, $debug );
                }

            },
            _child          => \&child_sessions,
            init_server     => sub { Granite::Component::Server->new()->run( $_[SESSION]->ID() ) },
            client_commands => \&_controller,
            get_nodes       => \&_get_node_list,
            watch_queue     => \&Granite::Component::Scheduler::Queue::Watcher::run,
            init_granite_queue => \&Granite::Component::Scheduler::Queue::init,
            _default        => \&handle_default,
            terminate       => sub { $_[KERNEL]->post('_stop') },
            _stop           => \&_terminate,
        },
        heap => { scheduler => $self->scheduler, self => $self },
        options => { trace => $Granite::trace, debug => $debug },
    ) or $log->logcroak('[ ' . $_[SESSION]->ID() .  " ] can't POE::Session->create: $!" );

    $poe_kernel->run();

}

=head4 B<_terminate>

  If termination signal arrives

=cut

sub _terminate {
    my ($heap, $kernel, $sender, $session )
        = @_[ HEAP, KERNEL, SENDER, SESSION ];

    $log->info('[ ' . $session->ID() . ' ] Terminating...(caller: ' . $sender . ')');
    delete $heap->{server};
    unlink $Granite::cfg->{server}->{unix_socket}
        if -e $Granite::cfg->{server}->{unix_socket};

    my $qparent_session = $kernel->alias_resolve('QueueParent');
    $_[KERNEL]->post( $qparent_session , 'process_new_queue_data', ['shutdown'] )
        if $qparent_session;

    $kernel->stop();
    Granite->QUIT;
}

=head4 B<_init_modules>

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

    MODULES:
    for my $module ( keys %{$Granite::cfg->{modules}} ){
        # Skip if module not enabled
        next MODULES unless $Granite::cfg->{modules}->{$module}->{enabled};
        # Build package name
        my $package = 'Granite::Modules::' . ucfirst($module)
                    . '::' . $Granite::cfg->{modules}->{$module}->{name};
        $log->debug("Attempting to load module '" . $package . "'") if $debug;
        if ( my $error = load_module( $package ) ){
            $log->logcroak("Failed to load module '" . $package . "': $error" );
        }
        else {
            my $instance = $package->new(
                    name     => $package,
                    metadata => $Granite::cfg->{modules}->{$module}->{metadata},
                    hook => $Granite::cfg->{modules}->{$module}->{hook}
                );
            $self->modules->{$module}->{$package} = $instance;
            $log->debug("Loaded module '" . $package . "' OK") if $debug;
        }
    }    

    # Set cache
    # =========
    $self->_set_cache_obj( $self->modules->{cache} )
        if $self->modules->{cache};

    # Set scheduler
    # =============
    $self->scheduler ( $self->modules->{scheduler} )
        && delete $self->modules->{scheduler};    

    # Set scheduler queue
    # ====================
    $self->scheduler->{queue} = Granite::Component::Scheduler::Queue->new;
    
    # Set scheduler nodes
    # ===================
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

=head4 B<child_sessions>

  Used to maintain status of engine's created sessions

=cut

sub child_sessions {
    my ($heap, $kernel, $operation, $child) = @_[HEAP, KERNEL, ARG0, ARG1];

    if ($operation eq 'create' or $operation eq 'gain') {
        $log->debug('[ ' . $_[SESSION]->ID()
                    . ' ] New child session spawned:'
                    . ' (' . $child->ID() . ')'
        );
        $heap->{child_count}++;
    }
    elsif ($operation eq 'lose') {
        $log->debug('[ ' . $_[SESSION]->ID()
                    . ' ] Child session terminated:'
                    . ' (' . $child->ID() . ')'
        );
        $heap->{child_count}--;
    }
}

=head4 B<_controller>

  Initialize Engine's controller

=cut

sub _controller {
    my ($kernel, $heap, $input, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

    my ($cmd, $args) = split(' ', $input);

    my $output = '';
    my $server_session = $kernel->alias_resolve('server');
    $log->debug('[ ' . $_[SESSION]->ID()
                . " ] At _controller with command: '$cmd'"
                . ( $args ? ' and args: ' . $args : '' )
    );
    
    # Get all known commands
    # ======================
    if ( $cmd eq 'privmode' ){
        $heap->{self}->client_privmode->{$wheel_id} = 1;
        $kernel->post( $server_session, 'reply_client', 'privmode enabled', $wheel_id );
        return;
    }
    elsif ( $cmd eq 'usermode' ){
        delete $heap->{self}->client_privmode->{$wheel_id};
        $kernel->post( $server_session, 'reply_client', 'privmode enabled', $wheel_id );
        return;
    }

    # Get all commands
    # ================
    my @commands = sort keys $heap->{self}->client_commands;
    if ( exists $heap->{self}->client_privmode->{$wheel_id} ){
        $log->debug('[ ' . $_[SESSION]->ID(). " ] User $wheel_id is in privmode");
        for ( sort keys $heap->{self}->engine_commands ) {
            next if $_ ~~ @commands;
            push @commands, $_;
            $heap->{self}->client_commands->{$_} = $heap->{self}->engine_commands->{$_};
        }
    }

    
    # Check if use command exists.
    # Return the list of commands to user
    # if user's command is unrecognized.
    # Otherwise, perform closure to exec
    # the configured command method and pass
    # the POE variables + client's wheel_id
    # =====================================
    unless ( $cmd ~~ @commands ) {
        $output = "Commands:\n" . ( join "\n", @commands );
        $kernel->post( $server_session, 'reply_client', $output, $wheel_id );
    }
    else {
        $log->info('[ ' . $_[SESSION]->ID() . " ] Executing client ($wheel_id) command '$cmd'");
        my $ret_val = $heap->{self}->client_commands->{"$cmd"}->( $kernel, $heap, $wheel_id, $args );

        # Command alias "hook"
        # ========================
        $heap->{self}->client_commands->{"$ret_val"}->( $kernel, $heap, $wheel_id, $args )
            if ( $ret_val && $ret_val ~~ @commands );
    }

}


=head4 B<handle_default>

  Default method to capture unrecognized POE requests

=cut

sub handle_default {
    my ($event, $args) = @_[ARG0, ARG1];
    $log->logcroak(
      'Session [ ' . $_[SESSION]->ID .
      " ] caught unhandled event '$event' with " . Dumper @{$args}
    );
}



__PACKAGE__->meta->make_immutable(inline_constructor => 0);

=head1 AUTHOR

  Nuriel Shem-Tov

=cut

1;
