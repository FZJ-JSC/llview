# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 

package LML_DBupdate_file;

my $VERSION='$Revision: 1.00 $';
my $debug=0;

use strict;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );

use LML_DBupdate_util;
use LML_DBupdate_adapt_workflows;

my $state_to_t = {
  "running"    => 'A',
  "idle"       => 'A',
  "allocated"  => 'A',
  "drained"    => 'D',
  "down"       => 'D',
  "maint"      => 'D',
  "unknown"    => 'U',
};
my $state_to_nr = {
  "running"    => 1,
  "idle"       => 1,
  "allocated"  => 1,
  "drained"    => 2,
  "down"       => 2,
  "maint"      => 2,
  "unknown"    => 3
};


sub get_status {
  my($self) = shift;
  my($nstate)=@_; 
  my($mstatus,$substatus,$statusnr);

  my $mainstate;

  my @substates=split(/\+/,$nstate);
  $mainstate=$substates[0];
  $substatus="";
  foreach my $s (@substates) {
    if($s=~/NOT_RESPONDING/) {
      $substatus.="NotRes";
    } elsif($s=~/POWER(ED|ING)_DOWN/) {
      $substatus.="PowDo";
    } elsif($s=~/POWER(ED|ING)_UP/) {
      $substatus.="PowUp";
    } elsif($s=~/^(.)(.)/) {
      $substatus.=uc($1).lc($2);
    } elsif ($s=~/^(.)/) {
      $substatus.=uc($1);
    } else {
      $substatus="-";
    }
  }

  $mstatus='Un'; $statusnr=9;
  if($nstate=~/\b(allocated|running)\b/i) {
    $mstatus='Ru';	$statusnr=1;
  } elsif($nstate=~/\b(drain|drained|down)\b/i) {
    $mstatus='Do';	$statusnr=2;
  } elsif($nstate=~/\b(reserved)\b/i) {
    $mstatus='Re';	$statusnr=6;
  } elsif($nstate=~/\b(idle)\b/i) {
    if($nstate=~/\b(planned)\b/i) {
      $mstatus='Pl';  $statusnr=4;
    } elsif($nstate=~/\b(power)/i) {
      $mstatus='Po';  $statusnr=5;
    } else {
      $mstatus='Id';  $statusnr=3;
    }	    
  } else {
    printf (STDERR "UNKNOWN state of node: $nstate\n");
    $mstatus='Un';
    $statusnr=9;
  }
  
  # printf(STDERR "map %-40s -> %2s, %20s, %3d \n",$nstate,$mstatus,$substatus,$statusnr);
  return($mstatus,$substatus,$statusnr);
}

sub get_status_gpu {
  my($self) = shift;
  my($nstate)=@_; 
  my($mstatus,$substatus,$statusnr);

  my $mainstate;

  my @substates=split(/\+/,$nstate);
  $mainstate=$substates[0];
  $substatus="";
  foreach my $s (@substates) {
    if($s=~/NOT_RESPONDING/) {
      $substatus.="NotRes";
    } elsif($s=~/POWER(ED|ING)_DOWN/) {
      $substatus.="PowDo";
    } elsif($s=~/POWER(ED|ING)_UP/) {
      $substatus.="PowUp";
    } elsif($s=~/^(.)(.)/) {
      $substatus.=uc($1).lc($2);
    } elsif ($s=~/^(.)/) {
      $substatus.=uc($1);
    } else {
      $substatus="-";
    }
  }
  
  if(exists($state_to_t->{lc($mainstate)})) {
    $mstatus=$state_to_t->{lc($mainstate)};
    $statusnr=$state_to_nr->{lc($mainstate)};
  } else {
    printf (STDERR "UNKNOWN state of node: $mainstate\n");
    $mstatus='U';
    $statusnr=9;
  }
  
  return($mstatus,$substatus,$statusnr);
}

