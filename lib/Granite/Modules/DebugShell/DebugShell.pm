package Granite::Modules::DebugShell::DebugShell;
use Moose;
use MooseX::NonMoose;
extends 'POE::Component::DebugShell';
use Data::Dumper;
use POE::API::Peek;

has _api => (
	is => 'ro',
	isa => 'Object',
	writer => '_set_api',
	predicate => '_has_api',
	default => sub {{}},
	lazy => 1,
);

around new => sub {
	my $orig = shift;
    my $class = shift;
    my $self = $class->$orig(@_);
	
	my $api = POE::API::Peek->new()
		or $Granite::log->logcroack("Unable to create POE::API::Peek object");
	 
	$self->_set_api($api);
	return $self;	
};

sub show_sessions_aliases {
    my ( $self, $args ) = @_;
    return undef if !$self->_has_api;
    my $ret_val = eval {
        POE::Component::DebugShell::cmd_list_aliases(
            api => $self->_api,
            args => $args,
        );
    };
    if ( $@ ){
        $Granite::log->error('Error at ' . __PACKAGE__ . ' line ' . __LINE__ . ': ' . $@);
        return undef;
    }
    return $ret_val;
}

sub show_sessions_stats {
    my ( $self, $args ) = @_;
    return undef if !$self->_has_api;
    my $ret_val = eval {
        POE::Component::DebugShell::cmd_session_stats(
            api => $self->_api,
            args => $args,
        );
    };
    if ( $@ ){
        $Granite::log->error('Error at ' . __PACKAGE__ . ' line ' . __LINE__ . ': ' . $@);
        return undef;
    }
    return $ret_val;
}

sub show_sessions {
	my $self = shift;
	return undef if !$self->_has_api;
	my $ret_val = eval { POE::Component::DebugShell::cmd_show_sessions( api => $self->_api ); };
    if ( $@ ){
        $Granite::log->error('Error at ' . __PACKAGE__ . ' line ' . __LINE__ . ': ' . $@);
        return undef;
    }
    return $ret_val;

}

sub show_sessions_queue {
	my $self = shift;
	return undef if !$self->_has_api;
	my $ret_val = eval { POE::Component::DebugShell::cmd_queue_dump( api => $self->_api ); };
    if ( $@ ){
        $Granite::log->error('Error at ' . __PACKAGE__ . ' line ' . __LINE__ . ': ' . $@);
        return undef;
    }
    return $ret_val;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;
