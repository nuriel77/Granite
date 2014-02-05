use strict;
use Test::More;
use File::Copy;
use lib './lib/Granite/ExtUtils/GenerateSSLCerts/blib/lib';

my $num_tests = $ENV{GRANITE_KEEP_KEYCERT_FILES} ? 4 : 6;

plan tests => $num_tests;

sub DEBUG { $ENV{GRANITE_DEBUG} }

BEGIN {
    my $require = './lib/Granite/ExtUtils/GenerateSSLCerts/blib/arch/auto/GenerateSSLCerts';
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
    use_ok( 'GenerateSSLCerts');
}


my $key_file = 'conf/ssl/granite.default.key';
my $cert_file = 'conf/ssl/granite.default.crt';

move ( $key_file, $key_file . '.OLD' ) if ( -f $key_file );
move ( $cert_file, $cert_file . '.OLD' ) if ( -f $cert_file );

#Usage: GenerateSSLCerts::gen_key_n_cert(key_file, cert_file, bits, serial, days)
is (
    GenerateSSLCerts::gen_key_n_cert($key_file, $cert_file, 2048, 0, (365*10)),
    0,
    'generate default Granite key and certificate'
);

ok ( -f $key_file, 'check key file exists' );
ok ( -f $cert_file, 'check certificate file exists' );

unless ( $ENV{GRANITE_KEEP_KEYCERT_FILES} ){
    ok ( unlink( $key_file ) , 'Key file removed' );
    ok ( unlink( $cert_file ), 'Certificate file removed' );
}

done_testing();
