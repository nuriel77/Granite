package Granite::Component::Scheduler::Queue::Watcher;
use strict;
use warnings;
use POE;
use vars qw($log $debug $scheduler);

sub run {
    ( $log, $debug ) = @_[ ARG0..ARG2 ];
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    
    my $scheduler = $heap->{scheduler};

    $log->debug('[ ' . $_[SESSION]->ID() . ' ] Initializing ' . __PACKAGE__)
        if $debug;

    my $session = POE::Session->create(
        inline_states => {
            _start => sub { $kernel->post( $_[SESSION], 'next', $scheduler ) },
            next   => \&process_input,
            save   => \&save_queue_state,
        },
        heap => { scheduler => $scheduler }
    );

    $log->info('[ ' . $_[SESSION]->ID() . ' ] QueueWatcher session started with ID: [ ' . $session->ID() . ' ]');
}

sub process_input {
    my ( $heap, $kernel ) = @_[ HEAP, KERNEL ];
    my $scheduler = $heap->{scheduler};
    my ($module) = keys $scheduler;
    my $queue_data = $scheduler->{$module}->get_queue();

    if ( $queue_data ) {
        $log->info("[ " . $_[SESSION]->ID . " ] Have queue data: '$queue_data'" );
        $kernel->post( $_[SESSION], "save", $queue_data );
    }
    else {
        $log->info("[ " . $_[SESSION]->ID . " ] Queue empty.");
        $kernel->delay("_start" => 10);
    }

}

sub save_queue_state {
    $log->debug('[ ' . $_[SESSION]->ID() . ' ] Save queue data') if $debug;
    $_[KERNEL]->delay('_start' => 10);
}

1;
