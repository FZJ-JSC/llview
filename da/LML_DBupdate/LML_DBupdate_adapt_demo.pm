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


# modify LML data so that it can be inserted into DB
sub adapt_data_demo_mode {
  my($self) = shift;
  my $data=$self->{DATA};
  my($ref,$spec,$node,$pos,$num);
  my $currentts=$data->{SYSTEM_TS};

  my $statefilename=sprintf("%s/demo_mapping.dat",$self->{DBDIR});

  $self->read_or_generate_demo_mapping($statefilename);

  my $nodebug=1;
  # job information
  foreach my $jobref (@{$data->{JOBS_ENTRIES}}, @{$data->{JOBSTEP_ENTRIES}}) {
    my $jobid=$jobref->{step} // $jobref->{jobid};
    if (!defined($jobid)) {
      printf(STDERR "[LLmonDB_input_LML_jobmap.pm] ERROR: step or jobid is not defined: " . Dumper($jobref) . "\n");
    }

    if(exists($jobref->{owner})) {
      $jobref->{owner}=$self->get_demo_login($jobref->{owner},$nodebug);
    }
    if(exists($jobref->{account})) {
      $jobref->{account}=$self->get_demo_project($jobref->{account},$nodebug);
    }
    if(exists($jobref->{group})) {
      $jobref->{group}=$self->get_demo_project($jobref->{group},$nodebug);
    }
    if(exists($jobref->{name})) {
      $jobref->{name}=$self->get_demo_jobname($jobref->{name},$nodebug);
    }
    if(exists($jobref->{comment})) {
      $jobref->{comment}=$self->get_demo_comment($jobref->{comment},$nodebug);
    }
    if(exists($jobref->{command})) {
      $jobref->{command}=$self->get_demo_command($jobref->{command},$nodebug);
    }
    if(exists($jobref->{state})) {
      $jobref->{state}=$self->get_demo_state($jobref->{state},$nodebug);
    }
  }

  foreach my $ref ( @{$data->{USERMAP_ENTRIES}}, @{$data->{PIPAMAP_ENTRIES}},
                    @{$data->{MENTORMAP_ENTRIES}}, @{$data->{SUPPORTMAP_ENTRIES}}) {
    foreach my $key ("wsaccount","id") {
      if(exists($ref->{$key})) {
        $ref->{$key}=$self->get_demo_login($ref->{$key});
      }
    }
    foreach my $key ("project") {
      if(exists($ref->{$key})) {
        $ref->{$key}=$self->get_demo_project($ref->{$key});
      }
    }
  }

  $self->save_state_demo($statefilename);

  printf("\t LML_DBupdate_file: adapt_data_demo_mode\n") if($debug>=3);
}


sub read_or_generate_demo_mapping {
  my $self = shift;
  my ($statefile)=@_;
  my ($login,$project,$adv,$cnt,$line,$type,$ori,$mapped);

  my $mapping=$self->{MAPPING};
  
  if(-f $statefile) {
    open(IN, $statefile) or die "cannot open $statefile";
    $line=<IN>;			#  header
    if($line=~/^COUNTER;(\d+);(\d+);(\d+)/) {
      ($mapping->{demologinCNT},$mapping->{demoprojectCNT},$mapping->{advprojectCNT})=($1,$2,$3);
      # printf("FOUND COUNTER;%d;%d;%d\n",$mapping->{demologinCNT},$mapping->{demoprojectCNT},$mapping->{advprojectCNT});
    }
    
    while($line=<IN>) {
      chomp($line);
      ($type,$ori,$mapped)=split(";",$line);
      if($type eq "login") {
        $mapping->{login2demologin}->{$ori}=$mapped;
      } elsif($type eq "project") {
        $mapping->{project2demoproject}->{$ori}=$mapped;
      } elsif($type eq "adv") {
        $mapping->{adv2demoadv}->{$ori}=$mapped;
      }
    }
    close(IN);
    printf("\t LML_DBupdate_file:  read demo state to $statefile   %d;%d;%d\n",$mapping->{demologinCNT},$mapping->{demoprojectCNT},$mapping->{advprojectCNT});
  } else {
    $mapping->{demologinCNT}=1000;
    $mapping->{demoprojectCNT}=200;
    $mapping->{advprojectCNT}=30;
  }

  return();
}

sub save_state_demo {
  my $self = shift;
  my ($statefile)=@_;
  my ($login,$project,$adv,$cnt);

  my $mapping=$self->{MAPPING};

  printf("\t LML_DBupdate_file: saving demo state to $statefile   %d;%d;%d\n",$mapping->{demologinCNT},$mapping->{demoprojectCNT},$mapping->{advprojectCNT});
  open(OUT, "> $statefile") or die "cannot open $statefile";
  printf(OUT "COUNTER;%d;%d;%d\n",$mapping->{demologinCNT},$mapping->{demoprojectCNT},$mapping->{advprojectCNT});
  foreach $login (keys(%{$mapping->{login2demologin}})) {
    print OUT "login;$login;".$mapping->{login2demologin}->{$login},"\n";
  }
  foreach $project (keys(%{$mapping->{project2demoproject}})) {
    print OUT "project;$project;".$mapping->{project2demoproject}->{$project},"\n";
  }
  foreach $adv (keys(%{$mapping->{adv2demoadv}})) {
    print OUT "adv;$adv;".$mapping->{adv2demoadv}->{$adv},"\n";
  }
  close(OUT);

  return();
}



