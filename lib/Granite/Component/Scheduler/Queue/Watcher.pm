package Granite::Component::Scheduler::Queue::Watcher;
use strict;
use warnings;
use POE;
use vars qw($log $debug $scheduler);

sub run {
    ( $log, $debug, $scheduler ) = @_[ ARG0..ARG2 ];

    $log->debug('Initializing ' . __PACKAGE__) if $debug;

    POE::Session->create(
        inline_states => {
            _start        => sub { 
                $_[KERNEL]->post( $_[SESSION], 'next', $scheduler );
            },
            next => \&process_input,
            save => \&save_queue_state,
        }
    );

    $log->info('QueueWatcher session started <' . $_[SESSION]->ID . '>');
}

sub process_input {
    my $scheduler = $_[ARG0];
    my ($module) = keys $scheduler;
    my $queue_data = $scheduler->{$module}->get_queue();

    if ( $queue_data ) {
        $log->info("<" . $_[SESSION]->ID . "> Have queue data: '$queue_data'" ) if $debug;
        $_[KERNEL]->post( $_[SESSION], "save", $queue_data );
    }
    else {
        $log->info("<" . $_[SESSION]->ID . "> Queue empty.");
        $_[KERNEL]->delay("_start" => 10);
    }

}

sub save_queue_state {
    $log->debug('Save queue data') if $debug;
    $_[KERNEL]->delay("_start" => 10);
}

1;
