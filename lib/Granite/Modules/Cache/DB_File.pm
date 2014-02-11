package Granite::Modules::Cache::DB_File;
use Moose;
with 'Granite::Modules::Cache',
     'Granite::Utils::Cmd';
use DB_File;
use vars qw(%hash);

=head1 DESCRIPTION

  The default cache backend - DB_File

=head1 SYNOPSIS

  See configuration file for more details

=head2 METHOD MODIFIERS

=head4 B<around 'new'>

    Override constructor, tie hash to file after some verifications

=cut

around new => sub {
    my $orig = shift;
    my $class = shift;
    my $self = $class->$orig(@_);

    # Run prescript if exists
    # =======================
    if ( $self->_has_hook and $self->hook->{prescript} ){
        return unless exec_hook($self->hook->{prescript}, 'pre');
    }

    my $cache_dir = _verify_dir( $self->{metadata}->{cache_dir} || $Granite::cfg->{main}->{cache_dir} );
    my $file_name = $self->{metadata}->{file_name};

    tie %hash, "DB_File", $cache_dir.'/'.$file_name, O_RDWR|O_CREAT, 0666, $DB_HASH
        or $Granite::log->logdie( "Cannot open file '".$cache_dir."/jobQueue.db': $!" );

    return $self->cache($self) unless $self->{hook};

    # Run postscript if exists
    # ========================
    if ($self->hook->{postscript}->{file}){
        return undef unless exec_hook($self->hook->{postscript}, 'post');   
    }
    
    $self->cache($self);
    return $self;
};


=head4 B<get>

  Get a key

=cut

sub get {
    my ( $self, $key ) = @_;
    return $hash{$key};
}

=head4 B<set>

  Set a key/value

=cut

sub set {
    my ( $self, $key, $val ) = @_;
    $hash{$key} = $val;
}

=head4 B<delete>

  Delete key/value

=cut

sub delete {
    my ($self, $key) = @_;
    delete $hash{$key};
}

=head4 B<get_keys>

  Get multuple keys, can provide a prefix

=cut

sub get_keys {
    my ( $self, $prefix ) = @_;
    grep { /^$prefix\d+/ } keys %hash;
}

=head4 B<list>

  List all keys

=cut

sub list { return join "\n", sort keys %hash }

=head4 B<_verify_dir>

  Verify directory exists in config and is writable

=cut

sub _verify_dir {
    my $cache_dir = shift;
    if ( ! $cache_dir ){
        $Granite::log->logcroak('Cannot find cache_dir in configuration file');
    }
    elsif ( ! -w $cache_dir ){
        $Granite::log->logcroak("No write permissions on cache directory '$cache_dir'")
    }
    return $cache_dir;
}

=head4 B<DEMOLISH>

  untie the has on class destruction

=cut

sub DEMOLISH { untie %hash }

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

=head1 AUTHOR

  Nuriel Shem-Tov

=cut

1;

