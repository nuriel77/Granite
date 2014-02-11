package Granite::Modules::Cloud::OpenStack;
use Moose;
use Granite::Modules::Cloud::OpenStack::Compute;
use namespace::autoclean;

with 'Granite::Modules::Cloud';


=head1 DESCRIPTION

  Uses the subclass of Net::OpenStack::Compute

  (Granite::Modules::Cloud::OpenStack::Compute)

=head1 SYNOPSIS

  See configuration file for more details

=head2 METHOD MODIFIERS

=head4 B<around 'new'>

    Override constructor, load OpenStack subclass

=cut

around 'new' => sub {
    my $orig = shift;
    my $class = shift;
    my $self = $class->$orig(@_);

    my $compute = Granite::Modules::Cloud::OpenStack::Compute->new(
        auth_url     => $ENV{OS_AUTH_URL}               || $self->metadata->{auth_url},
        user         => $ENV{OS_USERNAME}               || $self->metadata->{user},
        password     => $ENV{OS_PASSWORD}               || $self->metadata->{password},
        project_id   => $ENV{OS_TENANT_NAME}            || $self->metadata->{project_id},
        # Optional:
        region       => $ENV{NOVA_REGION_NAME}          || $self->metadata->{region},
        service_name => $ENV{NOVA_SERVICE_NAME}         || $self->metadata->{service_name},
        is_rax_auth  => $ENV{NOVA_RAX_AUTH}             || $self->metadata->{rax_auth},
        verify_ssl   => $self->metadata->{verify_ssl}   || 0,
    ) or Granite->log->logcroack('Cannot Net::OpenStack::Compute->new: ' . $!);

    $self->compute ( $compute );
    return $self;
};

=head2 METHODS

=head4 B<get_all_instances>

  Same as nova list

=cut

sub get_all_instances { shift->compute->get_servers(detail => 1) }


=head4 B<get_all_hypervisors>

  Get hypervisors and their details

=cut

sub get_all_hypervisors { shift->compute->get_hypervisors(detail => 1) }


=head4 B<boot_instance>

  Boot an instance

=cut

sub boot_instance { shift->compute->create_server(shift) }

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

=head1 AUTHOR

Nuriel Shem-Tov

=cut

1;
