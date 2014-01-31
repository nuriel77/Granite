package Granite;
use warnings;
use strict;
use Granite::Engine;
use Sys::Hostname;
use Log::Log4perl qw(:easy);
use Data::Dumper;
use vars qw( $debug $log $log_config $server $host_name );

$host_name   = $ENV{GRANITE_HOSTNAME} || hostname();
$log_config  = '/home/clustervision/granite/conf/log.conf';

$SIG{INT} = \&QUIT;
$SIG{__DIE__} = sub {
    if($^S) { 
        # skip eval
        return;
    }
    $Log::Log4perl::caller_depth++;
    LOGDIE @_;
};

sub init {

    $debug = $::debug || 0;
    Log::Log4perl::init($log_config);
    $log = Log::Log4perl->get_logger(__PACKAGE__);
    Granite::Engine::init( $log, $debug );
    exit;
}

sub QUIT
{
    $log->debug('Termination signal detected...');
    print STDERR "Termination signal detected\n";
    exit 1;
}

1;
