package Granite::Component::Scheduler::QueueWatcher;
use strict;
use warnings;
use POE;
use vars qw($log $debug $scheduler);

sub run {
    ( $log, $debug, $scheduler ) = @_[ ARG0..ARG2 ];

    $log->debug('Initializing Granite::Component::QueueWatcher');

    POE::Session->create(
        inline_states => {
            _start        => sub { 
                $_[KERNEL]->post( $_[SESSION], 'next', $scheduler );
            },
            next => \&process_input,
            save => \&save_queue_state,
        }
    );

    $log->debug('QueueWatcher session started [' . $_[SESSION]->ID . ']');
}

sub process_input {
    my $scheduler = $_[ARG0];
    my ($module) = keys $scheduler;
    my $queue_data = $scheduler->{$module}->get_queue();

    $log->debug("<" . $_[SESSION]->ID . "> Have queue data: '$queue_data'");
    $_[KERNEL]->post( $_[SESSION], "save",  $queue_data);

}

sub save_queue_state {
    $log->debug('Save queue data');
    $_[KERNEL]->delay("_start" => 10);
}

1;
