package Granite::Engine;
use strict;
use warnings;
use Granite::Engine::Daemonize;
use Granite::Component::Server;
use Granite::Modules::Schedulers;
use Granite::Component::Scheduler::QueueWatcher;
use Cwd 'getcwd';
use POE;
use Moose;
    with 'Granite::Modules::Schedulers', 'Granite::Engine::Logger';

use namespace::autoclean;
use vars qw($log $debug);

has scheduler => ( is => 'rw', isa => 'HashRef', default => sub {{}} );
has debug     => ( is => 'ro', isa => 'Bool' );
has logger    => ( is => 'ro', isa => 'Object', required => 1 );

sub init {
    my $self = shift;
    ( $log, $debug ) = ($self->logger, $self->debug);

    set_logger_stdout($log) if $debug;
    $log->debug('At Granite::Engine::init');

    if ( !$ENV{GRANITE_FOREGROUND} && $CONF::cfg->{main}->{daemonize} ){
        # Daemonize
        my $daemon = Granite::Engine::Daemonize->new(
            logger   => $log,
            workdir  => $ENV{GRANITE_WORK_DIR} || getcwd(),
            pid_file => $ENV{GRANITE_PID_FILE}
                || $CONF::cfg->{main}->{pid_file}
                || '/var/run/granite/granite.pid'
        );
    }

    $self->_init_modules();

    # Start main session
    POE::Session->create(
        inline_states => {
            _start       => sub {
                my ($heap, $kernel) = @_[ HEAP, KERNEL ];

                # Queue watcher
                $kernel->yield("watch_queue", $log, $debug, $self->scheduler );

                # Server
                unless ( $ENV{GRANITE_NO_TCP} ) {
                    $log->debug('Initializing Granite::Component::Server');
                    $kernel->yield("init_server", $log, $debug );
                }
            },
            init_server  => \&Granite::Component::Server::run,
            watch_queue  => \&Granite::Component::Scheduler::QueueWatcher::run,
            _stop        => \&_terminate,
        }
    );

    $log->info('Starting up engine');
    $poe_kernel->run();

}

sub _terminate {
    my ($heap, $kernel) = @_[ HEAP, KERNEL ];
    $log->debug('Terminating...');
    delete $heap->{server};
    Granite->QUIT;
}

sub _init_modules {
    my $self = shift;

    my $scheduler = $CONF::cfg->{modules}->{scheduler};
    if ( my $error = init_scheduler_module ( $scheduler ) ) {
        $log->logcroak("Failed to load dynamic module '" . $scheduler . "': $error" );
    }
    else {
        $self->scheduler->{$scheduler} = $scheduler->new( name => $scheduler );
        $log->debug("Loaded module '" . $scheduler . "'");
    }

}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;
