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

use strict;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );

sub adapt_workflows {
  my $self = shift;
  my ($currentts)=@_;
  my ($job,$jobref,$dep_graph, $singleton_lookup, $arrayjob_lookup,
      $depjob, $nextchainnr, $depnr,$jobid_to_wf, $wf_max_wjid,
      $iosea_wf_lookup); 
  my $data=$self->{DATA};

  # system info, jobs statistics 
  my $jobsref;
  my $het_lookup;
  ($nextchainnr,$jobid_to_wf,$wf_max_wjid)=$self->load_jobid_wf_map();
  
  foreach $jobref (@{$data->{JOBS_ENTRIES}}) {
    my $jobid=$jobref->{step} // $jobref->{jobid};
    $jobsref->{$jobid}=$jobref;
    
    $jobref->{chainid}=$jobref->{'wf_id'}=$jobref->{'wf_jid'}="-";
    # need to be improved, multiple dependencies possible
    if(exists($jobref->{dependency})) {
      if($jobref->{dependency}=~/after.*:([^+:\(]+)/) {
        $depjob=$1;
        push(@{$dep_graph->{$depjob}->{nxt}},$jobid);
        push(@{$dep_graph->{$jobid}->{prev}},$depjob);
        $dep_graph->{$jobid}->{wf_type}=$dep_graph->{$depjob}->{wf_type}="chain";
      }
      if($jobref->{dependency}=~/.*singleton.*/) {
        if(exists($jobref->{name})) {
          push(@{$singleton_lookup->{$jobref->{name}}},$jobid);
        }
      }
    }
    if(exists($jobref->{ArrayJobId})) {	
      push(@{$arrayjob_lookup->{$jobref->{ArrayJobId}}},$jobid);
    }
    if(exists($jobref->{HetJobId})) {	
      push(@{$het_lookup->{$jobref->{HetJobId}}},$jobid);
    }
  }
  
  # scan jobs from Workflow Manager (IO-SEA)
  my $wfm_lookup;
  foreach $jobref (@{$data->{WFMJOB_ENTRIES}}) {
    my $jobid=$jobref->{jobid};
    # print "TMPDEB: found WFMJOB $jobid\n";
    push(@{$wfm_lookup->{$jobref->{sessionid}}},$jobid);
  }

  # sort WFM jobs into dependency graph
  foreach my $sessionid (keys(%{$wfm_lookup})) {
    my @jobids=(sort (@{$wfm_lookup->{$sessionid}}));
    my $first_jobid= shift @jobids;
    my $jcount=0;
    $dep_graph->{$first_jobid}->{nxt}=[];
    $dep_graph->{$first_jobid}->{wf_type}="WFM";
    $jobref->{wf_id}=$jobref->{sessionid}; $jobref->{wf_jid}=$jcount++;
    my $last_jobid=$first_jobid;
    foreach my $jobid (@jobids) {
      push(@{$dep_graph->{$last_jobid}->{nxt}},$jobid);
      push(@{$dep_graph->{$jobid}->{prev}},$last_jobid);
      $dep_graph->{$jobid}->{wf_type}="WFM";
      $jobref->{wf_id}=$jobref->{sessionid}; $jobref->{wf_jid}=$jcount++;
      my $last_jobid=$jobid;
    }
  }
  # print "WFM:",Dumper($dep_graph);

  # sort HET jobs into dependency graph
  foreach my $hetjobid (keys(%{$het_lookup})) {
    my @jobids=(sort (@{$het_lookup->{$hetjobid}}));
    my $first_jobid= shift @jobids;
    my $jcount=0;
    $dep_graph->{$first_jobid}->{nxt}=[];
    $dep_graph->{$first_jobid}->{wf_type}="HetJob";
    $jobref->{wf_id}=$jobref->{HetJobId}; $jobref->{wf_jid}=$jcount++;
    my $last_jobid=$first_jobid;
    foreach my $jobid (@jobids) {
      push(@{$dep_graph->{$last_jobid}->{nxt}},$jobid);
      push(@{$dep_graph->{$jobid}->{prev}},$last_jobid);
      $dep_graph->{$jobid}->{wf_type}="HetJob";
      $jobref->{wf_id}=$jobref->{HetJobId}; $jobref->{wf_jid}=$jcount++;
      my $last_jobid=$jobid;
    }
  }

  # sort singleton jobs into dependency graph
  foreach my $jobname (keys(%{$singleton_lookup})) {
    my $first_jobid=$singleton_lookup->{$jobname}->[0];
    $dep_graph->{$first_jobid}->{prev}=[];
    $dep_graph->{$first_jobid}->{nxt}=[];
    $dep_graph->{$first_jobid}->{wf_type}="singleton";
    foreach my $jobid (sort(@{$singleton_lookup->{$jobname}})) {
      next if($jobid eq $first_jobid);
      push(@{$dep_graph->{$first_jobid}->{nxt}},$jobid);
      $dep_graph->{$jobid}->{wf_type}="singleton";
    }
  }

  
  # sort array jobs into dependency graph
  foreach my $arrayjobid (keys(%{$arrayjob_lookup})) {
    #  search master job, sort others
    my(@jlist,$masterjob); 
    foreach my $jobid (sort(@{$arrayjob_lookup->{$arrayjobid}})) {
      if($jobid==$arrayjobid) {
        $masterjob=$jobid;
      } else {
        push(@jlist,$jobid);
      }
    }

    my $lastid=undef;
    my @deplist=(undef,(sort {$a <=> $b} (@jlist)), $masterjob,undef);
    # print "arrayjob: $masterjob -> @deplist\n";
    for(my $j=1;$j<$#deplist;$j++)  {
      if(defined($deplist[$j-1])) {
        push(@{$dep_graph->{$deplist[$j-1]}->{nxt}},$deplist[$j]);
        push(@{$dep_graph->{$deplist[$j]}->{prev}},$deplist[$j-1]);
      }
      # if(defined($deplist[$j+1])) {
      #   push(@{$dep_graph->{$deplist[$j+1]}->{prev}},$deplist[$j]);
      #   push(@{$dep_graph->{$deplist[$j]}->{nxt}},$deplist[$j+1]);
      # }
      $dep_graph->{$deplist[$j]}->{wf_type}="array";
    }
  }

  if(0) {
    foreach my $jobid (sort(keys(%{$dep_graph}))) {
      printf("DEP[%s] ",$jobid);
      printf("prev=%s ",join(",",(@{$dep_graph->{$jobid}->{prev}}))) if(exists($dep_graph->{$jobid}->{prev}));
      printf("next=%s ",join(",",(@{$dep_graph->{$jobid}->{nxt}}))) if(exists($dep_graph->{$jobid}->{nxt}));
      printf("\n");
    }
    return();
  }
  
  # find entry point of job chains and make chains
  foreach my $jobid (keys(%{$dep_graph})) {
    if ( exists($dep_graph->{$jobid}->{nxt}) && (!exists($dep_graph->{$jobid}->{prev}) ) ) {
      # check first if chain has already a wfid
      my $wf=&check_chain_iterative($jobid,$dep_graph,$jobid_to_wf,0);
      if(defined($wf)) {
        $depnr=$wf_max_wjid->{$wf};
        &enum_chain_iter($jobid,$wf,\$depnr,$dep_graph,$jobsref,$jobid_to_wf,$currentts,0);
      } else {
        $nextchainnr++; $depnr=0;
        &enum_chain_iter($jobid,$nextchainnr,\$depnr,$dep_graph,$jobsref,$jobid_to_wf,$currentts,0);
      }
    }
  }

  $self->save_jobid_wf_map($nextchainnr,$jobid_to_wf,$currentts);
}

sub check_chain_iterative {
  my($jobid,$dep_graph,$jobid_to_wf,$rdepth)=@_;
  my @queue;
  push(@queue,$jobid);
  while($jobid = shift(@queue)) {
    if(exists($jobid_to_wf->{$jobid})) {
      return($jobid_to_wf->{$jobid}->{wf});
    } else {
      foreach my $njob (@{$dep_graph->{$jobid}->{nxt}}) {
        push(@queue,$njob);
      }
    }
  }
  return(undef);
}

sub check_chain {
  my($jobid,$dep_graph,$jobid_to_wf,$rdepth)=@_;
  if(exists($jobid_to_wf->{$jobid})) {
    return($jobid_to_wf->{$jobid}->{wf});
  } else {
    if($rdepth>1000) {
      print STDERR "check_chain: $jobid depth to high ($rdepth), stop recursion ...\n";
      return(undef);
    }
    foreach my $njob (@{$dep_graph->{$jobid}->{nxt}}) {
      my $wf=&check_chain($njob,$dep_graph,$jobid_to_wf,$rdepth+1);
      return($wf) if (defined($wf));
    }
  }
  # print STDERR "check_chain: $jobid: wf not found\n";
  return(undef);
}

sub enum_chain_iter {
  my($jobid,$chainnr,$depnrref,$dep_graph,$jobsref,$jobid_to_wf,$currentts,$rdepth)=@_;
  my @queue;
  push(@queue,$jobid);
  while($jobid = shift(@queue)) {
    # add info only to existing jobs, not jobs which are already finished and not in the data base
    if(exists($jobsref->{$jobid})) {
      if(exists($jobid_to_wf->{$jobid})) {
        $jobsref->{$jobid}->{'wf_id'}=sprintf("%06d",$jobid_to_wf->{$jobid}->{wf});
        $jobsref->{$jobid}->{'wf_jid'}=$jobid_to_wf->{$jobid}->{wjid};
      } else {
        $$depnrref++;
        $jobsref->{$jobid}->{'wf_id'}=sprintf("%06d",$chainnr);
        $jobsref->{$jobid}->{'wf_jid'}=$$depnrref;
        $jobid_to_wf->{$jobid}->{wf}=$jobsref->{$jobid}->{'wf_id'};
        $jobid_to_wf->{$jobid}->{wjid}=$jobsref->{$jobid}->{'wf_jid'};
      }
      $jobid_to_wf->{$jobid}->{lastts}=$currentts;
      $jobsref->{$jobid}->{chainid}=sprintf("ch%02d_l%02d",
                $jobsref->{$jobid}->{'wf_id'},
                $jobsref->{$jobid}->{'wf_jid'});
      $jobsref->{$jobid}->{'wf_type'}=$dep_graph->{$jobid}->{'wf_type'};
    } 
    foreach my $njob (@{$dep_graph->{$jobid}->{nxt}}) {
      push(@queue,$njob);
    }
  }
}

sub enum_chain {
  my($jobid,$chainnr,$depnrref,$dep_graph,$jobsref,$jobid_to_wf,$currentts,$rdepth)=@_;
  # add info only to existing jobs, not jobs which are already finished and not in the data base
  if(exists($jobsref->{$jobid})) {
    if(exists($jobid_to_wf->{$jobid})) {
      $jobsref->{$jobid}->{'wf_id'}=sprintf("%06d",$jobid_to_wf->{$jobid}->{wf});
      $jobsref->{$jobid}->{'wf_jid'}=$jobid_to_wf->{$jobid}->{wjid};
    } else {
      $$depnrref++;
      $jobsref->{$jobid}->{'wf_id'}=sprintf("%06d",$chainnr);
      $jobsref->{$jobid}->{'wf_jid'}=$$depnrref;
      $jobid_to_wf->{$jobid}->{wf}=$jobsref->{$jobid}->{'wf_id'};
      $jobid_to_wf->{$jobid}->{wjid}=$jobsref->{$jobid}->{'wf_jid'};
    }
    $jobid_to_wf->{$jobid}->{lastts}=$currentts;
    $jobsref->{$jobid}->{chainid}=sprintf("ch%02d_l%02d",
                $jobsref->{$jobid}->{'wf_id'},
                $jobsref->{$jobid}->{'wf_jid'});
    $jobsref->{$jobid}->{'wf_type'}=$dep_graph->{$jobid}->{'wf_type'};
  } 
  if($rdepth>1000) {
    print STDERR "enum_chain: $jobid depth to high ($rdepth), stop recursion ...\n";
    return(undef);
  }
  foreach my $njob (@{$dep_graph->{$jobid}->{nxt}}) {
    &enum_chain($njob,$chainnr,$depnrref,$dep_graph,$jobsref,$jobid_to_wf,$currentts,$rdepth+1);
  }
}


sub load_jobid_wf_map {
  my $self = shift;
  my ($line);
  my $nextchainnr=0;
  my $jobid_to_wf={};
  my $wf_max_wjid={};
  my $filename=sprintf("%s/jobid_to_wf.map",$self->{DBDIR});
  my $contents=`cat $filename`;
  
  if(-f $filename) {
    open(WFIN,$filename) or die "cannot open $filename";
    $line=<WFIN>;
    if(defined($line)) {
      chomp($line);
      $nextchainnr=$line;
      while($line=<WFIN>) {
        chomp($line);
        my($jobid,$wf,$wjid,$lastts)=split(":",$line);
        $jobid_to_wf->{$jobid}->{wf}=$wf;
        $jobid_to_wf->{$jobid}->{wjid}=$wjid;
        $jobid_to_wf->{$jobid}->{lastts}=$lastts;
        $wf_max_wjid->{$jobid}=LML_DBupdate::_max($wf_max_wjid->{$jobid},$wjid);
      }
    }
    close(WFIN);
  } 
  # print STDERR Dumper($jobid_to_wf);
  return($nextchainnr,$jobid_to_wf,$wf_max_wjid);
}

sub save_jobid_wf_map {
  my $self = shift;
  my($nextchainnr,$jobid_to_wf,$currentts)=@_;
  
  my $filename=sprintf("%s/jobid_to_wf.map",$self->{DBDIR});
  open(OUT,"> $filename") or die "cannot open $filename";
  print OUT $nextchainnr,"\n";
  foreach my $jobid (sort(keys(%{$jobid_to_wf}))) {
    next if(  ($currentts-$jobid_to_wf->{$jobid}->{lastts}) > 72*24*3600 );
    
    printf(OUT "%s:%s:%s:%d\n", $jobid,
                $jobid_to_wf->{$jobid}->{wf},
                $jobid_to_wf->{$jobid}->{wjid},
                $jobid_to_wf->{$jobid}->{lastts});
  } 
  close(OUT);
  return();
}

1;