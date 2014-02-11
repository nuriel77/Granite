package Granite::Component::Resources::CPU;
use Moose::Role;
use Sys::Info::Constants qw( :device_cpu );

=head1 DESCRIPTION

Returns local CPU resources
  
=head1 SYNOPSIS

See L<Granite::Component::Resources>

=head1 METHODS

=head4 get_cpuinfo( Sys::Info->new() )

See L<Sys::Info::Device::CPU|http://search.cpan.org/~burak/Sys-Info-Base-0.7802/lib/Sys/Info/Device/CPU.pm>

=cut

sub get_cpuinfo {
	my ($sysinfo, $args) = @_;
	$args->{cache} = 1;
	$sysinfo->device( 'CPU', %{$args} );
}

=head1 AUTHOR

  Nuriel Shem-Tov
  
=cut

no Moose;
1;

