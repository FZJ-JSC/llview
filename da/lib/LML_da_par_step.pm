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

package LML_da_step;

my $VERSION='1.1';
my $PRIMARKER="TOP";
my $msg;

use strict;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time usleep );
use Parallel::ForkManager;

use LML_da_util qw( substitute_recursive logmsg );
use LML_da_step_execute;

sub parprocess {
  my ($self) = shift;
  my ($globalvarref,$MAX_PROCESSES)=@_;
  my ($step,$steprefs,@steplist,%stepstate,$depsteps,$depstep,$stepref,$dep_graph);
  my $rc=0;
  my $rc_all=0;
  my $num_notfinished=0;
  my $starttime=time();
  
  $steprefs=$self->{STEPDEFS};
  foreach $step (keys(%{$steprefs})) {
    $steprefs->{$step}->{active}=0  if(!exists($steprefs->{$step}->{active}));
    $steprefs->{$step}->{onerror}="stop"  if(!exists($steprefs->{$step}->{onerror}));
    $steprefs->{$step}->{state}="todo";
    $num_notfinished++;
  }
  
  $self->analyse_step_chains();
  $dep_graph=$self->{DEPGRAPH};
  # print "steprefs=",Dumper($steprefs);
  # print "dep_graph=",Dumper($dep_graph);

  # parallel processing
  my $pm = Parallel::ForkManager->new($MAX_PROCESSES);

  # Setup a callback for when a child finishes up so we can
  # get it's exit code
  $pm->run_on_finish( sub {
                            my ($pid, $exit_code, $ident) = @_;
                            $msg=$self->{VERBOSE} ? sprintf("[$PRIMARKER] ** $ident just got out of the pool with PID $pid and exit code: $exit_code\n") : ""; logmsg($msg);
                            $msg=sprintf("[$PRIMARKER] ** $ident just got out of the pool with PID $pid and exit code: $exit_code\n"); logmsg($msg);
                            
                            # handle rc
                            if($steprefs->{$ident}->{state} ne "stop_in_deps") {
                              $steprefs->{$ident}->{state}=($exit_code)?"failed":"done";
                            } else {
                              $steprefs->{$ident}->{state}="noexec";
                            }
                            if ($steprefs->{$ident}->{state} eq "failed") {
                              $rc_all |= $exit_code;
                            }
                            $msg=$self->{VERBOSE} ? sprintf("[$PRIMARKER] Executed $ident $steprefs->{$ident}->{state}\n") : ""; logmsg($msg);
                            $steprefs->{$ident}->{end}=time()-$starttime;
                            
                            # check on how to handle a failed step
                            if(($steprefs->{$ident}->{state} eq "failed") && ($steprefs->{$ident}->{onerror} eq "stop")) {
                              $steprefs->{$ident}->{state}="stop_on_error";
                              $msg=$self->{VERBOSE} ? sprintf("[$PRIMARKER] Step failed $ident $steprefs->{$ident}->{state}\n") : ""; logmsg($msg,\*STDERR);
                            }
                            
                            # add depend steps to queue 
                            foreach my $nstep (@{$dep_graph->{graph}->{$ident}->{nxt}}) {
                              # skip already queued or executed steps
                              next if(!defined($nstep));
                              $msg=$self->{VERBOSE} ? sprintf("[$PRIMARKER] Added to queue: $nstep\n") : ""; logmsg($msg);
                              next if($steprefs->{$nstep}->{state}=~/(inqueue|done|failed)/);
                              push(@steplist,$nstep);
                              $steprefs->{$nstep}->{state}="inqueue";
                            }
                            $num_notfinished--;
                          });
  
  $pm->run_on_start( sub {
                            my ($pid, $ident)=@_;
                            $msg=$self->{VERBOSE} ? sprintf("[$PRIMARKER] ** $ident started, pid: $pid\n") : ""; logmsg($msg);
                          });
  
  $pm->run_on_wait( sub {
                          $msg=$self->{VERBOSE} ? sprintf("[$PRIMARKER] ** Have to wait for one child...\n") : ""; logmsg($msg);
                        },
                        0.5
                        );
  
  # init loop with entry step
  # steps in steplist have (some) fulfilled dependencies and can be execute if all dependencies are fulfilled
  push(@steplist,$dep_graph->{entry});
  $steprefs->{$dep_graph->{entry}}->{state}="inqueue";
  $msg=sprintf("[$PRIMARKER] Initializing execution: %s\n",$self->get_stepstatus_string(\@steplist)); logmsg($msg);
  # start loop over steps
  my $cycles=0;
  my $startgroupnum=0;
  STEPS:
  while($num_notfinished > 0) {
    # initiate call backs for finished steps
    $pm->reap_finished_children();
    $cycles++;
    
    #  check for new steps which can be executed
    my (@to_execute, @to_queue);
    
    while(@steplist) {
      $step=shift(@steplist);
      # my(@dependsteps);
      # check if all dependencies are fulfilled
      my $not_fulfilled=0;
      my $stop_found=0;
      foreach my $pstep (@{$dep_graph->{graph}->{$step}->{prev}}) {
        if( $steprefs->{$pstep}->{state}=~/^(todo|do|inqueue)$/ ) {
          # push(@dependsteps,$pstep);
          $not_fulfilled++; 
        }
        $stop_found++ if($steprefs->{$pstep}->{state} eq "stop_on_error");
        $stop_found++ if($steprefs->{$pstep}->{state} eq "stop_in_deps");
      }
      
      if($stop_found>0) {
        $steprefs->{$step}->{state}="stop_in_deps";
      }
      
      if($not_fulfilled>0) {
        push(@to_queue,$step);
      } else {
        push(@to_execute,$step);
      }
      # $msg=sprintf("[$PRIMARKER] DEPEND: %s -> notfilled=%d stop_found=%d dependsteps=%s\n",$step,$not_fulfilled,$stop_found,join(",",@dependsteps)); logmsg($msg);
    }
    @steplist=(@to_queue);

    $msg=($cycles%10==1) ? sprintf("[$PRIMARKER] CHECK: #not_finished=%d, #proc=%d %s\n",
                                    $num_notfinished, scalar $pm->running_procs(),
                                    $self->get_stepstatus_string(\@steplist)) : ""; logmsg($msg);
    $msg=$self->{VERBOSE} ? sprintf("[$PRIMARKER] CHECK: to execute: %s\n",join(",",@to_execute)) : ""; logmsg($msg);
    $msg=$self->{VERBOSE} ? sprintf("[$PRIMARKER] CHECK: to requeue: %s\n",join(",",@to_queue)) : ""; logmsg($msg);
    
    if(!@to_execute) {
      # check on consistency
      if((scalar $pm->running_procs() == 0) && ($num_notfinished>0)) {
        $msg=sprintf("[$PRIMARKER] ERROR: Something went wrong: #not_finished=%d, but no process forked, leaving loop... %s\n",
                      $num_notfinished,$self->get_stepstatus_string(\@steplist)); logmsg($msg,\*STDERR);
        last;
      }
      $msg=$self->{VERBOSE} ? sprintf("[$PRIMARKER] Waiting 1 second for new steps to be ready\n") : ""; logmsg($msg);
      if(exists($globalvarref->{sleepusec})) {
	  usleep($globalvarref->{sleepusec});
      }
      else {
	  usleep(1000000);
      }
      next STEPS;
    }

    $startgroupnum++ if(@to_execute);
    
    SUBSTEPS: for $step (@to_execute) {
      # execute step in a forked process

      $steprefs->{$step}->{start}=time()-$starttime;
      $steprefs->{$step}->{startgroupnum}=$startgroupnum;
      $steprefs->{$step}->{state}="do" if($steprefs->{$step}->{state} ne "stop_in_deps");

      $msg=sprintf("[$PRIMARKER] Before fork on step '%s': %s\n",$step,$self->get_stepstatus_string(\@steplist)); logmsg($msg);
      
      # fork now
      my $pid = $pm->start($step) and next SUBSTEPS;
      
      # do not execute if stop found in dep steps or step not active
      $rc=0;
      if(($steprefs->{$step}->{state} ne "stop_in_deps") && ($steprefs->{$step}->{active})) {
        $rc=$self->execute_step_par($step);
        $msg=sprintf("[$step] Finished execution of '$step' state='$steprefs->{$step}->{state}'\n"); logmsg($msg);
      } else {
        $msg=sprintf("[$step] Skip execution of '$step' state='$steprefs->{$step}->{state}' active='$steprefs->{$step}->{active}'\n"); logmsg($msg);
      }
      $pm->finish($rc);
    }
  }

  $msg=$self->{VERBOSE} ? sprintf("[$PRIMARKER] Waiting for children...\n") : ""; logmsg($msg);
  $pm->wait_all_children;
  $msg=$self->{VERBOSE} ? sprintf("[$PRIMARKER] Everybody is out of the pool, execution done!\n") : ""; logmsg($msg);

  my $endtime=time();
  $msg=sprintf("[$PRIMARKER] STEP Summary: Total time=%8.3fs #Wait_cycles=%d\n",$endtime-$starttime,$cycles); logmsg($msg);
  
  foreach $step (sort {$steprefs->{$a}->{start} <=> $steprefs->{$b}->{start}} (keys(%{$steprefs}))) {
    $msg=sprintf("[$PRIMARKER] STEPtiming: dt=%8.3fs [%8.3fs ... %8.3fs] %s(%d) %-20s\n",
                  $steprefs->{$step}->{end}-$steprefs->{$step}->{start},
                  $steprefs->{$step}->{start},
                  $steprefs->{$step}->{end},
                  " "x$steprefs->{$step}->{startgroupnum},$steprefs->{$step}->{startgroupnum},
                  $step); logmsg($msg);
  }    

  if(exists($globalvarref->{steptimingfile})) {
    my $current_cnt=0;
    if(exists($globalvarref->{stepcounter})) {
      if (-f $globalvarref->{stepcounter} ) {
        $current_cnt=`cat $globalvarref->{stepcounter}`;
      }
    }

    my $wf_name="workflow";
    $wf_name=$globalvarref->{name} if(exists($globalvarref->{name}));
    $self->write_steptimings_lml($globalvarref->{steptimingfile},$current_cnt,$wf_name,$starttime,$endtime,$cycles,$steprefs);

    $msg=sprintf("[$PRIMARKER] Generated steptiming file: $globalvarref->{steptimingfile}\n"); logmsg($msg);
  }
  return($rc_all);
}

