package Granite::Utils::ConfigLoader;
use strict;
use warnings;
use YAML::Tiny;
use Carp 'confess';

sub load_app_config {
    my $file = shift;

    if ( not -e $file ){
        confess "Config file '$file' not found\n";
    }
    elsif ( not -r $file ){
        confess "Cannot read file '$file': permission denied\n";
    }

    my $config = eval { YAML::Tiny->read( $file ) };
    confess( "$@\n" ) if $@;
    return $config->[0];
}

1;

