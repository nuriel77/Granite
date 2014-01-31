package Granite::Engine::Logger;
use Log::Log4perl;
use Moose::Role;

sub set_logger_stdout {

    my $layout =
        Log::Log4perl::Layout::PatternLayout->new("[%r] %p %F %L %m%n");

    my $stdout_appender =
        Log::Log4perl::Appender->new(
            "Log::Log4perl::Appender::Screen",
            name      => "Screen",
            stderr    => 0
        );

    $stdout_appender->layout($layout);
    shift->add_appender( $stdout_appender );
}

no Moose;

1;
