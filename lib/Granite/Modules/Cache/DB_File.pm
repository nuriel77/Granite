package Granite::Modules::Cache::DB_File;
use Moose;
with 'Granite::Modules::Cache';
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

    my $cache_dir = _verify_dir( $self->{metadata}->{cache_dir} || $Granite::cfg->{main}->{cache_dir} );
    my $file_name = $self->{metadata}->{file_name};

    tie %hash, "DB_File", $cache_dir.'/'.$file_name, O_RDWR|O_CREAT, 0666, $DB_HASH
        or $Granite::log->logdie( "Cannot open file '".$cache_dir."/jobQueue.db': $!" );

    $self->cache($self);

    return $self->cache unless $self->{hook};

    $Granite::log->debug('Executing cache module hook');
    for my $type ( keys %{$self->{hook}} ){
        my $ret_val = $self->_exec_hook($type, $self->{hook}->{$type});
        $Granite::log->debug("$type hook returned '$ret_val'")
            if $ret_val;
    }

    return $self->cache;
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

=head4 B<_exec_hook>

  Execute hook code/script

=cut

sub _exec_hook {
    my ( $self, $type, $hook, $timeout ) = @_;
    $timeout ||= 2;
    my ( $err, $rc, $output );
    eval {
        local $SIG{ALRM} = sub { die "TIMEOUT\n" };
        alarm $timeout;
        if ( $type eq 'script' ){
            die "Script not found or not executable"
                if ! -f "$hook" || ! -x "$hook";
            $output = `$hook 2>&1`;
            $rc = $? >> 8;
        }
        elsif ( $type eq 'code' ){
            $output = eval $hook;
        }
        $err = $@;
        alarm 0;
    };
    $err .= $@ if $@;
    if ( $err || $rc ){
        $Granite::log->error("Module $type hook code execution failed: "
                            . $err . ( $rc ? 'exit code ' . $rc : '' )
                            . ( $output ? ' output: ' . $output : '')
        );
        return undef;
    }
    chomp($output);
    return $output;
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

