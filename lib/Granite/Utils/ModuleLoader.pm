package Granite::Utils::ModuleLoader;
use strict;
use warnings;
use Module::Load;
use Moose::Role;

sub load_module {
    my $modules = shift;

    my $err;

    if ( ref $modules eq 'ARRAY' ){
        eval { load $modules->[0], $modules->[1] };
        $err = $@;
    }
    else {
        eval { load $modules };
        $err = $@;
    }

    return $err ? $err : undef;
}

no Moose;

1;




