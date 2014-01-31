package Granite::Engine;
use strict;
use warnings;
use Granite::Component::Server;
use Granite::Component::Scheduler::QueueWatcher;
use POE;
use vars qw($log $debug);

sub init {
    ( $log, $debug ) = @_;

    $log->debug('At Granite::Engine::init');

    POE::Session->create(
        inline_states => {
            _start       => \&init_components,
            init_server  => \&Granite::Component::Server::run,
            watch_queue  => \&Granite::Component::Scheduler::QueueWatcher::run,
            _stop        => \&terminate,
        }
    );

    $log->debug('Starting up engine');
    $poe_kernel->run();
}

sub init_components {
    my ($heap, $kernel) = @_[ HEAP, KERNEL ];
    
    # Queue watcher
    $log->debug('Initializing Granite::Component::QueueWatcher');
    $kernel->yield("watch_queue");

    # Server
    unless ( $ENV{GRANITE_NO_TCP} ) {
        $log->debug('Initializing Granite::Component::Server');
        $debug && print STDOUT "Initializing Granite::Component::Server\n";
        $kernel->yield("init_server", $log, $debug );
    }    

}

sub terminate {
    my ($heap, $kernel) = @_[ HEAP, KERNEL ];
    $log->debug('Terminating...');
    exit;
}

1;