# handle also stdout/stderr 
sub execute_step_par {
  my ($self) = shift;
  my ($step) = shift;
  my ($stepref,$stepinfile,$stepoutfile);
  my $rc=0;
  my $laststep=$self->{LASTSTEP};
  $PRIMARKER="execute_step";
  if($self->{DOSTEPFILES}) {
    $stepinfile=$self->{GLOBALVARS}->{tmpdir}."/datastep_$laststep.xml";
    $stepoutfile=$self->{GLOBALVARS}->{tmpdir}."/datastep_$step.xml";
  }
  $msg=$self->{VERBOSE} ? sprintf("[$PRIMARKER] STEP: %-10\n",$step) : ""; logmsg($msg);
  
  if($self->{DOSTEPFILES}) {
    $msg=$self->{VERBOSE} ? sprintf("[$PRIMARKER]   (%-30s->%-30s)\n",$stepinfile,$stepoutfile) : ""; logmsg($msg);
    $self->{GLOBALVARS}->{stepinfile}=$stepinfile;
    $self->{GLOBALVARS}->{stepoutfile}=$stepoutfile;
  }
  
  $stepref=$self->{STEPDEFS}->{$step};
  &substitute_recursive($stepref,$self->{GLOBALVARS}); 

  if($self->{DOSTEPFILES}) {
    if(!-f $stepinfile) {
      $msg=sprintf("[$PRIMARKER] Input file '%s' for step '%s' not found!\n",$stepinfile,$step); logmsg($msg,\*STDERR);
      if($laststep eq "__init__") {
        $msg=sprintf("[$PRIMARKER] --> Generating empty file '%s'...\n",$stepinfile); logmsg($msg);
        system("touch $stepinfile");
      }
    }
    if(-f $stepoutfile) {
      $msg=sprintf("[$PRIMARKER] Deleting output file '%s' from previous run...\n",$stepoutfile); logmsg($msg);
      unlink($stepoutfile);
    }
  }

  if($stepref->{type} eq "execute") {
    my $execobj=LML_da_step_execute->new($stepref,$self->{GLOBALVARS});
    $rc=$execobj->execute_delay_output();
  }
  
  if($self->{DOSTEPFILES}) {
    if(! -f $stepoutfile) {
      $msg=sprintf("[$PRIMARKER] Output file not generated by step, renaming input file '%s' to '%s' ...\n",$stepinfile,$stepoutfile); logmsg($msg);
      rename($stepinfile,$stepoutfile);
    }
    $self->{GLOBALVARS}->{stepinfile}="";
    $self->{GLOBALVARS}->{stepoutfile}="";
  }

  $self->{LASTSTEP} = $step;
  return($rc);
}

