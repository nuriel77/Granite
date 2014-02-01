package Granite::Modules::Scheduler;
use strict;
use warnings;
use Moose::Role;

has 'name'      => ( is => 'ro', isa => 'Str', required => 1);
has 'metadata'  => ( is => 'ro', isa => 'HashRef' );
has 'scheduler' => ( is => 'rw', isa => 'Object' );

requires 'get_queue';
requires 'get_nodes';

no Moose;

1;
