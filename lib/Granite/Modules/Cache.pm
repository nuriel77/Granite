package Granite::Modules::Cache;
use Moose::Role;

=head1 DESCRIPTION

  This package provides an interface for Cache backends.

  The default module is currently DB_File

=head1 SYNOPSIS

  use Moose;
  with 'Granite::Modules::Cache'

=head1 ATTRIBUTES

=over

=item * B<cache>
=cut

has cache      => ( is => 'rw', isa => 'Object', predicate => '_has_cache' );


=item * B<name>
=cut

has name       => ( is => 'rw', isa => 'Str', required => 1 );


=item * B<metadata>
=cut

has metadata   => ( is => 'rw', isa => 'HashRef', );


=item * B<callback>
=cut

has callback   => ( is => 'rw', isa => 'Any', );


=back

=head1 REQUIRES

#B<get_all_instances>

=cut

requires 'get_keys';

no Moose;

1;


