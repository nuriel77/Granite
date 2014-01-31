#!/usr/bin/env perl
use warnings;
use strict;
use lib 'lib';
use vars '$debug';
use Granite;

$debug = $ENV{GRANITE_DEBUG};

if ( !$ENV{GRANITE_FOREGROUND} and !$ENV{GRANITE_DEBUG} ){
    $debug && print STDERR "Forking.\n";
    fork && exit;
}

Granite::init();
