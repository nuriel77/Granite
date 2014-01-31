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
with 'Granite::Modules::Schedulers', 'Granite::Utils::Debugger';
use namespace::autoclean;
use vars qw($log $debug);

sub init {
    ( $log, $debug ) = @_;

    $log->debug('At Granite::Engine::init');

    unless ( $ENV{GRANITE_FOREGROUND} ){
        my $daemon = Granite::Engine::Daemonize->new(
            logger   => $log,
            workdir  => $ENV{GRANITE_WORK_DIR} || getcwd(),
            pid_file => $ENV{GRANITE_PID_FILE} || '/var/run/granite.pid'
        );
    
        # Daemonize
        $daemon->init;
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

    $log->debug('Starting up engine');

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

    my $scheduler_modules = $CONF::cfg->{modules}->{scheduler};
    my ($scheduler_name) = (keys %{$scheduler_modules})[0];
    my $packages = $CONF::cfg->{modules}->{scheduler}->{$scheduler_name};

    if ( my $error = init_scheduler_module ( $packages ) ) {
        $log->logdie("Failed to load dynamic module '" . $scheduler_name . "': $error" );
    }
    else {
        $log->debug("Loaded module '" . $scheduler_name . "'");
    }

}

sub _terminate {
    my ($heap, $kernel) = @_[ HEAP, KERNEL ];
    $log->debug('Terminating...');
    delete $heap->{server};
    debug('Terminating');    
    exit;
}

1;
