# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl GenerateSSLCerts.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;
use Cwd;
use lib './blib/lib';
use Test::More tests => 1;

BEGIN {
    my $require = getcwd().'/blib/arch/auto/GenerateSSLCerts';

    my $ld = $ENV{LD_LIBRARY_PATH};

    if(  ! $ld  )
    {
        $ENV{LD_LIBRARY_PATH} = $require;
    }
    elsif(  $ld !~ m#(^|:)\Q$require\E(:|$)#  )
    {
        $ENV{LD_LIBRARY_PATH} .= ':' . $require;
    }
    else
    {
        $require = '';
    }

    if(  $require  )
    {
        exec 'env', $^X, $0, @ARGV;
    }

    use_ok('GenerateSSLCerts');

}


#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

