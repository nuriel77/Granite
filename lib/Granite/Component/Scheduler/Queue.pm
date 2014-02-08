package Granite::Component::Scheduler::Queue;
use POE;
use POE::XS::Queue::Array;
use vars qw($log $debug $scheduler $pqa);
use Moose;

our $child_max = 1;

before 'new' => sub {
    $pqa = POE::XS::Queue::Array->new();
};


sub process_queue {
    my ( $self, $heap, $sessionId ) = @_;
    ( $log, $debug ) = ( $Granite::log, $Granite::debug );

    my $scheduler         = $heap->{scheduler}->{(keys %{$heap->{scheduler}})[0]};

    $log->debug('[ ' . $sessionId . ' ] Entered ' . __PACKAGE__
                . '::process_queue from caller ID [ ' . $scheduler->{queue}->{by} . ' ]' )
        if $debug;

    my @_queue = $pqa->peek_items( sub { 1; } );
    _enqueue(\@_queue, $scheduler->{queue}->{data});

    $log->debug('Have ' . $pqa->get_item_count() . ' job(s) in active queue');

    #for my $job ( @{$scheduler->{queue}->{data}} ){
    #    POE::Session->create
    #    (
    #       inline_states =>
    #        {
    #            _start => sub { $_[KERNEL]->yield('next') },
    #            next => sub { warn "At next from " . $_[SESSION]->ID() },
    #            _stop => sub { warn "Done : " . $_[SESSION]->ID() }
    #        },
    #    ) or $log->logcluck('[ ' . $_[SESSION]->ID() .  " ] can't POE::Session->create: $!" );
    #}
}

sub _enqueue {
    my ( $queue, $data ) = @_;
    for my $job ( @{$data} ) {
        $pqa->enqueue($job->{priority}, $job)
            unless grep { $_->[2]->{job_id} == $job->{job_id} } @{$queue};
    }
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;
