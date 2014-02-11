package Granite;
use Moose;
use MooseX::ClassAttribute;
use Log::Log4perl qw(:easy);
use Granite::Engine;
use Granite::Modules::DB;
use Granite::Utils::ConfigLoader;

use vars qw( $VERSION $trace );

use 5.14.2;

=head1 NAME

  Granite - Scheduling HPC in the Cloud 

=head1 VERSION v1.001

  Version 1.001 of the application.

=cut 

$VERSION = '1.001';

=head1 DESCRIPTION

  Daemon manager application for Scheduling for HPC in the cloud

  This application requires Slurm compiled from source code with its perl API,

  and a cloud API module (Net::OpenStack::Compute by default)


=head1 SYNOPSIS

  scripts/granited runs the application, optionally use provided rc init script.

=head2 CLASS ATTRIBUTES

=over

=item * B<cfg>
=cut

class_has cfg => (
    is => 'ro',
    isa => 'HashRef',
    default => sub {
        my $config_file = $ENV{GRANITE_CONFIG} || './conf/granite.conf';
        Granite::Utils::ConfigLoader::load_app_config($config_file);
    }
);

=item * B<log>
=cut

class_has log => (
    is => 'ro',
    isa => 'Object',
    writer => '_set_log',
    default => sub {{}},
    lazy => 1,
);

=item * B<dbh>
=cut

class_has dbh => (
    is => 'ro',
    isa => 'Object',
    default => sub { Granite::Modules::DB->new },
);

=item * B<debug>
=cut

class_has debug => (
    is => 'rw',
    isa => 'Bool',
    default => $ENV{GRANITE_DEBUG},
);

=back

=head2 METHODS MODIFIERS

=head4 B<around new>

  initializes configuration, logging,
  exit handler, and runs the application.

=cut

#around 'new' => sub {
#    my $orig = shift;
#    my $class = shift;
#    my $self = $class->$orig(@_);
 
    $SIG{INT} = \&QUIT;
    $SIG{__DIE__} = \&DEATH;

    # Load config to Granite->cfg (global)
    # =====================================
    #my $config_file = $ENV{GRANITE_CONFIG} || './conf/granite.conf';
    #$cfg = Granite::Utils::ConfigLoader::load_app_config($config_file);

    __PACKAGE__->debug(
        $ENV{GRANITE_FOREGROUND} ? $ENV{GRANITE_DEBUG} : __PACKAGE__->cfg->{main}->{debug}
    );
    $trace = $ENV{GRANITE_TRACE} || __PACKAGE__->cfg->{main}->{trace};

    # Load log config
    # ===============
    my $log_config = __PACKAGE__->cfg->{main}->{log_config} || 'conf/granite.conf';

    Log::Log4perl::Config->allow_code(0);
    Log::Log4perl::init($log_config);
    __PACKAGE__->_set_log( Log::Log4perl->get_logger(__PACKAGE__) );

#};

=head2 METHODS

=head4 B<init>

  Run Granite's Engine

=cut

sub init {

    # Run engine
    # ==========
    Granite::Engine->new()->run;

    exit;
}

sub QUIT {
    __PACKAGE__->log->info("Termination signal detected\n");
    exit 1;
}

sub DEATH {
    return unless defined $^S and $^S == 0; # Ignore errors in eval
    my ($error) = @_;
    chomp $error;
    print STDERR "died: $error\n";
}


__PACKAGE__->meta()->make_immutable();

=head1 AUTHOR

  Nuriel Shem-Tov

=head1 LICENSE

  This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself, 

  either Perl version 5.14.2 or, at your option, any later version of Perl 5 you may have available.

=cut

1;
