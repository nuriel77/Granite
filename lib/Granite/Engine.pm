package Granite::Engine;
use strict;
use warnings;
use Granite::Engine::Daemonize;
use Granite::Component::Server;
use Granite::Component::Scheduler::Nodes;
use Granite::Component::Scheduler::QueueWatcher;
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

    set_logger_stdout($log) if $debug;
    $log->debug('At Granite::Engine::init') if $debug;

    if ( !$ENV{GRANITE_FOREGROUND} && $CONF::cfg->{main}->{daemonize} ){
        # Daemonize
        my $daemon = Granite::Engine::Daemonize->new(
            logger   => $log,
            debug    => $debug,
            workdir  => $ENV{GRANITE_WORK_DIR} || getcwd(),
            pid_file => $ENV{GRANITE_PID_FILE}
                || $CONF::cfg->{main}->{pid_file}
                || '/var/run/granite/granite.pid'
        );
    }

    # Load modules
    $self->_init_modules();


#
#   Temporarily here:
#
    my $scheduler_nodes =
        Granite::Component::Scheduler::Nodes->new(
            scheduler => $self->modules->{scheduler},
            logger => $log,
            debug => $debug );

    my $node_array = $scheduler_nodes->list_nodes;
    my @visible_nodes = grep defined, @{$node_array};

    if ( $debug ){
        $log->debug( "Defined Node: " . Dumper $_ ) for @visible_nodes;
    }



    # Start main session
    POE::Session->create(
        inline_states => {
            _start       => sub {
                my ($heap, $kernel) = @_[ HEAP, KERNEL ];

                # Queue watcher
                $kernel->yield("watch_queue", $log, $debug, $self->modules->{scheduler} );

                # Server
                if ( !$ENV{GRANITE_NO_TCP} && !$CONF::cfg->{server}->{disable} ){
                    $log->debug('Initializing Granite::Component::Server') if $debug;
                    $kernel->yield("init_server", $log, $debug );
                }
            },
            init_server     => \&Granite::Component::Server::run,
            watch_queue     => \&Granite::Component::Scheduler::QueueWatcher::run,
            _stop           => \&_terminate,
        }
    );

    $log->info('Starting up engine');
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

    for my $module ( keys %{$CONF::cfg->{modules}} ){
        my $package = 'Granite::Modules::' . ucfirst($module)
                    . '::' . $CONF::cfg->{modules}->{$module}->{name};
        if ( my $error = load_module( $package ) ){
            $log->logcroak("Failed to load module '" . $package . "': $error" );
        }
        else {
            $self->modules->{$module}->{$package} =
                $package->new(
                    name => $package,
                    metadata => $CONF::cfg->{modules}->{$module}->{metadata}
                );
            $log->debug("Loaded module '" . $package . "'") if $debug;
        }
    }
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;
