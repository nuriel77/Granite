package Granite::Modules::DB;
use Moose;
use Try::Tiny;
use Granite::Schema;
use Config::Any;
use vars '$connection_info';

=head1 DESCRIPTION

  Database DBIx::Class schema connector

=head1 SYNOPSIS

  Granite::Modules::DB->new->connect;

=head1 ATTRIBUTES

=over

=item * B<schema>
=cut

has schema => (
    is => 'ro',
    isa => 'Object',
    writer => '_set_schema',
    clearer => '_unset_schema',
    predicate => '_has_schema',
);

=back

=head1 METHODS

=head4 B<connect()>

  Establishes connection to database and returns handle

=cut

sub connect {    
    my $self = shift;
    $self->_set_schema ( Granite::Schema->connect( _get_connection_info() ) )
        unless $self->_has_schema;
}

=head4 B<_get_connection_info()>

  Load the database connection configuration

=cut

sub _get_connection_info {
    my $file = Granite->cfg->{main}->{sql_config};
    my $cfg = Config::Any->load_files({ files => [ $file ], use_ext => 1 });
    $connection_info = $cfg->[0]->{$file}->{connect_info};    
}


__PACKAGE__->meta->make_immutable(inline_constructor => 0);

=head1 AUTHOR

  Nuriel Shem-Tov

=cut

1;