# modify LML data so that it can be inserted into DB
sub adapt_data {
  my($self) = shift;
  my $data=$self->{DATA};
  my $nodedata=$data->{NODES_BY_NODEID};
  my $gpudata=$data->{GPUNODES_BY_NODEID};
  my($ref,$jobref,$spec,$node,$pos,$num);
  my $currentts=$data->{SYSTEM_TS};

  # init new attributes in NODE ENTRIES
  foreach $ref (@{$data->{NODE_ENTRIES}} ) {
    $ref->{requ_cores}=0;
    $ref->{ts}=$currentts;

    if(exists($ref->{state})) {
      ($ref->{status},$ref->{substatus},$ref->{istatus})=$self->get_status($ref->{state});
    }
    
    $ref->{feat}="U";
    if(exists($ref->{features})) {
      $ref->{feat}="CPU" if($ref->{features}=~/cpu/);
      $ref->{feat}="GPU" if($ref->{features}=~/gpu/);
      $ref->{feat}="GPU" if($ref->{features}=~/GPU/);
      $ref->{feat}="KNL" if($ref->{features}=~/knl/);
      $ref->{feat}="ARM" if($ref->{features}=~/arm/);
      $ref->{feat}="IPU" if($ref->{features}=~/ipu/);
    }
    # check for core info
    my $nodeid=$ref->{id};
    if(exists($data->{CINODES_BY_NODEID}->{$nodeid})) {
      $ref->{usage}=$data->{CINODES_BY_NODEID}->{$nodeid}->{usage};
      $ref->{used_cores}=$data->{CINODES_BY_NODEID}->{$nodeid}->{physcoresused}+(defined($data->{CINODES_BY_NODEID}->{$nodeid}->{logiccoresused})? $data->{CINODES_BY_NODEID}->{$nodeid}->{logiccoresused}: 0);
      $ref->{used_cores_phys}=$data->{CINODES_BY_NODEID}->{$nodeid}->{physcoresused};
      $ref->{used_cores_logic}=(defined($data->{CINODES_BY_NODEID}->{$nodeid}->{logiccoresused})? $data->{CINODES_BY_NODEID}->{$nodeid}->{logiccoresused}: 0);
    }
    # check for loadmemnode info, overwrite SLURM info
    if(exists($data->{LMNODES_BY_NODEID}->{$nodeid})) {
      my $r=$data->{LMNODES_BY_NODEID}->{$nodeid};
      $ref->{cpuload} = $ref->{memtotal} = $ref->{memavail} = $ref->{memfree} = $ref->{pp_size} = 0;
      $ref->{cpuload}  = $r->{cpuload}   if(exists($r->{cpuload}));
      $ref->{memtotal} = $r->{memtotal}  if(exists($r->{memtotal}));
      $ref->{memavail} = $r->{memavail}  if(exists($r->{memavail}));
      $ref->{memfree}  = $r->{memfree}   if(exists($r->{memfree}));
      $ref->{memused}  = $r->{memused}   if(exists($r->{memused}));
      $ref->{pp_size}  = $r->{pp_size}   if(exists($r->{pp_size}));
    }
  }

  # init new attributes in IONODE ENTRIES
  foreach $ref (@{$data->{IONODE_ENTRIES}} ) {
    $ref->{ts}=$currentts if(!exists($ref->{ts}));

    #  file system info
    $ref->{"fs_bw_all"}=$ref->{"fs_br_all"}=$ref->{"fs_ooc_all"}=0;
    foreach my $fs ("home", "scratch", "project1", "data1") {
      $ref->{"fs_ts_$fs"}  = $currentts if(!exists($ref->{"fs_ts_$fs"}));
      $ref->{"fs_dts_$fs"} = 60         if(!exists($ref->{"fs_dts_$fs"}));

      if(!exists($ref->{"fs_bw_$fs"}) && (exists($ref->{"fs_bww_$fs"}))) {
        $ref->{"fs_bw_$fs"}  = $ref->{"fs_dts_$fs"}*1024*1024*$ref->{"fs_bww_$fs"};
      }
      $ref->{"fs_bw_all"}+=$ref->{"fs_bw_$fs"} if(exists($ref->{"fs_bw_$fs"}));
      
      if(!exists($ref->{"fs_br_$fs"}) && (exists($ref->{"fs_bwr_$fs"}))) {
        $ref->{"fs_br_$fs"}  = $ref->{"fs_dts_$fs"}*1024*1024*$ref->{"fs_bwr_$fs"};
      }
      $ref->{"fs_br_all"}+=$ref->{"fs_br_$fs"} if(exists($ref->{"fs_br_$fs"}));

      if(!exists($ref->{"fs_ooc_$fs"}) && (exists($ref->{"fs_ocr_$fs"}))) {
        $ref->{"fs_oc_$fs"} = $ref->{"fs_dts_$fs"}*$ref->{"fs_ocr_$fs"}  ;
      }
      $ref->{"fs_oc_all"}+=$ref->{"fs_oc_$fs"} if(exists($ref->{"fs_oc_$fs"}));;

      $ref->{"fs_ts_all"}=$ref->{"fs_ts_$fs"};
      $ref->{"fs_dts_all"}=$ref->{"fs_dts_$fs"};
    }
  }

  
  # init new attributes in GPUNODE ENTRIES
  foreach $ref (@{$data->{GPUNODE_ENTRIES}} ) {
    $ref->{ts}=$currentts;
    $ref->{used}=0;

    if(exists($ref->{state})) {
      ($ref->{status},$ref->{substatus},$ref->{istatus})=$self->get_status_gpu($ref->{state});
    }

    $ref->{feat}="U";
    if(exists($ref->{features})) {
      $ref->{feat}="CPU" if($ref->{features}=~/cpu/);
      $ref->{feat}="GPU" if($ref->{features}=~/gpu/);
      $ref->{feat}="GPU" if($ref->{features}=~/GPU/);
      $ref->{feat}="KNL" if($ref->{features}=~/knl/);
      $ref->{feat}="ARM" if($ref->{features}=~/arm/);
      $ref->{feat}="IPU" if($ref->{features}=~/ipu/);
    }
  }
  # SCAN RUNNING JOBS
  # - update used_cores in node_entries
  #
  foreach $jobref (@{$data->{JOBS_RUNNING_ENTRIES}}) {
    my($jobnodes,$jobgpunodes);
    if(exists($jobref->{nodelist})) {
      if($jobref->{nodelist} ne "-") {
        foreach $spec (split(/\),?\(/,$jobref->{nodelist})) {
          $spec=~/\(?([^,]+),(\d+)\)?/;$node=$1;$pos=$2;
          $nodedata->{$node}->{requ_cores}++;
          $jobnodes->{$node}++;
        }
      }
    }
    if(exists($jobref->{vnodelist})) {
      if($jobref->{vnodelist} ne "-") {
        foreach $spec (split(/\),?\(/,$jobref->{vnodelist})) {
          $spec=~/\(?([^,]+),(\d+)\)?/;$node=$1;$num=$2;
          $nodedata->{$node}->{requ_cores}+=$num;
          $jobnodes->{$node}++;
        }
      }
    }
    
    if(exists($jobref->{gpulist})) {
      if($jobref->{gpulist} ne "-") {
        foreach $spec (split(/\),?\(/,$jobref->{gpulist})) {
          $spec=~/\(?([^,]+),(\d+)\)?/;$node=$1;$pos=$2;
          $node=~s/-gpu//s;
          $node.=sprintf("_%02d",$pos);
          $gpudata->{$node}->{used}=1;
          $jobgpunodes->{$node}++;
        }
      }
    }
    $jobref->{NODES}    = join(" ",(sort(keys(%{$jobnodes}))));
    $jobref->{GPUNODES} = join(" ",(sort(keys(%{$jobgpunodes}))));
  }

  # job information
  
  my $jstatref;
  foreach $jobref (@{$data->{JOBS_ENTRIES}}) {
    my $jobid=$jobref->{step};

    #  TS
    if(!exists($jobref->{ts})) {
      $jobref->{ts}=$currentts;
    }
    
    # JOB statistics
    $jstatref->{jobs}->{$jobid}->{ref}=$jobref;
    if( ($jobref->{state} eq "Running")
        || ($jobref->{state} eq "Completed")
        || ($jobref->{state} eq "Failed") ) {
      $jobref->{posinqueue}=-1;
    } else {
      if (!defined($jobref->{userprio})) {
        $jstatref->{prioqueue}->{$jobref->{queue}}->{-1}->{$jobid}=1;
      } else {
        $jstatref->{prioqueue}->{$jobref->{queue}}->{$jobref->{userprio}}->{$jobid}=1;
      }
    }
    $jobref->{waittime}=0.0;
    if(exists($jobref->{queuedate})) {
      my $endwaitts; 
      if(($jobref->{state} ne "Pending") && exists($jobref->{starttime}) && ($jobref->{starttime}) && ($jobref->{starttime} ne "Unknown")) {
        # If job has already started, and is not pending anymore (so, it has a start time)
        $endwaitts=LML_da_util::date_to_secj($jobref->{starttime});
      } else {
        # If the job is still in the queue endwaitts is the current ts
        $endwaitts=$currentts;
      }
      if($jobref->{queuedate}) {
        $jobref->{waittime}=($endwaitts-LML_da_util::date_to_secj($jobref->{queuedate}));
      } 
    }
    if(exists($jobref->{starttime})) {
      if($jobref->{starttime} && $jobref->{starttime} ne "Unknown") {
        $jobref->{timetostart}=LML_da_util::date_to_secj($jobref->{starttime})-$currentts;
        delete($jobref->{timetostart}) if($jobref->{timetostart}<0); # already started
        # printf("TMPDEB: timetostart: %d %d -> %d\n",LML_da_util::date_to_secj($jobref->{starttime}),$currentts,LML_da_util::date_to_secj($jobref->{starttime})-$currentts);
      }
    }

    if(exists($jobref->{owner})) {
      if($jobref->{owner} eq "nobody") {
        printf(STDERR "ERROR: job with id $jobid has owner nobody (%s)\n",Dumper($jobref));
      }
    }
    if(exists($jobref->{runtime})) {
      if($jobref->{runtime} eq "INVALID") {
        delete($jobref->{runtime});
      }
    }
  }

  # Update pos in queue
  foreach my $queue (keys(%{$jstatref->{prioqueue}})) {
    my $posinqueue=0;
    foreach my $prio (sort {$b <=> $a} (keys(%{$jstatref->{prioqueue}->{$queue}}))) {
      foreach my $jobid (sort(keys(%{$jstatref->{prioqueue}->{$queue}->{$prio}}))) {
        $posinqueue++;
        $jstatref->{jobs}->{$jobid}->{ref}->{posinqueue}=$posinqueue;
      }
    }
  }

  foreach $jobref (@{$data->{JOBRC_ENTRIES}}) {
    #  TS Start,End 
    if(exists($jobref->{start}) && $jobref->{start} ne "None") {
      if(!exists($jobref->{ts_start})) {
        $jobref->{ts_start}=LML_DBupdate::date_to_sec($jobref->{start});
        # print "TMPDEB: $jobref->{start} $jobref->{ts_start}\n";
      }
    }
    if(exists($jobref->{end})) {
      if(!exists($jobref->{ts_end})) {
        if($jobref->{end} eq "Unknown") {
          $jobref->{ts_end}=-1;
        } else {
          $jobref->{ts_end}=LML_DBupdate::date_to_sec($jobref->{end});
        }
      }
    }
  }

  foreach $jobref (@{$data->{JOBSTEP_ENTRIES}}) {
    #  TS
    if(!exists($jobref->{ts})) {
      $jobref->{ts}=$currentts;
    }

    #  TS Start,End 
    if(exists($jobref->{start}) && $jobref->{start} ne "None") {
      if(!exists($jobref->{ts_start})) {
        $jobref->{ts_start}=LML_DBupdate::date_to_sec($jobref->{start});
        # print "TMPDEB: $jobref->{start} $jobref->{ts_start}\n";
      }
    }
    if(exists($jobref->{end})) {
      if(!exists($jobref->{ts_end})) {
        if($jobref->{end} eq "Unknown") {
          $jobref->{ts_end}=-1;
        } else {
          $jobref->{ts_end}=LML_DBupdate::date_to_sec($jobref->{end});
        }
      }
    }
  }
  $self->adapt_workflows($currentts);

  #  add reason_nr, timetostart_real
  my @reason_pattern_array=("None", "Priority", "Dependency",
                            "QOSMaxNodePerUserLimit", "NonZeroExitCode", "Resources",
                            "Nodes_required_for_job_are_DOWN,_DRAINED", "TimeLimit",
                            "QOSMaxJobsPerUserLimit", "QOSMaxWallDurationPerJobLimit",
                            "BeginTime", "JobLaunchFailure", "BadConstraints" );
  my %reason_pattern_hash;
  for (my $i=0;$i<=$#reason_pattern_array;$i++) {
    $reason_pattern_hash{$reason_pattern_array[$i]}=$i;
  }

  foreach $jobref (@{$data->{JOBS_ENTRIES}}) {
    my $reason=$jobref->{reason};
    # print line
    $jobref->{reason_nr}=13;
    if (exists($reason_pattern_hash{$reason})) {
      $jobref->{reason_nr}=$reason_pattern_hash{$reason};
    } else {
      $jobref->{reason_nr}=13;
    }
  }
  foreach my $resref (@{$data->{RESERVATION_ENTRIES}}) {
    if (exists($resref->{starttime})) {
      $resref->{startts}=LML_da_util::date_to_secj($resref->{starttime});
    } else {
      $resref->{startts}=-1;
    }
    if (exists($resref->{endtime})) {
      $resref->{endts}=LML_da_util::date_to_secj($resref->{endtime});
    } else {
      $resref->{endts}=-1;
    }
  }

  foreach my $stref (@{$data->{STEPTIME_ENTRIES}}) {
    if (exists($stref->{wf_name}) && exists($stref->{name})) {
      $stref->{id}=$stref->{wf_name}."_".$stref->{name};
    } else {
      $stref->{id}="unknown";
    }
  }

  #  add error cls to error messages 
  foreach my $msgref (@{$data->{NODEERR_ENTRIES}}) {
    $msgref->{MSGCLS}=0;
    if (exists($msgref->{MESSAGE})) {
      if($msgref->{MESSAGE}=~/segfault/i) {
        $msgref->{MSGCLS}=1;
      } elsif($msgref->{MESSAGE}=~/oom-killer/i) {
        $msgref->{MSGCLS}=2;
      } elsif($msgref->{MESSAGE}=~/nodeDownAlloc/i) {
        $msgref->{MSGCLS}=3;
      }
    }
  }

  #  add ts to class info
  foreach my $clsref (@{$data->{CLASSES_ENTRIES}}) {
    $clsref->{ts}=$currentts;
  }

  #  add ts to class info
  foreach my $ioiref (@{$data->{IOIJOB_ENTRIES}}) {
    $ioiref->{ts}=$currentts;
  }
  foreach my $ioiref (@{$data->{IOIWF_ENTRIES}}) {
    $ioiref->{ts}=$currentts;
  }
  foreach my $coiref (@{$data->{COREINFO_ENTRIES}}) {
    $coiref->{ts}=$currentts;
  }
  foreach my $coiref (@{$data->{PCOREINFO_ENTRIES}}) {
    $coiref->{ts}=$currentts;
  }
  foreach my $wfmref (@{$data->{WFMJOB_ENTRIES}}) {
    $wfmref->{ts}=$currentts;
  }

  printf("\t LML_DBupdate_file: adapt_data\n") if($debug>=3);
}

1;