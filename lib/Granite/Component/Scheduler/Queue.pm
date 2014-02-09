package Granite::Component::Scheduler::Queue;
use Moose;
use JSON::XS;
use POE::Session::YieldCC;
use POE::XS::Queue::Array;
use Granite::Component::Scheduler::Job;
use Data::Dumper;
use vars qw($log $debug $scheduler $pqa %job_queue $kernel);

before 'new' => sub {
    $pqa = POE::XS::Queue::Array->new();
};

sub init {
    $kernel = $_[KERNEL];
    my ( $heap, $log, $debug ) = @_[HEAP, ARG0,ARG1 ];

    my $cache_api;
    my $engine_heap = $kernel->alias_resolve('engine')->get_heap();
    if ( $engine_heap->{self}->_has_cache_obj ){
        my $cache_obj = $engine_heap->{self}->{modules}->{cache};
        $cache_api = $cache_obj->{(keys %{$cache_obj})[0]};
    }

    $log->debug('[ ' . $_[SESSION]->ID . ' ] Initializing Granite queue');

    POE::Session::YieldCC->create(
        inline_states => {
            _start => sub {
                # At this stage, override the sig INT
                # so we can shutdown nicely. Otherwise
                # Coro::State woes.
                $SIG{INT} = \&_killme,
                $_[KERNEL]->alias_set('QueueParent');
                $log->debug('[ ' . $_[SESSION]->ID . ' ] At POE::Session::YieldCC');
                $_[KERNEL]->yield('event_listener', $cache_api);
            },
            event_listener  => \&_wait_for_event,
            process_queue   => \&_process_queue,
        },
        heap => { cache => $cache_api }
    )
}

sub _killme {
    $Granite::log->warn('Termination signal detected. Shutting down gracefully...');
    my $qparent_session = $kernel->alias_resolve('QueueParent');
    if ( $qparent_session ){
        $kernel->post( $qparent_session , 'process_new_queue_data', ['shutdown'] );
    }
    else {
        $kernel->yield('_stop');
        POE::Kernel->stop;
    }
}

sub _wait_for_event {
    my $cache = $_[ARG0];

    $Granite::log->debug('[ ' . $_[SESSION]->ID . ' ] Listening for new events');
    my ( $ok, $args ) = $_[SESSION]->wait('process_new_queue_data');
    if ( $ok ){        
        $Granite::log->info('[ ' . $_[SESSION]->ID . " ] 'process_new_queue_data' event triggered");
        if ( $args->[0] eq 'shutdown' ){
            $Granite::log->info('[ ' . $_[SESSION]->ID . " ] 'shutdown' event triggered");
            my $engine = $kernel->alias_resolve('engine');
            $_[KERNEL]->post($engine, '_stop');
        }
        else {
            $_[KERNEL]->post($_[SESSION], 'process_queue', $args, $cache );
        }
    }
    else {
        $Granite::log->error('[ ' . $_[SESSION]->ID
                            . " ] 'process_new_queue_data' event"
                            . ' triggered with unknown failure!');
        $_[KERNEL]->delay('event_listener' => 2);
    }
}

sub _process_queue {
    my ( $heap, $args, $cache ) = @_[ HEAP, ARG0, ARG1 ];
    ( $log, $debug ) = ( $Granite::log, $Granite::debug );

    $log->debug('[ ' . $_[SESSION]->ID . ' ] At process_queue' )
        if $debug;

    # Get all items in active queue
    # compare to items from the scheduler's
    # reservation queue and skip if already enqueued
    my @_queue = $pqa->peek_items( sub { 1; } );

    # If pqa is empty, we search the cache backend
    # to see if any items are registered there
    # and load them into pqa active queue.
    # Items should be removed from the backend
    # when items are in state complete and
    # being dequeued from pqa.
    if ( !@_queue && defined $cache ){
        $Granite::log->debug('Reloading active queue from cache backend');
        _populate_pqa($cache);
        @_queue = $pqa->peek_items( sub { 1; } );

    }

    _enqueue(\@_queue, $args, $cache );
    $log->debug('Have ' . $pqa->get_item_count() . ' job(s) in active queue');
    $_[KERNEL]->delay('event_listener' => 0.3);

}

sub _populate_pqa {
    my $cache = shift;
    my @keys = $cache->get_keys( 'job_' );
    return unless @keys;
    if( ref $keys[0] eq 'HASH' ){
        for ( keys $keys[0] ){
            my $hash = $keys[0]->{$_};
            $Granite::log->debug('Cache backend has job key ' . $_ );
            my $job = JSON::XS->new->allow_blessed->decode( $hash );
            $pqa->enqueue($job->{priority}, $job);
        }
    }
    else {
        for ( @keys ){
            my $hash = $cache->get($_);
            next unless $hash;
            $Granite::log->debug('Cache backend has job key ' . $_ );
            my $job = JSON::XS->new->allow_blessed->decode( $hash );
            $pqa->enqueue($job->{priority}, $job);
        }
    }
}

sub _enqueue {
    my ( $queue, $data, $cache ) = @_;
    for my $job ( @{$data} ) {
        # Check if this job is already in the active queue
        unless ( grep { $_->[2]->{job_id} == $job->{job_id} } @{$queue} ){
            my $job_api = Granite::Component::Scheduler::Job->new( job => $job );
            eval { $job_api->process };
            if ( $@ ){
                $log->error( '{'.$job->{job_id}.'} Failed to enter lifecycle process: ' . $@ );
            }
            else {
                $pqa->enqueue($job->{priority}, $job);
                if ( $cache ){
                    my $enc = eval { JSON::XS->new->allow_blessed->encode( $job ) };
                    $cache->set( 'job_'.$job->{job_id} => $enc )
                        unless $@;
                    $Granite::log->error('{'.$job->{job_id}.'} Failed to write to cache backend: ' . $@ )
                        if $@;
                }
            }
        }
        else {
            $Granite::log->info('Not enqueueing jobId ' . $job->{job_id} . ': Already in active queue');
        }
    }
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;
