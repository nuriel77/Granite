package Granite::Modules::Cloud;
use Moose::Role;

has cloud       => ( is => 'rw', isa => 'Object' );
has compute     => ( is => 'rw', isa => 'Object' );
has metadata    => ( is => 'rw', isa => 'HashRef' );

requires 'get_all_instances';
requires 'get_all_hypervisors';
requires 'get_resouces_stats';

no Moose;

1;

