package Granite::Component::Scheduler::Nodes;
use Moose;

has scheduler => ( is => 'ro', isa => 'HashRef', required => 1, default => sub {{}} );
has logger    => ( is => 'ro', isa => 'Object', required => 1 );
has debug     => ( is => 'ro', isa => 'Bool' );

sub list_nodes {
    my $self = shift;
    my $scheduler_object = $self->scheduler;
    my $scheduler = $scheduler_object->{(keys %{$scheduler_object} )[0]};
    $self->logger->debug('Getting scheduler node list');
    return $scheduler->get_nodes();
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;
