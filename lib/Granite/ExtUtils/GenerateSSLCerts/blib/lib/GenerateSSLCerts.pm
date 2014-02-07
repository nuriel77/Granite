package GenerateSSLCerts;

use 5.014002;
use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use GenerateSSLCerts ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '0.01';

require XSLoader;
XSLoader::load('GenerateSSLCerts', $VERSION);

# Preloaded methods go here.

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

GenerateSSLCerts - Perl extension for creating default certificate and key for Granite

=head1 SYNOPSIS

  use GenerateSSLCerts;
  GenerateSSLCerts::gen_key_n_cert(int argc, char *argv[]);

=head1 DESCRIPTION

  Create initial certificates for Granite

=head1 SEE ALSO

    Thanks to 'Ozweepay': http://openssl.6102.n7.nabble.com/create-certificate-request-programmatically-using-OpenSSL-API-tt29197.html#a29198
    And perlxstut: http://search.cpan.org/~dagolden/perl-5.15.0/pod/perlxstut.pod

=head1 AUTHOR

Nuriel Shem-Tov

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.14.2 or,
at your option, any later version of Perl 5 you may have available.


=cut
