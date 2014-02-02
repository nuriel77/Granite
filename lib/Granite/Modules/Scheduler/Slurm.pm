package Granite::Modules::Scheduler::Slurm;
use strict;
use warnings;
use Slurm;
use Slurm qw(:constant);
use Carp 'confess';
use Moose;
    with 'Granite::Modules::Scheduler';
use namespace::autoclean;

around 'new' => sub {
    my $orig = shift;
    my $class = shift;
    my $self = $class->$orig(@_);

    my $slurm_conf = $self->metadata->{config_file};
    $self->scheduler( Slurm::new($slurm_conf) );
    confess "Slurm error: " . $self->scheduler->strerror() . "\n"
        if $self->scheduler->get_errno();

    return $self;    
};

sub get_queue {
    my $self = shift;
    my $sq = $self->scheduler->load_jobs();
    return $sq->{job_array} if $sq->{job_array};
}

sub get_nodes {
    my $self = shift;
    my $nodes = $self->scheduler->load_node;

    die "Slurm error: " . $self->scheduler->strerror() . "\n"
        if $self->scheduler->get_errno();

    return $nodes->{node_array};
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;