sub get_demo_login {
  my $self = shift;
  my ($login,$nodebug)=@_;
  my $llogin;
  $llogin=lc($login);
  
  my $mapping=$self->{MAPPING};
  
  if(!exists($mapping->{login2demologin}->{$llogin})) {
    $mapping->{demologinCNT}++;
    $mapping->{login2demologin}->{$llogin}=sprintf("user%04d",$mapping->{demologinCNT});
    if(!defined($nodebug)) {
      printf("COUNTER;%d;%d;%d\n",$mapping->{demologinCNT},$mapping->{demoprojectCNT},$mapping->{advprojectCNT});
      print "demo new login mapping: $llogin  $mapping->{login2demologin}->{$llogin}\n";
    }
  } else {
    if(!defined($nodebug)) {
      print "demo exist.login mapping: $llogin  $mapping->{login2demologin}->{$llogin}\n";
    }
  }
  
  return($mapping->{login2demologin}->{$llogin});
}

sub get_demo_project {
  my $self = shift;
  my ($project,$nodebug)=@_;
  my $lproject;
  $lproject=lc($project);

  my $mapping=$self->{MAPPING};
  
  if(!exists($mapping->{project2demoproject}->{$lproject})) {
    my $cnt=$mapping->{demoprojectCNT}++;
    $mapping->{project2demoproject}->{$lproject}=sprintf("grp%03d",$cnt);
    if(!defined($nodebug)) {
      # printf("COUNTER;%d;%d;%d\n",$mapping->{demologinCNT},$mapping->{demoprojectCNT},$mapping->{advprojectCNT});
      print "demo new project mapping: $lproject  $mapping->{project2demoproject}->{$lproject}\n";
    }
  }
  
  return($mapping->{project2demoproject}->{$lproject});
}

sub get_demo_adv {
  my $self = shift;
  my ($adv,$nodebug)=@_;
  my $ladv;
  $ladv=lc($adv);

  my $mapping=$self->{MAPPING};
  
  if(!exists($mapping->{adv2demoadv}->{$ladv})) {
    my $cnt=$mapping->{demoadvCNT}++;
    $mapping->{adv2demoadv}->{$ladv}=sprintf("men%03d",$cnt);
    if(!defined($nodebug)) {
      # printf("COUNTER;%d;%d;%d\n",$mapping->{demologinCNT},$mapping->{demoprojectCNT},$mapping->{advprojectCNT});
      print "demo new adv mapping: $ladv  $mapping->{adv2demoadv}->{$ladv}\n";
    }
  }
  
  return($mapping->{adv2demoadv}->{$ladv});
}

sub get_demo_jobname {
  my $self = shift;
  my ($jobname,$nodebug)=@_;
  my $ljobname;
  $ljobname=lc($jobname);

  my $mapping=$self->{MAPPING};
  
  if(!exists($mapping->{jobname2demojobname}->{$ljobname})) {
    my $cnt=$mapping->{demojobnameCNT}++;
    $mapping->{jobname2demojobname}->{$ljobname}=sprintf("jobname%05d",$cnt);
    if(!defined($nodebug)) {
      print "demo new jobname mapping: $ljobname  $mapping->{jobname2demojobname}->{$ljobname}\n";
    }
  }
  
  return($mapping->{jobname2demojobname}->{$ljobname});
}

sub get_demo_comment {
  my $self = shift;
  my ($jobcomment,$nodebug)=@_;
  my $ljobcomment;
  $ljobcomment=lc($jobcomment);

  my $mapping=$self->{MAPPING};
  
  if(!exists($mapping->{jobcomment2demojobcomment}->{$ljobcomment})) {
    my $cnt=$mapping->{demojobcommentCNT}++;
    $mapping->{jobcomment2demojobcomment}->{$ljobcomment}=sprintf("jobcomment%05d",$cnt);
    if(!defined($nodebug)) {
      print "demo new jobcomment mapping: $ljobcomment  $mapping->{jobcomment2demojobcomment}->{$ljobcomment}\n";
    }
  }
  
  return($mapping->{jobcomment2demojobcomment}->{$ljobcomment});
}

sub get_demo_command {
  my $self = shift;
  my ($jobcommand,$nodebug)=@_;
  my $ljobcommand;
  $ljobcommand=lc($jobcommand);

  my $mapping=$self->{MAPPING};
  
  if(!exists($mapping->{jobcommand2demojobcommand}->{$ljobcommand})) {
    my $cnt=$mapping->{demojobcommandCNT}++;
    $mapping->{jobcommand2demojobcommand}->{$ljobcommand}=sprintf("jobcommand%05d",$cnt);
    if(!defined($nodebug)) {
      print "demo new jobcommand mapping: $ljobcommand  $mapping->{jobcommand2demojobcommand}->{$ljobcommand}\n";
    }
  }
  
  return($mapping->{jobcommand2demojobcommand}->{$ljobcommand});
}

sub get_demo_state {
  my $self = shift;
  my ($jobsstate,$nodebug)=@_;

  if ( $jobsstate =~ /^CANCELLED by (.+)$/ ) {
    my $login = $1;
    my $demologin = $self->get_demo_login($login,$nodebug);
    $jobsstate =~ s/$login/$demologin/; 
  }

  return($jobsstate);
}

1;