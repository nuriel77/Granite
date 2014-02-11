package Granite::Modules::Scheduler::Slurm;
use strict;
use warnings;
use Slurm;
use Slurm qw(:constant);
use Moose;
    with 'Granite::Modules::Scheduler',
         'Granite::Utils::Cmd';
use namespace::autoclean;

=head1 DESCRIPTION

Slurm API pluggable module
  
=head1 SYNOPSIS

See configuration file on how to load modules
  
=head1 METHOD MODIFIERS

around 'new' => overrides default constructor

=cut

around 'new' => sub {
    my $orig = shift;
    my $class = shift;
    my $self = $class->$orig(@_);

    # Run prescript if exists
    # =======================
    if ( $self->_has_hook and $self->hook->{prescript} ){
        return undef unless exec_hook($self->hook->{prescript}, 'pre');
    }
    
    my $slurm_conf = $self->metadata->{config_file};
    $self->scheduler( Slurm::new($slurm_conf) );

    Granite->log->logcroak( "Slurm error: " . $self->scheduler->strerror() )
        if $self->scheduler->get_errno();

    return $self unless $self->hook->{postscript};    
    
    # Run postscript if exists
    # ========================
    if ( $self->hook->{postscript}->{file} ){
        return undef unless exec_hook($self->hook->{postscript}, 'post');
    }
    
    return $self;    
};

=head1 METHODS

=head4 B<get_queue>

Get the schedulers queues

=cut

sub get_queue {
    my $self = shift;
    my $sq = $self->scheduler->load_jobs();
    return $sq->{job_array} if $sq->{job_array};
}

=head4 B<get_nodes> 

Get the schedulers visible nodes

=cut

sub get_nodes {
    my $self = shift;
    my $nodes = $self->scheduler->load_node;

    die "Slurm error: " . $self->scheduler->strerror() . "\n"
        if $self->scheduler->get_errno();

    return $nodes->{node_array};
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

=head1 AUTHOR

Nuriel Shem-Tov

=cut

1;
