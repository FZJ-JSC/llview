# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 
#    Filipe Guimarães (Forschungszentrum Juelich GmbH) 

package LML_da_step_execute;

my $debug=0;
my $caller=$0;$caller=~s/^.*\/([^\/]+)$/$1/gs;
my $PRIMARKER="[${caller}]";
my $msg;

use strict;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );

use LML_da_util qw( logmsg check_folder );

sub new {
  my $self    = {};
  my $proto   = shift;
  my $class   = ref($proto) || $proto;
  my $stepdef      = shift;
  my $globalvarref = shift;
  printf("\t LML_da_step: new %s\n",ref($proto)) if($debug>=3);
  $self->{STEPDEF}   = $stepdef;
  $self->{GLOBALVARS}= $globalvarref;
  $self->{VERBOSE}   = $globalvarref->{verbose};
  $self->{TMPDIR}    = $globalvarref->{"tmpdir"};
  $self->{PERMDIR}   = $globalvarref->{"permdir"};
  $self->{LOGDIR}    = $globalvarref->{"logdir"};
  bless $self, $class;
  return $self;
}

sub execute {
  my($self) = shift;
  my($file,$newfile)=@_;
  my($cmd,$cmdref);
  my($tstart,$tdiff);
  my $rc=0;
  my $count=0;
  my $step=$self->{STEPDEF}->{id};
  my $stepref=$self->{STEPDEF};

#    print Dumper($stepref);

  foreach $cmdref (@{$self->{STEPDEF}->{cmd}}) {
    $count++;
    $cmd=$cmdref->{exec};
    $cmd=~s/\&gt;/>/gs;
    $msg=$self->{VERBOSE} ? sprintf("$PRIMARKER Executing %s\n",$cmd) : ""; logmsg($msg);
    $tstart=time;
    system($cmd);$rc=$? >> 8?$? >> 8:0;
    $tdiff=time-$tstart;
    $msg=$self->{VERBOSE} ? sprintf("$PRIMARKER %30s -> ready, time used %10.4ss\n","",$tdiff) : ""; logmsg($msg);
    $msg=$self->{VERBOSE} ? sprintf("$PRIMARKER TIMESTEP[%s_%02d]=%.6ss\n",$step,$count,$tdiff) : ""; logmsg($msg);
    if($rc) {
      $msg=sprintf("$PRIMARKER rc=%d: Failed executing command: %s \n",$rc,$cmd); logmsg($msg,\*STDERR);
      return($rc);
    }
  }
  return($rc);
}


# Sequential commands are executed with their output delayed and captured into temporary log files.
# To prevent disk space exhaustion from detached background processes holding zombie file descriptors,
# target files are explicitly truncated and closed prior to deletion.
#
# Arguments:
#   $self    - (Object) The LML_da_step_execute instance
#   $file    - (String) Unused legacy parameter
#   $newfile - (String) Unused legacy parameter
#
# Returns:
#   (Integer) The exit code of the executed commands (0 for success)
sub execute_delay_output {
  my ($self, $file, $newfile) = @_;
  my ($cmd, $cmdref);
  my ($tstart, $tdiff);
  my $rc = 0;
  my $step = $self->{STEPDEF}->{id};
  my $stepref = $self->{STEPDEF};
  my $steplogdir = sprintf("%s/steps/", $self->{LOGDIR});
  &check_folder($steplogdir);

  my $fn_log_out = sprintf("%s/%s.log", $steplogdir, $step);
  my $fn_log_out_last = sprintf("%s/%s_last.log", $steplogdir, $step);
  # Existing output logs are explicitly truncated and closed before deletion.
  # This forces the operating system to release disk blocks even if a detached process is holding the file handle.
  if (-f $fn_log_out) {
    open(my $clear_fh, '>', $fn_log_out);
    close($clear_fh);
    unlink($fn_log_out);
  }
  
  my $fn_log_err = sprintf("%s/%s.errlog", $steplogdir, $step);
  my $fn_log_err_last = sprintf("%s/%s_last.errlog", $steplogdir, $step);
  # Existing error logs are explicitly truncated and closed before deletion.
  if (-f $fn_log_err) {
    open(my $clear_fh, '>', $fn_log_err);
    close($clear_fh);
    unlink($fn_log_err);
  }
  
  foreach $cmdref (@{$self->{STEPDEF}->{cmd}}) {
    $cmd = $cmdref->{exec};
    $cmd =~ s/\&gt;/>/gs;
    $msg = $self->{VERBOSE} ? sprintf("$PRIMARKER Step '%s', executing %s\n", $step, $cmd) : ""; 
    logmsg($msg);
    
    $tstart = time;
    system("($cmd) >> $fn_log_out 2>> $fn_log_err "); 
    $rc = $? >> 8 ? $? >> 8 : 0;
    $tdiff = time - $tstart;
    
    $msg = $self->{VERBOSE} ? sprintf("$PRIMARKER %30s -> Step '%s' ready, time used %10.4ss\n", "", $step, $tdiff) : ""; 
    logmsg($msg);
    
    if ($rc) {
      $msg = sprintf("$PRIMARKER Step '%s' rc=%d: Failed executing command: %s \n", $step, $rc, $cmd); 
      logmsg($msg, \*STDERR);
      last;
    }
  }

  my $lines = $self->cat_to_stderrout($fn_log_err, $step, 0);
  $self->cat_to_stderrout($fn_log_out, $step, 1);
  
  if ($lines) {
    rename($fn_log_out, $fn_log_out_last) if (-f $fn_log_out);
    rename($fn_log_err, $fn_log_err_last) if (-f $fn_log_err);
  } else {
    rename($fn_log_out, $fn_log_out_last) if (-f $fn_log_out);
    if (-f $fn_log_err) {
      # The error log is safely truncated and closed before unlinking to reclaim disk space instantly.
      open(my $clear_fh, '>', $fn_log_err);
      close($clear_fh);
      unlink($fn_log_err);
    }
  }

  return $rc;
}


# The contents of a specified file are read and forwarded to either standard output or standard error.
#
# Arguments:
#   $self - (Object) The LML_da_step_execute instance
#   $fn   - (String) The file path to be read
#   $tag  - (String) An identifier tag for logging purposes
#   $type - (Integer) Determines output destination (0 for STDERR, 1 for STDOUT)
#
# Returns:
#   (Integer) The number of lines read and printed
sub cat_to_stderrout {
  my ($self, $fn, $tag, $type) = @_;

  return 0 if (! -f $fn);
  my $count = 0;
  
  # A lexical filehandle is utilized to prevent global namespace collisions during concurrent operations.
  # The file opening is explicitly verified to prevent readline errors on locked or inaccessible files.
  my $fh;
  if (open($fh, '<', $fn)) {
    while (my $line = <$fh>) {
      $count++;
      if ($type == 0) {
        print STDERR "$line";
      } else {
        print "$line";
      }
    }
    close($fh);
  } else {
    printf(STDERR "%s WARNING: Cannot open file %s for reading.\n", $PRIMARKER, $fn);
  }
  
  return $count;
}

1;
