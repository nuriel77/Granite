use strict;
use Test::More;
use Cwd;
use constant MyTempLib => $ENV{GRANITE_TEMP_LIB} || './blib/lib';
use lib MyTempLib;

my $num_tests = 4;
$num_tests -= 2 if $ENV{GRANITE_KEEP_KEYCERT_FILES};

plan tests => $num_tests;

sub DEBUG { $ENV{GRANITE_DEBUG} }

BEGIN {
    my $require = $ENV{GRANITE_BLIB_DIR} || './blib/arch/auto/GenerateSSLCerts';
    my $ld = $ENV{LD_LIBRARY_PATH};
    if(  ! $ld  ){
        $ENV{LD_LIBRARY_PATH} = $require;
    } elsif(  $ld !~ m#(^|:)\Q$require\E(:|$)#  ) {
        $ENV{LD_LIBRARY_PATH} .= ':' . $require;
    } else {
        $require = '';
    }
    if(  $require  ) {
        exec 'env', $^X, $0, @ARGV;
    }
}

use_ok( 'GenerateSSLCerts');

my $key_file  = $ENV{GRANITE_NEW_KEY_FILE} || '/tmp/granite.test.key';
my $cert_file = $ENV{GRANITE_NEY_CRT_FILE} || '/tmp/granite.test.crt';

#
#Usage: GenerateSSLCerts::gen_key_n_cert(key_file, cert_file, bits, serial, days)
#
is (
    GenerateSSLCerts::gen_key_n_cert($key_file, $cert_file, 2048, 0, (365*10)),
    0,
    'generate default Granite key and certificate'
);

unless ( $ENV{GRANITE_KEEP_KEYCERT_FILES} ){
    ok ( unlink( $key_file ) , 'Key file removed' );
    ok ( unlink( $cert_file ), 'Certificate file removed' );
}

done_testing();

