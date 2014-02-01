package Granite;
use warnings;
use strict;
use Sys::Hostname;
use Carp 'confess';
use Log::Log4perl qw(:easy);
use Granite::Engine;
use Granite::Utils::ConfigLoader;
use vars qw( $debug $log $log_config );

our $VERSION = 1.0;

sub init {

    $debug = $::debug || 0;

    $SIG{INT} = \&QUIT;

    # Load config to $CONF::cfg (global)
    my $config_file = $ENV{GRANITE_CONFIG} || './conf/granite.conf';
    Granite::Utils::ConfigLoader->load_app_config($config_file);

    # Load log config
    confess "Failed to load configuration\n"
        unless ( $log_config = $CONF::cfg->{main}->{log_config} || './conf/log.conf' );

    Log::Log4perl::Config->allow_code(0);
    Log::Log4perl::init($log_config);
    $log = Log::Log4perl->get_logger(__PACKAGE__);

    # Init engine
    Granite::Engine->new( logger => $log, debug => $debug )->init;
    exit;
}

sub QUIT
{
    $log->info("Termination signal detected\n");
    exit 1;
}

1;
