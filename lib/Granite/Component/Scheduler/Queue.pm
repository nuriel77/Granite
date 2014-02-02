package Granite::Component::Scheduler::Queue;
use strict;
use warnings;
use Data::Dumper::Concise;
use POE;
use vars qw($log $debug $scheduler $queue);

our $child_max = 1;

sub process_queue {
    ( $log, $debug )      = ( $Granite::log, $Granite::debug );
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    my $scheduler         = $heap->{scheduler}->{(keys %{$heap->{scheduler}})[0]};

    $log->debug('[ ' . $_[SESSION]->ID() . ' ] Entered ' . __PACKAGE__
                . '::process_queue from caller ID [ ' . $scheduler->{queue}->{by} . ' ]' )
        if $debug;

    for my $job ( @{$scheduler->{queue}->{data}} ){
        POE::Session->create
        (
            inline_states =>
            {
                _start => sub { $_[KERNEL]->yield('next') },
                next => sub { warn "At next from " . $_[SESSION]->ID() },
                _stop => sub { warn "Done : " . $_[SESSION]->ID() }
            },
        );
    }

}

1;
