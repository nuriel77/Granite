package Granite::TraitFor::Component::Resources::Memory;
use Moose::Role;
use Sys::MemInfo qw(totalmem freemem totalswap);

no Moose;

1;