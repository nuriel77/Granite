package Granite::Engine;
use strict;
use warnings;
use Granite::Engine::Daemonize;
use Granite::Component::Server;
use Granite::Component::Scheduler::Nodes;
use Granite::Component::Scheduler::Queue::Watcher;
use Cwd 'getcwd';
use POE;
use Data::Dumper::Concise;
use Moose;
    with 'Granite::Engine::Logger',
         'Granite::Utils::ModuleLoader';

use namespace::autoclean;
use vars qw($log $debug);

has modules   => ( is => 'rw', isa => 'HashRef', default => sub {{}} );
has debug     => ( is => 'ro', isa => 'Bool' );
has logger    => ( is => 'ro', isa => 'Object', required => 1 );

sub init {
    my $self = shift;
    ( $log, $debug ) = ($self->logger, $self->debug);

    $log->debug('At Granite::Engine::init') if $debug;

    if ( !$ENV{GRANITE_FOREGROUND} && $Granite::cfg->{main}->{daemonize} ){
        # Daemonize
        my $daemon = Granite::Engine::Daemonize->new(
            logger   => $log,
            debug    => $debug,
            workdir  => $ENV{GRANITE_WORK_DIR} || getcwd(),
            pid_file => $ENV{GRANITE_PID_FILE}
                || $Granite::cfg->{main}->{pid_file}
                || '/var/run/granite/granite.pid'
        );
    }
    else {
        set_logger_stdout($log) if $debug;
    }

    # Load modules
    $self->_init_modules();

    # Start main session
    # ==================
    my $session = POE::Session->create(
        inline_states => {
            _start          => sub {
                my ($heap, $kernel) = @_[ HEAP, KERNEL ];

                # Queue watcher
                # =============
                $kernel->yield("watch_queue", $log, $debug, $self->modules->{scheduler} );

                # Server
                # ======
                if ( !$ENV{GRANITE_NO_TCP} && !$Granite::cfg->{server}->{disable} ){
                    $kernel->yield("init_server", $log, $debug );
                }
                
                $kernel->yield('list_nodes', $self->modules->{scheduler} );
            },
            init_server     => \&Granite::Component::Server::run,
            list_nodes      => \&_get_node_list,
            watch_queue     => \&Granite::Component::Scheduler::Queue::Watcher::run,
            _stop           => \&_terminate,
        }
    );

    $log->info('Starting up POE sessions. Parent ID: [ ' . $session->ID() . ' ]' );
    $poe_kernel->run();

}

sub _terminate {
    my ($heap, $kernel) = @_[ HEAP, KERNEL ];
    $log->info('Terminating...');
    delete $heap->{server};
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

#
#   Temporarily here:
#
sub _get_node_list {

    my $scheduler_nodes =
        Granite::Component::Scheduler::Nodes->new(
            #scheduler => $self->modules->{scheduler},
            scheduler => $_[ARG0],
            logger => $log,
            debug => $debug );

    my $node_array = $scheduler_nodes->list_nodes;
    my @visible_nodes = grep defined, @{$node_array};

    if ( $debug ){
        $log->debug( "Defined Node: " . Dumper $_ ) for @visible_nodes;
    }
}
__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;
