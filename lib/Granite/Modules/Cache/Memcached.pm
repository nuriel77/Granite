package Granite::Modules::Cache::Memcached;
use Moose;
use Cache::Memcached;
use Scalar::Util 'looks_like_number';
with 'Granite::Modules::Cache',
     'Granite::Utils::Cmd';
use namespace::autoclean;

use constant DEFAULT_EXPIRATION => 2592000; # 30 days
use constant TIMEOUT => 2;

=head1 DESCRIPTION

    Pluggable memcached module

=head1 SYNOPSIS

    See configuration on how to load modules

=head1 METHOD MODIFIERS

=head4 B<around new> 

    Overrides default constructor

=cut

around 'new' => sub {
    my $orig = shift;
    my $class = shift;
    my $self = $class->$orig(@_);
    my %connection_args;

    for ( keys %{$self->{metadata}} ){
        next unless $self->{metadata}->{$_};
        $connection_args{$_} = looks_like_number($self->{metadata}->{$_})
            ? $self->{metadata}->{$_}*1
            : $self->{metadata}->{$_}
    }
    
    # Run prescript if exists
    # =======================
    if ( $self->_has_hook and $self->hook->{prescript} ){
        return unless exec_hook($self->hook->{prescript}, 'pre');
    }
        
    my $memc;
    eval {
        local $SIG{ALRM} = sub { die "TIMEOUT\n" };
        alarm TIMEOUT;
        $memc = new Cache::Memcached { %connection_args };
        alarm 0;
    };
    if ( $@ ){
        $Granite::log->error('Failed to construct new Granite::Modules::Cache::Memcached::SubClass object: ' . $@);
        return undef;
    }

    $self->cache($memc) if $memc;   
    return $self unless $self->{hook};

    # Run postscript if exists
    # ========================
    if ($self->hook->{postscript}->{file}){
        return undef unless exec_hook($self->hook->{postscript}, 'post');   
    }
    
    return $self;
};

=head1 METHODS 

=head4 <get_keys>

    Get key listing

=cut

sub get_keys {
    my ( $self, $prefix ) = @_;
    my @keys;
    $prefix ||= 'job_';
    # FIXME: There's a way to get keys from memcached
    for (1..10000){
        my $keyname = $prefix . $_;
        push @keys, $keyname;
    }
    my $hashref = $self->cache->get_multi(@keys);
}

=head4 B<set>

    Set key/value

=cut

sub set     { shift->cache->set(shift, shift, DEFAULT_EXPIRATION) }

=head4 B<get>

    Get values by keyname

=cut

sub get     { shift->cache->get(shift) }

=head4 <delete>

    Delete key/value

=cut

sub delete  { shift->cache->delete(shift) }

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

=head1 AUTHOR

    Nuriel Shem-Tov

=cut

1;
