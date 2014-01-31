#!/usr/bin/env perl
use warnings;
use strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Granite;
use vars '$debug';

$debug = $ENV{GRANITE_DEBUG};
Granite::init();
