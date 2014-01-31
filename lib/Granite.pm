package Granite;
use warnings;
use strict;
use Sys::Hostname;
use Carp 'confess';
use Log::Log4perl qw(:easy);
use Granite::Engine;
use Granite::Utils::ConfigLoader;
use Moose;
with 'Granite::Utils::Debugger';
use namespace::autoclean;
use vars qw( $debug $log $log_config );

our $VERSION = 1.0;

$SIG{INT} = \&QUIT;
$SIG{__DIE__} = sub {
    return if $^S; # skip eval

    $Log::Log4perl::caller_depth++;
    unlink ( $ENV{GRANITE_PID_FILE} || $CONF::cfg->{main}->{pid_file} || '/var/run/granite.pid' )
        if -f ( $ENV{GRANITE_PID_FILE} || $CONF::cfg->{main}->{pid_file} || '/var/run/granite.pid' );

    LOGDIE @_;
};

sub init {

    $debug = $::debug || 0;

    my $config_file = $ENV{GRANITE_CONFIG} || './conf/granite.conf';

    # Load config to $CONF::cfg (global)
    Granite::Utils::ConfigLoader->load_app_config($config_file);

    # Load log config
    confess "Failed to load configuration\n"
        unless ( $log_config = $CONF::cfg->{main}->{log_config} || './conf/log.conf' );

    Log::Log4perl::Config->allow_code(0);
    Log::Log4perl::init($log_config);
    $log = Log::Log4perl->get_logger(__PACKAGE__);
                                
    # Init engine
    Granite::Engine::init( $log, $debug );
    exit;
}

sub QUIT
{
    $log->debug('Termination signal detected...');
    debug ("Termination signal detected");
    unlink ( $ENV{GRANITE_PID_FILE} || $CONF::cfg->{main}->{pid_file} || '/var/run/granite.pid' )
        if -e ( $ENV{GRANITE_PID_FILE} || $CONF::cfg->{main}->{pid_file} || '/var/run/granite.pid' );
    exit 1;
}

1;
