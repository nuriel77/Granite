package Granite::Modules::Cloud::OpenStack::Compute;
use Moose;
use Data::Dumper;
use Carp;
use HTTP::Request;
use JSON qw(from_json to_json);
use LWP;

extends 'Net::OpenStack::Compute';

=head1 DESCRIPTION

Subclass of Net::OpenStack::Compute

=head1 SYNOPSYS

See http://search.cpan.org/~ironcamel/Net-OpenStack-Compute-1.1002/lib/Net/OpenStack/Compute.pm

=cut

sub get_hypervisors {
    my ($self, %params) = @_;
    my $q = Net::OpenStack::Compute::_get_query(%params);
    my $param = (keys %params)[0];
    my $res = $self->_get($self->_url("/os-hypervisors", $params{$param}, $q));
    return from_json($res->content)->{'hypervisors'};
}

sub get_hypervisors_stats {
    shift->get_hypervisors(statistics => 1);
}


__PACKAGE__->meta->make_immutable;

1;
