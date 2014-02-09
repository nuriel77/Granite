package Granite::Modules::Cloud;
use Moose::Role;

=head1 DESCRIPTION

  This package provides an interface for Cloud modules.

  The default module is currently OpenStack

=head1 SYNOPSIS

  use Moose;
  with 'Granite::Modules::Cloud'

=head1 ATTRIBUTES

  B<cloud>

  B<compute>

  B<metadata>

=cut

has cloud       => ( is => 'rw', isa => 'Object' );
has compute     => ( is => 'rw', isa => 'Object' );
has metadata    => ( is => 'rw', isa => 'HashRef' );

=head1 REQUIRES

  B<get_all_instances>
  B<get_all_hypervisors>

=cut

requires 'get_all_instances';
requires 'get_all_hypervisors';
requires 'boot_instance';

no Moose;

1;

