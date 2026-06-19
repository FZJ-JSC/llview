# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 

package LLmonDB;

my $VERSION='$Revision: 1.00 $';
my $debug=0;

use strict;
use warnings::unused;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );

sub add_to_jobtsmap {
  my($self) = shift;
  my($dbobj,$table)=@_;
  my($colsref);
  my ($cnt,$rc,$numerrors,$jobid);

  $self->get_jobtsmap_from_DB() if(!$self->{JOBTSMAP_AVAIL}); 
  
  push(@{$colsref},"jobid");
  push(@{$colsref},"ts");

  my @jobids = sort(keys(%{$self->{JOBTSMAP}}));

  if(1) {
    #  remove old jobs from table
    my $where=sprintf("(jobid not in (%s) )",join(",",@jobids));
    $dbobj->delete($table,
                    {
                    type => 'some_rows',
                    where => $where
                    });
  }
  
  my $seq=$dbobj->start_insert_sequence($table,$colsref);

  $cnt=0; $numerrors=0;
  foreach $jobid (sort(keys(%{$self->{JOBTSMAP}}))) {
    my $data;
    $data->[0]=$jobid;
    $data->[1]=$self->{JOBTSMAP}->{$jobid}->{ts};
    $rc=$dbobj->insert_sequence($seq,$data);
    $cnt++;
    $numerrors++ if($rc != 1); # inserted on row
  }
  
  $dbobj->end_insert_sequence($seq);
  printf("$self->{INSTNAME} LLmonDB:     end add_to_jobtsmap (add %d entries to %s, #errors=%d)\n",$cnt,$table,$numerrors)  if($debug>=3);
  
  return($cnt);
  
  $self->{A}=0;  #dummy statement to avoid unused warning
}

sub add_to_jobnodemap {
  my($self) = shift;
  my($dbobj,$table)=@_;
  my($colsref);
  my ($cnt,$rc,$numerrors,$jobid,$node);

  $self->get_jobnodemap_from_DB() if(!$self->{JOBTSMAP_AVAIL}); 
  
  push(@{$colsref},"jobid");
  push(@{$colsref},"nodeid");
  push(@{$colsref},"perc");

  my @jobids = sort(keys(%{$self->{JOBNODEMAP}}));
  if(0) {
    my $where=sprintf("(jobid in (%s) )",join(",",@jobids));
    $dbobj->delete($table,
                    {
                    type => 'some_rows',
                    where => $where
                    });
  }
  $dbobj->remove_contents($table);
  
  my $seq=$dbobj->start_insert_sequence($table,$colsref);

  $cnt=0;$numerrors=0;
  foreach $jobid (@jobids) {
    my $data;
    $data->[0]=$jobid;
    foreach $node (sort(keys(%{$self->{JOBNODEMAP}->{$jobid}}))) {
      $data->[1]=$node;
      $data->[2]=$self->{JOBNODEMAP}->{$jobid}->{$node}->{perc};
      $rc=$dbobj->insert_sequence($seq,$data);
      $cnt++;
      $numerrors++ if($rc != 1); # inserted on row
    }
  }
  
  $dbobj->end_insert_sequence($seq);
  printf("$self->{INSTNAME} LLmonDB:     end add_to_jobnodemap (add %d entries to %s, #errors=%d)\n",$cnt,$table,$numerrors)  if($debug>=3);
  
  return($cnt);
  
  $self->{A}=0;  #dummy statement to avoid unused warning
}

