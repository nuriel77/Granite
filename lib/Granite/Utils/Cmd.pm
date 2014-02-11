package Granite::Utils::Cmd;
use Moose::Role;
use IPC::Cmd qw( can_run run run_forked );

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

    $Granite::log->debug('Executing cache module '.$type.'script');

    my $ret_val = _exec_command(
       $type.'script',
       $hook->{file},
       $hook->{args},
       $hook->{timeout} || 2,
       1
    );

    $Granite::log->debug(ucfirst($type)."script hook returned '$ret_val'")
        if $ret_val;

    return $ret_val;
}

=head4 exec_command($type, $script, @$args, $timeout, $run_forked)

  Execute command script. This function will capture both stderr and stdout.
  
  Exit code of the scripts is important:
  
  0 = OK
  
  1 = Log error, load module.
  
  2 = Log error, don't load module.
  
  3 = Log error and die. 

=cut

sub _exec_command {
    my ( $type, $script, $args, $timeout, $forked ) = @_;

    $timeout ||= 2;

    undef $forked unless IPC::Cmd->can_use_run_forked;

    $Granite::log->logdie("Script '$script' not found or not executable")
            if ! -f "$script" || ! -x "$script";

    my @_cmd = ( $script, @{$args} );

    unless ( can_run($script) ){
        $Granite::log->logdie("Cannot run hook script: '$script': $!")
    }

    # There's a difference in passing args and
    # return args with run_forked and normal run.
    # ===========================================
    my %opts = $forked
        ? ( join(' ', @_cmd), {
                timeout => $timeout,
                terminate_on_parent_sudden_death => 1,
            }
          )
        : (
            command => [ @_cmd ],
            verbose => $Granite::debug,
            timeout => $timeout,
          );
 
    my ( $success, $error_code, $full_buf, $output );
    unless ( $forked ){
        ( $success, $error_code, $full_buf ) = run(%opts);
        $output = join( "\n", @{$full_buf} )
            if $full_buf;
    }
    else {
        my $ret_val = run_forked(%opts);
        $error_code = $ret_val->{exit_code};
        my $timed_out = $ret_val->{timeout};
        $output = $ret_val->{merged}
                . ( $timed_out ? ". Timed out after: $timed_out" : '' );
        $success = 1 unless $error_code;
    }

    # In case of failure
    # ==================
    unless ( $success ){
        my $msg = "Module $type hook execution failed! "
                  . ( $error_code ? "exit code: " . $error_code : '' )
                  . ( $output ? ' output: ' . $output : '');
        # Exit code 1 means - log error, load module, continue.
        # =====================================================
        if ( $error_code == 1 ){
            $Granite::log->error($msg);
        }
        # Exit code 2 means - log error, don't load module, continue.
        # ===========================================================
        elsif ( $error_code == 2 ){
        	$Granite::log->error($msg);
        	return undef;
        }
        # Exit code3 means - log error and die.
        # =====================================
        elsif ( $error_code == 3 ){
            $Granite::log->logdie($msg);
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
