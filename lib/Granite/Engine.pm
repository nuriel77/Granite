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

sub init {
    ( $log, $debug ) = @_;

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

    &_init_modules();

    # Start main session
    POE::Session->create(
        inline_states => {
            _start       => \&_init_components,
            init_server  => \&Granite::Component::Server::run,
            watch_queue  => \&Granite::Component::Scheduler::QueueWatcher::run,
            _stop        => \&_terminate,
        }
    );

    $log->info('Starting up engine');

    $poe_kernel->run();


}

sub _init_components {
    my ($heap, $kernel) = @_[ HEAP, KERNEL ];

    # Queue watcher
    $log->debug('Initializing Granite::Component::QueueWatcher');
    $kernel->yield("watch_queue");

    # Server
    unless ( $ENV{GRANITE_NO_TCP} ) {
        $log->debug('Initializing Granite::Component::Server');
        $kernel->yield("init_server", $log, $debug );
    }

}

sub _init_modules {

    my $scheduler_name = $CONF::cfg->{modules}->{scheduler};

    if ( my $error = init_scheduler_module ( $scheduler_name ) ) {
        $log->logcroak("Failed to load dynamic module '" . $scheduler_name . "': $error" );
    }
    else {
        $log->debug("Loaded module '" . $scheduler_name . "'");
    }

}

sub _terminate {
    my ($heap, $kernel) = @_[ HEAP, KERNEL ];
    $log->debug('Terminating...');
    delete $heap->{server};
    Granite->QUIT;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;
