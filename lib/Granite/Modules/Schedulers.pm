package Granite::Modules::Schedulers;
use strict;
use warnings;
use Granite::Utils::ModuleLoader;
use Moose::Role;

sub init_scheduler_module {
    my $scheduler = shift;

    if ( my $error = Granite::Utils::ModuleLoader::load_module( $scheduler ) ){ 
        # Failed to load
        return $error;
    }   

}

1;
