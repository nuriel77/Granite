package Granite::Component::Scheduler::Queue::Watcher;
use strict;
use warnings;
use Data::Dumper;
use POE;
use vars qw($log $debug $scheduler $queue);

sub run {
    ( $log, $debug )      = @_[ ARG0..ARG2 ];
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];

    $scheduler            = $heap->{scheduler};

    $log->debug('[ ' . $_[SESSION]->ID() . ' ] Initializing ' . __PACKAGE__)
        if $debug;

    my $parent_session = 
        POE::Session->create
        (
            inline_states =>
            {
                _start => \&parent_start,
                _stop  => \&parent_stop,
                _child => \&parent_spawn_child,
                # TODO: Create local default handler, otherwise we kill the engine
                _default => \&Granite::Engine::handle_default,
                result => \&parent_got_result,
            },
            heap => { scheduler => $scheduler->{(keys %{$scheduler})[0]} },
            options => { trace => $Granite::trace, debug => $debug },
        ) or $log->logcroak('[ ' . $_[SESSION]->ID() .  " ] can't POE::Session->create: $!" );
    
    $log->debug( '[ ' . $_[SESSION]->ID()
                . ' ] QueueWatcher session created with ID: '
                . $parent_session->ID() );
    return;
}

sub parent_start {
    $_[KERNEL]->alias_set('QueueWatcher');
    &create_child;
}

sub parent_spawn_child {
    my ($heap, $kernel, $operation, $child) = @_[HEAP, KERNEL, ARG0, ARG1];
 
    # TODO: Create main class to handle any event management
    if ($operation eq 'create' or $operation eq 'gain') {
        $heap->{child_count}++;
        $log->debug( '[ ' . $_[SESSION]->ID . ' ] Child ID [ ', $child->ID, ' ] visible to parent ID [ ',
            $_[SESSION]->ID, ' ] (have ', $heap->{child_count},
            ' active children)'
        );
    }
    # This child is departing.  Remove it from our pool count; if we
    # have fewer children than $child_max, then spawn a new one to take
    # the departing child's place.
    elsif ($operation eq 'lose') {
        $heap->{child_count}--;
        $log->debug( '[ ' . $_[SESSION]->ID . ' ] Child ID [ ', $child->ID, ' ] left parent ID [ ',
            $_[SESSION]->ID, ' ] (have ', $heap->{child_count},
            ' active children)'
        );
        if ($heap->{child_count} < $child_max) {
            $log->debug( '[ ' . $_[SESSION]->ID . ' ] Spawning a new child session in '
                        . $heap->{scheduler}->{metadata}->{reservation_flush_interval}
                        . ' seconds');
            $kernel->delay('_start' => $heap->{scheduler}->{metadata}->{reservation_flush_interval} || 10 );
        }
    }
}

sub create_child {

    my $session = POE::Session->create
    (
        inline_states => 
        {
            _start => sub
            {
                $_[KERNEL]->alias_set("QueueWatcher child");
                $_[HEAP]->{parent} = $_[SENDER];
                $_[KERNEL]->yield( 'next', $scheduler )
            },
            next   => \&child_process_input,
        },
        heap => { scheduler => $_[HEAP]->{scheduler} },
        options => { trace => $Granite::trace, debug => $debug },
    ) or $log->logdie('[ ' . $_[SESSION]->ID() .  " ] can't POE::Session->create: $!" );

    $log->debug('[ ' . $_[SESSION]->ID() . ' ] Child session started with ID: [ ' . $session->ID() . ' ]');

}

sub parent_got_result {
    my ($kernel, $session, $heap) = @_[KERNEL, SESSION, HEAP];
    my ( $sessionId, $data ) = @_[ ARG0, ARG1 ];

    $log->debug('[ ' . $_[SESSION]->ID()
                . ' ] Save queue data from child ID [ '
                . $sessionId . ' ]' )
        if $debug;

    # Save data, or pass back to engine
    # =================================
    $heap->{scheduler}->{queue} = { by => $sessionId, data => $data };

    # Get jobs from the reservation queue only
    # ========================================
    my $reservation_queue = $heap->{scheduler}->{metadata}->{reservation_queue};
    my @in_reservation_queue = grep { $_->{partition} eq $reservation_queue } @{$data};

    # Post to parent queue event listener
    # ===================================
    my $qparent_session = $_[KERNEL]->alias_resolve('QueueParent');
    $_[KERNEL]->post( $qparent_session , 'process_new_queue_data', \@in_reservation_queue );
 
}

sub child_process_input {
    my ( $heap, $kernel, $sender ) = @_[ HEAP, KERNEL, SENDER ];
    my $scheduler = $heap->{scheduler};
    my $queue_data = $scheduler->get_queue();

    if ( ref $queue_data eq 'ARRAY' && @{$queue_data} > 0 ) {
        $log->debug('[ ' . $_[SESSION]->ID . ' ] Have ' . scalar @{$queue_data}
                   . ' jobs(s) from all queues. Posting to parent. Child terminating.');
        $_[KERNEL]->alias_remove("QueueWatcher child");
        $kernel->post($heap->{parent}, 'result', $_[SESSION]->ID(), $queue_data);
    }
    else {
        $log->info("[ " . $_[SESSION]->ID . " ] Queue empty.");
    }

}

1;
