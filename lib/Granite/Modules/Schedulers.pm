package Granite::Modules::Schedulers;
use strict;
use warnings;
use Granite::Utils::ModuleLoader;

sub init_scheduler_module {
    my $scheduler = $_[1];

    if ( my $error = Granite::Utils::ModuleLoader::load_module( $scheduler ) ){ 
        # Failed to load
        return $error;
    }   

}

1;
