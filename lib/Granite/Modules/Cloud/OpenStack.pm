package Granite::Modules::Cloud::OpenStack;
use strict;
use warnings;
use Net::OpenStack::Compute;
use Carp 'confess';
use Moose;
    with 'Granite::Modules::Cloud';

use namespace::autoclean;


around 'new' => sub {
    my $orig = shift;
    my $class = shift;
    my $self = $class->$orig(@_);

    my $compute = Net::OpenStack::Compute->new(
        auth_url     => $ENV{OS_AUTH_URL}               || $self->metadata->{auth_url},
        user         => $ENV{OS_USERNAME}               || $self->metadata->{user},
        password     => $ENV{OS_PASSWORD}               || $self->metadata->{password},
        project_id   => $ENV{OS_TENANT_NAME}            || $self->metadata->{project_id},
        # Optional:
        region       => $ENV{NOVA_REGION_NAME}          || $self->metadata->{region},
        service_name => $ENV{NOVA_SERVICE_NAME}         || $self->metadata->{service_name},
        is_rax_auth  => $ENV{NOVA_RAX_AUTH}             || $self->metadata->{rax_auth},
        verify_ssl   => $self->metadata->{verify_ssl}   || 0,
    ) or $Granite::log->logcroack('Cannot Net::OpenStack::Compute->new: ' . $!);


    $self->compute ( $compute );

    return $self;
};

sub get_instances {
    my $self = shift;
    return $self->compute->get_servers(detail => 1);
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);


1;
