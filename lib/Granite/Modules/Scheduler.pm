package Granite::Modules::Scheduler;
use Moose::Role;

has 'name'      => ( is => 'ro', isa => 'Str', required => 1);
has 'metadata'  => ( is => 'ro', isa => 'HashRef' );
has 'scheduler' => ( is => 'rw', isa => 'Object' );
has 'hook'      => ( is => 'ro', isa => 'Any', predicate => '_has_hook' );

requires 'get_queue';
requires 'get_nodes';

no Moose;

1;
