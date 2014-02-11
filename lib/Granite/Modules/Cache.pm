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

has name       => ( is => 'ro', isa => 'Str', required => 1 );


=item * B<metadata>
=cut

has metadata   => ( is => 'ro', isa => 'HashRef', );


=item * B<hook>
=cut

has hook   => ( is => 'ro', isa => 'HashRef', predicate => '_has_hook' );


=back

=head1 REQUIRES

  B<get_keys>

=cut

requires 'get_keys';

=head1 REQUIRES

  B<get>

=cut

requires 'get';


=head1 REQUIRES

  B<set>

=cut

requires 'set';


=head1 REQUIRES

  B<delete>

=cut

requires 'delete';


no Moose;

1;


