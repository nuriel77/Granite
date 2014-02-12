package Granite::Modules::Resources::Filters;
use Moose::Role;

has input => (
    is => 'ro',
    isa => 'HashRef',
    required => 1,
);

requires 'run';

no Moose;

1;
