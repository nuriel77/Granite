package Granite::Engine::Controller;
use Moose::Role;
use Data::Dumper;

=head1 DESCRIPTION

  Controller roles for the engine.
  
  Currently includes all userspace
  commands originating from user input

=head1 SYNOPSIS

  This package is a Moose Role:

  use Moose;

  with 'Granite::Enginer::Controller';


=head2 ATTRIBUTES

  * commands
  
=cut

has commands => (
    is => 'ro',
    isa => 'HashRef',
    default => \&_get_commands_hash
);


=head2 METHODS

=head3 B<_get_commands_hash>

  Return the commands dictionary

=cut

sub _get_commands_hash {
    { 
        ping            => sub { return 'pong' },
        hello           => sub { return 'what\'s up?' },
        shutdown        => sub { $_[0]->stop },
        server_shutdown => sub { return undef; },
        getnodes        => sub {
            my ( $kernel, $heap, $wheel_id ) = @_;           
            my $node_array = $heap->{self}->scheduler->{nodes}->list_nodes;
            my @visible_nodes = grep defined, @{$node_array};
		    if ( $Granite::debug ){
		        $Granite::log->debug( 'Defined Node: ' . Dumper $_ )
		              for @visible_nodes;
		    }
            my $server_session = $kernel->alias_resolve('server');           
            $kernel->post($server_session, 'reply_client', \@visible_nodes, $wheel_id);        	
        }
    }
}

no Moose;

=head1 AUTHOR

  Nuriel Shem-Tov
  
=cut

1;
