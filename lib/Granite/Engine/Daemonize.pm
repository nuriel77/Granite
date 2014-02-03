package Granite::Engine::Daemonize;
use File::Slurp qw(read_file write_file);
use Proc::ProcessTable;
use POSIX 'setsid';
use Carp qw(cluck confess);
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

    
    $self->logger->debug('At Granite::Engine::Daemonize') if $self->debug;

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

    my $pid = fork ();

    if ( !$pid ){
        $self->poe_kernel->has_forked ;
    } elsif ( $pid < 0 ){
        confess "fork: $!\n";
    } elsif ($pid) {
        unless ( write_file( $pid_file, { binmode => ':raw', err_mode => 'carp'}, $pid ) ){
            $self->poe_kernel->stop;
            $self->logger->logwarn( "Cannot write pid to '$pid_file'" );
            return undef;
        }
        $self->logger->info('Process datached from parent with pid ' . $pid) if $self->debug;

        POSIX::setsid or confess "setsid: $!\n";

        chdir $self->workdir or confess "Cannot chdir: $!\n";
        umask 0;
        delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV'};

        exit 0;
    }

    return $self;

};

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;
