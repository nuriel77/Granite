package Granite::Modules::Cloud::OpenStack::Compute;
use Moose;
use Carp;
use HTTP::Request;
use JSON qw(from_json to_json);
use LWP;

extends 'Net::OpenStack::Compute';

=head1 DESCRIPTION

Subclass of Net::OpenStack::Compute

=head1 SYNOPSIS

See http://search.cpan.org/~ironcamel/Net-OpenStack-Compute-1.1002/lib/Net/OpenStack/Compute.pm

=head1 METHODS

=head2 get_hypervisors

Get all hypervisors with details

=cut

sub get_hypervisors {
    my ($self, $param) = @_;
    my $res = $self->_get($self->_build_url("/os-hypervisors", $param));
    return from_json($res->content)->{'hypervisors'};
}

=head2 _build_url

Helper function to construct a generic URL

=cut

sub _build_url {
    my ($self, $path, $action) = @_;
    my $url = $self->base_url . $path;
    $url .= '/' . $action if $action;
    return $url;
}


__PACKAGE__->meta->make_immutable;

1;
