package Granite::Component::Scheduler::Job;
use Moose;
use POE;
use POE::Wheel::Run;
use Data::Dumper;
use vars qw($self);


=head1 DESCRIPTION

  Job lifecycle: search for resources, spawn resources, run job, cleanup

=head1 SYNOPSIS

    use Granite::Component::Scheduler::Job;
    my $job_api = Granite::Component::Scheduler::Job->new(job => $job);
    $job_api->process;

=head2 ATTRIBURES

=over

=item * job
=cut

has job => (
    is => 'ro',
    isa => 'HashRef',
    required => 1,
);

=back

=head2 METHODS

=head4 B<process>

  Process the job, submit to start lifecycle

=cut

sub process {
    $self = shift;

    $Granite::log->debug('{' . $self->job->{job_id} . '} At process');
    $_[HEAP]->{worker} =  POE::Wheel::Run->new(
        Program     => \&_in_session,
    ) or die "$0: can't POE::Wheel::Run->new";

}

=head4 B<_in_session>

  Job lifecycle starts here

=cut

sub _in_session {
    my $job = $self->job;

    # New pid
    # =======
    $poe_kernel->stop();

    $Granite::log->debug('{' . $job->{job_id} . '} At _in_session with PID ' . $$ );

    POE::Session->create
    (
        inline_states =>
        {
            # Start
            _start            => \&_init,
            setup_failure     => \&_failed_setup,
            # State resources
            resources_search  => \&_resources_search,
            resources_success => \&_resouces_success,
            resources_failure => \&_resources_failure,
            # State spawn
            spawn_instances   => \&_spawn_instances,
            spawn_success     => \&_spawn_success,
            spawn_failure     => \&_spawn_failure,
            # State job
            job_submit        => \&_job_submit,
            job_running       => \&_job_running,
            job_failure       => \&_job_failure,
            job_complete      => \&_job_complete,
            # End
            cleanup           => \&_cleanup,
            _stop             => \&_leave,
        },
        heap => { job => $job },
        options => { trace => $Granite::trace, debug => $Granite::debug },
    );

    $poe_kernel->run();
}

=head2 L<STATE SETUP> - Setup job

=head4 B<_init>

  Initialize job workflow

=cut

sub _init {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    $Granite::log->debug('{' . $heap->{job}->{job_id} . '} At _init');
    $kernel->post($_[SESSION],'resources_search');
}

=head4 B<_failed_setup>

  Setup fails

=cut

sub _failed_setup {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    $Granite::log->debug('{' . $heap->{job}->{job_id} . '} At setup failure');
}

=head2 L<STATE RESOURCES> - Resources state

=head4 B<_resources_search>

  Search for resources in the cloud

=cut

sub _resources_search {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    $Granite::log->debug('{' . $heap->{job}->{job_id} . '} At _resources_search');
    unless ( 1 ) {
        $kernel->yield('{' . $heap->{job}->{job_id} . '} resources_failure');
    }
    else {
        $kernel->yield('{' . $heap->{job}->{job_id} . '} resources_success');
    }
}

=head4 B<_resources_success>

  Resources found

=cut

sub _resouces_success {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    $Granite::log->debug('{' . $heap->{job}->{job_id} . '} At _resources_success');
    $kernel->yield('spawn_instances');
}

=head4 B<_resources_failure>

  Resources not found

=cut

sub _resources_failure {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    $Granite::log->debug('{' . $heap->{job}->{job_id} . '} At resouces failure');
}

=head2 L<STATE SPAWN> - Spawn instance(s) state: request resources from cloud

=head4 B<_spawn_instances>

  Spawn instance(s)

=cut

sub _spawn_instances {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    unless ( 1 ){
        $kernel->yield('{' . $heap->{job}->{job_id} . '} spawn_failure');
    }
    else {
        $kernel->yield('{' . $heap->{job}->{job_id} . '} spawn_success');
    }
}

=head4 B<_spawn_success>

  Instance(s) spawned OK

=cut

sub _spawn_success {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    $Granite::log->debug('{' . $heap->{job}->{job_id} . '} At _spawn_success');
    $kernel->yield('job_submit');
}

=head4 B<_spawn_instances>

  Instance(s) spawn failure

=cut

sub _spawn_failure {}


=head2 L<STATE JOB> - Job ready to be submitted to execute on its resources

=head4 B<_job_submit>

  Submit the job to run

=cut

sub _job_submit {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    unless ( 1 ){
        $kernel->yield('job_failure');
    }
    else {
        $kernel->yield('job_running');
    }
}

=head4 B<_job_running>

  Monitor the running job

=cut

sub _job_running {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    # ...    
    $kernel->yield('job_complete');
}

=head4 B<_job_failure>

  Job fails

=cut

sub _job_failure {}

=head4 B<_job_complete>

  Job completes

=cut

sub _job_complete {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    $Granite::log->debug('{' . $heap->{job}->{job_id} . '} At _job_complete');
    $kernel->yield('cleanup');
}

=head2 L<STATE COMPLETE> - Job completed successfully

=head4 B<_cleanup>

  Clean up after job

=cut

sub _cleanup {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
}

=head4 B<_leave>

  Leave the job palace

=cut

sub _leave {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    $Granite::log->debug('{' . $heap->{job}->{job_id} . '} At _leave with PID ' . $$ );
}

=head1 AUTHOR

  Nuriel Shem-Tov

=cut

1;
