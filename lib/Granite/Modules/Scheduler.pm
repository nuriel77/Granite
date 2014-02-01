package Granite::Modules::Scheduler;
use strict;
use warnings;
use Moose::Role;

has 'name'     => (is => 'ro', isa => 'Str', required => 1);
has 'metadata' => (is => 'ro', isa => 'HashRef' );

requires 'get_queue';

no Moose;

1;
