package Granite::Component::Scheduler::Queue;
use Moose;
use JSON::XS;
use POE::Session::YieldCC;
use POE::XS::Queue::Array;
use Granite::Component::Scheduler::Job;
use Data::Dumper;
use vars qw($log $debug $scheduler $pqa %job_queue);

before 'new' => sub {
    my $cache_dir = $Granite::cfg->{main}->{cache_dir};
    if ( ! $cache_dir ){
        $Granite::log->logcroak('Cannot find cache_dir in configuration file');
    }
    elsif ( ! -w $cache_dir ){
        $Granite::log->logcroak("No write permissions on cache directory '$cache_dir'")
    }
    $pqa = POE::XS::Queue::Array->new();
};

sub _compare_jobs { "\L$_[0]" cmp "\L$_[1]" }


sub init {
    my ( $kernel, $heap, $log, $debug ) = @_[KERNEL, HEAP, ARG0,ARG1 ];
    $log->debug('[ ' . $_[SESSION]->ID . ' ] Initializing Granite queue');
    POE::Session::YieldCC->create(
        inline_states => {
            _start => sub {
                $_[KERNEL]->alias_set('QueueParent');
                $log->debug('[ ' . $_[SESSION]->ID . ' ] At POE::Session::YieldCC');
                $_[KERNEL]->yield('event_listener');
            },
            event_listener  => \&_wait_for_event,
            process_queue   => \&_process_queue,
        }
    )
}

sub _wait_for_event {
    $Granite::log->debug('[ ' . $_[SESSION]->ID . ' ] Listening for new events');
    my ( $ok, $args ) = $_[SESSION]->wait('process_new_queue_data');
    if ( $ok ){
        $Granite::log->info('[ ' . $_[SESSION]->ID . " ] 'process_new_queue_data' event triggered");
        $_[KERNEL]->post($_[SESSION], 'process_queue', $args);
    }
    else {
        $Granite::log->error('[ ' . $_[SESSION]->ID
                            . " ] 'process_new_queue_data' event"
                            . ' triggered with unknown failure!');
        $_[KERNEL]->delay('event_listener' => 2);
    }
}

sub _process_queue {
    my ( $heap, $kernel, $args ) = @_[ HEAP, KERNEL, ARG0 ];
    ( $log, $debug ) = ( $Granite::log, $Granite::debug );

    $log->debug('[ ' . $_[SESSION]->ID . ' ] At process_queue' )
        if $debug;

    # Get all items in active queue
    # compare to items from the scheduler's
    # reservation queue and skip if already enqueued
    my @_queue = $pqa->peek_items( sub { 1; } );
    _enqueue(\@_queue, $args);
    $log->debug('Have ' . $pqa->get_item_count() . ' job(s) in active queue');
    $_[KERNEL]->delay('event_listener' => 0.3);

}

sub _enqueue {
    my ( $queue, $data ) = @_;
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
            }
        }
        else {
            $Granite::log->info('Not enqueueing jobId ' . $job->{job_id} . ': Already in active queue');
        }
    }
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;
