package Granite::Component::Resources;
use Moose;
use Sys::Info;
with 'Granite::Component::Resources::CPU';
use Data::Dumper;

=head1 DESCRIPTION

  Cloud scheduler on demand resource manager

=head1 SYNOPSIS

  use Granite::Component::Resourcs;
  my $rsm = Granite::Component::Resources->new( cloud => $cloud_api );
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

=item * resources
=cut

has resources => (
	is => 'rw',
	isa => 'HashRef',
	clearer => '_unset_resources',
	default => sub {
		{
			cores => 0,
			memory => 0,
		}
	}
);

=back

=head1 METHODS

=head4 B<get_cloud_resources>

  Example return ArrayRef from cloud:
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

  Example return from CPU info:
  

=cut

	
sub get_cloud_resources {
    my $self = shift;
    my $cloud_resources = $self->cloud->get_all_hypervisors;
    my $resources = {};
	
	my $totals = {
		cores => 0,
		memory => 0,
	};

	# TODO: Open new POE Session here (new pid) to be async
	# Todo: skip hypervisor types not specified in config
	for my $resource ( @{$cloud_resources} ){
		$resources->{$resource->{id}} = {
			cloud_data	=> $resource,
			name		=> $resource->{hypervisor_hostname},
		};
		$self->resources->{memory} += $resource->{free_ram_mb} || 0; 
		if ( ! _is_remote($resource->{hypervisor_hostname}) ) {
	    	my $cpu_info = get_cpuinfo( Sys::Info->new() );
			my $cores_per_socket = ($cpu_info->identify)[0]->{number_of_cores};
			my $sockets = $cpu_info->count / $cores_per_socket;
			my $arch = ($cpu_info->identify)[0]->{architecture};

			$Granite::log->debug($resource->{hypervisor_hostname} . ' has '
							   . ( $cores_per_socket * $sockets ) . ' cores' );

			$self->resources->{cores} += ($cores_per_socket * $sockets);
			
			# Mask the cores starting with index 1
			# ====================================
			my @ns = map { 2 ** $_ } 0 .. ( $cores_per_socket * $sockets ) - 1;
			my $mask_sum = unpack "%123d*" , pack( "d*", @ns);

			$Granite::log->debug( $resource->{hypervisor_hostname} . " has: "
								. ( join "+", @ns ) . ", sum: " . $mask_sum );
			
	    	$resources->{$resource->{id}}->{cpu} = {
	    		name		=> scalar($cpu_info->identify)  || 'N/A',
	    		speed		=> $cpu_info->speed 			|| 'N/A',
	    		cores		=> $cores_per_socket,
	    		sockets 	=> $sockets,
	    		load		=> $cpu_info->load,
	    		arch		=> $arch						|| 'N/A',
	    		total_cores	=> $cores_per_socket * $sockets,
	    		mask		=> $mask_sum,
	    		alloc_mask	=> undef, 
	    	};
	    	$resources->{$resource->{id}}->{updated} = time();
	    	$self->resources->{hypervisors}->{$resource->{id}} = $resources->{$resource->{id}};
		}
	}

	warn Dumper $self->resources;
}

# temp method, later to create class
sub _is_remote {
	return undef;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

=head1 AUTHOR

  Nuriel Shem-Tov

=cut


1;
