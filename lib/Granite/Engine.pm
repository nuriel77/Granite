package Granite::Engine;
use strict;
use warnings;
use Granite::Engine::Daemonize;
use Granite::Component::Server;
use Granite::Component::Scheduler::Queue;
use Granite::Component::Scheduler::Nodes;
use Granite::Component::Scheduler::Queue::Watcher;
use Cwd 'getcwd';
use POE;
use Data::Dumper::Concise;
use Moose;
    with 'Granite::Engine::Logger',
         'Granite::Utils::ModuleLoader';

use namespace::autoclean;
use vars qw($log $debug $daemon);

has modules   => ( is => 'rw', isa => 'HashRef', default => sub {{}} );
has debug     => ( is => 'ro', isa => 'Bool' );
has logger    => ( is => 'ro', isa => 'Object', required => 1 );

sub run {
    my $self = shift;
    ( $log, $debug ) = ($self->logger, $self->debug);

    if ( !$ENV{GRANITE_FOREGROUND} && $Granite::cfg->{main}->{daemonize} ){
        # Daemonize
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
        set_logger_stdout($log) if $debug;
    }

    $self->_init;
}

sub _init {
    my $self = shift;

    $log->debug('At Granite::Engine::init') if $debug;

    # Load modules
    $self->_init_modules();

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
                unless ( $ENV{GRANITE_NO_TCP} or $Granite::cfg->{server}->{disable} ){
                    $kernel->yield("init_server", $log, $debug );
                }

            },
            _child          => \&child_sessions,
            init_server     => \&Granite::Component::Server::run,
            process_res_q   => \&Granite::Component::Scheduler::Queue::process_queue,
            watch_queue     => \&Granite::Component::Scheduler::Queue::Watcher::run,
            _default        => \&handle_default,
            _stop           => \&terminate,
        },
        heap => { scheduler => $self->modules->{scheduler} }
    );

    $poe_kernel->run();

}

sub _terminate {
    my ($heap, $kernel, $sender, $session ) = @_[ HEAP, KERNEL, SENDER, SESSION ];
    $log->info('[ ' . $session->ID() . '] Terminating...(caller: ' . $sender . ')');
    delete $heap->{server};
    unlink $Granite::cfg->{server}->{unix_socket}
        if -e $Granite::cfg->{server}->{unix_socket};
    $kernel->stop();
    Granite->QUIT;
}

sub _init_modules {
    my $self = shift;

#modules:
#  scheduler:
#    name: Slurm
#    meta:
#      - '/opt/slurm/etc/slurm.conf'

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
}

sub child_sessions {
    my ($heap, $kernel, $operation, $child) = @_[HEAP, KERNEL, ARG0, ARG1];
    if ($operation eq 'create' or $operation eq 'gain') {
        $heap->{child_count}++;
    }
    elsif ($operation eq 'lose') {
        $heap->{child_count}--;
    }
}

sub handle_default {
    my ($event, $args) = @_[ARG0, ARG1];
    $log->logdie(
      "Session ", $_[SESSION]->ID,
      " caught unhandled event $event with (@$args).\n"
    );
}

=comment
#
#   Temporarily here:
#
sub _get_node_list {

    my $scheduler_nodes =
        Granite::Component::Scheduler::Nodes->new(
            scheduler => $_[HEAP]->{scheduler},
            logger => $log,
            debug => $debug );

    my $node_array = $scheduler_nodes->list_nodes;
    my @visible_nodes = grep defined, @{$node_array};

    if ( $debug ){
        $log->debug( '[ ' . $_[SESSION]->ID() . ' ] Defined Node: ' . Dumper $_ ) for @visible_nodes;
    }

    $log->debug( '[ ' . $_[SESSION]->ID() . ' ] Number of visible scheduler nodes: ' . scalar @visible_nodes );
}

=cut

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;
