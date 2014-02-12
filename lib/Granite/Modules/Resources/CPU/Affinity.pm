package Granite::Modules::Resources::CPU::Affinity;
use Moose;
with 'Granite::Modules::Resources::Filters';

use namespace::autoclean;

use Data::Dumper;

sub run {
	my $self = shift;
	#warn Dumper $self->meta;
	$self->process_affinity_request(@_); 
}

sub process_affinity_request {
    my $self = shift;
    my $cpu_req = $self->input;

    # TODO: Assign from "somewhere"
    my $cores = 12;

    my $req = [];
    if ( $cpu_req->{cores} > $cores ){
        Granite->log("Cannot fulfill request for $cpu_req->{cores}, only $cores left");
        return undef;
    }
#    for (my $i = 0; $i < $cpu_req; $i++){
#        my $num = get_rand_num($cpu->{cores_per_socket} * $cpu->{sockets});
#       $num = get_rand_num($cpu->{cores_per_socket} * $cpu->{sockets}) while ( check_used_core($num) || check_num_exists($num) );
#       $debug && print STDERR "Adding $num to req\n";
        #my $cpu_file = 2 ** $num;
#        my $core_file = `find $cpu_dir -mindepth 2 -name $cpu_file`;
#        chomp($core_file);
#       $debug && print STDERR "Marking core file as used ($core_file)\n";
#       `echo "$instance" > $core_file`;
#        push @{$req}, $num;
#    }
}

sub check_used_core {
    my ($num, $sum) = @_;
    
    if ( $sum & ( 2 ** $num  ) ){
        Granite->log("Request core $num is OK ($sum & $num)");
        return 0;
    }
    else {
        Granite->log("Request core $num is NOT OK, skip.");
        return 1;
    }
}

sub get_rand_num { int(rand(shift)) }
#sub check_num_exists { $_[0] ~~ @{$req} }

1;