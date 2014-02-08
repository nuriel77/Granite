package Granite::Engine::Daemonize;
use File::Slurp qw(read_file);
use Proc::ProcessTable;
use POSIX 'setsid';
use Carp;
use Moose;
use namespace::autoclean;

has 'logger'   => ( is => 'ro', isa => 'Object', required => 1 );
has 'debug'    => ( is => 'rw', isa => 'Bool' );
has 'pid_file' => ( is => 'ro', isa => 'Str', required => 1 );
has 'workdir'  => ( is => 'ro', isa => 'Str', required => 1 );
has 'poe_kernel' => ( is => 'ro', isa => 'Object', required => 1 );

$| = 1;

around 'new' => sub {
    my $orig = shift;
    my $class = shift;
    my $self = $class->$orig(@_);

    
    $self->logger->debug('At Granite::Engine::Daemonize')
        if $self->debug;

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

    my $parent_pid = $$;
    my $pid = fork ();
    if ( !$pid ){
        $self->logger->info('Child process with pid ' . $$)
            if $self->debug;
    } elsif ( $pid < 0 ){
        confess "fork: $!\n";
    } elsif ($pid) {
        open ( PIDFILE, ">$pid_file" ) or do {
            $self->poe_kernel->stop;
            kill INT => $pid;
            $self->logger->logdie( "Cannot write pid $pid to '$pid_file': $!" );
        };
        print PIDFILE $pid;
        close PIDFILE or $self->logger->logdie( "Cannot close pid file '$pid_file': $!" );

        $self->logger->info('Process datached from parent with pid ' . $pid) if $self->debug;

        POSIX::setsid or confess "setsid: $!\n";

        chdir $self->workdir or confess "Cannot chdir: $!\n";
        umask 0;
        delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV'};

        exit 0;
    }

};

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;
