package Granite::Modules::Cloud;
use Moose::Role;

has cloud       => ( is => 'rw', isa => 'Object' );
has compute     => ( is => 'rw', isa => 'Object' );
has metadata    => ( is => 'rw', isa => 'HashRef' );

requires 'get_instances';

no Moose;

1;

