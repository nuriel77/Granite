#!/usr/bin/perl
use warnings;
use strict;

for ( glob('t/*.t') ){
   print "-------------> Running test file '$_'\n";
   do $_;
   print "\n";
}
