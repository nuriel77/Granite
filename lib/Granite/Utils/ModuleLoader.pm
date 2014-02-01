package Granite::Utils::ModuleLoader;
use Module::Load;
use Moose::Role;

sub load_module {
    my $package = shift;
    my $err;

    eval {
        load $package;
        $package->import();
    };
    $err = $@;
    return $err ? $err : undef;
}

no Moose;

1;
