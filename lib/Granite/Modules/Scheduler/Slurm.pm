package Granite::Modules::Scheduler::Slurm;
use strict;
use warnings;
use Slurm;
use Slurm qw(:constant);
use Carp 'confess';
use Moose;
    with 'Granite::Modules::Scheduler';
use namespace::autoclean;

has slurm => ( is => 'rw', isa => 'Object' );

around 'new' => sub {
    my $orig = shift;
    my $class = shift;
    my $self = $class->$orig(@_);

    my $slurm_conf = $self->metadata->{config_file};
    $self->slurm ( Slurm::new($slurm_conf) );
    confess "Slurm error: " . $self->slurm->strerror() . "\n"
        if $self->slurm->get_errno();

    return $self;    
};

sub get_queue {
    my $self = shift;
    my $reservation_queue = $self->metadata->{reservation_queue};

    my $sq = $self->slurm->load_jobs();

    my $output;
    for (@{$sq->{job_array}}){
         $output .= '' . ( join ":", ( $_->{job_id}, $_->{priority}, $_->{num_cpus}, $_->{num_nodes}) ) . ';'
            if $_->{partition} eq $reservation_queue;
    }
    return $output;
}

sub get_nodes {
    
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;
