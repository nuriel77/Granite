package Granite::Utils::ModuleLoader;
use Module::Load;
use Moose::Role;

sub load_module {
    my $module = shift;
    my $err;

    eval { load $module };
    $err = $@;

    return $err ? $err : undef;
}

no Moose;

1;