# handle also stdout/stderr 
sub write_steptimings_lml {
  my($self) = shift;
  my($filename,$current_cnt,$wf_name,$starttime,$endtime,$cycles,$steprefs)=@_;
  my($count,%stepnr,$step);
  
  open(OUT,"> $filename") || die "cannot open file $filename";
  printf(OUT "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
  printf(OUT "<lml:lgui xmlns:lml=\"http://eclipse.org/ptp/lml\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"\n");
  printf(OUT "	xsi:schemaLocation=\"http://eclipse.org/ptp/lml lgui.xsd\"\n");
  printf(OUT "	version=\"0.7\"\>\n");
  printf(OUT "<objects>\n");
  $count=0;
  foreach $step (sort {$steprefs->{$a}->{start} <=> $steprefs->{$b}->{start}} (keys(%{$steprefs}))) {
    $count++;$stepnr{$step}=$count;
    printf(OUT "<object id=\"fb%06d\" name=\"%s\" type=\"steptime\"/>\n",$count,$step);
  }

  {
    $step="ALL";
    $count++;$stepnr{$step}=$count;
    printf(OUT "<object id=\"fb%06d\" name=\"%s\" type=\"steptime\"/>\n",$count,$step);
  }
  
  printf(OUT "</objects>\n");
  printf(OUT "<information>\n");

  foreach $step (sort {$steprefs->{$a}->{start} <=> $steprefs->{$b}->{start}} (keys(%{$steprefs}))) {
    printf(OUT "<info oid=\"fb%06d\" type=\"short\">\n",$stepnr{$step});
    printf(OUT " <data %-20s value=\"%s\"/>\n","key=\"wf_name\"", $wf_name);
    printf(OUT " <data %-20s value=\"%s\"/>\n","key=\"name\"", $step);
    printf(OUT " <data %-20s value=\"%s\"/>\n","key=\"wf_startts\"", $starttime);
    printf(OUT " <data %-20s value=\"%s\"/>\n","key=\"nr\"", $stepnr{$step});
    printf(OUT " <data %-20s value=\"%.6f\"/>\n","key=\"start_ts\"", $starttime+$steprefs->{$step}->{start});
    printf(OUT " <data %-20s value=\"%.6f\"/>\n","key=\"end_ts\"", $starttime+$steprefs->{$step}->{end});
    printf(OUT " <data %-20s value=\"%.6f\"/>\n","key=\"dt\"", $steprefs->{$step}->{end} - $steprefs->{$step}->{start});
    printf(OUT " <data %-20s value=\"%d\"/>\n","key=\"group\"", $steprefs->{$step}->{startgroupnum});
    printf(OUT " <data %-20s value=\"%d\"/>\n","key=\"wf_cnt\"", $current_cnt);
    printf(OUT "</info>\n");
  }

  {
    $step="ALL";
    printf(OUT "<info oid=\"fb%06d\" type=\"short\">\n",$stepnr{$step});
    printf(OUT " <data %-20s value=\"%s\"/>\n","key=\"name\"", $step);
    printf(OUT " <data %-20s value=\"%s\"/>\n","key=\"wf_name\"", $wf_name);
    printf(OUT " <data %-20s value=\"%s\"/>\n","key=\"wf_startts\"", $starttime);
    printf(OUT " <data %-20s value=\"%s\"/>\n","key=\"nr\"", $stepnr{$step});
    printf(OUT " <data %-20s value=\"%.6f\"/>\n","key=\"start_ts\"", $starttime);
    printf(OUT " <data %-20s value=\"%.6f\"/>\n","key=\"end_ts\"", $endtime);
    printf(OUT " <data %-20s value=\"%.6f\"/>\n","key=\"dt\"", $endtime-$starttime);
    printf(OUT " <data %-20s value=\"%d\"/>\n","key=\"group\"", 0);
    printf(OUT " <data %-20s value=\"%d\"/>\n","key=\"wf_cnt\"", $current_cnt);
    printf(OUT "</info>\n");
  }
  printf(OUT "</information>\n");
  printf(OUT "</lml:lgui>\n");
  close(OUT);
}

1;
