package Granite::Utils::ConfigLoader;
use strict;
use warnings;
use YAML::Tiny;
use Carp 'confess';

sub load_app_config {
    my $file = $_[1];

    if ( not -e $file ){
        confess "Config file '$file' not found\n";
    }
    elsif ( not -r $file ){
        confess "Cannot read file '$file': permission denied\n";
    }

    #my $config = LoadFile( $file );
    my $config =  YAML::Tiny->read( $file );

    {
        package CONF;
        our $cfg = $config->[0];
    }
}

1;

