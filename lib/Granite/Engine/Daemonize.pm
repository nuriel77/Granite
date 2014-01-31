package Granite::Engine::Daemonize;
use strict;
use warnings;
use Proc::ProcessTable;
use POSIX 'setsid';
use Carp qw(cluck confess confess);
use Moose;
with 'Granite::Utils::Debugger';
use namespace::autoclean;

has 'logger'   => ( is => 'rw', isa => 'Object', required => 1 );
has 'pid_file' => ( is => 'rw', isa => 'Str', required => 1 );
has 'workdir'  => ( is => 'rw', isa => 'Str', required => 1 );

$| = 1;

sub init {
    my $self = shift;

    $self->logger->trace('Granite::Engine::Daemonize - Daemonizing');
    debug( "Daemonizing" );

    my $pid_file = $self->pid_file;

    # check if pid already exists
    # and if daemon is already running
    if ( -f $pid_file ){
        my $pid;
        open ( PID, "<$pid_file") or confess "Cannot open pid file: $!\n";
        $pid .= $_ while <PID>;
        close PID;
        my $t = new Proc::ProcessTable;
        if ( grep { $_->pid == $pid } @{$t->table} ){
            die "Error: Already running with $pid\n";
        }
        else {
            die "Error: pid file '$pid_file' exists but daemon is not running\n";
        }
    }

    my $pid = fork ();
    if ($pid < 0) {
        confess "fork: $!\n";
    } elsif ($pid) {
        open ( PIDFILE, ">$pid_file") or confess "Cannot open pid file\n";
        print PIDFILE $pid;
        close PIDFILE;            
        exit 0;
    }

    POSIX::setsid or confess "setsid: $!\n";

    chdir $self->workdir or confess "Cannot chdir: $!\n";
    umask 0;
    delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV'};
    return $pid;

}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;
