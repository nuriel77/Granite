package Granite::Modules::Cache::Memcached;
use Moose;
use Cache::Memcached;
use Scalar::Util 'looks_like_number';
with 'Granite::Modules::Cache';
use namespace::autoclean;

use constant DEFAULT_EXPIRATION => 2592000; # 30 days
use constant TIMEOUT => 2;

use Data::Dumper;

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

    $Granite::log->debug('Executing cache module hook');
    for my $type ( keys %{$self->{hook}} ){
        my $ret_val = $self->_exec_hook($type, $self->{hook}->{$type});
        $Granite::log->debug("$type hook returned '$ret_val'")
            if $ret_val;
    }

    return $self;
};

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

sub get_keys {
    my ( $self, $prefix ) = @_;
    my @keys;
    $prefix ||= 'job_';
    for (1..10000){
        my $keyname = $prefix . $_;
        push @keys, $keyname;
    }
    my $hashref = $self->cache->get_multi(@keys);
}

sub set     { shift->cache->set(shift, shift, DEFAULT_EXPIRATION) }
sub get     { shift->cache->get(shift) }
sub delete  { shift->cache->delete(shift) }

1;
