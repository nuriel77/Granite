package Granite::Utils::Cmd;
use Moose::Role;

=head1 DESCRIPTION

Command execution role

=head1 SYNOPSIS

package MyPackage;
with 'Granite::Utils::Cmd';
...

=head1 METHODS

=head4 exec_hook( $hook, $type )

Execute hook pre/post script

=cut

sub exec_hook {
    my ($hook, $type) = @_;

    Granite->log->debug('Executing module hook '.$type.'script');

    my $ret_val = _exec_command(
       $type.'script',
       $hook->{file},
       $hook->{args},
       $hook->{timeout} || 2,
    );

    Granite->log->debug(ucfirst($type)."script hook returned '$ret_val'")
        if $ret_val;

    return $ret_val;
}

=head4 exec_command($type, $script, @$args, $timeout )

  Execute command script. This function will capture both stderr and stdout.
  
  Exit code of the scripts is important:
  
  0 = OK
  
  1 = Log error, load module.
  
  2 = Log error, don't load module.
  
  3 = Log error and die. 

=cut

sub _exec_command {
    my ( $type, $script, $args, $timeout ) = @_;

    $timeout ||= 2;

    Granite->log->logdie("Script '$script' not found or not executable")
            if ! -f "$script" || ! -x "$script";

    my $cmd = $script . ' ' . ( join ' ', @{$args} );
    my $output = `$cmd 2>&1`;
    my $error_code = $? >> 8;

    # In case of failure
    # ==================
    if ( $error_code ){
        my $msg = "Module $type hook execution failed! "
                  . ( $error_code ? "exit code: " . $error_code : '' )
                  . ( $output ? ' output: ' . $output : '');
        # Exit code 1 means - log error, load module, continue.
        # =====================================================
        if ( $error_code == 1 ){
            Granite->log->error($msg);
        }
        # Exit code 2 means - log error, don't load module, continue.
        # ===========================================================
        elsif ( $error_code == 2 ){
        	Granite->log->error($msg);
        	return undef;
        }
        # Exit code3 means - log error and die.
        # =====================================
        elsif ( $error_code == 3 ){
            Granite->log->logdie($msg);
            return undef; # don't think we can reach here
        }
    }

    chomp($output);
    return $output;
}

no Moose;

=head1 AUTHOR

Nuriel Shem-Tov

=cut

1;
