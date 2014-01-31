package Granite::Component::Scheduler::QueueWatcher;
use strict;
use warnings;
use POE;
use Granite::Modules::Schedulers;
use vars qw($log $debug);

sub run {

    POE::Session->create(
        inline_states => {
            _start        => \&init_watcher,
            process_input => \&process_input,
            save_queue_state => \&save_queue_state,
        }
    );
}

sub init_watcher {
    warn "queue watcher alive\n";
    $_[KERNEL]->delay("process_input" => 1, 'bla');
}

sub process_input { warn "Process input....". $_[ARG0] . "\n"; $_[KERNEL]->delay("save_queue_state" => 1, '');}
sub save_queue_state { warn "SSSAASASASve queue state\n"; $_[KERNEL]->delay("process_input" => 1, 'back') }
1;

