package Granite::Utils::Debugger;
use strict;
use warnings;
use Moose::Role;

sub debug {
    my $msg = shift;
    $::debug && print STDERR $msg . "\n";
}

1;