# get job to node mapping from entries (LML)
sub get_jobnodemap_from_LML {
  my($self) = shift;
  my($entries,$nodes)=@_;
  my($dataref,$jobid,$jobref,$spec,$node,$pos,$num);
  my $cnt=0;

  foreach $jobref (@{$entries}) {
    $jobid = $jobref->{step} // $jobref->{jobid};
    if (!defined($jobid)) {
      printf(STDERR "[LLmonDB_input_LML_jobmap.pm] ERROR: step or jobid is not defined: " . Dumper($jobref) . "\n");
    }
    next unless defined($jobid);

    if(exists($jobref->{nodelist})) {
      if($jobref->{nodelist} ne "-") {
        foreach $spec (split(/\),?\(/,$jobref->{nodelist})) {
          $spec=~/\(?([^,]+),(\d+)\)?/;
          $node=$1;$pos=$2;
          $dataref->{$jobid}->{$node}->{perc}++;
        }
      }
    }
    if(exists($jobref->{vnodelist})) {
      if($jobref->{vnodelist} ne "-") {
        foreach $spec (split(/\),?\(/,$jobref->{vnodelist})) {
          $spec=~/\(?([^,]+),(\d+)\)?/;
          $node=$1;$num=$2;
          $dataref->{$jobid}->{$node}->{perc}+=$num;
        }
      }
    }
    foreach $node (keys(%{$dataref->{$jobid}})) {
      if(exists($nodes->{$node})) {
        if(exists($nodes->{$node}->{used_cores_requ})) {
          $dataref->{$jobid}->{$node}->{perc}/=$nodes->{$node}->{used_cores_requ};
        } else {
          $dataref->{$jobid}->{$node}->{perc}=1.0;
        }
      } else {
        $dataref->{$jobid}->{$node}->{perc}=1.0;
      }
    }
  }
  $self->{JOBNODEMAP_AVAIL}=1;
  $self->{JOBNODEMAP}=$dataref;

  if($self->{VERBOSE}) {
    foreach $jobid (keys(%{$dataref})) {
      $cnt+=scalar keys(%{$dataref->{$jobid}});
    }
    printf("$self->{INSTNAME} LLmonDB:     get_jobnodemap_from_LML (found %d entries)\n",$cnt) ;
  }
  return();

  $self->{A}=0;  #dummy statement to avoid unused warning
}

# get job to node mapping from entries (LML)
sub get_jobnodemap_from_DB {
  my($self) = shift;
  my ($dataref);

  if(exists($self->{DBcontains_map_data})) {
    $dataref=$self->query($self->{DBcontains_map_data},"jobnodemap",
                          {
                          type => 'hash_values',
                          hash_keys => ['jobid','nodeid'],
                          hash_value => 'perc',
                          });
    
    $self->{JOBNODEMAP_AVAIL}=1;
    $self->{JOBNODEMAP}=$dataref;
  } else {
    printf("$self->{INSTNAME} LLmonDB:     WARNING get_jobnodemap_from_DB (no database found with mapping data)\n");
  } 
  printf("$self->{INSTNAME} LLmonDB:     end get_jobtsmap_from_DB (found %d entries)\n",scalar keys(%{$dataref}))  if($self->{VERBOSE});
  return();
}

# get job to ts mapping from entries (LML)
sub get_jobtsmap_from_LML {
  my($self) = shift;
  my($entries)=@_;
  my ($dataref,$jobref,$jobid);
  my $cnt=0;

  foreach $jobref (@{$entries}) {
    $jobid = $jobref->{step} // $jobref->{jobid};
    if (!defined($jobid)) {
      printf(STDERR "[LLmonDB_input_LML_jobmap.pm] ERROR: step or jobid is not defined: " . Dumper($jobref) . "\n");
    }
    next unless defined($jobid);

    my $active=0;
    if(exists($jobref->{nodelist})) {
      $active=1 if($jobref->{nodelist} ne "-");
    }
    if(exists($jobref->{vnodelist})) {
      $active=1 if($jobref->{vnodelist} ne "-");
    }
    next if(!$active);
    
    if(exists($jobref->{ts})) {
      $dataref->{$jobid}->{ts}=$jobref->{ts};
    } else {
      $dataref->{$jobid}->{ts}=-1;
    }
    $cnt++;
  }
  $self->{JOBTSMAP_AVAIL}=1;
  $self->{JOBTSMAP}=$dataref;
  printf("$self->{INSTNAME} LLmonDB:     end get_jobtsmap_from_LML (found %d entries)\n",$cnt)  if($self->{VERBOSE});
  return($dataref);
}

# get job to ts mapping from entries (DB)
sub get_jobtsmap_from_DB {
  my($self) = shift;
  my ($dataref);

  if(exists($self->{DBcontains_map_data})) {
    $dataref=$self->query($self->{DBcontains_map_data},"jobtsmap",
                          {
                          type => 'hash_values',
                          hash_keys => 'jobid',
                          hash_value => 'ts',
                          });
    
    $self->{JOBTSMAP_AVAIL}=1;
    $self->{JOBTSMAP}=$dataref;
  } else {
    printf("$self->{INSTNAME} LLmonDB:     WARNING get_jobtsmap_from_DB (no database found with mapping data)\n");
  }
    printf("$self->{INSTNAME} LLmonDB:     end get_jobtsmap_from_DB (found %d entries)\n",scalar keys(%{$dataref}))  if($self->{VERBOSE});
  return($dataref);
}

1;