package Granite::TraitFor::Component::Resources::Memory;
use Moose::Role;
use Sys::MemInfo qw(totalmem freemem totalswap freeswap);
use Readonly;
use vars qw(%sizes);

Readonly::Hash %sizes => ( 
	B  => 1,
	KB => 1024,
	MB => 1024**2,
	GB => 1024**3,
    TB => 1024**4,
);

around [qw( total_mem free_mem total_swap free_swap )] => sub {
	my ( $orig, $self, $req_size ) = @_;
	$req_size = uc($req_size || 'b' );
	return $self->$orig($req_size);
};

sub total_mem   { Sys::MemInfo::totalmem() / $sizes{$_[1]} }

sub free_mem    { Sys::MemInfo::freemem() / $sizes{$_[1]} }

sub total_swap  { Sys::MemInfo::totalswap() / $sizes{$_[1]} }

sub free_swap   { Sys::MemInfo::freeswap() / $sizes{$_[1]} }


no Moose;

1;