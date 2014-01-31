package Granite::Engine::Daemonize;
use strict;
use warnings;
use File::Slurp 'read_file', 'write_file';
use Proc::ProcessTable;
use POSIX 'setsid';
use Carp qw(cluck confess);
use Moose;
with 'Granite::Utils::Debugger';
use namespace::autoclean;

has 'logger'   => ( is => 'ro', isa => 'Object', required => 1 );
has 'pid_file' => ( is => 'ro', isa => 'Str', required => 1 );
has 'workdir'  => ( is => 'ro', isa => 'Str', required => 1 );

$| = 1;

around 'new' => sub {
    my $orig = shift;
    my $class = shift;
    my $self = $class->$orig(@_);

    $self->logger->trace('At Granite::Engine::Daemonize');

    my $pid_file = $self->pid_file;

    # check if pid already exists
    # and if daemon is already running
    if ( -f $pid_file ){
        if ( my $pid = read_file($pid_file, err_mode => 'carp', chomp => 1) ){
            my $t = new Proc::ProcessTable;
            for ( @{$t->table} ){
                confess "Error: Already running with $pid\n" if ( $_->pid == $pid );
            }
        }
    }

    debug( "Daemonizing" );
    my $pid = fork ();

    if ($pid < 0) {
        confess "fork: $!\n";
    } elsif ($pid) {
        unless ( write_file( $pid_file, { binmode => ':raw', err_mode => 'carp'}, $pid ) ){
            die "Cannot write pid to '$pid_file'\n";
        }
        $self->logger->debug('Process datached from parent with pid ' . $pid);            
        exit 0;
    }

    POSIX::setsid or confess "setsid: $!\n";

    chdir $self->workdir or confess "Cannot chdir: $!\n";
    umask 0;
    delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV'};

    return $self;

};

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;
