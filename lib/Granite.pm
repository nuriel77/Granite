package Granite;
use warnings;
use strict;
use Sys::Hostname;
use Carp 'confess';
use Log::Log4perl qw(:easy);
use Granite::Engine;
use Granite::Utils::ConfigLoader;

use vars qw( $cfg $debug $log );
use strict 'vars';

use 5.14.2;

our $VERSION = 1.0;

=head1 NAME

Granite - Scheduling HPC in the Cloud 

=head1 VERSION

Version 1.0 of the application.

=head1 SYNOPSYS

scripts/granited runs the application, optionally use provided rc init script.

=over

=item *

This application requires Slurm compiled from source code with its perl API,

and a cloud API module (Net::OpenStack::Compute by default)

=back

=head1 METHODS

=head2 L<init()>

    initializes configuration, logging,
    exit handler, and runs the application.

=cut


sub init {

    $SIG{INT} = \&QUIT;

    # Load config to $Granite::cfg (global)
    my $config_file = $ENV{GRANITE_CONFIG} || './conf/granite.conf';
    $cfg = Granite::Utils::ConfigLoader::load_app_config($config_file);

    $debug = $ENV{GRANITE_FOREGROUND} ? $ENV{GRANITE_DEBUG} : $cfg->{main}->{debug};

    # Load log config
    my $log_config = $Granite::cfg->{main}->{log_config} || 'conf/granite.conf';

    Log::Log4perl::Config->allow_code(0);
    Log::Log4perl::init($log_config);
    $log = Log::Log4perl->get_logger(__PACKAGE__);

    # Init engine
    Granite::Engine->new( logger => $log, debug => $debug )->run;
    exit;
}

sub QUIT
{
    $log->info("Termination signal detected\n");
    exit 1;
}

=head1 AUTHOR

Nuriel Shem-Tov

=head1 LICENSE

This software is distributed under the GPL license.

=cut

1;
