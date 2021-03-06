package Granite::Component::Resources;
use Moose;
with 'Granite::Utils::ModuleLoader';
use Try::Tiny;
use namespace::autoclean;
use Data::Dumper;

=head1 DESCRIPTION

  Cloud scheduler on demand resource manager

=head1 SYNOPSIS

  use Granite::Component::Resourcs;
  my $rsm = Granite::Component::Resources->new( cloud => $cloud_api );
  my $resources = $rsm->get_cloud_resources();
  ...

=head1 TRAITS

  Use traits namespace to load package roles
  
=cut 

with 'MooseX::Traits';
has '+_trait_namespace' => (
    default => sub {
        my ( $P, $SP ) = __PACKAGE__ =~ /^(\w+)::(.*)$/;
        return $P . '::TraitFor::' . $SP;
    }
);

=head1 ATTRIBUTES

=over

=item * L<roles>
=cut

has roles => (
    is => 'ro',
    isa => 'Object',
    writer => '_set_roles',
    predicate => '_has_roles',    
);

=item * L<resources>
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
        'hypervisor_hostname' => 'localhost',
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
    my $cloud_resources = Granite::Engine->cloud->get_all_hypervisors;
    #my $scheduler_nodes = Granite::Engine::Controller->get_scheduler_nodes;
    #warn Dumper $scheduler_nodes;
    my $resources = {};

    $self->_set_roles (
        $self->new_with_traits(
            traits         => [ qw( CPU Memory ) ],
        )
    ) unless $self->_has_roles;
    
    my $dbh = Granite::Engine->dbh;
	
	# Todo: skip hypervisor types not specified in config
	for my $resource ( @{$cloud_resources} ){
		$resources->{$resource->{id}} = {
			cloud_data	=> $resource,
			name		=> $resource->{hypervisor_hostname},
		};
		$self->resources->{memory} += $resource->{free_ram_mb} || 0; 
		if ( ! _is_remote($resource->{hypervisor_hostname}) ) {
	    	my $cpu_info = $self->roles->cpuinfo();
			my $cores_per_socket = ($cpu_info->identify)[0]->{number_of_cores};
			my $sockets = $cpu_info->count / $cores_per_socket;
			my $arch = ($cpu_info->identify)[0]->{architecture};

			Granite->log->debug($resource->{hypervisor_hostname} . ' has '
							   . ( $cores_per_socket * $sockets ) . ' cores' );

			$self->resources->{cores} += ($cores_per_socket * $sockets);
			
			# Mask the cores starting with index 1
			# ====================================
			my @ns = map { 2 ** $_ } 0 .. ( $cores_per_socket * $sockets ) - 1;
			my $mask_sum = unpack "%123d*" , pack( "d*", @ns);

			Granite->log->debug( $resource->{hypervisor_hostname} . " has: "
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
            $resources->{$resource->{id}}->{memory} = {
            	total_mem => $self->roles->total_mem,
            	free_mem => $self->roles->free_mem,
            	total_swap => $self->roles->total_swap,
            	free_swap => $self->roles->free_swap,
            };
            try {
                $dbh->resultset('Resource')->update_or_create({
                    id                  => $resource->{id},
                    hostname            => $resource->{hypervisor_hostname},
                    cpuload             => $cpu_info->load,
                    sockets             => $sockets,
                    cores_per_socket    => $cores_per_socket,
                    alloc_memory        => $self->roles->total_mem - $self->roles->free_mem,
                    real_memory         => $self->roles->total_mem,
                    diskspace_free      => $resource->{free_disk_gb},
                    alloc_cores         => $mask_sum,
                })
            }
            catch { Granite->log->logdie($_) };

	    	$resources->{$resource->{id}}->{updated} = time();
	    	$self->resources->{hypervisors}->{$resource->{id}} = $resources->{$resource->{id}};
		}
	}

	return $self->resources;
}

#
# Example $request:
# $request = {
#   cores   => ..., # number 0..[max_cores]
#	socket_bind => ..., # number of socket (0 or 1...) -> user can specify this if there's only socket requirement (not core)
#   affinity => ..., # typical affinity notation (3-7,1 etc...) . Affinity takes precedence over socket_bind parameter. 
#                      If user specifies socket_bind that means that if we could not satisfy affinity, we try to satisfy socket_bind
#   memory => ..., # total required memory
#   runtime => ...,
#   deadline => ...,
#   reservation => ...,
#}
sub test_request {
    my ( $self, $request ) = @_;

    #my $scheduler_nodes = Granite::Engine::Controller->get_scheduler_nodes;
    #warn Dumper $scheduler_nodes;

    return undef if !$request || ref $request ne 'HASH'; 
    
    # For module ... check if has pluggable module (filter module)
    # .... found module affinity....
    if ( my $error = load_module ('Granite::Modules::Resources::CPU::Affinity') ){
        Granite->log->logdie( "LOADER FAILURE: '$error'" );
    }
    else {
        my $filter = Granite::Modules::Resources::CPU::Affinity->new( input => $request)->run;
    }
    
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
