package Granite::Component::ResourceManager;
use Moose;
use Data::Dumper;

=head1 DESCRIPTION

  Cloud resource manager

=head1 SYNOPSIS

  use Granite::Component::ResourceManager;
  my $rsm = Granite::Component::ResourceManager->new( cloud => $cloud_api );
  my $resources = $rsm->get_cloud_resources();
  ...

=head1 ATTRIBUTES

=over

=item * cloud
=cut

has cloud => (
    is => 'ro',
    isa => 'Object',
    required => 1,
);

=back

=head1 METHODS

=head4 B<get_cloud_resources>

  Example return ArrayRef:
  [
     {
        'hypervisor_version' => 1,
        'memory_mb' => 32159,
        'free_disk_gb' => 45,
        'vcpus_used' => 0,
        'free_ram_mb' => 31647,
        'local_gb' => 45,
        'disk_available_least' => 39,
        'local_gb_used' => 0,
        'memory_mb_used' => 512,
        'id' => 4,
        'running_vms' => 0,
        'vcpus' => 1,
        'current_workload' => 0,
        'hypervisor_hostname' => 'nova.clustervision.com',
        'cpu_info' => '?',
        'service' => {
                       'id' => 5,
                       'host' => 'nova'
                     },
        'hypervisor_type' => 'docker'
     }
  ];

=cut

sub get_cloud_resources {
    my $self = shift;
    my $resources = $self->cloud->get_all_hypervisors;

    my $ret_val = {
        vcpu => 0,
        free_ram_mb => 0,
    };

    for my $resouce ( @{$resources} ){
        next unless $resouce->{hypervisor_type} eq $self->cloud->{metadata}->{hypervisor_type};
        next if $resouce->{free_ram_mb} < ( $Granite::cfg->{main}->{min_allowable_hypervisor_ram} || 128 );
        $ret_val->{vcpu} += $resouce->{vcpus};
        $ret_val->{free_ram_mb} += $resouce->{free_ram_mb};
    }
    warn Dumper $ret_val;
    return $ret_val;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

=head1 AUTHOR

  Nuriel Shem-Tov

=cut


1;
