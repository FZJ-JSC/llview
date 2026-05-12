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


sub execute_delay_output {
  my($self) = shift;
  my($file,$newfile)=@_;
  my($cmd,$cmdref);
  my($tstart,$tdiff);
  my $rc=0;
  my $step=$self->{STEPDEF}->{id};
  my $stepref=$self->{STEPDEF};
  my $steplogdir=sprintf("%s/steps/",$self->{LOGDIR});
  &check_folder($steplogdir);

  my $fn_log_out=sprintf("%s/%s.log",$steplogdir,$step);
  my $fn_log_out_last=sprintf("%s/%s_last.log",$steplogdir,$step);
  unlink($fn_log_out) if(-f $fn_log_out);
  my $fn_log_err=sprintf("%s/%s.errlog",$steplogdir,$step);
  my $fn_log_err_last=sprintf("%s/%s_last.errlog",$steplogdir,$step);
  unlink($fn_log_err) if(-f $fn_log_err);
  
  foreach $cmdref (@{$self->{STEPDEF}->{cmd}}) {
    $cmd=$cmdref->{exec};
    # some substitutes
    $cmd=~s/\&gt;/>/gs;
    $msg=$self->{VERBOSE} ? sprintf("$PRIMARKER Step '%s', executing %s\n",$step,$cmd) : ""; logmsg($msg);
    $tstart=time;
    system("($cmd) >> $fn_log_out 2>> $fn_log_err "); $rc=$? >> 8?$? >> 8:0;
    $tdiff=time-$tstart;
    $msg=$self->{VERBOSE} ? sprintf("$PRIMARKER %30s -> Step '%s' ready, time used %10.4ss\n","",$step,$tdiff) : ""; logmsg($msg);
    if($rc) {
      $msg=sprintf("$PRIMARKER Step '%s' rc=%d: Failed executing command: %s \n",$step,$rc,$cmd); logmsg($msg,\*STDERR);
      last;
    }
  }

  my $lines = $self->cat_to_stderrout($fn_log_err,$step,0);
  $self->cat_to_stderrout($fn_log_out,$step,1);
  # save last full step log
  if ($lines) {
    rename($fn_log_out, $fn_log_out_last) if (-f $fn_log_out);
    rename($fn_log_err, $fn_log_err_last) if (-f $fn_log_err);
  } else {
    rename($fn_log_out, $fn_log_out_last) if (-f $fn_log_out);
    unlink($fn_log_err) if (-f $fn_log_err);
  }

  return($rc);
}

sub cat_to_stderrout {
  my($self) = shift;
  my($fn,$tag,$type) = @_;

  return if(! -f $fn);
  my $count = 0;
  open(IN,$fn);
  while(my $line=<IN>) {
    $count++;
    if($type==0) {
      print STDERR "$line";
      # $msg=sprintf("$PRIMARKER [$tag/ERR] $line"); logmsg($msg,\*STDERR);
    } else {
      print "$line";
      # $msg=sprintf("$PRIMARKER [$tag/OUT] $line"); logmsg($msg);
    }
  }
  close(IN);
  return $count;
}

1;
