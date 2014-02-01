package Granite::Modules::Schedulers::Slurm;
use strict;
use warnings;
use Slurm;
use Slurm qw(:constant);
use Carp 'confess';
use Moose;

sub get_queue {
    my $slurm_conf = '/opt/slurm/etc/slurm.conf';
    my $slurm = Slurm::new($slurm_conf);
    my $default_partition = '_root_';

    confess "Slurm error: " . $slurm->strerror() . "\n"
        if $slurm->get_errno();

    my $sq = $slurm->load_jobs();

    my $output;
    for (@{$sq->{job_array}}){
        #print $_->{job_id} . ", prio = $_->{priority}, num_cpus = $_->{num_cpus}, num_nodes = $_->{num_nodes}\n"
         $output .= '' . ( join ":", ( $_->{job_id}, $_->{priority}, $_->{num_cpus}, $_->{num_nodes}) ) . ';'
            if $_->{partition} eq $default_partition;
    }
    return $output;
}


1;
