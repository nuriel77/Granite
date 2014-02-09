package Granite::Utils::ModuleLoader;
use Module::Load;
use Moose::Role;

=head1 DESCRIPTION

  Module loader

=head1 SYNOPSIS

  load_module($package_name)

=head1 METHODS

=head2 B<load_module>

  Load a perl package or return the error

=cut

sub load_module {
    my $package = shift;
    eval { load $package };
    return $@ ? $@ : undef;

}

no Moose;

1;
